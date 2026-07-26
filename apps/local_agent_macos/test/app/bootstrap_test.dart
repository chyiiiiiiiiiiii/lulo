import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/bootstrap.dart';

void main() {
  test('local bootstrap keeps the app local-only at 120 frames per second', () {
    final BootstrapConfig config = createBootstrapConfig();

    expect(config.localOnly, isTrue);
    expect(config.targetFrameRate, 120);
  });
}
