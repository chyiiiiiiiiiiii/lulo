import 'dart:convert';
import 'dart:io';

import 'package:local_agent_macos/features/presence/agent_presence_frame_metrics.dart';

/// Validates one preserved raw profile report using the pure timing evaluator.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/benchmark/agent_presence_profile_report.dart '
      '<frame-timing.json>',
    );
    exitCode = 64;
    return;
  }

  final File input = File(arguments.single);
  if (!input.existsSync()) {
    stderr.writeln('Profile report does not exist.');
    exitCode = 66;
    return;
  }

  final Object? decoded = jsonDecode(input.readAsStringSync());
  final Map<String, Object?>? envelope = _stringMap(decoded);
  final Map<String, Object?>? report = _stringMap(
    envelope?['agent_presence_frame_report'] ?? decoded,
  );
  if (report == null) {
    stderr.writeln('Profile report has no agent-presence payload.');
    exitCode = 65;
    return;
  }

  final AgentPresenceFrameEvaluation evaluation =
      evaluateAgentPresenceFrameReport(report);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(evaluation.toJson()),
  );
  if (!evaluation.isAccepted) {
    exitCode = 1;
  }
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  return value.map<String, Object?>(
    (Object? key, Object? entry) => MapEntry<String, Object?>('$key', entry),
  );
}
