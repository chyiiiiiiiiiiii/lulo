import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/voice/pigeon_voice_service.dart';

import '../../support/recording_voice_host_api.dart';

/// The respelling exists between the text and the synthesiser, and nowhere
/// else. This is the one place it is applied, so this is where that is held.
void main() {
  // Constructing the service registers its event handler, which needs the
  // binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the voice is handed the respelling, not the real word', () async {
    final RecordingVoiceHostApi host = RecordingVoiceHostApi();
    final PigeonVoiceService voice = PigeonVoiceService(
      hostApi: host,
      respellings: () => const <SpokenRespelling>[
        SpokenRespelling(word: '企業', saidAs: '氣業'),
      ],
    );

    await voice.speak('這家企業很大');

    expect(host.spoken.single, '這家氣業很大');
  });

  test('a table taught after the service was built still applies', () async {
    // Read at every utterance rather than captured, so a word taught in
    // Settings is said properly in the very next sentence.
    final RecordingVoiceHostApi host = RecordingVoiceHostApi();
    List<SpokenRespelling> table = const <SpokenRespelling>[];
    final PigeonVoiceService voice = PigeonVoiceService(
      hostApi: host,
      respellings: () => table,
    );

    await voice.speak('這家企業很大');
    table = const <SpokenRespelling>[
      SpokenRespelling(word: '企業', saidAs: '氣業'),
    ];
    await voice.speak('這家企業很大');

    expect(host.spoken, <String>['這家企業很大', '這家氣業很大']);
  });

  test('a voice with no table says exactly what it was given', () async {
    final RecordingVoiceHostApi host = RecordingVoiceHostApi();
    final PigeonVoiceService voice = PigeonVoiceService(hostApi: host);

    await voice.speak('這家企業很大');

    expect(host.spoken.single, '這家企業很大');
  });
}
