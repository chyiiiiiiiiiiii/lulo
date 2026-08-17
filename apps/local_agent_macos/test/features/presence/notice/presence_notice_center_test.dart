import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_center.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_ledger.dart';
import 'package:local_agent_macos/features/presence/notice/presence_notice_policy.dart';

void main() {
  const PresenceNoticeKind kind = PresenceNoticeKind.memoryWrite;

  /// Builds a center inside [body]'s fake clock, resting unless told not to.
  void run(
    void Function(
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    )
    body, {
    bool Function()? resting,
    DateTime? epoch,
  }) {
    final DateTime start = epoch ?? DateTime(2026, 8, 17, 9);
    fakeAsync(initialTime: start, (FakeAsync async) {
      final InMemoryPresenceNoticeStore store = InMemoryPresenceNoticeStore();
      final PresenceNoticeCenter center = PresenceNoticeCenter(
        store: store,
        resting: resting ?? () => true,
        now: () => start.add(async.elapsed),
      );
      center.load();
      async.flushMicrotasks();
      body(async, center, store);
      center.dispose();
    });
  }

  test('a trigger while resting lights the orb', () {
    run((FakeAsync async, PresenceNoticeCenter center, _) {
      center.trigger(kind, 'The user lives in Tainan.');
      async.flushMicrotasks();
      expect(center.lit.value?.summary, 'The user lives in Tainan.');
    });
  });

  test('a trigger while the user is already looking is dropped', () {
    run(resting: () => false, (
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      center.trigger(kind, 'a fact');
      async.flushMicrotasks();
      expect(center.lit.value, isNull);
      expect(center.tallyOf(kind).suppressedCount, 1);
    });
  });

  test('a glance settles the notice and puts the light out', () {
    run((
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      final int before = center.revision.value;
      center.trigger(kind, 'a fact');
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 2));
      final PresenceNotice? glanced = center.glance();
      async.flushMicrotasks();
      expect(glanced?.summary, 'a fact');
      expect(center.lit.value, isNull);
      // The settings sheet redraws its tallies off this.
      expect(center.revision.value, greaterThan(before));
      final PresenceNoticeLedger ledger = InMemoryLedger.of(store, async);
      expect(ledger.notices.single.outcome, PresenceNoticeOutcome.glanced);
      expect(ledger.notices.single.glancedAfter, const Duration(minutes: 2));
    });
  });

  test('an expiry with the user present is seen and ignored', () {
    run((
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      center.trigger(kind, 'a fact');
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      center.noteActivity();
      async.elapse(PresenceNoticePolicy.noticeLifetime);
      async.flushMicrotasks();
      expect(center.lit.value, isNull);
      expect(
        InMemoryLedger.of(store, async).notices.single.outcome,
        PresenceNoticeOutcome.seenIgnored,
      );
    });
  });

  test('an expiry with nobody there is unseen', () {
    run((
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      center.trigger(kind, 'a fact');
      async.flushMicrotasks();
      async.elapse(PresenceNoticePolicy.noticeLifetime);
      async.flushMicrotasks();
      expect(
        InMemoryLedger.of(store, async).notices.single.outcome,
        PresenceNoticeOutcome.unseen,
      );
    });
  });

  test('activity from before the light does not count as presence', () {
    run((
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      center.noteActivity();
      async.elapse(const Duration(minutes: 1));
      center.trigger(kind, 'a fact');
      async.flushMicrotasks();
      async.elapse(PresenceNoticePolicy.noticeLifetime);
      async.flushMicrotasks();
      expect(
        InMemoryLedger.of(store, async).notices.single.outcome,
        PresenceNoticeOutcome.unseen,
      );
    });
  });

  test('five ignored notices mute the kind and later triggers stay dark', () {
    run((
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      for (int i = 0; i < PresenceNoticePolicy.muteStreak; i += 1) {
        center.trigger(kind, 'fact $i');
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        center.noteActivity();
        async.elapse(PresenceNoticePolicy.noticeLifetime);
        async.flushMicrotasks();
        // Clear of every budget: past the gap, and never more than two in
        // any calendar day.
        async.elapse(const Duration(hours: 13));
      }
      expect(center.isMuted(kind), isTrue);
      center.trigger(kind, 'one more');
      async.flushMicrotasks();
      expect(center.lit.value, isNull);
    });
  });

  test('re-enabling lets a muted kind light again', () {
    run((
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      for (int i = 0; i < PresenceNoticePolicy.muteStreak; i += 1) {
        center.trigger(kind, 'fact $i');
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        center.noteActivity();
        async.elapse(PresenceNoticePolicy.noticeLifetime);
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 13));
      }
      expect(center.isMuted(kind), isTrue);
      center.reenable(kind);
      async.flushMicrotasks();
      expect(center.isMuted(kind), isFalse);
      center.trigger(kind, 'a fresh start');
      async.flushMicrotasks();
      expect(center.lit.value?.summary, 'a fresh start');
    });
  });

  test('opening the unlit orb counts toward the baseline', () {
    run((
      FakeAsync async,
      PresenceNoticeCenter center,
      InMemoryPresenceNoticeStore store,
    ) {
      expect(center.glance(), isNull);
      async.flushMicrotasks();
      expect(InMemoryLedger.of(store, async).unlitOpens['2026-08-17'], 1);
    });
  });

  test('load starts from what the last run measured', () {
    fakeAsync(initialTime: DateTime(2026, 8, 17, 9), (FakeAsync async) {
      final InMemoryPresenceNoticeStore store = InMemoryPresenceNoticeStore();
      PresenceNoticeLedger seeded = PresenceNoticeLedger.empty();
      for (int day = 1; day <= PresenceNoticePolicy.muteStreak; day += 1) {
        seeded = seeded.appendNotice(
          PresenceNotice(
            kind: kind,
            litAt: DateTime(2026, 8, day),
            summary: 'fact $day',
            outcome: PresenceNoticeOutcome.seenIgnored,
          ),
        );
      }
      store.save(seeded);
      async.flushMicrotasks();
      final PresenceNoticeCenter center = PresenceNoticeCenter(
        store: store,
        resting: () => true,
        now: () => DateTime(2026, 8, 17, 9).add(async.elapsed),
      );
      center.load();
      async.flushMicrotasks();
      expect(center.isMuted(kind), isTrue);
      center.dispose();
    });
  });
}

/// Reads the store synchronously under a fake clock.
final class InMemoryLedger {
  static PresenceNoticeLedger of(
    InMemoryPresenceNoticeStore store,
    FakeAsync async,
  ) {
    late PresenceNoticeLedger ledger;
    store.load().then((PresenceNoticeLedger loaded) => ledger = loaded);
    async.flushMicrotasks();
    return ledger;
  }
}
