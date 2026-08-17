import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_ledger.dart';

void main() {
  PresenceNotice notice(
    DateTime litAt, {
    PresenceNoticeOutcome? outcome,
    Duration? glancedAfter,
    String summary = 'The user lives in Tainan.',
  }) {
    return PresenceNotice(
      kind: PresenceNoticeKind.memoryWrite,
      litAt: litAt,
      summary: summary,
      outcome: outcome,
      glancedAfter: glancedAfter,
    );
  }

  group('the ledger', () {
    test('caps its notices at the capacity, dropping the oldest', () {
      PresenceNoticeLedger ledger = PresenceNoticeLedger.empty();
      for (int i = 0; i <= PresenceNoticeLedger.capacity; i += 1) {
        ledger = ledger.appendNotice(
          notice(
            DateTime(2026, 1, 1).add(Duration(hours: i)),
            outcome: PresenceNoticeOutcome.unseen,
            summary: 'fact $i',
          ),
        );
      }
      expect(ledger.notices, hasLength(PresenceNoticeLedger.capacity));
      expect(ledger.notices.first.summary, 'fact 1');
      expect(
        ledger.notices.last.summary,
        'fact ${PresenceNoticeLedger.capacity}',
      );
    });

    test('settles the one lit notice and leaves settled ones alone', () {
      final PresenceNoticeLedger ledger = PresenceNoticeLedger.empty()
          .appendNotice(
            notice(
              DateTime(2026, 8, 1),
              outcome: PresenceNoticeOutcome.glanced,
            ),
          )
          .appendNotice(notice(DateTime(2026, 8, 2)))
          .settleLit(
            PresenceNoticeOutcome.glanced,
            after: const Duration(minutes: 2),
          );
      expect(ledger.notices.last.outcome, PresenceNoticeOutcome.glanced);
      expect(ledger.notices.last.glancedAfter, const Duration(minutes: 2));
      expect(ledger.notices.first.glancedAfter, isNull);
    });

    test('counts suppressions and unlit opens without growing the notices', () {
      final PresenceNoticeLedger ledger = PresenceNoticeLedger.empty()
          .suppress(PresenceNoticeKind.memoryWrite)
          .suppress(PresenceNoticeKind.memoryWrite)
          .countUnlitOpen(DateTime(2026, 8, 17, 9))
          .countUnlitOpen(DateTime(2026, 8, 17, 21));
      expect(ledger.notices, isEmpty);
      expect(ledger.suppressed[PresenceNoticeKind.memoryWrite], 2);
      expect(ledger.unlitOpens['2026-08-17'], 2);
    });
  });

  group('the codec', () {
    test('round-trips every field', () {
      final PresenceNoticeLedger ledger = PresenceNoticeLedger.empty()
          .appendNotice(
            notice(
              DateTime(2026, 8, 16, 10, 30),
              outcome: PresenceNoticeOutcome.glanced,
              glancedAfter: const Duration(seconds: 42),
            ),
          )
          .appendNotice(
            notice(
              DateTime(2026, 8, 16, 12),
              outcome: PresenceNoticeOutcome.seenIgnored,
            ),
          )
          .suppress(PresenceNoticeKind.memoryWrite)
          .countUnlitOpen(DateTime(2026, 8, 16, 13))
          .reenable(PresenceNoticeKind.memoryWrite, DateTime(2026, 8, 16, 14));
      final PresenceNoticeLedger back = decodePresenceNoticeLedger(
        jsonDecode(jsonEncode(encodePresenceNoticeLedger(ledger))),
      );
      expect(back.notices, hasLength(2));
      expect(back.notices.first.outcome, PresenceNoticeOutcome.glanced);
      expect(back.notices.first.glancedAfter, const Duration(seconds: 42));
      expect(back.notices.first.litAt, DateTime(2026, 8, 16, 10, 30));
      expect(back.notices.last.outcome, PresenceNoticeOutcome.seenIgnored);
      expect(back.suppressed[PresenceNoticeKind.memoryWrite], 1);
      expect(back.unlitOpens['2026-08-16'], 1);
      expect(
        back.reenabledAt[PresenceNoticeKind.memoryWrite],
        DateTime(2026, 8, 16, 14),
      );
    });

    test('settles a notice that was still lit when the process died', () {
      final PresenceNoticeLedger ledger = PresenceNoticeLedger.empty()
          .appendNotice(notice(DateTime(2026, 8, 16, 10)));
      final PresenceNoticeLedger back = decodePresenceNoticeLedger(
        jsonDecode(jsonEncode(encodePresenceNoticeLedger(ledger))),
      );
      expect(back.notices.single.outcome, PresenceNoticeOutcome.unseen);
    });

    test('drops a kind this version does not know rather than failing', () {
      final Map<String, Object?> json =
          encodePresenceNoticeLedger(
              PresenceNoticeLedger.empty().appendNotice(
                notice(
                  DateTime(2026, 8, 16),
                  outcome: PresenceNoticeOutcome.glanced,
                ),
              ),
            )
            ..['notices'] = <Object?>[
              {
                'kind': 'screen-watch',
                'litAt': '2026-08-16T10:00:00.000',
                'summary': 'from the future',
                'outcome': 'glanced',
              },
            ];
      expect(decodePresenceNoticeLedger(json).notices, isEmpty);
    });

    test('reads nonsense as an empty ledger', () {
      expect(decodePresenceNoticeLedger('not a map').notices, isEmpty);
      expect(decodePresenceNoticeLedger(null).notices, isEmpty);
    });
  });

  group('the file store', () {
    test('round-trips through an indented file a person can read', () async {
      final Directory home = Directory.systemTemp.createTempSync('notices');
      addTearDown(() => home.deleteSync(recursive: true));
      final File file = File('${home.path}/presence_notices.json');
      final FilePresenceNoticeStore store = FilePresenceNoticeStore(file: file);
      await store.save(
        PresenceNoticeLedger.empty().appendNotice(
          notice(DateTime(2026, 8, 16), outcome: PresenceNoticeOutcome.glanced),
        ),
      );
      expect(file.readAsStringSync(), contains('\n  '));
      final PresenceNoticeLedger back = await store.load();
      expect(back.notices.single.summary, 'The user lives in Tainan.');
    });

    test('reads a missing or unreadable file as an empty ledger', () async {
      final Directory home = Directory.systemTemp.createTempSync('notices');
      addTearDown(() => home.deleteSync(recursive: true));
      final File file = File('${home.path}/presence_notices.json');
      final FilePresenceNoticeStore store = FilePresenceNoticeStore(file: file);
      expect((await store.load()).notices, isEmpty);
      file.writeAsStringSync('{{{');
      expect((await store.load()).notices, isEmpty);
    });
  });
}
