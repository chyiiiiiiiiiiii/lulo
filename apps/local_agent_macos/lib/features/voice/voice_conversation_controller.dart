import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../conversation/conversation_view_model.dart';
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
  }) : this._(voice, conversation);

  VoiceConversationController._(this._voice, this._conversation) {
    _events = _voice.events.listen(_onVoiceEvent);
    _conversation.completedTurnsListenable.addListener(_onTurnsChanged);
    _conversation.canSubmitListenable.addListener(_onCanSubmitChanged);
    _spokenThrough = _conversation.completedTurnsListenable.value.length;
  }

  final VoiceService _voice;
  final ConversationViewModel _conversation;
  StreamSubscription<VoiceEvent>? _events;

  bool _enabled = false;

  /// True while [enable] is waiting for the stored history to land.
  bool _enabling = false;
  bool _disposed = false;
  bool _speaking = false;

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

  /// How many completed turns have already been considered for speaking.
  ///
  /// Seeded with what is already there, so enabling voice over yesterday's
  /// conversation does not recite it.
  int _spokenThrough = 0;

  /// Whether the conversation is currently being run by voice.
  bool get enabled => _enabled || _enabling;

  /// Whether the agent is being spoken aloud right now.
  bool get speaking => _speaking;

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
          _yieldToTheUser();
        }
      case FinalTranscript(:final String text):
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
      case ListeningStarted() || ListeningStopped():
        notifyListeners();
    }
  }

  void _onCanSubmitChanged() {
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
          turn.status == TurnStatus.completed &&
          turn.text.trim().isNotEmpty) {
        _speechRequested = true;
        unawaited(_voice.speak(turn.text));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
    super.dispose();
  }
}
