import 'dart:convert';
import 'dart:io';

import 'presence_notice.dart';

/// Everything the notice feature has done, on this machine and nowhere else.
///
/// The numbers `an-ignored-light-stays-ignored.md` commits to are computed
/// over this — which is why it keeps what it keeps: notices with outcomes
/// for the tripwires, suppression counts so a bounded feature does not read
/// as "covered everything", unlit opens as the attribution baseline, and the
/// per-kind re-enable marks that start a muted kind's count over.
final class PresenceNoticeLedger {
  /// Creates a ledger over its four records.
  const PresenceNoticeLedger({
    required this.notices,
    required this.reenabledAt,
    required this.suppressed,
    required this.unlitOpens,
  });

  /// A ledger with nothing in it.
  factory PresenceNoticeLedger.empty() {
    return const PresenceNoticeLedger(
      notices: <PresenceNotice>[],
      reenabledAt: <PresenceNoticeKind, DateTime>{},
      suppressed: <PresenceNoticeKind, int>{},
      unlitOpens: <String, int>{},
    );
  }

  /// The most notices kept, oldest dropped first.
  ///
  /// Two hundred is far past both tripwire windows, so nothing the policy
  /// reads is ever the part that was dropped.
  static const int capacity = 200;

  /// Every notice kept, oldest first.
  final List<PresenceNotice> notices;

  /// When each kind was last re-enabled in Settings, absent if never.
  final Map<PresenceNoticeKind, DateTime> reenabledAt;

  /// How many triggers were dropped by the budget, per kind.
  final Map<PresenceNoticeKind, int> suppressed;

  /// Opens of the unlit orb per day — the baseline a glance is read against.
  final Map<String, int> unlitOpens;

  /// The day [at] falls on, as the ledger writes days.
  static String dayKey(DateTime at) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${pad(at.month)}-${pad(at.day)}';
  }

  /// This ledger with [notice] appended, the oldest dropped past [capacity].
  PresenceNoticeLedger appendNotice(PresenceNotice notice) {
    final List<PresenceNotice> next = <PresenceNotice>[...notices, notice];
    return _with(
      notices: next.length > capacity
          ? next.sublist(next.length - capacity)
          : next,
    );
  }

  /// This ledger with the one still-lit notice settled as [outcome].
  ///
  /// A ledger holds at most one lit notice — the budget's minimum gap is far
  /// longer than a notice lives — so this settles the newest unsettled one
  /// and changes nothing else.
  PresenceNoticeLedger settleLit(
    PresenceNoticeOutcome outcome, {
    Duration? after,
  }) {
    for (int i = notices.length - 1; i >= 0; i -= 1) {
      if (notices[i].outcome == null) {
        final List<PresenceNotice> next = <PresenceNotice>[...notices];
        next[i] = notices[i].settled(outcome, after: after);
        return _with(notices: next);
      }
    }
    return this;
  }

  /// This ledger with one more budget-dropped trigger of [kind].
  PresenceNoticeLedger suppress(PresenceNoticeKind kind) {
    return _with(
      suppressed: <PresenceNoticeKind, int>{
        ...suppressed,
        kind: (suppressed[kind] ?? 0) + 1,
      },
    );
  }

  /// This ledger with [kind] re-enabled at [at].
  PresenceNoticeLedger reenable(PresenceNoticeKind kind, DateTime at) {
    return _with(
      reenabledAt: <PresenceNoticeKind, DateTime>{...reenabledAt, kind: at},
    );
  }

  /// This ledger with one more open of the unlit orb at [at].
  PresenceNoticeLedger countUnlitOpen(DateTime at) {
    final String day = dayKey(at);
    return _with(
      unlitOpens: <String, int>{...unlitOpens, day: (unlitOpens[day] ?? 0) + 1},
    );
  }

  PresenceNoticeLedger _with({
    List<PresenceNotice>? notices,
    Map<PresenceNoticeKind, DateTime>? reenabledAt,
    Map<PresenceNoticeKind, int>? suppressed,
    Map<String, int>? unlitOpens,
  }) {
    return PresenceNoticeLedger(
      notices: notices ?? this.notices,
      reenabledAt: reenabledAt ?? this.reenabledAt,
      suppressed: suppressed ?? this.suppressed,
      unlitOpens: unlitOpens ?? this.unlitOpens,
    );
  }
}

/// Writes [ledger] as the JSON the file keeps.
Map<String, Object?> encodePresenceNoticeLedger(PresenceNoticeLedger ledger) {
  return <String, Object?>{
    'notices': <Object?>[
      for (final PresenceNotice notice in ledger.notices)
        <String, Object?>{
          'kind': notice.kind.wireName,
          'litAt': notice.litAt.toIso8601String(),
          'summary': notice.summary,
          if (notice.outcome != null) 'outcome': notice.outcome!.name,
          if (notice.glancedAfter != null)
            'glancedAfterMs': notice.glancedAfter!.inMilliseconds,
        },
    ],
    'reenabledAt': <String, Object?>{
      for (final MapEntry<PresenceNoticeKind, DateTime> entry
          in ledger.reenabledAt.entries)
        entry.key.wireName: entry.value.toIso8601String(),
    },
    'suppressed': <String, Object?>{
      for (final MapEntry<PresenceNoticeKind, int> entry
          in ledger.suppressed.entries)
        entry.key.wireName: entry.value,
    },
    'unlitOpens': ledger.unlitOpens,
  };
}

/// Reads a ledger back, defensively.
///
/// Anything unreadable — nonsense, a kind a later version wrote, a corrupt
/// entry — is dropped rather than fatal: losing the ledger loses measurement,
/// not memory, and a crash over a measurement file is the wrong trade. A
/// notice that was still lit when the process died comes back `unseen`,
/// because a light does not survive the process that lit it and nobody was
/// shown anything they could have glanced at.
PresenceNoticeLedger decodePresenceNoticeLedger(Object? json) {
  if (json is! Map<String, Object?>) {
    return PresenceNoticeLedger.empty();
  }
  final List<PresenceNotice> notices = <PresenceNotice>[];
  final Object? rawNotices = json['notices'];
  if (rawNotices is List<Object?>) {
    for (final Object? entry in rawNotices) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      final PresenceNoticeKind? kind = switch (entry['kind']) {
        final String name => PresenceNoticeKind.fromWireName(name),
        _ => null,
      };
      final DateTime? litAt = switch (entry['litAt']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      };
      if (kind == null || litAt == null) {
        continue;
      }
      final PresenceNoticeOutcome outcome = switch (entry['outcome']) {
        'glanced' => PresenceNoticeOutcome.glanced,
        'seenIgnored' => PresenceNoticeOutcome.seenIgnored,
        _ => PresenceNoticeOutcome.unseen,
      };
      final Object? afterMs = entry['glancedAfterMs'];
      notices.add(
        PresenceNotice(
          kind: kind,
          litAt: litAt,
          summary: switch (entry['summary']) {
            final String summary => summary,
            _ => '',
          },
          outcome: outcome,
          glancedAfter: afterMs is int ? Duration(milliseconds: afterMs) : null,
        ),
      );
    }
  }
  final Map<PresenceNoticeKind, DateTime> reenabledAt =
      <PresenceNoticeKind, DateTime>{};
  final Object? rawReenabled = json['reenabledAt'];
  if (rawReenabled is Map<String, Object?>) {
    for (final MapEntry<String, Object?> entry in rawReenabled.entries) {
      final PresenceNoticeKind? kind = PresenceNoticeKind.fromWireName(
        entry.key,
      );
      final DateTime? at = switch (entry.value) {
        final String at => DateTime.tryParse(at),
        _ => null,
      };
      if (kind != null && at != null) {
        reenabledAt[kind] = at;
      }
    }
  }
  final Map<PresenceNoticeKind, int> suppressed = <PresenceNoticeKind, int>{};
  final Object? rawSuppressed = json['suppressed'];
  if (rawSuppressed is Map<String, Object?>) {
    for (final MapEntry<String, Object?> entry in rawSuppressed.entries) {
      final PresenceNoticeKind? kind = PresenceNoticeKind.fromWireName(
        entry.key,
      );
      final Object? count = entry.value;
      if (kind != null && count is int) {
        suppressed[kind] = count;
      }
    }
  }
  final Map<String, int> unlitOpens = <String, int>{};
  final Object? rawUnlit = json['unlitOpens'];
  if (rawUnlit is Map<String, Object?>) {
    for (final MapEntry<String, Object?> entry in rawUnlit.entries) {
      final Object? count = entry.value;
      if (count is int) {
        unlitOpens[entry.key] = count;
      }
    }
  }
  return PresenceNoticeLedger(
    notices: notices,
    reenabledAt: reenabledAt,
    suppressed: suppressed,
    unlitOpens: unlitOpens,
  );
}

/// Where the ledger is kept between runs.
abstract interface class PresenceNoticeStore {
  /// Reads the ledger, empty when there is none.
  Future<PresenceNoticeLedger> load();

  /// Writes [ledger] out.
  Future<void> save(PresenceNoticeLedger ledger);
}

/// A ledger that lives only as long as the app runs.
///
/// For widget tests and the preview, which must not write measurement into
/// the user's real file.
final class InMemoryPresenceNoticeStore implements PresenceNoticeStore {
  PresenceNoticeLedger _ledger = PresenceNoticeLedger.empty();

  @override
  Future<PresenceNoticeLedger> load() async => _ledger;

  @override
  Future<void> save(PresenceNoticeLedger ledger) async {
    _ledger = ledger;
  }
}

/// The ledger in one JSON file beside the profile.
final class FilePresenceNoticeStore implements PresenceNoticeStore {
  /// Creates a store for [file].
  const FilePresenceNoticeStore({required this.file});

  /// The one file, human-readable on purpose.
  final File file;

  @override
  Future<PresenceNoticeLedger> load() async {
    if (!file.existsSync()) {
      return PresenceNoticeLedger.empty();
    }
    try {
      return decodePresenceNoticeLedger(jsonDecode(file.readAsStringSync()));
    } on Object {
      return PresenceNoticeLedger.empty();
    }
  }

  @override
  Future<void> save(PresenceNoticeLedger ledger) async {
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    // Indented, like the profile beside it: this is the file the user opens
    // when they want to know what the light has been doing.
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(encodePresenceNoticeLedger(ledger))}\n',
      flush: true,
    );
  }
}
