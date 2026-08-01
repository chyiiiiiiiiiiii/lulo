import 'package:lulo_voice_eval/voice_eval.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reports transcript and turn metrics without private text in Markdown',
    () {
      final VoiceCorpus corpus = _corpus();
      final EvaluationReport report = VoiceEvaluation.evaluate(
        corpus: corpus,
        candidates: <CandidateRun>[_transcriptRun(), _turnRun()],
        blindSeed: 7,
      );

      final Map<String, Object?> json = report.toJson();
      final List<Object?> candidates = json['candidates']! as List<Object?>;
      expect(candidates, hasLength(2));
      expect(report.toSummaryMarkdown(), contains('apple-baseline'));
      expect(report.toSummaryMarkdown(), contains('within_window'));
      expect(report.toSummaryMarkdown(), isNot(contains('私人逐字稿')));
    },
  );

  test('reports TTS timing and deterministic separated blind keys', () {
    final EvaluationReport first = VoiceEvaluation.evaluate(
      corpus: _corpus(),
      candidates: <CandidateRun>[_ttsRun('qwen-a'), _ttsRun('qwen-b')],
      blindSeed: 42,
    );
    final EvaluationReport second = VoiceEvaluation.evaluate(
      corpus: _corpus(),
      candidates: <CandidateRun>[_ttsRun('qwen-a'), _ttsRun('qwen-b')],
      blindSeed: 42,
    );

    expect(first.reviewSheet, second.reviewSheet);
    expect(first.reviewKey, second.reviewKey);
    expect(first.reviewSheet.toString(), isNot(contains('qwen-a')));
    expect(first.reviewKey.toString(), contains('qwen-a'));

    final List<Object?> candidates =
        first.toJson()['candidates']! as List<Object?>;
    final Map<String, Object?> firstRun =
        candidates.first! as Map<String, Object?>;
    final Map<String, Object?> metrics =
        firstRun['summary']! as Map<String, Object?>;
    expect(metrics['meanFirstAudioLatencyMs'], 430.0);
    expect(metrics['meanRealTimeFactor'], closeTo(1.1605, 0.0001));
  });

  test('rejects duplicate identities and mismatched corpus ids', () {
    expect(
      () => VoiceEvaluation.evaluate(
        corpus: _corpus(),
        candidates: <CandidateRun>[_transcriptRun(), _transcriptRun()],
        blindSeed: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => VoiceEvaluation.evaluate(
        corpus: _corpus(),
        candidates: <CandidateRun>[
          CandidateRun.fromJson(
            _envelope('transcript', 'wrong-corpus', const <Object?>[]),
            source: 'wrong.json',
          ),
        ],
        blindSeed: 1,
      ),
      throwsArgumentError,
    );
  });
}

VoiceCorpus _corpus() => VoiceCorpus.fromJson(<String, Object?>{
  'schemaVersion': 1,
  'corpusId': 'zh-TW-v1',
  'locale': 'zh-TW',
  'cases': <Object?>[
    <String, Object?>{
      'id': 'private-case',
      'category': 'short_answer',
      'prompt': '私人逐字稿',
      'expectedTranscript': '正確答案',
      'audioPath': 'audio/private-case.wav',
      'tags': <String>['private'],
      'expectedPausesMs': <int>[],
      'notes': '',
    },
  ],
}, source: 'corpus.json');

CandidateRun _transcriptRun() => CandidateRun.fromJson(
  _envelope('transcript', 'zh-TW-v1', <Object?>[
    <String, Object?>{
      'caseId': 'private-case',
      'rawTranscript': '私人逐字稿',
      'refinedTranscript': '正確答案',
      'partialEvents': <Object?>[],
      'finalAtMs': 900,
    },
  ]),
  source: 'transcript.json',
);

CandidateRun _turnRun() => CandidateRun.fromJson(<String, Object?>{
  ..._envelope('turn', 'zh-TW-v1', <Object?>[
    <String, Object?>{
      'caseId': 'private-case',
      'speechSegments': <Object?>[
        <String, Object?>{'startMs': 0, 'endMs': 940},
      ],
      'baselineSubmitAtMs': 1740,
      'candidateSubmitAtMs': 1320,
      'expectedSubmitWindowMs': <String, Object?>{'start': 1200, 'end': 1800},
    },
  ]),
  'runId': 'smart-turn-shadow',
}, source: 'turn.json');

CandidateRun _ttsRun(String runId) => CandidateRun.fromJson(<String, Object?>{
  ..._envelope('tts', 'zh-TW-v1', <Object?>[
    <String, Object?>{
      'caseId': 'private-case',
      'text': '私人逐字稿',
      'voice': 'ryan',
      'requestStartedAtMs': 0,
      'firstAudioAtMs': 430,
      'completedAtMs': 3180,
      'audioDurationMs': 2740,
      'audioPath': 'artifacts/$runId.wav',
    },
  ]),
  'runId': runId,
  'adapter': <String, Object?>{'name': runId, 'version': '1'},
}, source: '$runId.json');

Map<String, Object?> _envelope(
  String kind,
  String corpusId,
  List<Object?> cases,
) => <String, Object?>{
  'schemaVersion': 1,
  'kind': kind,
  'runId': 'apple-baseline',
  'adapter': <String, Object?>{'name': 'apple', 'version': '27'},
  'corpusId': corpusId,
  'cases': cases,
};
