import 'package:lulo_voice_eval/voice_eval.dart';
import 'package:test/test.dart';

void main() {
  test('decodes a transcript candidate without replacing raw text', () {
    final CandidateRun run = CandidateRun.fromJson(
      _candidate(
        kind: 'transcript',
        cases: <Object?>[
          <String, Object?>{
            'caseId': 'code-switch-product-names',
            'rawTranscript': '我用 flutter',
            'refinedTranscript': '我用 Flutter',
            'partialEvents': <Object?>[
              <String, Object?>{'atMs': 420, 'text': '我用'},
            ],
            'finalAtMs': 2380,
          },
        ],
      ),
      source: 'candidate.json',
    );

    expect(run.kind, CandidateKind.transcript);
    expect(run.identity, 'transcript:apple-baseline');
    final TranscriptCandidateCase result =
        run.cases.single as TranscriptCandidateCase;
    expect(result.rawTranscript, '我用 flutter');
    expect(result.refinedTranscript, '我用 Flutter');
  });

  test('rejects non-monotonic partial timestamps without echoing text', () {
    expect(
      () => CandidateRun.fromJson(
        _candidate(
          kind: 'transcript',
          cases: <Object?>[
            <String, Object?>{
              'caseId': 'private-case',
              'rawTranscript': '不要出現在錯誤裡',
              'partialEvents': <Object?>[
                <String, Object?>{'atMs': 500, 'text': '私人內容'},
                <String, Object?>{'atMs': 400, 'text': '更多私人內容'},
              ],
              'finalAtMs': 900,
            },
          ],
        ),
        source: '/Users/you/private.json',
      ),
      throwsA(
        isA<FormatException>()
            .having(
              (FormatException error) => error.message,
              'field',
              contains('partialEvents'),
            )
            .having(
              (FormatException error) => error.message,
              'privacy',
              isNot(contains('私人內容')),
            ),
      ),
    );
  });

  test('decodes turn and TTS candidates through kind-specific schemas', () {
    final CandidateRun turn = CandidateRun.fromJson(
      _candidate(
        kind: 'turn',
        cases: <Object?>[
          <String, Object?>{
            'caseId': 'endpoint-thinking-pause',
            'speechSegments': <Object?>[
              <String, Object?>{'startMs': 0, 'endMs': 940},
            ],
            'baselineSubmitAtMs': 1740,
            'candidateSubmitAtMs': 1320,
            'expectedSubmitWindowMs': <String, Object?>{
              'start': 1200,
              'end': 1800,
            },
          },
        ],
      ),
      source: 'turn.json',
    );
    final CandidateRun tts = CandidateRun.fromJson(
      _candidate(
        kind: 'tts',
        cases: <Object?>[
          <String, Object?>{
            'caseId': 'punctuation-natural-clauses',
            'text': '先回答核心，細節等等補。',
            'voice': 'ryan',
            'requestStartedAtMs': 0,
            'firstAudioAtMs': 430,
            'completedAtMs': 3180,
            'audioDurationMs': 2740,
            'audioPath': 'artifacts/result.wav',
          },
        ],
      ),
      source: 'tts.json',
    );

    expect(turn.cases.single, isA<TurnCandidateCase>());
    expect(tts.cases.single, isA<TtsCandidateCase>());
  });

  for (final String kind in <String>['unknown', '']) {
    test('rejects invalid candidate kind $kind', () {
      expect(
        () => CandidateRun.fromJson(
          _candidate(kind: kind, cases: const <Object?>[]),
          source: 'candidate.json',
        ),
        throwsFormatException,
      );
    });
  }
}

Map<String, Object?> _candidate({
  required String kind,
  required List<Object?> cases,
}) => <String, Object?>{
  'schemaVersion': 1,
  'kind': kind,
  'runId': 'apple-baseline',
  'adapter': <String, Object?>{'name': 'apple-speech', 'version': '27'},
  'corpusId': 'zh-TW-v1',
  'cases': cases,
};
