import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../conversation/conversation_view_model.dart';
import '../conversation/token_batcher.dart';
import 'voice_service.dart';

/// Runs the conversation by voice: hear, answer, speak, yield when spoken
/// over.
///
/// Pure coordination over the existing text pipeline — an utterance submits
/// like a typed message, a completed answer is read aloud, and the user
/// starting to talk silences whatever the agent was saying or generating,
/// because a friend stops talking when you start.
final class VoiceConversationController extends ChangeNotifier {
  /// Creates the controller over [voice] and [conversation].
  VoiceConversationController({
    required VoiceService voice,
    required ConversationViewModel conversation,
    BatchScheduler utteranceScheduler = const TimerBatchScheduler(),
    DateTime Function() now = DateTime.now,
  }) : this._(voice, conversation, utteranceScheduler, now);

  VoiceConversationController._(
    this._voice,
    this._conversation,
    this._utteranceScheduler,
    this._now,
  ) {
    _events = _voice.events.listen(_onVoiceEvent);
    _conversation.completedTurnsListenable.addListener(_onTurnsChanged);
    _conversation.canSubmitListenable.addListener(_onCanSubmitChanged);
    _conversation.activeTurnListenable.addListener(_onActiveTurnChanged);
    _spokenThrough = _conversation.completedTurnsListenable.value.length;
  }

  final VoiceService _voice;
  final ConversationViewModel _conversation;
  final BatchScheduler _utteranceScheduler;
  final DateTime Function() _now;
  StreamSubscription<VoiceEvent>? _events;

  /// When the last utterance settled.
  ///
  /// The fast endpointer submits within a second of the user's last sound,
  /// so the microphone is live exactly where their trailing breath lands.
  /// A partial inside [_postFinalCooldown] of the final is that breath,
  /// not an interruption — it must not cancel the answer just asked for.
  DateTime? _lastFinalAt;
  static const Duration _postFinalCooldown = Duration(milliseconds: 500);

  /// How long a partial may sit unchanged before the utterance is settled.
  ///
  /// The transcriber's own endpointing waits out seconds of silence; a
  /// partial that has stopped changing for this long is the user having
  /// finished their sentence.
  static const Duration _utteranceSettleDelay = Duration(milliseconds: 1500);

  CancelBatch? _pendingSettle;

  /// Forced-finalize attempts for the current utterance, bounded so a
  /// transcriber that never answers cannot be poked forever.
  int _settleAttempts = 0;
  static const int _maxSettleAttempts = 3;

  /// True from asking the generation to stop until its turn winds down.
  ///
  /// The cancel flushes the token batcher, and a flushed tail that happens
  /// to finish a sentence must not be dispatched to the voice — the
  /// interruption exists to stop exactly that.
  bool _stopRequestedForActive = false;

  bool _enabled = false;

  /// True while [enable] is waiting for the stored history to land.
  bool _enabling = false;
  bool _disposed = false;
  bool _speaking = false;
  bool _listening = false;

  /// True from asking the synthesizer to speak until it reports finishing.
  ///
  /// [SpeakingStarted] takes a whole round trip to come back; the user can
  /// start talking inside that window, and the answer must still give way.
  bool _speechRequested = false;
  String _partialTranscript = '';
  String? _failure;

  /// An utterance finished while the previous answer was still winding
  /// down; submitted the moment the conversation can take it.
  String? _pendingUtterance;

  /// How much of the streaming answer has already been sent to the voice.
  ///
  /// Speech begins with the first finished sentence rather than waiting for
  /// the whole answer: generation, synthesis, and playback overlap instead
  /// of stacking end to end.
  int _dispatchedOfActive = 0;

  /// Where a spoken chunk may end: a sentence has visibly finished.
  static final RegExp _sentenceEnd = RegExp(r'[。！？!?.…；;\n]');

  /// Where the answer's very first chunk may end early: a clause has
  /// finished, even though its sentence has not.
  ///
  /// Deliberately no colons: a colon is how every URL starts, and a chunk
  /// cut at "https:" leaves a link half stripped and read aloud.
  static const String _clauseEnds = ',,、';

  /// The first clause must have this much substance before it is worth an
  /// extra synthesis seam; "好的," alone reads as a stutter.
  static const int _firstClauseTarget = 6;

  /// Anything CJK: the answer's language is decided by its beginning.
  static final RegExp _cjk = RegExp(
    r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]',
  );

  /// After the first fast sentence, chunks accumulate to at least this
  /// many characters: single short sentences drift in timbre, and every
  /// separate synthesis pays its own prosody reset.
  static const int _chunkTarget = 40;

  /// The language pinned to the answer being spoken, decided once at its
  /// first chunk — one English word inside a Chinese reply must not flip
  /// the accent mid-thought.
  String? _activeLang;

  /// Whether the next dispatch is the answer's first, which goes out alone
  /// so the voice starts as early as possible.
  bool _firstChunkOfAnswer = true;

  /// How many completed turns have already been considered for speaking.
  ///
  /// Seeded with what is already there, so enabling voice over yesterday's
  /// conversation does not recite it.
  int _spokenThrough = 0;

  /// Whether the conversation is currently being run by voice.
  bool get enabled => _enabled || _enabling;

  /// Whether the agent is being spoken aloud right now.
  bool get speaking => _speaking;

  /// Whether the microphone is truly open, as the host reported it.
  ///
  /// Deliberately not [enabled]: starting can sit in a minutes-long asset
  /// download, and an indicator must not claim an open microphone then.
  bool get listening => _listening;

  /// What is being heard, before the transcriber settles it.
  String get partialTranscript => _partialTranscript;

  /// Why the pipeline went quiet, or null while it is healthy.
  String? get failure => _failure;

  /// Opens the ears and starts running the conversation by voice.
  Future<void> enable() async {
    if (_enabled || _enabling) {
      return;
    }
    _enabling = true;
    _failure = null;
    notifyListeners();
    // Not enabled before the stored history has landed: the restore fires
    // the turns listener, and with the speak-from-here mark still at zero
    // it would recite yesterday aloud, turn by turn.
    await _conversation.restored;
    if (_disposed || !_enabling) {
      // Disabled — or torn down entirely — while the history was still
      // loading. In release builds notifyListeners on a disposed notifier
      // is silent, and the microphone would open with nobody listening.
      return;
    }
    _spokenThrough = _conversation.completedTurnsListenable.value.length;
    _enabling = false;
    _enabled = true;
    notifyListeners();
    await _voice.startListening();
  }

  /// Releases the ears and the voice.
  Future<void> disable() async {
    if (_enabling) {
      // Never finished enabling: nothing has been started that needs
      // stopping.
      _enabling = false;
      notifyListeners();
      return;
    }
    if (!_enabled) {
      return;
    }
    _enabled = false;
    _partialTranscript = '';
    _pendingUtterance = null;
    _pendingSettle?.cancel();
    _pendingSettle = null;
    _listening = false;
    _speaking = false;
    _speechRequested = false;
    notifyListeners();
    await _voice.stopSpeaking();
    await _voice.stopListening();
  }

  void _onVoiceEvent(VoiceEvent event) {
    if (!_enabled) {
      return;
    }
    switch (event) {
      case PartialTranscript(:final String text):
        _partialTranscript = text;
        notifyListeners();
        if (text.trim().isNotEmpty) {
          final DateTime? lastFinal = _lastFinalAt;
          if (lastFinal == null ||
              _now().difference(lastFinal) >= _postFinalCooldown) {
            _yieldToTheUser();
          }
          // The user is still talking; push the settle out again.
          _settleAttempts = 0;
          _pendingSettle?.cancel();
          _pendingSettle = _utteranceScheduler.schedule(
            _utteranceSettleDelay,
            _settleUtterance,
          );
        }
      case FinalTranscript(:final String text):
        _lastFinalAt = _now();
        _pendingSettle?.cancel();
        _pendingSettle = null;
        _settleAttempts = 0;
        _partialTranscript = '';
        notifyListeners();
        if (text.trim().isEmpty) {
          return;
        }
        if (_conversation.canSubmit) {
          unawaited(_conversation.submit(text));
        } else {
          // The previous answer is still winding down from the
          // interruption; the replacement question must not be dropped on
          // the floor.
          _pendingUtterance = text;
        }
      case SpeakingStarted():
        _speaking = true;
        notifyListeners();
      case SpeakingFinished():
        _speaking = false;
        _speechRequested = false;
        notifyListeners();
      case VoiceFailed(:final String message):
        // A dead pipeline must not leave the button lit as listening —
        // nor keep reading the answer aloud when the button has already
        // gone dark and disable can no longer reach it.
        _pendingSettle?.cancel();
        _pendingSettle = null;
        _listening = false;
        if (_speaking || _speechRequested) {
          unawaited(_voice.stopSpeaking());
        }
        _enabled = false;
        _partialTranscript = '';
        _pendingUtterance = null;
        _speaking = false;
        _speechRequested = false;
        _failure = message;
        notifyListeners();
      case ListeningStarted():
        _listening = true;
        notifyListeners();
      case ListeningStopped():
        _listening = false;
        notifyListeners();
    }
  }

  void _onActiveTurnChanged() {
    final Turn? active = _conversation.activeTurnListenable.value;
    if (active == null) {
      _dispatchedOfActive = 0;
      _stopRequestedForActive = false;
      _activeLang = null;
      _firstChunkOfAnswer = true;
      return;
    }
    if (!_enabled || _stopRequestedForActive) {
      return;
    }
    final String text = active.text;
    if (text.length <= _dispatchedOfActive) {
      return;
    }
    final String undispatched = text.substring(_dispatchedOfActive);
    int lastEnd = _lastSentenceEnd(undispatched);
    if (lastEnd < 0) {
      // No sentence yet — but the answer's first chunk may go out on a
      // finished clause, so the voice starts before the full stop arrives.
      if (!_firstChunkOfAnswer) {
        return;
      }
      lastEnd = _lastClauseEnd(undispatched);
      if (lastEnd + 1 < _firstClauseTarget) {
        return;
      }
    }
    // The first sentence goes out alone so the voice starts early; after
    // that, sentences accumulate into steadier chunks.
    if (!_firstChunkOfAnswer && lastEnd + 1 < _chunkTarget) {
      return;
    }
    final String chunk = undispatched.substring(0, lastEnd + 1);
    _dispatchedOfActive += chunk.length;
    _firstChunkOfAnswer = false;
    _speakAloud(chunk, decidedBy: text);
  }

  /// The last sentence boundary in [text] that is safe to speak through,
  /// or -1 when there is none.
  ///
  /// An ASCII full stop between digits is a decimal point: "3.14" must
  /// not be read as "three." and then the rest. At the very end of the
  /// buffer, a full stop after a digit might be exactly that — the next
  /// delta settles it. CJK 。 never appears inside a number and needs no
  /// guard.
  static int _lastSentenceEnd(String text) {
    for (int i = text.length - 1; i >= 0; i--) {
      if (!_sentenceEnd.hasMatch(text[i])) {
        continue;
      }
      if (text[i] == '.') {
        if (i + 1 < text.length) {
          if (_isDigit(text.codeUnitAt(i + 1))) {
            continue;
          }
        } else if (i > 0 && _isDigit(text.codeUnitAt(i - 1))) {
          continue;
        }
      }
      return i;
    }
    return -1;
  }

  /// The last clause boundary in [text] that is safe to speak through, or
  /// -1 when there is none.
  ///
  /// A boundary needs a following character that is not a digit: "1,234"
  /// must not be read as "one" and then the rest, and a comma at the very
  /// end of the buffer might be exactly that — the next delta settles it.
  static int _lastClauseEnd(String text) {
    for (int i = text.length - 2; i >= 0; i--) {
      if (_clauseEnds.contains(text[i]) && !_isDigit(text.codeUnitAt(i + 1))) {
        return i;
      }
    }
    return -1;
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  void _speakAloud(String text, {String? decidedBy}) {
    final String spoken = speakableText(text);
    if (spoken.isEmpty) {
      return;
    }
    _activeLang ??= _cjk.hasMatch(decidedBy ?? text) ? 'zh' : 'en';
    _speechRequested = true;
    unawaited(_voice.speak(spoken, language: _activeLang));
  }

  /// The partial has sat still long enough: the user has finished talking.
  void _settleUtterance() {
    _pendingSettle = null;
    if (!_enabled || _partialTranscript.trim().isEmpty) {
      return;
    }
    _settleAttempts += 1;
    unawaited(_voice.finalizeUtterance());
    if (_settleAttempts < _maxSettleAttempts) {
      // Re-armed until the final actually arrives: a finalize the analyzer
      // ignored must not leave the utterance hanging on screen forever.
      _pendingSettle = _utteranceScheduler.schedule(
        _utteranceSettleDelay,
        _settleUtterance,
      );
    } else {
      // Three asks is enough; a transcript that will never settle should
      // not sit on screen pretending it might.
      _settleAttempts = 0;
      _partialTranscript = '';
      notifyListeners();
    }
  }

  void _onCanSubmitChanged() {
    if (_conversation.canSubmit) {
      // The generation has fully ended. The null-to-null active turn of a
      // prefill cancel never notifies, so the dispatch guard is lifted
      // here, where the end is always visible.
      _stopRequestedForActive = false;
    }
    final String? pending = _pendingUtterance;
    if (pending == null || !_enabled || !_conversation.canSubmit) {
      return;
    }
    _pendingUtterance = null;
    unawaited(_conversation.submit(pending));
  }

  /// The user started talking: whatever the agent was saying or still
  /// generating gives way.
  void _yieldToTheUser() {
    if (_speaking || _speechRequested) {
      unawaited(_voice.stopSpeaking());
    }
    if (!_conversation.canSubmit) {
      _stopRequestedForActive = true;
      unawaited(_conversation.stop());
    }
  }

  void _onTurnsChanged() {
    final List<Turn> turns = _conversation.completedTurnsListenable.value;
    if (!_enabled) {
      _spokenThrough = turns.length;
      return;
    }
    for (; _spokenThrough < turns.length; _spokenThrough++) {
      final Turn turn = turns[_spokenThrough];
      if (turn.role == TurnRole.assistant &&
          turn.status == TurnStatus.completed) {
        // Only what the streaming dispatch has not already said. This
        // leans on the ViewModel notifying completedTurns BEFORE nulling
        // the active turn: the counter and language below are read here
        // first, and only then reset by _onActiveTurnChanged seeing null.
        final int alreadySpoken = _dispatchedOfActive <= turn.text.length
            ? _dispatchedOfActive
            : turn.text.length;
        _dispatchedOfActive = 0;
        _speakAloud(turn.text.substring(alreadySpoken), decidedBy: turn.text);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingSettle?.cancel();
    _pendingSettle = null;
    // The view that owns this controller is torn down on every conversation
    // switch; the microphone must not outlive it.
    if (_enabled || _enabling) {
      _enabling = false;
      unawaited(_voice.stopSpeaking());
      unawaited(_voice.stopListening());
    }
    unawaited(_events?.cancel());
    _events = null;
    _conversation.completedTurnsListenable.removeListener(_onTurnsChanged);
    _conversation.canSubmitListenable.removeListener(_onCanSubmitChanged);
    _conversation.activeTurnListenable.removeListener(_onActiveTurnChanged);
    super.dispose();
  }
}

/// [text] with everything a voice cannot say stripped away.
///
/// The synthesizer reads exactly what it is given: emoji become their
/// spelled-out names, markdown becomes noise, and code is unreadable aloud.
/// Speech gets the sentences alone; the full text stays on screen.
String speakableText(String text) {
  String speakable = text;
  // Whole code blocks go first, fences and all.
  speakable = speakable.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  // A link is read by its label; the address is for clicking.
  speakable = speakable.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (Match m) => m[1] ?? '',
  );
  speakable = speakable.replaceAll(RegExp(r'https?://\S+'), ' ');
  // Inline markup keeps its words and loses its marks.
  speakable = speakable.replaceAll(RegExp(r'[`*_~#>]'), '');
  // Emoji and pictographs, including variation selectors.
  speakable = speakable.replaceAll(
    RegExp(
      r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}'
      r'\u{2B00}-\u{2BFF}\u{FE00}-\u{FE0F}\u{200D}]',
      unicode: true,
    ),
    '',
  );
  return speakable.replaceAll(RegExp(r'\s+'), ' ').trim();
}
