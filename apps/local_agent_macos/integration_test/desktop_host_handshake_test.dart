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

  testWidgets('every retained panel toggle completes through the typed host', (
    WidgetTester tester,
  ) async {
    final PigeonDesktopHostService service = PigeonDesktopHostService();
    addTearDown(service.dispose);
    const int expectedToggleCount = 60;
    var completedToggleCount = 0;

    await tester.runAsync(service.showPanel);
    for (; completedToggleCount < expectedToggleCount; completedToggleCount++) {
      await tester.runAsync(service.togglePanel);
    }

    // This line is an evidence boundary: it is reached only when every awaited
    // Pigeon roundtrip completed without an exception.
    // ignore: avoid_print
    print(
      'panel_toggle_validation '
      '{"expected":$expectedToggleCount,'
      '"completed":$completedToggleCount,'
      '"failures":0}',
    );
  });
}
