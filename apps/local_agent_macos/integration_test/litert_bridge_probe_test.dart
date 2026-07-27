import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/features/conversation/pigeon_inference_service.dart';
import 'package:local_agent_macos/platform/pigeon_desktop_host_service.dart';

/// Absolute path to the installed Gemma 4 E4B model, inside the app sandbox.
const String _modelPath = String.fromEnvironment('LOCAL_MODEL_PATH');

/// Exercises the native boundary without the conversation UI.
///
/// When the widget-level slice fails, this isolates whether the fault is in
/// the Dart-to-native bridge or in the presentation layer above it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the native bridge streams real Gemma events',
    (WidgetTester tester) async {
      expect(_modelPath, isNotEmpty);

      final PigeonDesktopHostService host = PigeonDesktopHostService();
      final PigeonInferenceService service = PigeonInferenceService(
        desktopHostService: host,
        config: LocalModelConfig(
          modelId: 'gemma-4-E4B-it',
          modelPath: _modelPath,
          contextSize: 4096,
          temperature: 0.7,
          topP: 0.95,
          maxTokens: 48,
          seed: 7,
        ),
      );

      final List<String> observed = <String>[];
      final StringBuffer text = StringBuffer();

      await for (final GenerationEvent event in service.generate(
        const GenerationRequest(
          conversationId: ConversationId('probe-conversation'),
          prompt: 'Reply with exactly one short sentence about local AI.',
        ),
      )) {
        switch (event) {
          case GenerationStarted():
            observed.add('started');
          case GenerationDelta(:final String delta):
            observed.add('delta');
            text.write(delta);
          case GenerationCompleted():
            observed.add('completed');
          case GenerationCancelled():
            observed.add('cancelled');
          case GenerationFailed():
            observed.add('failed');
        }
      }

      await service.dispose();
      await host.dispose();

      expect(observed.first, 'started');
      expect(observed.last, 'completed');
      expect(
        observed.where((String kind) => kind == 'delta'),
        isNotEmpty,
        reason: 'Real generation must stream at least one delta.',
      );
      expect(text.toString().trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
