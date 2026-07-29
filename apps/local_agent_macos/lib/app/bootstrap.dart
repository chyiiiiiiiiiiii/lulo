import 'dart:async';
import 'dart:io';

import '../features/conversation/pigeon_inference_service.dart';
import '../features/settings/app_settings.dart';
import '../platform/pigeon_desktop_host_service.dart';
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
  String localModelPath = const String.fromEnvironment('LOCAL_MODEL_PATH'),
}) {
  if (inferenceRuntime != 'fake' && inferenceRuntime != 'litert') {
    throw UnsupportedError(
      'Unsupported INFERENCE_RUNTIME "$inferenceRuntime". '
      'Supported runtimes are "fake" and "litert".',
    );
  }

  final InMemoryConversationStorageService storageService =
      InMemoryConversationStorageService();
  if (inferenceRuntime == 'litert') {
    final String modelPath = localModelPath.trim();
    if (modelPath.isEmpty) {
      storageService.dispose();
      throw ArgumentError.value(
        localModelPath,
        'localModelPath',
        'A LiteRT-LM model path is required.',
      );
    }
    final PigeonDesktopHostService desktopHostService =
        PigeonDesktopHostService();
    final PigeonInferenceService inferenceService = PigeonInferenceService(
      desktopHostService: desktopHostService,
      config: LocalModelConfig(
        modelId: 'gemma-4-E4B-it',
        modelPath: modelPath,
        contextSize: 4096,
        temperature: 0.7,
        topP: 0.95,
        maxTokens: 512,
        seed: 7,
      ),
    );
    // Start loading the model immediately instead of on the first prompt.
    // The load takes seconds, and this is a resident agent that is launched
    // once and summoned repeatedly, so paying it during startup keeps it off
    // the critical path of the first answer.
    //
    // The failure is deliberately dropped here: the readiness attempt is
    // cleared when it fails, so the first real prompt retries and reports the
    // error through the conversation, where the user can actually see it.
    unawaited(inferenceService.warmUp().catchError((Object _) {}));
    return AppComposition(
      () async {
        await inferenceService.dispose();
        storageService.dispose();
        await desktopHostService.dispose();
      },
      storageService: storageService,
      inferenceService: inferenceService,
      settingsStore: _settingsStore(),
      presentationHost: desktopHostService,
    );
  }

  final DeterministicFakeInferenceService inferenceService =
      DeterministicFakeInferenceService();
  final PigeonDesktopHostService desktopHostService =
      PigeonDesktopHostService();
  return AppComposition(
    () async {
      await inferenceService.dispose();
      storageService.dispose();
      await desktopHostService.dispose();
    },
    storageService: storageService,
    inferenceService: inferenceService,
    settingsStore: _settingsStore(),
    presentationHost: desktopHostService,
  );
}

/// Where the user's choices live between runs.
///
/// Under Application Support like any other Mac app's own data. A home that
/// cannot be resolved falls back to memory, so settings are forgotten rather
/// than the app refusing to start.
SettingsStore _settingsStore() {
  final String? home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return InMemorySettingsStore();
  }
  return FileSettingsStore(
    directory: Directory('$home/Library/Application Support/Pocket Agent'),
  );
}
