import 'dart:async';

import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../features/agent_profile/agent_context_provider.dart';
import '../features/agent_profile/agent_memory_extractor.dart';
import '../features/agent_profile/agent_profile_store.dart';
import '../features/conversation/calendar_tool.dart';
import '../features/conversation/conversation_search_tool.dart';
import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/drift_conversation_storage_service.dart';
import '../features/conversation/pigeon_inference_service.dart';
import '../features/conversation/place_search_tool.dart';
import '../features/conversation/swappable_inference_service.dart';
import '../features/model/model_catalog.dart';
import '../features/model/model_download_manager.dart';
import '../features/model/model_file_service.dart';
import '../features/presence/notice/presence_notice.dart';
import '../features/presence/notice/presence_notice_center.dart';
import '../features/presence/notice/presence_notice_ledger.dart';
import '../features/settings/app_settings.dart';
import '../features/sidecar/sidecar_health.dart';
import '../features/transcript_refiner/deadline_transcript_refiner.dart';
import '../features/transcript_refiner/loopback_transcript_proposal_provider.dart';
import '../features/transcript_refiner/transcript_shadow_coordinator.dart';
import '../features/transcript_refiner/transcript_shadow_evidence.dart';
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
  String transcriptShadowEndpoint = const String.fromEnvironment(
    'TRANSCRIPT_SHADOW_ENDPOINT',
  ),
}) {
  final LoopbackTranscriptProposalProvider? transcriptProposalProvider =
      transcriptShadowEndpoint.trim().isEmpty
      ? null
      : LoopbackTranscriptProposalProvider(
          endpoint: Uri.parse(transcriptShadowEndpoint.trim()),
        );
  final TranscriptShadowEvidence? transcriptShadowEvidence =
      transcriptProposalProvider == null
      ? null
      : TranscriptShadowEvidence(capacity: 128);
  final TranscriptShadowCoordinator? transcriptShadow =
      transcriptProposalProvider == null
      ? null
      : TranscriptShadowCoordinator(
          provider: transcriptProposalProvider,
          onResult: transcriptShadowEvidence!.record,
        );
  final SettingsStore store = settingsStore ?? createSettingsStore();
  // Read by the inference service on every question, so a change applies to
  // the next answer without the model being reloaded.
  final ValueNotifier<AnswerStyle> answerStyle = ValueNotifier<AnswerStyle>(
    AnswerStyle.balanced,
  );
  // Read when the microphone opens, so a language chosen in settings is the
  // language of the next session rather than of the next launch.
  final ValueNotifier<AgentLanguage> conversationLanguage =
      ValueNotifier<AgentLanguage>(AgentLanguage.byDefault);
  final AgentProfileStore profileStore =
      agentProfileStore ?? createAgentProfileStore();
  unawaited(profileStore.load());
  // Shared with the composition, so the file the user opened in settings is
  // the file the next question is composed against.
  final ValueNotifier<String> openDocument = ValueNotifier<String>('');
  final ValueNotifier<String?> openDocumentName = ValueNotifier<String?>(null);
  final PigeonDesktopHostService desktopHostService =
      PigeonDesktopHostService();
  // Off until the user switches it on: which app they are in is theirs to
  // share, and the native side reports it whether or not anyone uses it.
  final ValueNotifier<bool> shareFrontmostApp = ValueNotifier<bool>(false);
  // Off until the user switches it on, for the reason above it is: the
  // profile is plaintext and the privacy slice `docs/features/agent-profile.md`
  // names has not been built, so nothing writes facts about the user until
  // they ask for it.
  final ValueNotifier<bool> rememberFacts = ValueNotifier<bool>(false);
  final AgentContextProvider agentContext = ProfileAgentContextProvider(
    () => profileStore.current,
    documentOf: () => openDocument.value,
    frontmostAppOf: () =>
        shareFrontmostApp.value ? desktopHostService.frontmostApp.value : '',
  );
  final DeadlineTranscriptRefiner transcriptRefiner = DeadlineTranscriptRefiner(
    const DeterministicTranscriptRefiner(),
  );
  if (inferenceRuntime != 'fake' && inferenceRuntime != 'litert') {
    unawaited(profileStore.dispose());
    transcriptRefiner.dispose();
    transcriptProposalProvider?.dispose();
    transcriptShadowEvidence?.clear();
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
  // The one toolbox both the first model and every later swap offer. Built
  // over the storage and the profile store the composition already owns.
  //
  // `RememberTool` is deliberately not in here. It is built, bounded and
  // tested, and gemma-4-E4B does not call it: 0/5 across eleven conditions,
  // including the one where the user says 「記住我住在台南」 outright — while
  // `search_conversations`, in the same toolbox on the same turn, fires 5/5.
  // A declaration costs context on every turn, so an unregistered tool is
  // what a measured 0/5 is worth. The write path it owns is what the second
  // pass will call; see
  // `docs/decisions/the-model-will-not-interrupt-itself-to-remember.md`.
  AgentToolbox buildToolbox() => AgentToolbox(<AgentTool>[
    ConversationSearchTool(
      searchConversations: storage.service.searchConversations,
    ),
    // Both exist because their absence was watched failing: asked for
    // quiet cafés, the model invented three shops and promised to search
    // Google Maps. System frameworks rather than third-party APIs — the
    // place query goes where the user's own Maps searches go, and the
    // calendar is read behind EventKit's own permission dialog.
    PlaceSearchTool(
      searchPlaces: (String query) async => <PlaceHit>[
        for (final DesktopPlaceHit hit in await desktopHostService.searchPlaces(
          query,
        ))
          PlaceHit(name: hit.name, address: hit.address),
      ],
    ),
    CalendarTool(
      readCalendar: (DateTime from, DateTime to) async {
        final DesktopCalendarAnswer answer = await desktopHostService
            .readCalendar(from: from, to: to);
        return CalendarWindowAnswer(
          authorized: answer.authorized,
          events: <CalendarEventHit>[
            for (final DesktopCalendarEvent event in answer.events)
              CalendarEventHit(
                title: event.title,
                start: event.start,
                end: event.end,
                calendar: event.calendar,
                allDay: event.allDay,
              ),
          ],
        );
      },
    ),
  ]);
  // Owned here so it survives a model swap: the service behind it is replaced,
  // and the thing the interface watches must not be.
  final ValueNotifier<bool> modelLoading = ValueNotifier<bool>(false);
  final SwappableInferenceService inferenceService;
  try {
    inferenceService = SwappableInferenceService(
      createInferenceService(
        inferenceRuntime: inferenceRuntime,
        localModelPath: localModelPath,
        desktopHostService: desktopHostService,
        agentContext: agentContext,
        answerStyle: () => answerStyle.value,
        modelLoading: modelLoading,
        toolbox: buildToolbox,
      ),
    );
  } on Object {
    unawaited(storage.release());
    unawaited(desktopHostService.dispose());
    unawaited(profileStore.dispose());
    transcriptRefiner.dispose();
    transcriptProposalProvider?.dispose();
    transcriptShadowEvidence?.clear();
    rethrow;
  }

  // Kept current by the shell that owns the presence controller, read by the
  // notice center's resting answer below.
  final ValueNotifier<bool> presenceIdle = ValueNotifier<bool>(true);
  // The budgets and tripwires of `an-ignored-light-stays-ignored.md`, over a
  // ledger beside the profile. A notice may light only while the user is not
  // already looking at Lulo: the orb form, idle.
  final PresenceNoticeCenter noticeCenter = PresenceNoticeCenter(
    store: createPresenceNoticeStore(),
    resting: () =>
        desktopHostService.presentation.value == DesktopPresentation.orb &&
        presenceIdle.value,
  );
  unawaited(noticeCenter.load());
  // The app-switch channel doubles as evidence the user is at the machine —
  // read locally for the seen-or-unseen judgement, never sent anywhere, and
  // independent of whether they chose to share the app's name with the model.
  desktopHostService.frontmostApp.addListener(noticeCenter.noteActivity);

  // Reads each finished turn for a fact about the user, in the runtime's
  // one generation slot, and gives that slot up the moment a question wants
  // it. Built over the swappable service rather than the one inside it, so
  // a model swap swaps what the extraction runs on too.
  final AgentMemoryExtractor memoryExtractor = AgentMemoryExtractor(
    inference: inferenceService,
    profileOf: () => profileStore.current,
    save: profileStore.save,
    enabled: () => rememberFacts.value,
    // A kept fact is the first notice kind: the surface silent memory
    // shipped without. Called only after the write has landed.
    onKept: (String fact) =>
        noticeCenter.trigger(PresenceNoticeKind.memoryWrite, fact),
  );

  return AppComposition(
    () async {
      // First: it holds a generation, and everything below tears down what
      // that generation is running on.
      await memoryExtractor.dispose();
      desktopHostService.frontmostApp.removeListener(noticeCenter.noteActivity);
      await inferenceService.dispose();
      await storage.release();
      await desktopHostService.dispose();
      await profileStore.dispose();
      transcriptRefiner.dispose();
      transcriptProposalProvider?.dispose();
      transcriptShadowEvidence?.clear();
    },
    betweenTurns: memoryExtractor,
    noticeCenter: noticeCenter,
    presenceIdle: presenceIdle,
    rememberFacts: rememberFacts,
    storageService: storage.service,
    inferenceService: inferenceService,
    settingsStore: store,
    presentationHost: desktopHostService,
    modelDownloads: modelDownloads ?? createModelDownloadManager(),
    catalog: catalog,
    voiceService: voiceService,
    transcriptRefiner: transcriptRefiner,
    transcriptShadow: transcriptShadow,
    transcriptShadowEvidence: transcriptShadowEvidence,
    protectedVocabulary: () => profileStore.current.vocabulary,
    misheard: () => profileStore.current.misheard,
    sidecarProbe: const SidecarHealthProbe(),
    modelLoading: modelLoading,
    openDocument: openDocument,
    openDocumentName: openDocumentName,
    floorControl: () => profileStore.current.floorControl,
    unfinishedEndings: () => profileStore.current.turnTaking.unfinished,
    agentProfile: profileStore,
    answerStyle: answerStyle,
    conversationLanguage: conversationLanguage,
    shareFrontmostApp: shareFrontmostApp,
    // The model is chosen in settings, and the only part of the graph that has
    // to change when it does is what sits behind this one service.
    changeModel: (String modelPath) => inferenceService.replaceWith(
      () async => createInferenceService(
        inferenceRuntime: modelPath.trim().isEmpty ? 'fake' : 'litert',
        localModelPath: modelPath,
        desktopHostService: desktopHostService,
        agentContext: agentContext,
        answerStyle: () => answerStyle.value,
        modelLoading: modelLoading,
        toolbox: buildToolbox,
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

/// The catalogue identity of the model file at [modelPath].
///
/// Catalogue entries are named `<id>.litertlm`, so the file name without its
/// extension is the id. Derived rather than fixed because it was fixed, at
/// `gemma-4-E4B-it`, for every model the user could choose: switching to E2B
/// left every run recorded under the name of a model that had not answered
/// it, and the load check compared the wrong id against itself and passed.
///
/// A file outside the catalogue keeps its own name, which is more honest than
/// borrowing another model's.
String modelIdForPath(String modelPath) {
  final String fileName = modelPath.split(Platform.pathSeparator).last;
  final int extension = fileName.lastIndexOf('.');
  return extension <= 0 ? fileName : fileName.substring(0, extension);
}

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
  AnswerStyle Function()? answerStyle,
  ValueNotifier<bool>? modelLoading,
  AgentToolbox Function()? toolbox,
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
      answerStyle: answerStyle,
      toolbox: toolbox,
      config: LocalModelConfig(
        modelId: modelIdForPath(modelPath),
        modelPath: modelPath,
        contextSize: localModelContextSize,
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
    //
    // Said out loud while it runs. The load is seconds — measured on the real
    // model at 3.7-8.5 s, against 1.5 s for the first answer once it is in
    // memory — and a question asked inside that window waits for it with
    // nothing to explain the wait, which is indistinguishable from a hang.
    // Cleared on failure as well as success: the notice says "still loading",
    // and a load that has stopped is not still loading whichever way it ended.
    modelLoading?.value = true;
    unawaited(
      inferenceService
          .warmUp()
          .catchError((Object _) {})
          .whenComplete(() => modelLoading?.value = false),
    );
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

/// Opens the notice ledger beside Lulo's other application data.
///
/// In memory where there is no home to write to, the same trade the other
/// stores make: measurement forgotten rather than the app refusing to start.
PresenceNoticeStore createPresenceNoticeStore({String? home}) {
  final String? resolvedHome = home ?? Platform.environment['HOME'];
  if (resolvedHome == null || resolvedHome.isEmpty) {
    return InMemoryPresenceNoticeStore();
  }
  final Directory directory = Directory(
    '$resolvedHome/Library/Application Support/Lulo',
  )..createSync(recursive: true);
  return FilePresenceNoticeStore(
    file: File('${directory.path}/presence_notices.json'),
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
