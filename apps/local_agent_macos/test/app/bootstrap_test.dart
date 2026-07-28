import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local bootstrap keeps the app local-only at 120 frames per second', () {
    final BootstrapConfig config = createBootstrapConfig();

    expect(config.localOnly, isTrue);
    expect(config.targetFrameRate, 120);
  });

  test('bootstrap rejects an unsupported inference runtime', () {
    expect(
      () => createAppComposition(inferenceRuntime: 'remote'),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError error) => error.message,
          'message',
          contains('remote'),
        ),
      ),
    );
  });

  test('bootstrap accepts an explicit LiteRT runtime and model path', () async {
    final composition = createAppComposition(
      inferenceRuntime: 'litert',
      localModelPath: '/models/gemma-4-E4B-it.litertlm',
    );

    await composition.dispose();
  });

  test('every runtime gives the app its desktop presence', () async {
    // The desktop form is how the agent is reached, not a property of which
    // runtime answers it. A composition without a presentation host renders
    // the conversation straight into the window, which at rest is orb-sized.
    for (final String runtime in <String>['fake', 'litert']) {
      final AppComposition composition = createAppComposition(
        inferenceRuntime: runtime,
        localModelPath: '/models/gemma-4-E4B-it.litertlm',
      );

      expect(
        composition.presentationHost,
        isNotNull,
        reason: 'The $runtime runtime bootstrapped without a desktop host.',
      );

      await composition.dispose();
    }
  });

  test('LiteRT bootstrap rejects a missing model path', () {
    expect(
      () => createAppComposition(
        inferenceRuntime: 'litert',
        localModelPath: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
