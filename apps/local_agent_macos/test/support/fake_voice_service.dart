import 'dart:async';

import 'package:local_agent_macos/features/voice/voice_service.dart';

/// A voice pipeline the tests hold in their hand.
///
/// Events are delivered asynchronously, the way the real pigeon channel
/// delivers them: a fake that answers synchronously hides every race the
/// round trip creates.
final class FakeVoiceService implements VoiceService {
  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  /// Every call made, in order, by name.
  final List<String> calls = <String>[];

  /// Every list of unfinished endings pushed to the endpointer, in order.
  final List<List<String>> unfinishedEndings = <List<String>>[];

  /// Every vocabulary pushed to the recogniser, in order.
  final List<List<String>> spokenVocabulary = <List<String>>[];

  /// Everything asked to be spoken, in order.
  final List<String> spoken = <String>[];

  /// When set, [speak] does not announce [SpeakingStarted] by itself; the
  /// test does, via [announceSpeaking] — the window where the user can talk
  /// over an answer whose start has not come back yet.
  bool holdSpeakingStarted = false;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<void> useUnfinishedEndings(List<String> endings) async {
    calls.add('useUnfinishedEndings');
    unfinishedEndings.add(List<String>.unmodifiable(endings));
  }

  @override
  Future<void> useSpokenVocabulary(List<String> terms) async {
    calls.add('useSpokenVocabulary');
    spokenVocabulary.add(List<String>.unmodifiable(terms));
  }

  @override
  Future<void> startListening() async {
    calls.add('startListening');
    hear(const ListeningStarted());
  }

  @override
  Future<void> stopListening() async {
    calls.add('stopListening');
    hear(const ListeningStopped());
  }

  @override
  Future<void> finalizeUtterance() async {
    calls.add('finalizeUtterance');
  }

  /// The language pinned to each spoken utterance, in order.
  final List<String?> spokenLanguages = <String?>[];

  @override
  Future<void> speak(String text, {String? language}) async {
    calls.add('speak');
    spoken.add(text);
    spokenLanguages.add(language);
    if (!holdSpeakingStarted) {
      hear(const SpeakingStarted());
    }
  }

  /// Delivers the held [SpeakingStarted], as the delegate callback would.
  void announceSpeaking() => hear(const SpeakingStarted());

  @override
  Future<void> stopSpeaking() async {
    calls.add('stopSpeaking');
    hear(const SpeakingFinished());
  }

  /// Stands in for the pipeline reporting [event], one round trip later.
  void hear(VoiceEvent event) {
    scheduleMicrotask(() {
      if (!_events.isClosed) {
        _events.add(event);
      }
    });
  }

  /// Releases the event stream.
  Future<void> dispose() => _events.close();
}
