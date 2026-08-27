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

/// ⌘N and ⇧⌘O, which every assistant on this desktop answers.
///
/// Both actions already existed on this side and had no way in but the
/// history sheet, so what is covered here is the wiring: a menu item built
/// natively and connected to nothing looks exactly like one that works.
void main() {
  Future<FakePresentationHost> pumpApp(WidgetTester tester) async {
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      settingsStore: InMemorySettingsStore(
        const AppSettings(modelPath: '/models/gemma.litertlm'),
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
    await tester.pump(const Duration(milliseconds: 50));
    return host;
  }

  testWidgets('File ▸ Conversations… puts the stored ones in front', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = await pumpApp(tester);
    expect(find.byKey(const Key('conversation-history-sheet')), findsNothing);

    host.conversationLists.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('conversation-history-sheet')), findsOneWidget);
  });

  testWidgets('File ▸ New starts an empty one', (WidgetTester tester) async {
    final FakePresentationHost host = await pumpApp(tester);
    await tester.enterText(
      find.byKey(const Key('conversation-composer-field')),
      '半途而廢的問題',
    );
    await tester.pump();

    host.newConversations.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('半途而廢的問題'),
      findsNothing,
      reason: 'a new conversation kept the last one on screen',
    );
  });
}
