import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';
import 'package:local_agent_macos/features/presence/notice/notice_glance_card.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  final PresenceNotice notice = PresenceNotice(
    kind: PresenceNoticeKind.memoryWrite,
    litAt: DateTime(2026, 8, 17, 9),
    summary: '使用者搬到台南了。',
  );

  AgentProfile profileWith(String content) => AgentProfile(
    memories: <AgentMemory>[
      AgentMemory(
        id: 'memory-1',
        kind: AgentMemoryKind.personal,
        content: content,
      ),
    ],
  );

  testWidgets('shows the kept sentence and who decided', (
    WidgetTester tester,
  ) async {
    final InMemoryAgentProfileStore store = InMemoryAgentProfileStore(
      profileWith('使用者搬到台南了。'),
    );
    addTearDown(store.dispose);
    bool dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoticeGlanceCard(
            notice: notice,
            profile: store,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    expect(find.text('使用者搬到台南了。'), findsOneWidget);
    final BuildContext context = tester.element(find.byType(NoticeGlanceCard));
    final AppLocalizations words = AppLocalizations.of(context);
    expect(find.text(words.profileMemoryByAgent), findsOneWidget);

    await tester.tap(find.text(words.noticeDismiss));
    await tester.pump();
    expect(dismissed, isTrue);
    // Dismissing keeps the memory; only forgetting deletes it.
    expect(store.current.memories, hasLength(1));
  });

  testWidgets('the forget button deletes exactly the kept sentence', (
    WidgetTester tester,
  ) async {
    final InMemoryAgentProfileStore store = InMemoryAgentProfileStore(
      profileWith('使用者搬到台南了。'),
    );
    addTearDown(store.dispose);
    bool dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoticeGlanceCard(
            notice: notice,
            profile: store,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    final BuildContext context = tester.element(find.byType(NoticeGlanceCard));
    final AppLocalizations words = AppLocalizations.of(context);
    await tester.tap(find.text(words.profileForget));
    await tester.pump();
    expect(store.current.memories, isEmpty);
    expect(dismissed, isTrue);
  });
}
