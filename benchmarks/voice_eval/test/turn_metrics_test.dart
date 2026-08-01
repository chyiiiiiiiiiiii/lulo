import 'package:lulo_voice_eval/voice_eval.dart';
import 'package:test/test.dart';

void main() {
  group('scoreTurn', () {
    test('classifies inclusive window boundaries', () {
      expect(
        _score(candidateSubmitAtMs: 1200).classification,
        TurnClassification.withinWindow,
      );
      expect(
        _score(candidateSubmitAtMs: 1800).classification,
        TurnClassification.withinWindow,
      );
    });

    test('classifies early late and missing decisions', () {
      expect(
        _score(candidateSubmitAtMs: 1199).classification,
        TurnClassification.early,
      );
      expect(
        _score(candidateSubmitAtMs: 1801).classification,
        TurnClassification.late,
      );
      expect(
        _score(candidateSubmitAtMs: null).classification,
        TurnClassification.missing,
      );
    });

    test('reports latency from final speech and delta from baseline', () {
      final TurnScore score = _score(candidateSubmitAtMs: 1320);

      expect(score.candidateLatencyMs, 380);
      expect(score.baselineLatencyMs, 800);
      expect(score.deltaFromBaselineMs, -420);
    });

    test('retains negative latency as premature evidence', () {
      final TurnScore score = _score(candidateSubmitAtMs: 900);

      expect(score.candidateLatencyMs, -40);
      expect(score.classification, TurnClassification.early);
    });
  });

  test('summarizes every classification', () {
    final TurnSummary summary = summarizeTurns(<TurnScore>[
      _score(candidateSubmitAtMs: 900),
      _score(candidateSubmitAtMs: 1500),
      _score(candidateSubmitAtMs: 1900),
      _score(candidateSubmitAtMs: null),
    ]);

    expect(summary.total, 4);
    expect(summary.early, 1);
    expect(summary.withinWindow, 1);
    expect(summary.late, 1);
    expect(summary.missing, 1);
  });

  test('rejects unordered speech segments', () {
    expect(
      () => TurnCandidate(
        caseId: 'bad-segments',
        speechSegments: const <SpeechSegment>[
          SpeechSegment(startMs: 500, endMs: 800),
          SpeechSegment(startMs: 700, endMs: 900),
        ],
        baselineSubmitAtMs: 1700,
        candidateSubmitAtMs: 1500,
        expectedSubmitWindow: const SubmitWindow(startMs: 1200, endMs: 1800),
      ),
      throwsArgumentError,
    );
  });
}

TurnScore _score({required int? candidateSubmitAtMs}) => scoreTurn(
  TurnCandidate(
    caseId: 'endpoint-thinking-pause',
    speechSegments: const <SpeechSegment>[
      SpeechSegment(startMs: 0, endMs: 940),
    ],
    baselineSubmitAtMs: 1740,
    candidateSubmitAtMs: candidateSubmitAtMs,
    expectedSubmitWindow: const SubmitWindow(startMs: 1200, endMs: 1800),
  ),
);
