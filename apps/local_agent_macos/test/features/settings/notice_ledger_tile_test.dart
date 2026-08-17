import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_center.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_ledger.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_policy.dart';
import 'package:local_agent_macos/features/settings/settings_sheet.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  Future<PresenceNoticeCenter> mutedCenter() async {
    final InMemoryPresenceNoticeStore store = InMemoryPresenceNoticeStore();
    PresenceNoticeLedger seeded = PresenceNoticeLedger.empty();
    for (int day = 1; day <= PresenceNoticePolicy.muteStreak; day += 1) {
      seeded = seeded.appendNotice(
        PresenceNotice(
          kind: PresenceNoticeKind.memoryWrite,
          litAt: DateTime(2026, 8, day),
          summary: 'fact $day',
          outcome: PresenceNoticeOutcome.seenIgnored,
        ),
      );
    }
    await store.save(seeded);
    final PresenceNoticeCenter center = PresenceNoticeCenter(
      store: store,
      resting: () => true,
    );
    await center.load();
    addTearDown(center.dispose);
    return center;
  }

  testWidgets('a muted kind shows its tallies and the way back on', (
    WidgetTester tester,
  ) async {
    final PresenceNoticeCenter center = await mutedCenter();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: <Widget>[NoticeLedgerTile(center: center)]),
        ),
      ),
    );
    final BuildContext context = tester.element(find.byType(NoticeLedgerTile));
    final AppLocalizations words = AppLocalizations.of(context);
    expect(
      find.textContaining(words.noticesTally(5, 0)),
      findsOneWidget,
      reason: 'five lit, none opened, is why it muted',
    );
    expect(find.textContaining(words.noticesMutedNote), findsOneWidget);

    await tester.tap(find.byKey(const Key('setting-notice-reenable')));
    await tester.pump();
    expect(
      find.byKey(const Key('setting-notice-reenable')),
      findsNothing,
      reason: 're-enabling starts the count over, so it is no longer muted',
    );
    expect(center.isMuted(PresenceNoticeKind.memoryWrite), isFalse);
  });
}
