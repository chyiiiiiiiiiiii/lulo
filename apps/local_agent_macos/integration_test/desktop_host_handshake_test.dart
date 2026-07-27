import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/platform/pigeon_desktop_host_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typed host handshake reaches the retained native panel', (
    WidgetTester tester,
  ) async {
    final PigeonDesktopHostService service = PigeonDesktopHostService();
    addTearDown(service.dispose);

    await tester.runAsync(service.showPanel);
    await tester.runAsync(service.hidePanel);
    await tester.runAsync(service.showPanel);
  });
}
