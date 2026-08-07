import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

/// What the app opens on when it has nothing to think with.
void main() {
  Future<void> pumpApp(WidgetTester tester, {required String modelPath}) async {
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      settingsStore: InMemorySettingsStore(AppSettings(modelPath: modelPath)),
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
  }

  testWidgets('with no model the app opens on what it still needs', (
    WidgetTester tester,
  ) async {
    // The conversation behind this answers from a built-in preview that says
    // the same thing every time. Letting the user talk to that first is the
    // app pretending to work.
    await pumpApp(tester, modelPath: '');

    expect(find.byKey(const Key('first-run')), findsOneWidget);
  });

  testWidgets('declining it leaves the conversation reachable', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, modelPath: '');

    await tester.tap(find.byKey(const Key('first-run-dismiss')));
    await tester.pump();

    expect(find.byKey(const Key('first-run')), findsNothing);
    expect(
      find.byKey(const Key('conversation-composer-field')),
      findsOneWidget,
    );
  });

  testWidgets('with a model chosen it is never in the way', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, modelPath: '/models/already-here.litertlm');

    expect(find.byKey(const Key('first-run')), findsNothing);
  });
}
