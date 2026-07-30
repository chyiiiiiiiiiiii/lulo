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
    _spokenThrough = _conversation.completedTurnsListenable.value.length;
  }

  final VoiceService _voice;
  final ConversationViewModel _conversation;
  StreamSubscription<VoiceEvent>? _events;

  bool _enabled = false;
  bool _speaking = false;
  String _partialTranscript = '';

  /// How many completed turns have already been considered for speaking.
  ///
  /// Seeded with what is already there, so enabling voice over yesterday's
  /// conversation does not recite it.
  int _spokenThrough = 0;

  /// Whether the conversation is currently being run by voice.
  bool get enabled => _enabled;

  /// Whether the agent is being spoken aloud right now.
  bool get speaking => _speaking;

  /// What is being heard, before the transcriber settles it.
  String get partialTranscript => _partialTranscript;

  /// Opens the ears and starts running the conversation by voice.
  Future<void> enable() async {
    if (_enabled) {
      return;
    }
    _enabled = true;
    _spokenThrough = _conversation.completedTurnsListenable.value.length;
    notifyListeners();
    await _voice.startListening();
  }

  /// Releases the ears and the voice.
  Future<void> disable() async {
    if (!_enabled) {
      return;
    }
    _enabled = false;
    _partialTranscript = '';
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
        if (text.trim().isNotEmpty) {
          unawaited(_conversation.submit(text));
        }
      case SpeakingStarted():
        _speaking = true;
        notifyListeners();
      case SpeakingFinished():
        _speaking = false;
        notifyListeners();
      case ListeningStarted() || ListeningStopped() || VoiceFailed():
        notifyListeners();
    }
  }

  /// The user started talking: whatever the agent was saying or still
  /// generating gives way.
  void _yieldToTheUser() {
    if (_speaking) {
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
        unawaited(_voice.speak(turn.text));
      }
    }
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _events = null;
    _conversation.completedTurnsListenable.removeListener(_onTurnsChanged);
    super.dispose();
  }
}
