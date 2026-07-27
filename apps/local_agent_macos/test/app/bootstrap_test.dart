import 'package:flutter_test/flutter_test.dart';
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
