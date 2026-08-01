import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:lulo_voice_eval/voice_eval.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption('corpus', mandatory: true, help: 'Voice corpus JSON manifest.')
    ..addMultiOption(
      'candidate',
      help: 'Candidate JSON file. May be supplied more than once.',
    )
    ..addOption('output', mandatory: true, help: 'New report directory.')
    ..addFlag(
      'require-audio',
      negatable: false,
      help: 'Fail when any private corpus WAV is missing.',
    );
  try {
    final ArgResults options = parser.parse(arguments);
    final File corpusFile = File(options.option('corpus')!);
    final Directory output = Directory(options.option('output')!);
    if (output.existsSync()) {
      throw StateError('output directory already exists');
    }
    final VoiceCorpus corpus = VoiceCorpus.fromJson(
      _readObject(corpusFile),
      source: corpusFile.path,
      audioExists: (String relativePath) =>
          File(p.join(corpusFile.parent.path, relativePath)).existsSync(),
    );
    final bool requireAudio = options.flag('require-audio');
    if (requireAudio &&
        corpus.cases.any(
          (VoiceEvalCase value) => value.audioStatus == AudioStatus.missing,
        )) {
      throw StateError('required private corpus audio is missing');
    }
    final List<CandidateRun> candidates = <CandidateRun>[];
    for (final String candidatePath in options.multiOption('candidate')) {
      final File file = File(candidatePath);
      candidates.add(
        CandidateRun.fromJson(_readObject(file), source: file.path),
      );
    }
    final EvaluationReport report = VoiceEvaluation.evaluate(
      corpus: corpus,
      candidates: candidates,
      blindSeed: 1,
    );
    await _writeAtomically(output, report);
    stdout.writeln('Voice evaluation written to ${_redactHome(output.path)}');
  } on Object catch (error) {
    stderr.writeln('voice-eval: ${_redactHome(error.toString())}');
    stderr.writeln(parser.usage);
    exitCode = 64;
  }
}

Map<String, Object?> _readObject(File file) {
  final Object? decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('JSON root must be an object');
  }
  return decoded;
}

Future<void> _writeAtomically(Directory output, EvaluationReport report) async {
  final Directory parent = output.parent;
  await parent.create(recursive: true);
  final Directory staging = Directory(
    p.join(
      parent.path,
      '.${p.basename(output.path)}.tmp-${Random.secure().nextInt(1 << 32)}',
    ),
  );
  await staging.create();
  try {
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    await File(
      p.join(staging.path, 'report.json'),
    ).writeAsString('${encoder.convert(report.toJson())}\n');
    await File(
      p.join(staging.path, 'summary.md'),
    ).writeAsString(report.toSummaryMarkdown());
    final List<Object?> reviewClips =
        report.reviewSheet['clips']! as List<Object?>;
    if (reviewClips.isNotEmpty) {
      await File(
        p.join(staging.path, 'review.json'),
      ).writeAsString('${encoder.convert(report.reviewSheet)}\n');
      await File(
        p.join(staging.path, 'review-key.json'),
      ).writeAsString('${encoder.convert(report.reviewKey)}\n');
    }
    await staging.rename(output.path);
  } on Object {
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    rethrow;
  }
}

String _redactHome(String value) {
  final String home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) {
    return value;
  }
  return value.replaceAll(home, '~');
}
