import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_policy.dart';

void main() {
  const PresenceNoticePolicy policy = PresenceNoticePolicy();
  final DateTime noon = DateTime(2026, 8, 17, 12);

  PresenceNotice notice(
    DateTime litAt, {
    PresenceNoticeOutcome? outcome,
    PresenceNoticeKind kind = PresenceNoticeKind.memoryWrite,
  }) {
    return PresenceNotice(
      kind: kind,
      litAt: litAt,
      summary: 'a fact',
      outcome: outcome,
    );
  }

  group('budget', () {
    test('an empty ledger admits a notice', () {
      expect(
        policy.refuse(
          notices: const <PresenceNotice>[],
          kind: PresenceNoticeKind.memoryWrite,
          now: noon,
        ),
        isNull,
      );
    });

    test('a notice inside the minimum gap is too soon', () {
      final List<PresenceNotice> notices = <PresenceNotice>[
        notice(
          noon.subtract(const Duration(minutes: 20)),
          outcome: PresenceNoticeOutcome.glanced,
        ),
      ];
      expect(
        policy.refuse(
          notices: notices,
          kind: PresenceNoticeKind.memoryWrite,
          now: noon,
        ),
        PresenceNoticeRefusal.tooSoon,
      );
    });

    test('a notice past the minimum gap may light again the same day', () {
      final List<PresenceNotice> notices = <PresenceNotice>[
        notice(
          noon.subtract(const Duration(minutes: 31)),
          outcome: PresenceNoticeOutcome.glanced,
        ),
      ];
      expect(
        policy.refuse(
          notices: notices,
          kind: PresenceNoticeKind.memoryWrite,
          now: noon,
        ),
        isNull,
      );
    });

    test('the day budget counts every kind and every outcome', () {
      final List<PresenceNotice> notices = <PresenceNotice>[
        for (int hour = 1; hour <= PresenceNoticePolicy.dayBudget; hour += 1)
          notice(
            DateTime(2026, 8, 17, hour),
            outcome: PresenceNoticeOutcome.unseen,
          ),
      ];
      expect(
        policy.refuse(
          notices: notices,
          kind: PresenceNoticeKind.memoryWrite,
          now: noon,
        ),
        PresenceNoticeRefusal.dayBudget,
      );
    });

    test('yesterday does not count against today', () {
      final List<PresenceNotice> notices = <PresenceNotice>[
        for (int hour = 1; hour <= PresenceNoticePolicy.dayBudget; hour += 1)
          notice(
            DateTime(2026, 8, 16, hour),
            outcome: PresenceNoticeOutcome.unseen,
          ),
      ];
      expect(
        policy.refuse(
          notices: notices,
          kind: PresenceNoticeKind.memoryWrite,
          now: noon,
        ),
        isNull,
      );
    });

    test('the kind budget binds before the day budget has run out', () {
      final List<PresenceNotice> notices = <PresenceNotice>[
        for (int hour = 1; hour <= PresenceNoticePolicy.kindBudget; hour += 1)
          notice(
            DateTime(2026, 8, 17, hour),
            outcome: PresenceNoticeOutcome.glanced,
          ),
      ];
      expect(
        policy.refuse(
          notices: notices,
          kind: PresenceNoticeKind.memoryWrite,
          now: noon,
        ),
        PresenceNoticeRefusal.kindBudget,
      );
    });
  });

  group('tripwires', () {
    List<PresenceNotice> ignoredRun(int count, {DateTime? from}) {
      final DateTime start = from ?? DateTime(2026, 8, 1, 9);
      return <PresenceNotice>[
        for (int day = 0; day < count; day += 1)
          notice(
            start.add(Duration(days: day)),
            outcome: PresenceNoticeOutcome.seenIgnored,
          ),
      ];
    }

    test('five consecutive seen-and-ignored notices mute the kind', () {
      expect(
        policy.isMuted(
          ignoredRun(PresenceNoticePolicy.muteStreak),
          PresenceNoticeKind.memoryWrite,
        ),
        isTrue,
      );
    });

    test('four consecutive seen-and-ignored notices do not', () {
      expect(
        policy.isMuted(
          ignoredRun(PresenceNoticePolicy.muteStreak - 1),
          PresenceNoticeKind.memoryWrite,
        ),
        isFalse,
      );
    });

    test('a glance breaks the streak', () {
      final List<PresenceNotice> notices = <PresenceNotice>[
        ...ignoredRun(4),
        notice(DateTime(2026, 8, 10), outcome: PresenceNoticeOutcome.glanced),
        ...ignoredRun(4, from: DateTime(2026, 8, 11)),
      ];
      expect(policy.isMuted(notices, PresenceNoticeKind.memoryWrite), isFalse);
    });

    test('unseen notices neither extend nor break the streak', () {
      final List<PresenceNotice> notices = <PresenceNotice>[
        ...ignoredRun(4),
        notice(DateTime(2026, 8, 10), outcome: PresenceNoticeOutcome.unseen),
        notice(
          DateTime(2026, 8, 11),
          outcome: PresenceNoticeOutcome.seenIgnored,
        ),
      ];
      expect(policy.isMuted(notices, PresenceNoticeKind.memoryWrite), isTrue);
    });

    test('a full window with too few glances mutes the kind', () {
      // Glance, then two ignores, repeating: no ignore streak ever reaches
      // five, but a trailing window of ten holds at most three glances — and
      // arranging the last ten to hold only two must trip the rate wire.
      final List<PresenceNotice> notices = <PresenceNotice>[
        for (int i = 0; i < 12; i += 1)
          notice(
            DateTime(2026, 8, 1).add(Duration(days: i)),
            outcome: i % 4 == 0
                ? PresenceNoticeOutcome.glanced
                : i % 4 == 3
                ? PresenceNoticeOutcome.unseen
                : PresenceNoticeOutcome.seenIgnored,
          ),
      ];
      // Seen sequence: G I I G I I G I I — nine seen, no full window yet.
      expect(
        policy.isMuted(notices.sublist(0, 11), PresenceNoticeKind.memoryWrite),
        isFalse,
      );
      // The twelfth entry is unseen, so the seen sequence is unchanged.
      expect(policy.isMuted(notices, PresenceNoticeKind.memoryWrite), isFalse);
      // Two more ignores slide the earliest glance out of the window.
      final List<PresenceNotice> slid = <PresenceNotice>[
        ...notices,
        notice(
          DateTime(2026, 8, 13),
          outcome: PresenceNoticeOutcome.seenIgnored,
        ),
        notice(DateTime(2026, 8, 14), outcome: PresenceNoticeOutcome.glanced),
        notice(
          DateTime(2026, 8, 15),
          outcome: PresenceNoticeOutcome.seenIgnored,
        ),
      ];
      // Window: I G I I G I I I G I → three glances, unmuted; drop the
      // trailing glance to two by ignoring twice more.
      final List<PresenceNotice> starved = <PresenceNotice>[
        ...slid,
        notice(
          DateTime(2026, 8, 16),
          outcome: PresenceNoticeOutcome.seenIgnored,
        ),
        notice(
          DateTime(2026, 8, 17),
          outcome: PresenceNoticeOutcome.seenIgnored,
        ),
      ];
      expect(policy.isMuted(starved, PresenceNoticeKind.memoryWrite), isTrue);
    });

    test('a muted kind is refused as muted', () {
      expect(
        policy.refuse(
          notices: ignoredRun(PresenceNoticePolicy.muteStreak),
          kind: PresenceNoticeKind.memoryWrite,
          now: noon,
        ),
        PresenceNoticeRefusal.muted,
      );
    });

    test('re-enabling starts the count over', () {
      final List<PresenceNotice> notices = ignoredRun(
        PresenceNoticePolicy.muteStreak,
      );
      expect(
        policy.isMuted(
          notices,
          PresenceNoticeKind.memoryWrite,
          reenabledAt: DateTime(2026, 8, 16),
        ),
        isFalse,
      );
    });
  });
}
