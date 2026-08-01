/// Relationship between a shadow submission and its expected time window.
enum TurnClassification {
  /// The candidate would have submitted too soon.
  early,

  /// The candidate submitted within the inclusive expected window.
  withinWindow,

  /// The candidate would have submitted too late.
  late,

  /// The candidate never emitted a submission decision.
  missing,
}

/// One measured segment of user speech.
final class SpeechSegment {
  /// Creates a segment using milliseconds from the start of source audio.
  const SpeechSegment({required this.startMs, required this.endMs});

  /// Inclusive segment start.
  final int startMs;

  /// Inclusive segment end.
  final int endMs;
}

/// Inclusive acceptable submission window.
final class SubmitWindow {
  /// Creates an expected window.
  const SubmitWindow({required this.startMs, required this.endMs});

  /// Earliest acceptable submission.
  final int startMs;

  /// Latest acceptable submission.
  final int endMs;
}

/// Timestamp evidence from today's endpoint and one shadow candidate.
final class TurnCandidate {
  /// Creates and validates a turn candidate without invoking live behavior.
  factory TurnCandidate({
    required String caseId,
    required List<SpeechSegment> speechSegments,
    required int baselineSubmitAtMs,
    required int? candidateSubmitAtMs,
    required SubmitWindow expectedSubmitWindow,
  }) {
    if (caseId.trim().isEmpty || speechSegments.isEmpty) {
      throw ArgumentError('caseId and speechSegments must be non-empty');
    }
    int previousEnd = -1;
    for (final SpeechSegment segment in speechSegments) {
      if (segment.startMs < 0 ||
          segment.endMs < segment.startMs ||
          segment.startMs < previousEnd) {
        throw ArgumentError(
          'speechSegments must be ordered and non-overlapping',
        );
      }
      previousEnd = segment.endMs;
    }
    if (expectedSubmitWindow.startMs < 0 ||
        expectedSubmitWindow.endMs < expectedSubmitWindow.startMs) {
      throw ArgumentError('expectedSubmitWindow must be ordered');
    }
    return TurnCandidate._(
      caseId: caseId,
      speechSegments: List<SpeechSegment>.unmodifiable(speechSegments),
      baselineSubmitAtMs: baselineSubmitAtMs,
      candidateSubmitAtMs: candidateSubmitAtMs,
      expectedSubmitWindow: expectedSubmitWindow,
    );
  }

  const TurnCandidate._({
    required this.caseId,
    required this.speechSegments,
    required this.baselineSubmitAtMs,
    required this.candidateSubmitAtMs,
    required this.expectedSubmitWindow,
  });

  /// Corpus case receiving the decision.
  final String caseId;

  /// Ordered measured speech intervals.
  final List<SpeechSegment> speechSegments;

  /// Submission time from today's production endpoint.
  final int baselineSubmitAtMs;

  /// Submission time the shadow candidate would choose, if any.
  final int? candidateSubmitAtMs;

  /// Human-authored acceptable submission window.
  final SubmitWindow expectedSubmitWindow;
}

/// Derived metrics for one shadow turn candidate.
final class TurnScore {
  /// Creates a complete turn score.
  const TurnScore({
    required this.caseId,
    required this.classification,
    required this.baselineLatencyMs,
    required this.candidateLatencyMs,
    required this.deltaFromBaselineMs,
  });

  /// Corpus case receiving the decision.
  final String caseId;

  /// Window classification for the shadow decision.
  final TurnClassification classification;

  /// Baseline submission latency after final measured speech.
  final int baselineLatencyMs;

  /// Shadow latency after final speech, or `null` when missing.
  final int? candidateLatencyMs;

  /// Shadow latency minus baseline latency, or `null` when missing.
  final int? deltaFromBaselineMs;
}

/// Corpus-level turn classification counts.
final class TurnSummary {
  /// Creates aggregate turn counts.
  const TurnSummary({
    required this.total,
    required this.early,
    required this.withinWindow,
    required this.late,
    required this.missing,
  });

  /// Total scored cases.
  final int total;

  /// Cases submitted before their expected window.
  final int early;

  /// Cases submitted inside their expected window.
  final int withinWindow;

  /// Cases submitted after their expected window.
  final int late;

  /// Cases with no shadow decision.
  final int missing;
}

/// Scores one shadow decision without changing the live endpoint.
TurnScore scoreTurn(TurnCandidate candidate) {
  final int lastSpeechEnd = candidate.speechSegments.last.endMs;
  final int baselineLatency = candidate.baselineSubmitAtMs - lastSpeechEnd;
  final int? submitAt = candidate.candidateSubmitAtMs;
  if (submitAt == null) {
    return TurnScore(
      caseId: candidate.caseId,
      classification: TurnClassification.missing,
      baselineLatencyMs: baselineLatency,
      candidateLatencyMs: null,
      deltaFromBaselineMs: null,
    );
  }
  final TurnClassification classification;
  if (submitAt < candidate.expectedSubmitWindow.startMs) {
    classification = TurnClassification.early;
  } else if (submitAt > candidate.expectedSubmitWindow.endMs) {
    classification = TurnClassification.late;
  } else {
    classification = TurnClassification.withinWindow;
  }
  final int candidateLatency = submitAt - lastSpeechEnd;
  return TurnScore(
    caseId: candidate.caseId,
    classification: classification,
    baselineLatencyMs: baselineLatency,
    candidateLatencyMs: candidateLatency,
    deltaFromBaselineMs: candidateLatency - baselineLatency,
  );
}

/// Aggregates classification counts without discarding missing decisions.
TurnSummary summarizeTurns(Iterable<TurnScore> scores) {
  int total = 0;
  int early = 0;
  int withinWindow = 0;
  int late = 0;
  int missing = 0;
  for (final TurnScore score in scores) {
    total += 1;
    switch (score.classification) {
      case TurnClassification.early:
        early += 1;
      case TurnClassification.withinWindow:
        withinWindow += 1;
      case TurnClassification.late:
        late += 1;
      case TurnClassification.missing:
        missing += 1;
    }
  }
  return TurnSummary(
    total: total,
    early: early,
    withinWindow: withinWindow,
    late: late,
    missing: missing,
  );
}
