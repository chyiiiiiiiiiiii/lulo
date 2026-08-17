import 'presence_notice.dart';

/// Why a trigger was not allowed to light the orb.
enum PresenceNoticeRefusal {
  /// The kind has been ignored past its tripwire and stays dark until the
  /// user re-enables it in Settings.
  muted,

  /// The last notice, of any kind, lit too recently.
  tooSoon,

  /// The day's budget across every kind is spent.
  dayBudget,

  /// The day's budget for this kind is spent.
  kindBudget,
}

/// The budgets and tripwires of `an-ignored-light-stays-ignored.md`.
///
/// Pure arithmetic over the ledger, so every number in that document is
/// testable without a timer, a file, or an orb. The numbers themselves are
/// deliberately conservative: they can be loosened by evidence, and the
/// user's habit of ignoring the light cannot be reset by a settings change.
final class PresenceNoticePolicy {
  /// Creates the policy.
  const PresenceNoticePolicy();

  /// How long a notice stays lit before expiring on its own.
  static const Duration noticeLifetime = Duration(minutes: 15);

  /// The least time between two notices of any kind.
  static const Duration minimumGap = Duration(minutes: 30);

  /// The most notices in one calendar day, all kinds together.
  static const int dayBudget = 4;

  /// The most notices of one kind in one calendar day.
  static const int kindBudget = 2;

  /// Consecutive seen-and-ignored notices that mute a kind.
  static const int muteStreak = 5;

  /// The trailing seen notices the chronic-rate tripwire looks at.
  static const int rateWindow = 10;

  /// The fewest glances a full [rateWindow] must hold to stay unmuted.
  static const int rateFloor = 3;

  /// Whether [kind] has tripped a wire and stays dark.
  ///
  /// Judged over the seen notices of [kind] after [reenabledAt] — glanced
  /// and seen-and-ignored, in order. Unseen notices are skipped entirely:
  /// they neither extend a streak nor break one.
  bool isMuted(
    List<PresenceNotice> notices,
    PresenceNoticeKind kind, {
    DateTime? reenabledAt,
  }) {
    final List<PresenceNotice> seen = <PresenceNotice>[
      for (final PresenceNotice notice in notices)
        if (notice.kind == kind &&
            notice.seen &&
            (reenabledAt == null || notice.litAt.isAfter(reenabledAt)))
          notice,
    ];
    int streak = 0;
    for (int i = seen.length - 1; i >= 0; i -= 1) {
      if (seen[i].outcome != PresenceNoticeOutcome.seenIgnored) {
        break;
      }
      streak += 1;
      if (streak >= muteStreak) {
        return true;
      }
    }
    if (seen.length >= rateWindow) {
      int glanced = 0;
      for (int i = seen.length - rateWindow; i < seen.length; i += 1) {
        if (seen[i].outcome == PresenceNoticeOutcome.glanced) {
          glanced += 1;
        }
      }
      if (glanced < rateFloor) {
        return true;
      }
    }
    return false;
  }

  /// Why [kind] may not light at [now], or null when it may.
  ///
  /// Budgets count notices that lit, whatever became of them — the budget is
  /// a spend limit on the user's attention, and the attention was spent the
  /// moment the orb changed.
  PresenceNoticeRefusal? refuse({
    required List<PresenceNotice> notices,
    required PresenceNoticeKind kind,
    required DateTime now,
    DateTime? reenabledAt,
  }) {
    if (isMuted(notices, kind, reenabledAt: reenabledAt)) {
      return PresenceNoticeRefusal.muted;
    }
    int today = 0;
    int kindToday = 0;
    for (final PresenceNotice notice in notices) {
      if (now.difference(notice.litAt) < minimumGap) {
        return PresenceNoticeRefusal.tooSoon;
      }
      if (_sameDay(notice.litAt, now)) {
        today += 1;
        if (notice.kind == kind) {
          kindToday += 1;
        }
      }
    }
    if (today >= dayBudget) {
      return PresenceNoticeRefusal.dayBudget;
    }
    if (kindToday >= kindBudget) {
      return PresenceNoticeRefusal.kindBudget;
    }
    return null;
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
