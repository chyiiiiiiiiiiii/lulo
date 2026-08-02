import 'dart:collection';

import 'package:agent_core/agent_core.dart';

/// Immutable aggregate and explicit-case snapshot of shadow evaluation.
final class TranscriptShadowEvidenceSnapshot {
  /// Creates an owned snapshot.
  TranscriptShadowEvidenceSnapshot({
    required Map<TranscriptShadowStatus, int> counts,
    required Map<String, TranscriptShadowResult> cases,
  }) : counts = Map<TranscriptShadowStatus, int>.unmodifiable(counts),
       cases = Map<String, TranscriptShadowResult>.unmodifiable(cases);

  /// Transcript-free terminal status totals.
  final Map<TranscriptShadowStatus, int> counts;

  /// Bounded transcript evidence from explicit development case IDs only.
  final Map<String, TranscriptShadowResult> cases;
}

/// Keeps aggregate statuses and a bounded set of explicit evaluation cases.
final class TranscriptShadowEvidence {
  /// Creates an in-memory evidence sink.
  TranscriptShadowEvidence({required this.capacity}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  /// Maximum number of transcript-bearing cases retained.
  final int capacity;

  final Map<TranscriptShadowStatus, int> _counts =
      <TranscriptShadowStatus, int>{};
  final LinkedHashMap<String, TranscriptShadowResult> _cases =
      LinkedHashMap<String, TranscriptShadowResult>();

  /// Records one result without retaining ordinary transcript text.
  void record(TranscriptShadowResult result) {
    _counts.update(result.status, (int count) => count + 1, ifAbsent: () => 1);
    final String? caseId = result.request.caseId;
    if (caseId == null) {
      return;
    }
    _cases.remove(caseId);
    _cases[caseId] = result;
    while (_cases.length > capacity) {
      _cases.remove(_cases.keys.first);
    }
  }

  /// Returns immutable copies of current counters and explicit cases.
  TranscriptShadowEvidenceSnapshot snapshot() =>
      TranscriptShadowEvidenceSnapshot(counts: _counts, cases: _cases);

  /// Clears counters and all transcript-bearing evidence.
  void clear() {
    _counts.clear();
    _cases.clear();
  }
}
