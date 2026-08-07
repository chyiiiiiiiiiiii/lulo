import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

/// What the status-bar menu is told, which is the only thing it can show.
///
/// The menu is built by AppKit at the moment it opens, so anything Dart has
/// not already pushed is not there. A menu wired up but never told anything
/// is the failure this covers, and it is invisible from the native side.
void main() {
  Future<(FakePresentationHost, AppComposition)> pumpApp(
    WidgetTester tester, {
    required InMemoryConversationStorageService store,
  }) async {
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: store,
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      settingsStore: InMemorySettingsStore(
        const AppSettings(modelPath: '/models/gemma-4-E4B-it.litertlm'),
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
    return (host, composition);
  }

  testWidgets('the menu is told what it needs before it is ever opened', (
    WidgetTester tester,
  ) async {
    final InMemoryConversationStorageService store =
        InMemoryConversationStorageService();
    await store.saveUserTurn(
      const ConversationId('yesterday'),
      const Turn(
        role: TurnRole.user,
        text: '明天台中天氣如何',
        status: TurnStatus.completed,
      ),
    );
    final (FakePresentationHost host, _) = await pumpApp(tester, store: store);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      host.menuBarStates,
      isNotEmpty,
      reason: 'the menu was wired up and never told anything',
    );
    final FakeMenuBarState latest = host.menuBarStates.last;
    expect(latest.conversations.single.title, '明天台中天氣如何');
    expect(latest.modelName, 'gemma-4-E4B-it.litertlm');
    // Every word the menu shows comes from here, because AppKit has no
    // localizations of its own.
    expect(latest.labels.quit, isNotEmpty);
    expect(latest.labels.activity, isNotEmpty);
  });

  testWidgets('choosing a conversation from the menu opens it', (
    WidgetTester tester,
  ) async {
    final InMemoryConversationStorageService store =
        InMemoryConversationStorageService();
    await store.saveUserTurn(
      const ConversationId('yesterday'),
      const Turn(
        role: TurnRole.user,
        text: '昨天說到哪',
        status: TurnStatus.completed,
      ),
    );
    final (FakePresentationHost host, _) = await pumpApp(tester, store: store);

    host.presentation.value = DesktopPresentation.orb;
    await tester.pump();
    host.menuConversations.add(const ConversationId('yesterday'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Brought forward as well as opened: changing something behind a hidden
    // window looks like the menu item did nothing.
    expect(host.presentation.value, DesktopPresentation.expanded);
  });

  testWidgets('forgetting a conversation takes it out of the menu too', (
    WidgetTester tester,
  ) async {
    // The menu holds a cached list on the native side, so anything that
    // changes the conversations has to push again. Without this the menu goes
    // on offering one the user has forgotten, and choosing it opens an empty
    // screen.
    final InMemoryConversationStorageService store =
        InMemoryConversationStorageService();
    await store.saveUserTurn(
      const ConversationId('yesterday'),
      const Turn(
        role: TurnRole.user,
        text: '要被忘掉的',
        status: TurnStatus.completed,
      ),
    );
    final (FakePresentationHost host, _) = await pumpApp(tester, store: store);
    await tester.pump(const Duration(milliseconds: 50));
    expect(host.menuBarStates.last.conversations, hasLength(1));

    await tester.tap(find.byKey(const Key('conversation-history-button')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-menu-yesterday')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('conversation-delete-yesterday')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      host.menuBarStates.last.conversations,
      isEmpty,
      reason: 'the menu still offers a conversation that no longer exists',
    );
  });

  testWidgets(
    'asking for voice from the menu asks the conversation to listen',
    (WidgetTester tester) async {
      // The item promises the microphone will open. Bringing the window
      // forward and stopping there makes it a second Show button wearing a
      // different name.
      final (FakePresentationHost host, AppComposition composition) =
          await pumpApp(tester, store: InMemoryConversationStorageService());
      final int before = composition.voiceRequests.value;

      host.menuVoice.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(composition.voiceRequests.value, greaterThan(before));
    },
  );
}
