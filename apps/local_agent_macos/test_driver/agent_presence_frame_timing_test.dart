import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      final Object? rawReport = data?['agent_presence_frame_report'];
      final Map<Object?, Object?>? reportData =
          rawReport is Map<Object?, Object?> ? rawReport : null;
      if (reportData?['harness_completion_stage'] != 'complete') {
        throw StateError(
          'Presence profile did not reach the completed harness stage.',
        );
      }
      final bool isSmoke = reportData?['evidence_kind'] == 'smoke';
      final String destination = isSmoke
          ? 'build/agent_presence_profile/smoke'
          : 'build/agent_presence_profile';
      final String filename = isSmoke
          ? 'agent_presence_frame_timing_smoke'
          : 'agent_presence_frame_timing';
      await writeResponseData(
        data,
        testOutputFilename: filename,
        destinationDirectory: destination,
      );

      final File report = File('$destination/$filename.json');
      final ProcessResult hash = await Process.run('shasum', <String>[
        '-a',
        '256',
        report.path,
      ]);
      if (hash.exitCode != 0) {
        throw StateError('Unable to hash the presence profile report.');
      }
      final String digest = LineSplitter.split(
        hash.stdout.toString(),
      ).first.split(' ').first;
      File(
        '$destination/$filename.sha256',
      ).writeAsStringSync('$digest  $filename.json\n', flush: true);
    },
  );
}
