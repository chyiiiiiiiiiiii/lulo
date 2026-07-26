import 'app_composition.dart';
import 'fake_runtime.dart';

/// Immutable configuration selected before the application composition is built.
final class BootstrapConfig {
  /// Creates bootstrap configuration for the local macOS application.
  const BootstrapConfig({
    required this.localOnly,
    required this.targetFrameRate,
  });

  /// Whether the application communicates only with local services.
  final bool localOnly;

  /// The intended animation refresh-rate budget.
  final int targetFrameRate;
}

/// Creates the fixed bootstrap configuration for the local-first application.
BootstrapConfig createBootstrapConfig() {
  return const BootstrapConfig(localOnly: true, targetFrameRate: 120);
}

/// Builds the application dependency graph from compile-time configuration.
AppComposition createAppComposition({
  String inferenceRuntime = const String.fromEnvironment(
    'INFERENCE_RUNTIME',
    defaultValue: 'fake',
  ),
}) {
  if (inferenceRuntime != 'fake') {
    throw UnsupportedError(
      'Unsupported INFERENCE_RUNTIME "$inferenceRuntime". '
      'The testable preview currently supports only "fake".',
    );
  }

  final InMemoryConversationStorageService storageService =
      InMemoryConversationStorageService();
  final DeterministicFakeInferenceService inferenceService =
      DeterministicFakeInferenceService();
  return AppComposition(
    () async {
      await inferenceService.dispose();
      storageService.dispose();
    },
    storageService: storageService,
    inferenceService: inferenceService,
  );
}
