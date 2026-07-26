import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      const String destination = 'build/agent_presence_profile';
      const String filename = 'agent_presence_frame_timing';
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
