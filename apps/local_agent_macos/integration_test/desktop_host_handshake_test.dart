import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/generated/desktop_host_api.g.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';
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

  testWidgets(
    'typed local runtime lifecycle reaches the deterministic native backend',
    (WidgetTester tester) async {
      final PigeonDesktopHostService service = PigeonDesktopHostService();
      addTearDown(service.dispose);
      final Future<void> orderedEvents = expectLater(
        service.generationEvents,
        emitsInOrder(<Object>[
          isA<DesktopGenerationEvent>()
              .having(
                (DesktopGenerationEvent event) => event.generationId,
                'generationId',
                'generation-integration',
              )
              .having(
                (DesktopGenerationEvent event) => event.type,
                'type',
                HostGenerationEventType.started,
              ),
          isA<DesktopGenerationEvent>()
              .having(
                (DesktopGenerationEvent event) => event.sequence,
                'sequence',
                2,
              )
              .having(
                (DesktopGenerationEvent event) => event.delta,
                'delta',
                'Deterministic response.',
              ),
          isA<DesktopGenerationEvent>()
              .having(
                (DesktopGenerationEvent event) => event.sequence,
                'sequence',
                3,
              )
              .having(
                (DesktopGenerationEvent event) => event.type,
                'type',
                HostGenerationEventType.completed,
              ),
        ]),
      );

      final DesktopRuntimeCapabilities? capabilities = await tester.runAsync(
        service.handshake,
      );
      final DesktopModelLoadResult? loadResult = await tester.runAsync(
        () => service.loadModel(
          const DesktopModelRequest(
            modelId: 'deterministic-model',
            modelPath: '/path/that/does/not/exist.bin',
            contextSize: 4096,
          ),
        ),
      );
      await tester.runAsync(
        () => service.startGeneration(
          const DesktopGenerationRequest(
            generationId: 'generation-integration',
            sessionId: 'session-integration',
            prompt: 'private prompt',
            context: <String>['private context'],
            temperature: 0.25,
            topP: 0.9,
            maxTokens: 128,
            seed: 7,
          ),
        ),
      );
      await orderedEvents;
      final DesktopCancellationAcknowledgement? cancellation = await tester
          .runAsync(() => service.cancelGeneration('generation-integration'));
      final DesktopOperationCompletion? reset = await tester.runAsync(
        () => service.resetSession('session-integration'),
      );
      final DesktopOperationCompletion? unload = await tester.runAsync(
        service.unloadModel,
      );

      expect(capabilities?.runtimeName, 'deterministic');
      expect(capabilities?.schemaVersion, DesktopHostService.schemaVersion);
      expect(loadResult?.loaded, isTrue);
      expect(cancellation?.acknowledged, isTrue);
      expect(reset?.completed, isTrue);
      expect(unload?.completed, isTrue);
    },
  );

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
