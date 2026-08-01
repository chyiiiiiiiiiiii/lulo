import 'dart:math';

import 'candidate.dart';
import 'corpus.dart';
import 'transcript_metrics.dart';
import 'turn_metrics.dart';

/// Deterministic machine and human-review artifacts for one evaluation.
final class EvaluationReport {
  /// Creates a completed report.
  const EvaluationReport({
    required this.corpusId,
    required this.candidateSummaries,
    required this.reviewSheet,
    required this.reviewKey,
  });

  /// Evaluated corpus identity.
  final String corpusId;

  /// Sorted machine-readable candidate summaries.
  final List<Map<String, Object?>> candidateSummaries;

  /// Opaque blind-review clips and score fields.
  final Map<String, Object?> reviewSheet;

  /// Separate mapping that reveals each blind clip's producer.
  final Map<String, Object?> reviewKey;

  /// Serializes stable machine-readable output.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'corpusId': corpusId,
    'candidates': candidateSummaries,
  };

  /// Builds a concise comparison without prompt or transcript content.
  String toSummaryMarkdown() {
    final StringBuffer output = StringBuffer()
      ..writeln('# Lulo voice evaluation')
      ..writeln()
      ..writeln('Corpus: `$corpusId`')
      ..writeln()
      ..writeln('| Candidate | Kind | Cases | Result |')
      ..writeln('|---|---:|---:|---|');
    for (final Map<String, Object?> candidate in candidateSummaries) {
      final Map<String, Object?> summary =
          candidate['summary']! as Map<String, Object?>;
      output.writeln(
        '| ${candidate['runId']} | ${candidate['kind']} | '
        '${candidate['caseCount']} | ${_summaryResult(summary)} |',
      );
    }
    return output.toString();
  }
}

/// Evaluates validated candidate runs against one corpus.
abstract final class VoiceEvaluation {
  /// Produces deterministic reports and blind-review ordering.
  static EvaluationReport evaluate({
    required VoiceCorpus corpus,
    required List<CandidateRun> candidates,
    required int blindSeed,
  }) {
    final Set<String> identities = <String>{};
    for (final CandidateRun run in candidates) {
      if (run.corpusId != corpus.corpusId) {
        throw ArgumentError('candidate corpusId does not match corpus');
      }
      if (!identities.add(run.identity)) {
        throw ArgumentError('duplicate candidate identity ${run.identity}');
      }
    }
    final Map<String, VoiceEvalCase> corpusCases = <String, VoiceEvalCase>{
      for (final VoiceEvalCase value in corpus.cases) value.id: value,
    };
    final List<CandidateRun> sortedRuns = List<CandidateRun>.of(candidates)
      ..sort(
        (CandidateRun a, CandidateRun b) => a.identity.compareTo(b.identity),
      );
    final List<Map<String, Object?>> summaries = sortedRuns
        .map((CandidateRun run) => _summarizeRun(run, corpusCases))
        .toList(growable: false);
    final List<_BlindClip> clips = <_BlindClip>[
      for (final CandidateRun run in sortedRuns)
        if (run.kind == CandidateKind.tts)
          for (final CandidateCase value in run.cases)
            _BlindClip(run: run, value: value as TtsCandidateCase),
    ]..shuffle(Random(blindSeed));
    final List<Map<String, Object?>> sheetEntries = <Map<String, Object?>>[];
    final List<Map<String, Object?>> keyEntries = <Map<String, Object?>>[];
    for (int index = 0; index < clips.length; index += 1) {
      final String label = 'clip-${(index + 1).toString().padLeft(3, '0')}';
      final _BlindClip clip = clips[index];
      sheetEntries.add(<String, Object?>{
        'label': label,
        'audioPath': 'artifacts/blind/$label.wav',
        'scores': <String, Object?>{
          'taiwanMandarinNaturalness': null,
          'voiceIdentityConsistency': null,
          'pacingAndPauses': null,
          'intelligibility': null,
          'listeningPreference': null,
        },
      });
      keyEntries.add(<String, Object?>{
        'label': label,
        'runId': clip.run.runId,
        'adapter': clip.run.adapter.name,
        'caseId': clip.value.caseId,
        'sourceAudioPath': clip.value.audioPath,
      });
    }
    return EvaluationReport(
      corpusId: corpus.corpusId,
      candidateSummaries: List<Map<String, Object?>>.unmodifiable(summaries),
      reviewSheet: <String, Object?>{'schemaVersion': 1, 'clips': sheetEntries},
      reviewKey: <String, Object?>{'schemaVersion': 1, 'clips': keyEntries},
    );
  }
}

Map<String, Object?> _summarizeRun(
  CandidateRun run,
  Map<String, VoiceEvalCase> corpusCases,
) {
  final List<CandidateCase> cases = List<CandidateCase>.of(run.cases)
    ..sort((CandidateCase a, CandidateCase b) => a.caseId.compareTo(b.caseId));
  final Map<String, Object?> summary;
  switch (run.kind) {
    case CandidateKind.transcript:
      final List<TranscriptComparison> comparisons = cases
          .map((CandidateCase value) {
            final TranscriptCandidateCase candidate =
                value as TranscriptCandidateCase;
            final VoiceEvalCase? reference = corpusCases[candidate.caseId];
            if (reference == null) {
              throw ArgumentError('unknown corpus case ${candidate.caseId}');
            }
            return compareTranscripts(
              reference: reference.expectedTranscript,
              rawTranscript: candidate.rawTranscript,
              refinedTranscript: candidate.refinedTranscript,
            );
          })
          .toList(growable: false);
      summary = <String, Object?>{
        'meanRawLiteralCer': _mean(
          comparisons.map(
            (TranscriptComparison value) => value.raw.literal.cer,
          ),
        ),
        'meanRawSpokenCer': _mean(
          comparisons.map((TranscriptComparison value) => value.raw.spoken.cer),
        ),
        'meanRefinedLiteralCer': _mean(
          comparisons
              .where((TranscriptComparison value) => value.refined != null)
              .map((TranscriptComparison value) => value.refined!.literal.cer),
        ),
        'meanRefinedSpokenCer': _mean(
          comparisons
              .where((TranscriptComparison value) => value.refined != null)
              .map((TranscriptComparison value) => value.refined!.spoken.cer),
        ),
      };
    case CandidateKind.turn:
      final TurnSummary turns = summarizeTurns(
        cases.map(
          (CandidateCase value) => scoreTurn((value as TurnCandidateCase).turn),
        ),
      );
      summary = <String, Object?>{
        'early': turns.early,
        'within_window': turns.withinWindow,
        'late': turns.late,
        'missing': turns.missing,
      };
    case CandidateKind.tts:
      final List<TtsCandidateCase> ttsCases = cases.cast<TtsCandidateCase>();
      summary = <String, Object?>{
        'meanFirstAudioLatencyMs': _mean(
          ttsCases.map(
            (TtsCandidateCase value) =>
                (value.firstAudioAtMs - value.requestStartedAtMs).toDouble(),
          ),
        ),
        'meanCompletionLatencyMs': _mean(
          ttsCases.map(
            (TtsCandidateCase value) =>
                (value.completedAtMs - value.requestStartedAtMs).toDouble(),
          ),
        ),
        'meanRealTimeFactor': _mean(
          ttsCases.map(
            (TtsCandidateCase value) =>
                (value.completedAtMs - value.requestStartedAtMs) /
                value.audioDurationMs,
          ),
        ),
      };
  }
  return <String, Object?>{
    'kind': run.kind.name,
    'runId': run.runId,
    'adapter': <String, Object?>{
      'name': run.adapter.name,
      'version': run.adapter.version,
    },
    'caseCount': cases.length,
    'summary': summary,
  };
}

double? _mean(Iterable<double> values) {
  final List<double> materialized = values.toList(growable: false);
  if (materialized.isEmpty) {
    return null;
  }
  return materialized.reduce((double a, double b) => a + b) /
      materialized.length;
}

String _summaryResult(Map<String, Object?> summary) {
  if (summary.containsKey('within_window')) {
    return 'within_window ${summary['within_window']}, early ${summary['early']}, '
        'late ${summary['late']}, missing ${summary['missing']}';
  }
  if (summary.containsKey('meanRawSpokenCer')) {
    return 'spoken CER ${summary['meanRawSpokenCer']}';
  }
  return 'first audio ${summary['meanFirstAudioLatencyMs']} ms';
}

final class _BlindClip {
  const _BlindClip({required this.run, required this.value});

  final CandidateRun run;
  final TtsCandidateCase value;
}
