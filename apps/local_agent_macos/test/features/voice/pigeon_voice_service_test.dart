import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/voice/pigeon_voice_service.dart';
import 'package:local_agent_macos/features/voice/voice_service.dart';
import 'package:local_agent_macos/generated/voice_host_api.g.dart';

/// The native side, held in the test's hand.
final class _RecordingHost extends VoiceHostApi {
  final List<String> calls = <String>[];

  /// Just the words handed to the synthesiser, without the call's framing —
  /// which carries dashes of its own for the absent voice and language.
  final List<String> spoken = <String>[];
  Object? failWith;

  Future<void> _call(String name) async {
    calls.add(name);
    final Object? failure = failWith;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<void> startListening() => _call('startListening');

  @override
  Future<void> stopListening() => _call('stopListening');

  @override
  Future<void> finalizeUtterance() => _call('finalizeUtterance');

  @override
  Future<void> speak(String text, String? voice, String? language) {
    spoken.add(text);
    return _call('speak:$text:${voice ?? "-"}:${language ?? "-"}');
  }

  @override
  Future<void> stopSpeaking() => _call('stopSpeaking');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('what the voice is handed has no markup left in it', () async {
    // The read-aloud button hands an answer straight here, and a 4B model
    // told not to write Markdown writes it anyway. Only the voice loop
    // stripped it, so pressing the button read "井字號井字號井字號" and
    // every list item began with a minus. This is the one place text
    // leaves for the voice, so it is where the stripping belongs.
    final _RecordingHost host = _RecordingHost();
    final PigeonVoiceService service = PigeonVoiceService(hostApi: host);

    await service.speak(
      '### 建議\n\n- 先熱身\n- 再訓練\n\n```dart\nvoid main() {}\n```',
    );

    expect(host.spoken.single, isNot(contains('#')));
    expect(host.spoken.single, isNot(contains('-')));
    expect(host.spoken.single, isNot(contains('`')));
    expect(host.spoken.single, contains('建議'));
    expect(host.spoken.single, contains('先熱身'));
    expect(host.spoken.single, isNot(contains('void main')));
  });

  test('drives the native host and relays its events', () async {
    final _RecordingHost host = _RecordingHost();
    final PigeonVoiceService service = PigeonVoiceService(hostApi: host);
    final List<VoiceEvent> events = <VoiceEvent>[];
    service.events.listen(events.add);

    await service.startListening();
    await service.speak('Sunny, all day.');
    await service.stopSpeaking();
    await service.stopListening();
    expect(host.calls, <String>[
      'startListening',
      'speak:Sunny, all day.:-:-',
      'stopSpeaking',
      'stopListening',
    ]);

    service.onVoiceEvent(
      HostVoiceEvent(type: HostVoiceEventType.listeningStarted),
    );
    service.onVoiceEvent(
      HostVoiceEvent(type: HostVoiceEventType.partialTranscript, text: 'wh'),
    );
    service.onVoiceEvent(
      HostVoiceEvent(
        type: HostVoiceEventType.finalTranscript,
        text: 'what time is it',
      ),
    );
    service.onVoiceEvent(
      HostVoiceEvent(type: HostVoiceEventType.speakingStarted),
    );
    service.onVoiceEvent(
      HostVoiceEvent(type: HostVoiceEventType.speakingFinished),
    );
    service.onVoiceEvent(
      HostVoiceEvent(
        type: HostVoiceEventType.voiceFailed,
        text: 'the microphone went away',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(6));
    expect(events[0], isA<ListeningStarted>());
    expect((events[1] as PartialTranscript).text, 'wh');
    expect((events[2] as FinalTranscript).text, 'what time is it');
    expect(events[3], isA<SpeakingStarted>());
    expect(events[4], isA<SpeakingFinished>());
    expect((events[5] as VoiceFailed).message, 'the microphone went away');

    await service.dispose();
  });

  test('a host that fails becomes a voice failure, not a crash', () async {
    final _RecordingHost host = _RecordingHost()
      ..failWith = Exception('no microphone permission');
    final PigeonVoiceService service = PigeonVoiceService(hostApi: host);
    final List<VoiceEvent> events = <VoiceEvent>[];
    service.events.listen(events.add);

    await service.startListening();
    await Future<void>.delayed(Duration.zero);

    expect(events.single, isA<VoiceFailed>());
    expect(
      (events.single as VoiceFailed).message,
      contains('no microphone permission'),
    );
    await service.dispose();
  });
}
