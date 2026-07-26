import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) {
      return writeResponseData(
        data,
        testOutputFilename: 'empty_shell_frame_timing',
        destinationDirectory: 'build/cp0_frame_timing',
      );
    },
  );
}
