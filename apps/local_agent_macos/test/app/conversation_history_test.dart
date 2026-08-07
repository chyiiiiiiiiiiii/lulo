import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

void main() {
  const ConversationId yesterday = ConversationId('conversation-yesterday');
  const ConversationId older = ConversationId('conversation-older');

  Turn user(String text) =>
      Turn(role: TurnRole.user, text: text, status: TurnStatus.completed);

  Future<InMemoryConversationStorageService> storeWithHistory() async {
    final InMemoryConversationStorageService store =
        InMemoryConversationStorageService();
    await store.saveUserTurn(older, user('an older thread'));
    await store.saveUserTurn(yesterday, user('what we talked about'));
    return store;
  }

  Future<FakePresentationHost> pumpApp(
    WidgetTester tester,
    InMemoryConversationStorageService store,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: store,
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      // A model already chosen: with none the app opens on the first-run
      // offer, which is the right thing for a first launch and not what
      // these tests are about.
      settingsStore: InMemorySettingsStore(
        const AppSettings(modelPath: '/models/already-here.litertlm'),
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
    // Twice: once for the stage geometry, once for the restore to land.
    await tester.pump();
    await tester.pump();
    return host;
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('conversation-history-button')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the header opens the list of conversations', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, await storeWithHistory());

    await openHistory(tester);

    expect(find.byKey(const Key('conversation-history-sheet')), findsOneWidget);
    expect(find.text('an older thread'), findsOneWidget);
  });

  testWidgets('choosing a conversation returns to it', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, await storeWithHistory());
    // The most recent conversation was resumed at launch.
    expect(find.text('what we talked about'), findsOneWidget);

    await openHistory(tester);
    await tester.tap(find.byKey(Key('conversation-row-${older.value}')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('conversation-history-sheet')), findsNothing);
    expect(find.text('an older thread'), findsOneWidget);
    expect(find.text('what we talked about'), findsNothing);
  });

  testWidgets('a new conversation starts empty', (WidgetTester tester) async {
    await pumpApp(tester, await storeWithHistory());
    expect(find.text('what we talked about'), findsOneWidget);

    await openHistory(tester);
    await tester.tap(find.byKey(const Key('conversation-new-button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('conversation-history-sheet')), findsNothing);
    expect(find.text('what we talked about'), findsNothing);
    expect(find.text('an older thread'), findsNothing);
  });

  testWidgets('forgetting a conversation removes it from the list', (
    WidgetTester tester,
  ) async {
    final InMemoryConversationStorageService store = await storeWithHistory();
    await pumpApp(tester, store);

    await openHistory(tester);
    // Forgetting is behind the row's menu now. Pumped by hand rather than
    // settled: the presence animates continuously, so this app never has a
    // settled frame to wait for.
    await tester.tap(find.byKey(Key('conversation-menu-${older.value}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(Key('conversation-delete-${older.value}')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('conversation-history-sheet')), findsOneWidget);
    expect(find.text('an older thread'), findsNothing);
    expect(
      (await store.listConversations()).map(
        (ConversationSummary summary) => summary.id,
      ),
      <ConversationId>[yesterday],
    );
  });

  testWidgets('a draft survives deleting a conversation that is not open', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, await storeWithHistory());

    // Forget the open conversation: the view deliberately starts fresh.
    await openHistory(tester);
    // Forgetting is behind the row's menu now.
    await tester.tap(find.byKey(Key('conversation-menu-${yesterday.value}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(Key('conversation-delete-${yesterday.value}')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('conversation-history-close-button')),
    );
    await tester.pump();

    // The user starts writing in the fresh conversation...
    await tester.enterText(
      find.byKey(const Key('conversation-composer-field')),
      'a draft worth keeping',
    );
    await tester.pump();

    // ...then tidies away another stored conversation. That one is not what
    // the view holds, so the draft must not be torn down with it.
    await openHistory(tester);
    // Forgetting is behind the row's menu now. Pumped by hand rather than
    // settled: the presence animates continuously, so this app never has a
    // settled frame to wait for.
    await tester.tap(find.byKey(Key('conversation-menu-${older.value}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(Key('conversation-delete-${older.value}')));
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('conversation-history-close-button')),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('conversation-composer-field')),
          )
          .controller
          ?.text,
      'a draft worth keeping',
      reason: 'Deleting an unrelated conversation discarded the draft.',
    );
  });

  testWidgets('forgetting the conversation being looked at starts fresh', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, await storeWithHistory());
    expect(find.text('what we talked about'), findsOneWidget);

    await openHistory(tester);
    // Forgetting is behind the row's menu now.
    await tester.tap(find.byKey(Key('conversation-menu-${yesterday.value}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(Key('conversation-delete-${yesterday.value}')));
    await tester.pump();
    await tester.pump();

    // The sheet stays up for further tidying; behind it the forgotten
    // conversation is no longer what the view holds.
    await tester.tap(
      find.byKey(const Key('conversation-history-close-button')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('what we talked about'), findsNothing);
  });
}
