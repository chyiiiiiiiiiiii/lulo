import 'dart:async';

import 'package:flutter/foundation.dart';

import 'presence_notice.dart';
import 'presence_notice_ledger.dart';
import 'presence_notice_policy.dart';

/// What one kind has done so far, in words the settings sheet can say.
final class PresenceNoticeTally {
  /// Creates one kind's tally.
  const PresenceNoticeTally({
    required this.litCount,
    required this.glancedCount,
    required this.suppressedCount,
    required this.muted,
  });

  /// How many times this kind has lit the orb.
  final int litCount;

  /// How many of those the user opened.
  final int glancedCount;

  /// How many triggers were dropped before lighting anything.
  final int suppressedCount;

  /// Whether the kind has tripped a wire and stays dark.
  final bool muted;
}

/// The one place a trigger becomes, or fails to become, a lit orb.
///
/// Enforces `an-ignored-light-stays-ignored.md` — the budget before the
/// light, the lifetime on it, the seen-or-unseen judgement at expiry, and
/// the tripwires that mute a kind the user has stopped opening. Everything
/// it decides is written to the ledger, which is the measurement the
/// document demands and the only output the feature has when nobody looks.
final class PresenceNoticeCenter {
  /// Creates the center over its ledger [store].
  ///
  /// [resting] answers whether the user is *not* already looking at Lulo —
  /// the orb form, idle. A trigger that fires anywhere else is dropped: a
  /// light competing with an open conversation is noise, not noticing.
  PresenceNoticeCenter({
    required this._store,
    required this._resting,
    this._now = DateTime.now,
    this._policy = const PresenceNoticePolicy(),
  });

  final PresenceNoticeStore _store;
  final bool Function() _resting;
  final DateTime Function() _now;
  final PresenceNoticePolicy _policy;

  final ValueNotifier<PresenceNotice?> _lit = ValueNotifier<PresenceNotice?>(
    null,
  );
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  PresenceNoticeLedger _ledger = PresenceNoticeLedger.empty();
  Future<void> _saving = Future<void>.value();
  Timer? _expiry;
  DateTime? _lastActivityAt;
  bool _disposed = false;

  /// The notice currently lit, or null while the orb is dark.
  ValueListenable<PresenceNotice?> get lit => _lit;

  /// Changes whenever the ledger does, for surfaces drawing tallies.
  ValueListenable<int> get revision => _revision;

  /// Reads the ledger the last run left.
  ///
  /// Any notice that was still lit when that process died has already been
  /// settled `unseen` by the codec, so nothing here is lit at load.
  Future<void> load() async {
    final PresenceNoticeLedger ledger = await _store.load();
    if (_disposed) {
      return;
    }
    _ledger = ledger;
  }

  /// Records that the user is demonstrably at the machine right now.
  ///
  /// Fed from the app-switch channel and from input to Lulo itself. This is
  /// what separates seen-and-ignored from unseen at expiry — the difference
  /// between a light the user declined and a light nobody was there for.
  void noteActivity() {
    _lastActivityAt = _now();
  }

  /// Offers [kind] the chance to light the orb, showing [summary] on glance.
  ///
  /// Dropped — silently, counted — when the user is already looking at Lulo
  /// or when the budget or a tripwire refuses it. Silence is the contract:
  /// the app's only responses to a trigger are a quiet light or nothing.
  void trigger(PresenceNoticeKind kind, String summary) {
    if (_disposed) {
      return;
    }
    final DateTime now = _now();
    final bool refused =
        !_resting() ||
        _policy.refuse(
              notices: _ledger.notices,
              kind: kind,
              now: now,
              reenabledAt: _ledger.reenabledAt[kind],
            ) !=
            null;
    if (refused) {
      _ledger = _ledger.suppress(kind);
      _persist();
      return;
    }
    final PresenceNotice notice = PresenceNotice(
      kind: kind,
      litAt: now,
      summary: summary,
    );
    _ledger = _ledger.appendNotice(notice);
    _lit.value = notice;
    _expiry?.cancel();
    _expiry = Timer(PresenceNoticePolicy.noticeLifetime, _expire);
    _persist();
  }

  /// Records the user opening the orb, returning what was lit if anything.
  ///
  /// A lit notice is settled `glanced` and the light goes out; an unlit open
  /// is counted toward the baseline the attribution note in the document
  /// asks for, and returns null.
  PresenceNotice? glance() {
    if (_disposed) {
      return null;
    }
    final DateTime now = _now();
    _lastActivityAt = now;
    final PresenceNotice? notice = _lit.value;
    if (notice == null) {
      _ledger = _ledger.countUnlitOpen(now);
      _persist();
      return null;
    }
    _expiry?.cancel();
    _expiry = null;
    _lit.value = null;
    _ledger = _ledger.settleLit(
      PresenceNoticeOutcome.glanced,
      after: now.difference(notice.litAt),
    );
    _persist();
    return notice;
  }

  /// Whether [kind] has tripped a wire and stays dark.
  bool isMuted(PresenceNoticeKind kind) {
    return _policy.isMuted(
      _ledger.notices,
      kind,
      reenabledAt: _ledger.reenabledAt[kind],
    );
  }

  /// Lets a muted [kind] light again, its count started over.
  void reenable(PresenceNoticeKind kind) {
    if (_disposed) {
      return;
    }
    _ledger = _ledger.reenable(kind, _now());
    _persist();
  }

  /// What [kind] has done so far, for the settings sheet to say.
  PresenceNoticeTally tallyOf(PresenceNoticeKind kind) {
    int litCount = 0;
    int glancedCount = 0;
    for (final PresenceNotice notice in _ledger.notices) {
      if (notice.kind != kind) {
        continue;
      }
      litCount += 1;
      if (notice.outcome == PresenceNoticeOutcome.glanced) {
        glancedCount += 1;
      }
    }
    return PresenceNoticeTally(
      litCount: litCount,
      glancedCount: glancedCount,
      suppressedCount: _ledger.suppressed[kind] ?? 0,
      muted: isMuted(kind),
    );
  }

  /// Stops the timer and ignores everything after.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _expiry?.cancel();
    _lit.dispose();
    _revision.dispose();
  }

  void _expire() {
    if (_disposed) {
      return;
    }
    final PresenceNotice? notice = _lit.value;
    _expiry = null;
    if (notice == null) {
      return;
    }
    _lit.value = null;
    // Seen only when there was activity after the light came on. Thin
    // evidence errs toward unseen, which errs in the trigger's favour —
    // an empty chair must not convict it.
    final DateTime? activity = _lastActivityAt;
    final bool seen = activity != null && activity.isAfter(notice.litAt);
    _ledger = _ledger.settleLit(
      seen ? PresenceNoticeOutcome.seenIgnored : PresenceNoticeOutcome.unseen,
    );
    _persist();
  }

  void _persist() {
    _revision.value += 1;
    final PresenceNoticeLedger ledger = _ledger;
    // Serialised so two writes cannot interleave, and swallowed on failure:
    // a ledger that cannot be written is measurement lost, not memory, and
    // nothing about it is worth interrupting anyone.
    _saving = _saving
        .then((_) => _store.save(ledger))
        .catchError((Object _) {});
  }
}
