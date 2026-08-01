import 'package:lulo_voice_eval/voice_eval.dart';
import 'package:test/test.dart';

void main() {
  group('VoiceCorpus', () {
    test('loads a valid Taiwan Mandarin manifest', () {
      final VoiceCorpus corpus = VoiceCorpus.fromJson(
        _manifest(<Map<String, Object?>>[_validCase()]),
        source: 'corpus.json',
      );

      expect(corpus.schemaVersion, 1);
      expect(corpus.corpusId, 'zh-TW-v1');
      expect(corpus.locale, 'zh-TW');
      expect(corpus.cases, hasLength(1));
      expect(corpus.cases.single.id, 'short-answer-ready');
      expect(corpus.cases.single.audioPath, 'audio/short-answer-ready.wav');
      expect(corpus.cases.single.audioStatus, AudioStatus.missing);
    });

    test('rejects duplicate case ids', () {
      expect(
        () => VoiceCorpus.fromJson(
          _manifest(<Map<String, Object?>>[_validCase(), _validCase()]),
          source: 'private/corpus.json',
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            'private/corpus.json: case short-answer-ready: duplicate id',
          ),
        ),
      );
    });

    for (final ({String name, Object? value}) example
        in <({String name, Object? value})>[
          (name: 'non-kebab id', value: 'Short Answer'),
          (name: 'empty id', value: ''),
        ]) {
      test('rejects ${example.name}', () {
        expect(
          () => VoiceCorpus.fromJson(
            _manifest(<Map<String, Object?>>[
              _validCase()..['id'] = example.value,
            ]),
            source: 'corpus.json',
          ),
          throwsA(
            isA<FormatException>().having(
              (FormatException error) => error.message,
              'message',
              contains('invalid id'),
            ),
          ),
        );
      });
    }

    for (final String audioPath in <String>[
      '/tmp/private.wav',
      'audio/../private.wav',
      '../audio/private.wav',
      'audio/private.mp3',
      'clips/private.wav',
    ]) {
      test('rejects unsafe audio path $audioPath', () {
        expect(
          () => VoiceCorpus.fromJson(
            _manifest(<Map<String, Object?>>[
              _validCase()..['audioPath'] = audioPath,
            ]),
            source: 'corpus.json',
          ),
          throwsA(
            isA<FormatException>().having(
              (FormatException error) => error.message,
              'message',
              contains('invalid audioPath'),
            ),
          ),
        );
      });
    }

    test('names a missing field without echoing private content', () {
      final Map<String, Object?> invalid = _validCase()
        ..remove('expectedTranscript')
        ..['prompt'] = '我的身分證號是不要出現在錯誤裡';

      expect(
        () => VoiceCorpus.fromJson(
          _manifest(<Map<String, Object?>>[invalid]),
          source: 'corpus.json',
        ),
        throwsA(
          isA<FormatException>()
              .having(
                (FormatException error) => error.message,
                'message',
                'corpus.json: case short-answer-ready: invalid expectedTranscript',
              )
              .having(
                (FormatException error) => error.message,
                'private content',
                isNot(contains('身分證')),
              ),
        ),
      );
    });
  });
}

Map<String, Object?> _manifest(List<Map<String, Object?>> cases) =>
    <String, Object?>{
      'schemaVersion': 1,
      'corpusId': 'zh-TW-v1',
      'locale': 'zh-TW',
      'cases': cases,
    };

Map<String, Object?> _validCase() => <String, Object?>{
  'id': 'short-answer-ready',
  'category': 'short_answer',
  'prompt': '好，可以開始了。',
  'expectedTranscript': '好，可以開始了。',
  'audioPath': 'audio/short-answer-ready.wav',
  'tags': <String>['short', 'acknowledgement'],
  'expectedPausesMs': <int>[],
  'notes': 'A natural short acknowledgement.',
};
