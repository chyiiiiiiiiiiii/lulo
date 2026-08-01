import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../conversation/conversation_view_model.dart';
import '../conversation/token_batcher.dart';
import 'voice_service.dart';

/// What the agent is doing, as far as the user should be able to tell.
///
/// In full duplex the microphone never closes, so "listening" is true from
/// the moment the ears open until they shut — which makes it useless on its
/// own as a status. Shown alone it cannot distinguish thinking from talking
/// from broken, and a user watching a silent window has no way to tell which
/// one they are looking at.
enum VoiceActivity {
  /// Waiting for the user. Nothing is being generated or said.
  listening,

  /// An answer is being generated, and nothing is being said yet.
  thinking,

  /// An answer is being read aloud. The microphone is still open.
  speaking,

  /// Speech was interrupted and is waiting to see whether the user was
  /// asking something or only reacting.
  paused,

  /// The push-to-talk key or button is held: the agent is all ears, and
  /// nothing submits until the release.
  holding,

  /// An answer born of held speech is playing and yields to nothing but
  /// the next hold.
  shielded,
}

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
    TranscriptRefiner transcriptRefiner = const _RawTranscriptRefiner(),
    List<String> Function() protectedVocabulary = _noProtectedVocabulary,
    BatchScheduler utteranceScheduler = const TimerBatchScheduler(),
    DateTime Function() now = DateTime.now,
  }) : this._(
         voice,
         conversation,
         transcriptRefiner,
         protectedVocabulary,
         utteranceScheduler,
         now,
       );

  VoiceConversationController._(
    this._voice,
    this._conversation,
    this._transcriptRefiner,
    this._protectedVocabulary,
    this._utteranceScheduler,
    this._now,
  ) {
    _events = _voice.events.listen(_onVoiceEvent);
    _conversation.completedTurnsListenable.addListener(_onTurnsChanged);
    _conversation.canSubmitListenable.addListener(_onCanSubmitChanged);
    _conversation.activeTurnListenable.addListener(_onActiveTurnChanged);
    _spokenThrough = _conversation.completedTurnsListenable.value.length;
    // Proof that this file's diagnostics reach the captured log at all. With
    // it, a run with no yield lines means no yield fired; without it, that
    // same run cannot be told apart from logging that never worked.
    debugPrint('Lulo voice controller: ready, diagnostics on');
  }

  final VoiceService _voice;
  final ConversationViewModel _conversation;
  final TranscriptRefiner _transcriptRefiner;
  final List<String> Function() _protectedVocabulary;
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

  /// Kept under the shared test clock's 600ms step: widening this past
  /// that step flips the pre-existing barge-in tests into exercising the
  /// cooldown branch instead (loudly — they fail, not silently pass).
  static const Duration _postFinalCooldown = Duration(milliseconds: 500);

  /// How much the user must say to take the floor back mid-sentence.
  ///
  /// Applies only while the agent is actually speaking. Until this existed,
  /// one character was enough: "OK" ended an answer 571 characters into
  /// being read aloud, and a single misheard syllable could do the same. "OK"
  /// and "嗯嗯" are how people show they are still listening, not requests to
  /// stop. Four characters is roughly a second of Chinese speech, which is
  /// about where acknowledging stops and interrupting starts.
  ///
  /// While nothing is being said, one character still takes the floor —
  /// there is nothing to take away, and a correction like "不對" must land
  /// as fast as it is spoken.
  static const int _charactersToInterruptSpeech = 4;

  /// How long an interrupted sentence waits to see if it was replaced.
  ///
  /// Longer than [_utteranceSettleDelay] on purpose: if what the user said
  /// becomes a question, that question must win, and it needs time to settle
  /// and be submitted first.
  static const Duration _resumeDelay = Duration(seconds: 2);

  /// How long a partial may sit unchanged before the utterance is settled.
  ///
  /// The transcriber's own endpointing waits out seconds of silence; a
  /// partial that has stopped changing for this long is the user having
  /// finished their sentence.
  static const Duration _utteranceSettleDelay = Duration(milliseconds: 1500);

  CancelBatch? _pendingSettle;

  /// Sentences handed to the voice and not yet known to have finished.
  ///
  /// Not a single "current" sentence: chunks are dispatched as the answer
  /// streams and the native side queues them back to back, so the most
  /// recently dispatched one is normally NOT the one being heard — the next
  /// is already handed over while the current plays. An interruption cuts
  /// somewhere inside this list without saying where, so the whole of it is
  /// put back. Over-repeating a sentence the user already heard is
  /// recoverable; skipping one is not.
  final List<String> _speechOutstanding = <String>[];

  /// The sentence an interruption cut off, awaiting [_resumeDelay].
  String? _interruptedSpeech;
  String? _interruptedLang;
  String? _outstandingLang;

  // Push-to-talk. While the button is held, finals buffer instead of
  // submitting — the endpointer keeps firing through a long press, and a
  // thinking pause must not send half a question. Release is the only
  // endpoint, and the answer it produces cannot be talked over: the next
  // hold is the one interruption.
  bool _pttHeld = false;
  bool _pttSettling = false;
  bool _pttProtected = false;

  /// Whether this hold has a batch recogniser behind it (the hotkey path
  /// captures audio natively; the composer button does not), and what it
  /// heard once it answers.
  bool _pttAwaitsBatch = false;
  String? _pttBatchText;
  static const Duration _pttBatchWait = Duration(seconds: 8);

  /// Whether a hold is physically in progress, tracked apart from
  /// [_pttHeld]: enabling takes seconds, and a press that auto-enabled the
  /// voice must not begin holding after its release already happened.
  bool _holdIntent = false;
  bool _holdIntentBatch = false;
  final List<String> _pttFinals = <String>[];
  CancelBatch? _pttSubmitBackstop;
  static const Duration _pttTrailingWait = Duration(milliseconds: 1500);
  CancelBatch? _pendingResume;

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
  TranscriptRefinement? _pendingUtterance;
  int _refinementEpoch = 0;

  /// How much of the streaming answer has already been sent to the voice.
  ///
  /// Speech begins with the first finished sentence rather than waiting for
  /// the whole answer: generation, synthesis, and playback overlap instead
  /// of stacking end to end.
  int _dispatchedOfActive = 0;

  /// Where a spoken chunk may end: a sentence has visibly finished.
  ///
  /// The CJK stops here are the ones that need no disambiguation: unlike a
  /// Latin full stop, none of them appears inside an abbreviation or a
  /// number, so seeing one is enough. ． (U+FF0E) and ｡ (U+FF61) were
  /// missing, and a sentence ending in either waited for punctuation that
  /// had already arrived.
  static final RegExp _sentenceEnd = RegExp(r'[。．｡！？!?.…；;\n]');

  /// Where the answer's very first chunk may end early: a clause has
  /// finished, even though its sentence has not.
  ///
  /// Deliberately no colons: a colon is how every URL starts, and a chunk
  /// cut at "https:" leaves a link half stripped and read aloud.
  static const String _clauseEnds = ',，、';

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
  ///
  /// The target is really a duration, and characters are only a cheap proxy
  /// for it — a proxy that is wrong by a factor of two between languages.
  /// Measured from the synthesiser's own log, Chinese runs about 0.156
  /// seconds per character, so forty characters is 6.2 seconds of audio
  /// against roughly three for the same count of English. Everything a long
  /// chunk costs doubles with it: the wait before the next one begins, how
  /// much of the answer an interruption takes away, and the width of the gap
  /// where nothing is speaking.
  ///
  /// Raised from three seconds' worth once /stop could cut a playing
  /// sentence mid-word: every chunk boundary is a fresh synthesis and a
  /// chance for the voice to drift, so fewer seams is a steadier person —
  /// and an interruption no longer has to wait a chunk out.
  static const int _chunkTarget = 64;

  /// The same few seconds of speech, counted in Chinese characters.
  static const int _cjkChunkTarget = 32;

  /// The chunk target for the answer being spoken.
  ///
  /// Keyed on the language already pinned for this answer, so it cannot
  /// change halfway through one.
  int get _chunkTargetForAnswer =>
      _activeLang == 'zh' ? _cjkChunkTarget : _chunkTarget;

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

  /// What the agent is doing right now.
  ///
  /// Ordered most-specific first: a paused answer is also technically
  /// listening, and a speaking one is also technically not submittable.
  VoiceActivity get activity {
    if (_pttHeld || _pttSettling) {
      return VoiceActivity.holding;
    }
    if (_interruptedSpeech != null) {
      return VoiceActivity.paused;
    }
    if (_deliveringAnswer) {
      return _pttProtected ? VoiceActivity.shielded : VoiceActivity.speaking;
    }
    if (!_conversation.canSubmit) {
      return VoiceActivity.thinking;
    }
    return VoiceActivity.listening;
  }

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
    _refinementEpoch += 1;
    _partialTranscript = '';
    _pendingUtterance = null;
    _pendingSettle?.cancel();
    _pendingSettle = null;
    _listening = false;
    _speaking = false;
    _speechRequested = false;
    _cancelPendingResume();
    notifyListeners();
    await _voice.stopSpeaking();
    await _voice.stopListening();
  }

  void _onVoiceEvent(VoiceEvent event) {
    if (!_enabled) {
      // A hold is the intent to talk; making the user find a toggle first
      // would answer that intent with silence. Everything else a disabled
      // controller ignores.
      if (event is HoldToTalkPressed) {
        holdToTalkPressed(withBatchRecognition: true);
      } else if (event is HoldToTalkReleased) {
        holdToTalkReleased();
      }
      return;
    }
    switch (event) {
      case PartialTranscript(:final String text):
        _partialTranscript = text;
        notifyListeners();
        if (_pttHeld || _pttSettling) {
          // Held speech is the question being composed: no floor to take,
          // no settle race. The release is the endpoint.
          return;
        }
        if (_pttProtected) {
          // The answer to held speech plays out; ambient speech is noise.
          return;
        }
        if (text.trim().isNotEmpty) {
          final DateTime? lastFinal = _lastFinalAt;
          if (lastFinal == null ||
              _now().difference(lastFinal) >= _postFinalCooldown) {
            debugPrint('Lulo partial: ${text.length} chars "$text"');
            if (_takesTheFloor(text)) {
              _yieldToTheUser(from: 'partial');
            }
          } else {
            debugPrint(
              'Lulo partial: ${text.length} chars, inside post-final cooldown '
              '— no yield',
            );
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
        if (_pttHeld || _pttSettling) {
          if (text.trim().isNotEmpty) {
            _pttFinals.add(text.trim());
          }
          if (_pttSettling) {
            // The trailing sentence has settled; the question is whole.
            _submitHeldSpeech();
          }
          return;
        }
        if (_pttProtected) {
          return;
        }
        if (text.trim().isEmpty) {
          // Whatever took the floor turned out to be nothing — a cough, a
          // misheard syllable. That is known now, so the interrupted answer
          // picks up immediately instead of waiting out the backstop.
          _resumeInterruptedSpeech();
          return;
        }
        if (!_conversation.canSubmit) {
          // A correction spoken wholly inside the post-final cooldown
          // never fired the yield from its partials; its final is the
          // last chance to interrupt the answer it replaces. Short
          // acknowledgements are held to the same threshold here as in the
          // partials, or "OK" would simply cancel a moment later instead.
          if (_takesTheFloor(text)) {
            _yieldToTheUser(from: 'final');
          }
        }
        unawaited(_refineFinalUtterance(text));
      case SpeakingStarted():
        _speaking = true;
        notifyListeners();
      case SpeakingFinished():
        _speaking = false;
        _speechRequested = false;
        // Everything handed over has drained; nothing is left to put back.
        _speechOutstanding.clear();
        if (_pttProtected && _conversation.canSubmit) {
          // The protected answer has been heard to the end; open
          // conversation resumes.
          _pttProtected = false;
        }
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
      case HoldToTalkPressed():
        holdToTalkPressed(withBatchRecognition: true);
      case HoldToTalkReleased():
        holdToTalkReleased();
      case HeldTranscript(:final String text):
        if (_pttSettling) {
          if (text.trim().isNotEmpty) {
            _pttBatchText = text.trim();
          }
          _submitHeldSpeech();
        }
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
    final int target = _chunkTargetForAnswer;
    int lastEnd = _firstChunkOfAnswer
        ? _lastSentenceEnd(undispatched)
        : _sentenceEndNear(undispatched, target);
    if (!_firstChunkOfAnswer && lastEnd + 1 < target) {
      // Conversational Chinese runs a long way between full stops. Once
      // twice the target has gone by with no sentence in sight, a clause is
      // a better seam than waiting: the alternative is one chunk of five
      // sentences, which is fifteen seconds an interruption throws away and
      // fifteen seconds of prosody drifting away from its neighbours.
      final int clause = _lastClauseEnd(undispatched);
      if (clause + 1 >= target * 2) {
        lastEnd = _clauseEndNear(undispatched, target);
      }
    }
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
    if (!_firstChunkOfAnswer && lastEnd + 1 < _chunkTargetForAnswer) {
      return;
    }
    final String chunk = undispatched.substring(0, lastEnd + 1);
    _dispatchedOfActive += chunk.length;
    _firstChunkOfAnswer = false;
    _speakAloud(chunk, decidedBy: text);
  }

  /// The first sentence boundary in [text] at or past [target] that is safe
  /// to speak through, or the last one available when none reaches it.
  ///
  /// The target is a minimum, and taking the last boundary instead made it a
  /// minimum with no maximum: whenever generation ran ahead of speech, one
  /// chunk swallowed every sentence that had arrived. Chunks measured in use
  /// ranged from 5 to 140 characters, the largest ten seconds of audio. Each
  /// is synthesised alone with no acoustic context from the one before, so
  /// uneven chunks are heard as the speaker changing — and a ten-second
  /// chunk is ten seconds an interruption throws away.
  static int _sentenceEndNear(String text, int target) {
    final int last = _lastSentenceEnd(text);
    if (last < 0) {
      return -1;
    }
    for (int i = 0; i <= last; i++) {
      if (i + 1 >= target && _isSentenceEndAt(text, i)) {
        return i;
      }
    }
    return last;
  }

  /// Whether [text] ends a sentence at [i], with the decimal-point guard.
  static bool _isSentenceEndAt(String text, int i) {
    if (!_sentenceEnd.hasMatch(text[i])) {
      return false;
    }
    if (text[i] == '.') {
      if (i + 1 < text.length) {
        if (_isDigit(text.codeUnitAt(i + 1))) {
          return false;
        }
      } else if (i > 0 && _isDigit(text.codeUnitAt(i - 1))) {
        return false;
      }
    }
    return true;
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

  /// The first clause boundary in [text] at or past [target].
  static int _clauseEndNear(String text, int target) {
    for (int i = target - 1; i < text.length - 1; i++) {
      if (i < 0) {
        continue;
      }
      if (_clauseEnds.contains(text[i]) && !_isDigit(text.codeUnitAt(i + 1))) {
        return i;
      }
    }
    return _lastClauseEnd(text);
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
      debugPrint(
        'Lulo speak: DROPPED — ${text.length} chars left nothing sayable',
      );
      return;
    }
    debugPrint('Lulo speak: dispatching ${spoken.length} chars');
    _activeLang ??= _cjk.hasMatch(decidedBy ?? text) ? 'zh' : 'en';
    _speechRequested = true;
    // Held so an interruption can put it back. The dispatch counters record
    // what was handed to the voice, not what was heard, so without this the
    // sentence the user talked over is lost the moment it is cut.
    _speechOutstanding.add(spoken);
    // Remembered with the sentences, not looked up at interruption time:
    // an answer finishing its turn clears _activeLang while its sentences
    // are still being heard.
    _outstandingLang = _activeLang;
    notifyListeners();
    unawaited(_voice.speak(spoken, language: _activeLang));
  }

  /// Whether the push-to-talk button is currently held.
  bool get holdingToTalk => _pttHeld;

  /// Whether the current answer came from held speech: it yields to
  /// nothing but the next hold.
  bool get answerShielded => _pttProtected;

  /// Push-to-talk pressed: the agent falls silent and held speech starts
  /// composing. Nothing submits until the release. A press while the
  /// voice is off turns it on first — the press IS the intent to talk.
  void holdToTalkPressed({bool withBatchRecognition = false}) {
    if (_disposed) {
      return;
    }
    _holdIntent = true;
    _holdIntentBatch = withBatchRecognition;
    if (!_enabled) {
      if (!_enabling) {
        unawaited(
          enable().then((_) {
            if (_holdIntent && _enabled) {
              _beginHold();
            }
          }),
        );
      }
      return;
    }
    _beginHold();
  }

  void _beginHold() {
    _pttHeld = true;
    _pttSettling = false;
    _pttFinals.clear();
    _pttProtected = false;
    _pttAwaitsBatch = _holdIntentBatch;
    _pttBatchText = null;
    _pttSubmitBackstop?.cancel();
    _pttSubmitBackstop = null;
    _cancelPendingResume();
    _pendingSettle?.cancel();
    _pendingSettle = null;
    if (_speaking || _speechRequested) {
      _speechRequested = false;
      _speechOutstanding.clear();
      unawaited(_voice.stopSpeaking());
    }
    if (!_conversation.canSubmit) {
      _stopRequestedForActive = true;
      unawaited(_conversation.stop());
    }
    notifyListeners();
  }

  /// Push-to-talk released: the question is done being spoken. Submits at
  /// once when the tail has already settled, otherwise waits for the
  /// trailing final with a backstop.
  void holdToTalkReleased() {
    _holdIntent = false;
    if (!_pttHeld) {
      return;
    }
    _pttHeld = false;
    _pttSettling = true;
    notifyListeners();
    if (_pttAwaitsBatch) {
      // The batch recogniser is listening to the same audio and answers
      // in a beat or two; Apple's streamed guess is only its backstop.
      _pttSubmitBackstop = _utteranceScheduler.schedule(
        _pttBatchWait,
        _submitHeldSpeech,
      );
    } else if (_partialTranscript.trim().isEmpty) {
      _submitHeldSpeech();
    } else {
      _pttSubmitBackstop = _utteranceScheduler.schedule(
        _pttTrailingWait,
        _submitHeldSpeech,
      );
    }
  }

  void _submitHeldSpeech() {
    if (!_pttSettling) {
      return;
    }
    _pttSettling = false;
    _pttSubmitBackstop?.cancel();
    _pttSubmitBackstop = null;
    final String question = (_pttBatchText ?? _pttFinals.join(' ')).trim();
    _pttBatchText = null;
    _pttFinals.clear();
    if (question.isEmpty || !_enabled) {
      notifyListeners();
      return;
    }
    _pttProtected = true;
    unawaited(_refineFinalUtterance(question));
    notifyListeners();
  }

  Future<void> _refineFinalUtterance(String raw) async {
    final int epoch = ++_refinementEpoch;
    final TranscriptRefinement refinement = await _transcriptRefiner.refine(
      TranscriptRefinementRequest(
        rawTranscript: raw,
        locale: 'zh-TW',
        protectedVocabulary: _protectedVocabulary(),
        deadline: const Duration(milliseconds: 250),
      ),
    );
    if (_disposed || !_enabled || epoch != _refinementEpoch) {
      return;
    }
    if (_conversation.canSubmit) {
      _cancelPendingResume();
      if (_speaking || _speechRequested) {
        unawaited(_voice.stopSpeaking());
      }
      unawaited(
        _conversation.submit(
          refinement.selectedTranscript,
          voiceInput: refinement,
        ),
      );
    } else {
      _pendingUtterance = refinement;
    }
  }

  /// Re-says the sentence an interruption cut off, if nothing replaced it.
  void _resumeInterruptedSpeech() {
    _pendingResume?.cancel();
    _pendingResume = null;
    final String? interrupted = _interruptedSpeech;
    final String? interruptedLang = _interruptedLang;
    _interruptedSpeech = null;
    _interruptedLang = null;
    notifyListeners();
    if (!_enabled || interrupted == null || _disposed) {
      return;
    }
    // Something took the floor for real: a question is being answered, or one
    // is queued behind the answer that was interrupted. Either way the old
    // sentence is no longer what the user is waiting for.
    if (!_conversation.canSubmit || _pendingUtterance != null) {
      return;
    }
    debugPrint('Lulo speak: resuming ${interrupted.length} chars');
    _speechRequested = true;
    _speechOutstanding
      ..clear()
      ..add(interrupted);
    _outstandingLang = interruptedLang;
    unawaited(_voice.speak(interrupted, language: interruptedLang));
  }

  void _cancelPendingResume() {
    _pendingResume?.cancel();
    _pendingResume = null;
    _interruptedSpeech = null;
    _interruptedLang = null;
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
    // Thinking becomes listening (or speaking) here, and nothing else on
    // this path tells the view.
    notifyListeners();
    if (_conversation.canSubmit) {
      // The generation has fully ended. The null-to-null active turn of a
      // prefill cancel never notifies, so the dispatch guard is lifted
      // here, where the end is always visible.
      _stopRequestedForActive = false;
    }
    final TranscriptRefinement? pending = _pendingUtterance;
    if (pending == null || !_enabled || !_conversation.canSubmit) {
      return;
    }
    _pendingUtterance = null;
    _cancelPendingResume();
    unawaited(
      _conversation.submit(pending.selectedTranscript, voiceInput: pending),
    );
  }

  /// Whether [text] is enough to take the floor from the agent.
  ///
  /// The threshold exists only for speech in progress; see
  /// [_charactersToInterruptSpeech].
  bool _takesTheFloor(String text) {
    if (!_deliveringAnswer) {
      return true;
    }
    return text.trim().runes.length >= _charactersToInterruptSpeech;
  }

  /// Whether an answer is in the middle of being delivered aloud.
  ///
  /// Deliberately wider than [_speaking]: the native side reports speech
  /// finished 300ms after the last chunk drains, and the next chunk needs
  /// enough new text to be worth synthesising. Whenever generation is slower
  /// than playback — routine for a local model on a long answer — there are
  /// gaps between chunks where nothing is technically speaking. Keying the
  /// interruption threshold on [_speaking] alone switched it off inside every
  /// one of those gaps, and a single misheard character could still end the
  /// answer.
  bool get _deliveringAnswer =>
      _speaking || _speechRequested || _speechOutstanding.isNotEmpty;

  /// The user started talking: whatever the agent was saying or still
  /// generating gives way.
  void _yieldToTheUser({required String from}) {
    if (_pttHeld || _pttSettling || _pttProtected) {
      // Push-to-talk owns the floor: the press already silenced the
      // agent, and its answer yields to nothing but the next press.
      return;
    }
    final bool cancelling = !_conversation.canSubmit;
    debugPrint(
      'Lulo yield: from=$from speaking=$_speaking '
      'requested=$_speechRequested cancelsGeneration=$cancelling',
    );
    if (_deliveringAnswer) {
      // What is being cut off is held for [_resumeDelay]: if the user turns
      // out to be asking something, that wins and this is dropped; if they
      // were only reacting, the answer picks up instead of going silent for
      // the rest of its life.
      _interruptedSpeech = _speechOutstanding.isEmpty
          ? null
          : _speechOutstanding.join();
      _interruptedLang = _outstandingLang;
      _speechOutstanding.clear();
      _pendingResume?.cancel();
      _pendingResume = _utteranceScheduler.schedule(
        _resumeDelay,
        _resumeInterruptedSpeech,
      );
      notifyListeners();
      unawaited(_voice.stopSpeaking());
    }
    if (cancelling) {
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
          (turn.status == TurnStatus.cancelled ||
              turn.status == TurnStatus.failed)) {
        // The answer was stopped, so stop saying it. Cancelling ends the
        // writing; the sentences already handed to the voice are minutes of
        // speech that outlive it, and until this the only way to shut them
        // up was switching the microphone off — which also stops listening,
        // which is not what stop means.
        debugPrint(
          'Lulo turn: ${turn.status.name} — NOT SPOKEN '
          '(${turn.text.length} chars written, $_dispatchedOfActive already out)',
        );
        // The answer is over, so there is nothing left to put back. Without
        // this the interruption that ended it would, a moment later, read one
        // orphaned sentence of an answer already abandoned.
        _cancelPendingResume();
        _speechOutstanding.clear();
        _dispatchedOfActive = 0;
        if (_speaking || _speechRequested) {
          _speechRequested = false;
          unawaited(_voice.stopSpeaking());
        }
        continue;
      }
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
    _refinementEpoch += 1;
    _pendingSettle?.cancel();
    _pendingSettle = null;
    _cancelPendingResume();
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

List<String> _noProtectedVocabulary() => const <String>[];

final class _RawTranscriptRefiner implements TranscriptRefiner {
  const _RawTranscriptRefiner();

  @override
  Future<TranscriptRefinement> refine(
    TranscriptRefinementRequest request,
  ) async => TranscriptRefinement(
    rawTranscript: request.rawTranscript,
    proposedTranscript: null,
    selectedTranscript: request.rawTranscript,
    status: TranscriptRefinementStatus.unchanged,
    edits: const <TranscriptEdit>[],
    rejectionReasons: const <TranscriptRejectionReason>[],
    refinerId: 'raw-pass-through',
    refinerVersion: '1',
    elapsed: Duration.zero,
  );
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
  // Horizontal rules and list markers are layout, not words: "---" read
  // aloud is a groan, and "- 第一點" starts with a minus.
  speakable = speakable.replaceAll(
    RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true),
    ' ',
  );
  speakable = speakable.replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '');
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
