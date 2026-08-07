import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

/// A setting is only a setting once something acts on it.
///
/// Everything between the sheet and the agent was covered — the sheet wrote
/// the value, the store round-tripped it, the service read its notifier — and
/// the one line joining them was not. Deleting it left every test green and
/// the choice with no effect at all.
void main() {
  testWidgets('a chosen answer style reaches the running agent', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      settingsStore: InMemorySettingsStore(
        const AppSettings(
          modelPath: '/models/already-here.litertlm',
          answerStyle: AnswerStyle.inventive,
        ),
      ),
    );
    addTearDown(() => unawaited(composition.dispose()));
    host.presentation.value = DesktopPresentation.expanded;

    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      composition.answerStyle.value,
      AnswerStyle.inventive,
      reason: 'the stored style never reached the thing that answers',
    );
  });
}
