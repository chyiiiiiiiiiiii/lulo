import 'package:integration_test/integration_test_driver.dart';

/// Drives the real-model slice so it can run against a profile-mode build.
///
/// The widget test records its own timings into `binding.reportData`, which
/// only `flutter drive` persists, so this driver writes them out as evidence.
Future<void> main() {
  return integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) {
      return writeResponseData(
        data,
        testOutputFilename: 'litert_gemma_slice',
        destinationDirectory: 'build/litert_evidence',
      );
    },
  );
}
