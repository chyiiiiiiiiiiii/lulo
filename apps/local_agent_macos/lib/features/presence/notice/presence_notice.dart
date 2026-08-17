/// What kind of thing Lulo noticed.
///
/// One value today, and the ceremony of an enum anyway, because the whole
/// measurement design in `docs/decisions/an-ignored-light-stays-ignored.md`
/// is per kind: triggers fail independently, and one bad trigger must not be
/// able to spend the feature's credibility for the others.
enum PresenceNoticeKind {
  /// The extraction pass kept a fact about the user.
  memoryWrite('memory-write');

  const PresenceNoticeKind(this.wireName);

  /// How this kind is written in the ledger file.
  final String wireName;

  /// The kind written as [wireName], or null for a name no version knows.
  static PresenceNoticeKind? fromWireName(String name) {
    for (final PresenceNoticeKind kind in values) {
      if (kind.wireName == name) {
        return kind;
      }
    }
    return null;
  }
}

/// How one notice ended.
enum PresenceNoticeOutcome {
  /// The user opened the orb while it was lit.
  glanced,

  /// The light expired while the user was demonstrably at the machine.
  ///
  /// This is the only outcome that convicts a trigger: the tripwires in
  /// `PresenceNoticePolicy` count nothing else against it.
  seenIgnored,

  /// The light expired with no evidence anyone was there.
  ///
  /// Excluded from every rate — an empty chair must not convict a trigger.
  unseen,
}

/// One time the orb quietly lit.
///
/// [outcome] is null exactly while the notice is the one currently lit; every
/// notice read back from disk is settled, because a light does not survive
/// the process that lit it.
final class PresenceNotice {
  /// Creates one notice record.
  const PresenceNotice({
    required this.kind,
    required this.litAt,
    required this.summary,
    this.outcome,
    this.glancedAfter,
  });

  /// The trigger that lit the orb.
  final PresenceNoticeKind kind;

  /// When the orb lit.
  final DateTime litAt;

  /// What glancing would show — for a memory write, the sentence kept.
  final String summary;

  /// How this notice ended, or null while it is still lit.
  final PresenceNoticeOutcome? outcome;

  /// How long the light waited before the user opened it, when they did.
  final Duration? glancedAfter;

  /// Whether the user was there to see this notice, whatever they did next.
  ///
  /// The denominator of every rate: glanced and seen-and-ignored count,
  /// unseen and still-lit do not.
  bool get seen =>
      outcome == PresenceNoticeOutcome.glanced ||
      outcome == PresenceNoticeOutcome.seenIgnored;

  /// This notice with its ending recorded.
  PresenceNotice settled(PresenceNoticeOutcome outcome, {Duration? after}) {
    return PresenceNotice(
      kind: kind,
      litAt: litAt,
      summary: summary,
      outcome: outcome,
      glancedAfter: after,
    );
  }
}
