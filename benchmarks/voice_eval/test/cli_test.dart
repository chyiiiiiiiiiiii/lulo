import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('lulo-voice-eval-');
  });

  tearDown(() {
    sandbox.deleteSync(recursive: true);
  });

  test(
    'metadata-only run writes a report despite missing private audio',
    () async {
      final File corpus = _writeCorpus(sandbox);
      final Directory output = Directory(p.join(sandbox.path, 'run'));

      final ProcessResult result = await _run(<String>[
        '--corpus',
        corpus.path,
        '--output',
        output.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(File(p.join(output.path, 'report.json')).existsSync(), isTrue);
      expect(File(p.join(output.path, 'summary.md')).existsSync(), isTrue);
    },
  );

  test('require-audio fails without creating a partial output', () async {
    final File corpus = _writeCorpus(sandbox);
    final Directory output = Directory(p.join(sandbox.path, 'run'));

    final ProcessResult result = await _run(<String>[
      '--corpus',
      corpus.path,
      '--output',
      output.path,
      '--require-audio',
    ]);

    expect(result.exitCode, isNonZero);
    expect(output.existsSync(), isFalse);
  });

  test('refuses to overwrite an existing output directory', () async {
    final File corpus = _writeCorpus(sandbox);
    final Directory output = Directory(p.join(sandbox.path, 'run'))
      ..createSync();
    File(p.join(output.path, 'keep.txt')).writeAsStringSync('keep');

    final ProcessResult result = await _run(<String>[
      '--corpus',
      corpus.path,
      '--output',
      output.path,
    ]);

    expect(result.exitCode, isNonZero);
    expect(File(p.join(output.path, 'keep.txt')).readAsStringSync(), 'keep');
  });
}

Future<ProcessResult> _run(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  <String>['run', 'tool/evaluate.dart', ...arguments],
  workingDirectory: Directory.current.path,
);

File _writeCorpus(Directory root) {
  final Directory corpusDirectory = Directory(p.join(root.path, 'corpus'))
    ..createSync();
  return File(p.join(corpusDirectory.path, 'zh-TW.json'))..writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'corpusId': 'zh-TW-test',
      'locale': 'zh-TW',
      'cases': <Object?>[
        <String, Object?>{
          'id': 'short-answer',
          'category': 'short_answer',
          'prompt': '好。',
          'expectedTranscript': '好。',
          'audioPath': 'audio/short-answer.wav',
          'tags': <String>['short'],
          'expectedPausesMs': <int>[],
          'notes': '',
        },
      ],
    }),
  );
}
