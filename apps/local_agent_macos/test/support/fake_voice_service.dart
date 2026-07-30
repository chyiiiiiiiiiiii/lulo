import 'dart:async';

import 'package:local_agent_macos/features/voice/voice_service.dart';

/// A voice pipeline the tests hold in their hand.
final class FakeVoiceService implements VoiceService {
  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  /// Every call made, in order, by name.
  final List<String> calls = <String>[];

  /// Everything asked to be spoken, in order.
  final List<String> spoken = <String>[];

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<void> startListening() async {
    calls.add('startListening');
    _events.add(const ListeningStarted());
  }

  @override
  Future<void> stopListening() async {
    calls.add('stopListening');
    _events.add(const ListeningStopped());
  }

  @override
  Future<void> speak(String text) async {
    calls.add('speak');
    spoken.add(text);
    _events.add(const SpeakingStarted());
  }

  @override
  Future<void> stopSpeaking() async {
    calls.add('stopSpeaking');
    _events.add(const SpeakingFinished());
  }

  /// Stands in for the transcriber hearing the user.
  void hear(VoiceEvent event) => _events.add(event);

  /// Releases the event stream.
  Future<void> dispose() => _events.close();
}
