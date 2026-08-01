import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../features/agent_profile/agent_context_provider.dart';
import '../features/agent_profile/agent_profile_store.dart';
import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/drift_conversation_storage_service.dart';
import '../features/conversation/pigeon_inference_service.dart';
import '../features/conversation/swappable_inference_service.dart';
import '../features/model/model_catalog.dart';
import '../features/model/model_download_manager.dart';
import '../features/model/model_file_service.dart';
import '../features/settings/app_settings.dart';
import '../features/voice/voice_service.dart';
import '../platform/desktop_host_service.dart';
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

/// A conversation store together with the way it is released.
///
/// The durable store has a database to close; the in-memory one has only its
/// maps to drop. Pairing each with its own release keeps the composition from
/// knowing which it holds — the same shape as [OwnedInferenceService].
final class OwnedConversationStorage {
  /// Creates a store paired with the way to release it.
  const OwnedConversationStorage({
    required this.service,
    required this.release,
  });

  /// The store itself.
  final ConversationStorageService service;

  /// Releases everything the store owns.
  final Future<void> Function() release;
}

/// Opens the durable conversation store, beside the settings.
///
/// SQLite through drift on a background isolate — the adapter ADR-003 names
/// as its maintainability control. A home that cannot be resolved falls back
/// to memory, so conversations are forgotten rather than the app refusing to
/// start — the same trade the settings make.
OwnedConversationStorage createDurableConversationStorage() {
  final String? home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    final InMemoryConversationStorageService fallback =
        InMemoryConversationStorageService();
    return OwnedConversationStorage(
      service: fallback,
      release: () async => fallback.dispose(),
    );
  }
  final Directory directory = Directory(
    '$home/Library/Application Support/Lulo',
  );
  directory.createSync(recursive: true);
  final DriftConversationStorageService service =
      DriftConversationStorageService(
        database: ConversationDatabase.atFile(
          File('${directory.path}/conversations.db'),
        ),
      );
  return OwnedConversationStorage(service: service, release: service.dispose);
}

/// Opens the curated-model download manager over the app's own models home.
///
/// Beside the conversations, under Application Support; a home that cannot be
/// resolved falls back to the system's temporary directory, the same trade
/// the other stores make.
ModelDownloadManager createModelDownloadManager() {
  final String? home = Platform.environment['HOME'];
  final String base = (home == null || home.isEmpty)
      ? Directory.systemTemp.path
      : '$home/Library/Application Support/Lulo';
  return ModelDownloadManager(
    files: ModelFileService(modelsDirectory: Directory('$base/models')),
  );
}

/// Builds the application dependency graph from compile-time configuration.
AppComposition createAppComposition({
  String inferenceRuntime = const String.fromEnvironment(
    'INFERENCE_RUNTIME',
    defaultValue: 'fake',
  ),
  String localModelPath = const String.fromEnvironment('LOCAL_MODEL_PATH'),
  SettingsStore? settingsStore,
  OwnedConversationStorage? conversationStorage,
  ModelDownloadManager? modelDownloads,
  AgentProfileStore? agentProfileStore,
  List<ModelCatalogEntry> catalog = modelCatalog,
  VoiceService? voiceService,
  ValueNotifier<String>? ttsVoice,
}) {
  final SettingsStore store = settingsStore ?? createSettingsStore();
  final AgentProfileStore profileStore =
      agentProfileStore ?? createAgentProfileStore();
  unawaited(profileStore.load());
  final AgentContextProvider agentContext = ProfileAgentContextProvider(
    () => profileStore.current,
  );
  if (inferenceRuntime != 'fake' && inferenceRuntime != 'litert') {
    unawaited(profileStore.dispose());
    throw UnsupportedError(
      'Unsupported INFERENCE_RUNTIME "$inferenceRuntime". '
      'Supported runtimes are "fake" and "litert".',
    );
  }

  // In memory unless the caller hands over something durable: tests and the
  // preview must not write into the user's real history.
  final InMemoryConversationStorageService fallbackStorage =
      InMemoryConversationStorageService();
  final OwnedConversationStorage storage =
      conversationStorage ??
      OwnedConversationStorage(
        service: fallbackStorage,
        release: () async => fallbackStorage.dispose(),
      );
  final PigeonDesktopHostService desktopHostService =
      PigeonDesktopHostService();
  final SwappableInferenceService inferenceService;
  try {
    inferenceService = SwappableInferenceService(
      createInferenceService(
        inferenceRuntime: inferenceRuntime,
        localModelPath: localModelPath,
        desktopHostService: desktopHostService,
        agentContext: agentContext,
      ),
    );
  } on Object {
    unawaited(storage.release());
    unawaited(desktopHostService.dispose());
    unawaited(profileStore.dispose());
    rethrow;
  }

  return AppComposition(
    () async {
      await inferenceService.dispose();
      await storage.release();
      await desktopHostService.dispose();
      await profileStore.dispose();
    },
    storageService: storage.service,
    inferenceService: inferenceService,
    settingsStore: store,
    presentationHost: desktopHostService,
    modelDownloads: modelDownloads ?? createModelDownloadManager(),
    catalog: catalog,
    voiceService: voiceService,
    // The model is chosen in settings, and the only part of the graph that has
    // to change when it does is what sits behind this one service.
    changeModel: (String modelPath) => inferenceService.replaceWith(
      () async => createInferenceService(
        inferenceRuntime: modelPath.trim().isEmpty ? 'fake' : 'litert',
        localModelPath: modelPath,
        desktopHostService: desktopHostService,
        agentContext: agentContext,
      ),
    ),
  );
}

/// Native context the local model runs with, in tokens.
///
/// Has to hold the conversation so far plus the answer being written.
const int localModelContextSize = 4096;

/// The most tokens one answer may run to.
///
/// Deliberately half the context: enough for a long, structured answer while
/// leaving the other half for the conversation that prompted it. The old
/// budget of 512 cut real answers off mid-sentence — a model that stops
/// halfway through its point reads as broken, not as concise.
const int localAnswerTokenBudget = 2048;

/// Builds the inference for one model, paired with the way to release it.
///
/// Called once at launch and again whenever the user chooses a different
/// model, so it takes everything it needs rather than reading it from the
/// settings itself: what is being loaded is the caller's decision.
OwnedInferenceService createInferenceService({
  required String inferenceRuntime,
  required String localModelPath,
  required DesktopHostService desktopHostService,
  AgentContextProvider? agentContext,
}) {
  if (inferenceRuntime == 'litert') {
    final String modelPath = localModelPath.trim();
    if (modelPath.isEmpty) {
      throw ArgumentError.value(
        localModelPath,
        'localModelPath',
        'A LiteRT-LM model path is required.',
      );
    }
    final PigeonInferenceService inferenceService = PigeonInferenceService(
      desktopHostService: desktopHostService,
      agentContext: agentContext,
      config: LocalModelConfig(
        modelId: 'gemma-4-E4B-it',
        modelPath: modelPath,
        contextSize: localModelContextSize,
        temperature: 0.7,
        topP: 0.95,
        maxTokens: localAnswerTokenBudget,
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
    return OwnedInferenceService(
      service: inferenceService,
      release: inferenceService.dispose,
    );
  }

  final DeterministicFakeInferenceService inferenceService =
      DeterministicFakeInferenceService();
  return OwnedInferenceService(
    service: inferenceService,
    release: inferenceService.dispose,
  );
}

/// Where the user's choices live between runs.
///
/// Under Application Support like any other Mac app's own data. A home that
/// cannot be resolved falls back to memory, so settings are forgotten rather
/// than the app refusing to start.
SettingsStore createSettingsStore() {
  final String? home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return InMemorySettingsStore();
  }
  return FileSettingsStore(
    directory: Directory('$home/Library/Application Support/Lulo'),
  );
}

/// Opens the developer profile beside Lulo's other application data.
FileAgentProfileStore createAgentProfileStore({
  String? home,
  bool watch = !kReleaseMode,
}) {
  final String? resolvedHome = home ?? Platform.environment['HOME'];
  final String base = resolvedHome == null || resolvedHome.isEmpty
      ? Directory.systemTemp.path
      : '$resolvedHome/Library/Application Support/Lulo';
  final Directory directory = Directory(base)..createSync(recursive: true);
  return FileAgentProfileStore(
    file: File('${directory.path}/agent_profile.json'),
    watch: watch,
  );
}
