import 'dart:async';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../features/agent_profile/agent_profile_store.dart';
import '../features/conversation/conversation_repository.dart';
import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/conversation_view_model.dart';
import '../features/conversation/inference_service.dart';
import '../features/model/model_catalog.dart';
import '../features/model/model_download_manager.dart';
import '../features/model/model_file_service.dart';
import '../features/obsidian/obsidian_journal_writer.dart';
import '../features/presence/notice/presence_notice_center.dart';
import '../features/presence/notice/presence_notice_ledger.dart';
import '../features/settings/app_settings.dart';
import '../features/sidecar/sidecar_health.dart';
import '../features/transcript_refiner/transcript_shadow_coordinator.dart';
import '../features/transcript_refiner/transcript_shadow_evidence.dart';
import '../features/voice/voice_service.dart';
import '../platform/desktop_host_service.dart';

/// Owns app-scoped dependencies and creates feature-scoped ViewModels.
final class AppComposition {
  /// Creates the application graph from explicit app-scoped dependencies.
  AppComposition(
    this._disposeServices, {
    required ConversationStorageService storageService,
    required InferenceService inferenceService,
    SettingsStore? settingsStore,
    this.presentationHost,
    Future<void> Function(String modelPath)? changeModel,
    ModelDownloadManager? modelDownloads,
    this.catalog = modelCatalog,
    this.voiceService,
    TranscriptRefiner? transcriptRefiner,
    this.transcriptShadow,
    this.transcriptShadowEvidence,
    List<String> Function()? protectedVocabulary,
    List<MisheardWord> Function()? misheard,
    this.sidecarProbe,
    ValueNotifier<String>? openDocument,
    ValueNotifier<String?>? openDocumentName,
    FloorControl Function()? floorControl,
    List<String> Function()? unfinishedEndings,
    ValueNotifier<String>? ttsVoice,
    AgentProfileStore? agentProfile,
    ValueNotifier<AnswerStyle>? answerStyle,
    ValueNotifier<AgentLanguage>? conversationLanguage,
    ValueNotifier<bool>? shareFrontmostApp,
    ValueNotifier<bool>? rememberFacts,
    ValueNotifier<bool>? obsidianJournal,
    ValueNotifier<String>? vaultHeading,
    ValueNotifier<int>? voiceRequests,
    ValueNotifier<(OrbActionKind, int)?>? orbActionRequests,
    ValueNotifier<bool>? voiceEngaged,
    ValueNotifier<bool>? modelLoading,
    PresenceNoticeCenter? noticeCenter,
    ValueNotifier<bool>? presenceIdle,
    this.betweenTurns,
  }) : noticeCenter =
           noticeCenter ??
           PresenceNoticeCenter(
             store: InMemoryPresenceNoticeStore(),
             resting: _neverResting,
           ),
       presenceIdle = presenceIdle ?? ValueNotifier<bool>(true),
       voiceRequests = voiceRequests ?? ValueNotifier<int>(0),
       orbActionRequests =
           orbActionRequests ?? ValueNotifier<(OrbActionKind, int)?>(null),
       voiceEngaged = voiceEngaged ?? ValueNotifier<bool>(false),
       answerStyle =
           answerStyle ?? ValueNotifier<AnswerStyle>(AnswerStyle.balanced),
       conversationLanguage =
           conversationLanguage ??
           ValueNotifier<AgentLanguage>(AgentLanguage.byDefault),
       shareFrontmostApp = shareFrontmostApp ?? ValueNotifier<bool>(false),
       rememberFacts = rememberFacts ?? ValueNotifier<bool>(false),
       obsidianJournal = obsidianJournal ?? ValueNotifier<bool>(false),
       vaultHeading = vaultHeading ?? ValueNotifier<String>('Lulo'),
       agentProfile = agentProfile ?? InMemoryAgentProfileStore(),
       ttsVoice = ttsVoice ?? ValueNotifier<String>('ryan'),
       transcriptRefiner =
           transcriptRefiner ?? const DeterministicTranscriptRefiner(),
       protectedVocabulary = protectedVocabulary ?? _emptyVocabulary,
       misheard = misheard ?? _nothingMisheard,
       modelLoading = modelLoading ?? ValueNotifier<bool>(false),
       openDocument = openDocument ?? ValueNotifier<String>(''),
       openDocumentName = openDocumentName ?? ValueNotifier<String?>(null),
       floorControl = floorControl ?? _builtInFloorControl,
       unfinishedEndings = unfinishedEndings ?? _emptyVocabulary,
       _changeModel = changeModel ?? _keepThePreview,
       settingsStore = settingsStore ?? InMemorySettingsStore(),
       modelDownloads = modelDownloads ?? _downloadsNowhere() {
    // Built here rather than in the initializer list so that it listens to
    // *this* graph's notifiers. Constructed up there it would be handed a
    // second notifier made from the same defaulted argument, and the setting
    // the user flips would be a different object from the one it reads.
    //
    // Wrapped rather than hooked into: with no window host there is nothing
    // to write through, and the app then runs with no mirror in the graph at
    // all rather than with one that quietly does nothing.
    final DesktopPresentationHost? host = presentationHost;
    journal = host == null
        ? null
        : ObsidianJournalWriter(
            inner: storageService,
            append: host.appendToVault,
            enabled: this.obsidianJournal,
            heading: this.vaultHeading,
          );
    _conversationRepository = ConversationRepository(
      storageService: journal ?? storageService,
      inferenceService: inferenceService,
    );
  }

  /// Where finished exchanges are also written, or null with no window host.
  ///
  /// Held so Settings can read how the last write went. A mirror that has
  /// quietly stopped working is worse than one never turned on: the user
  /// believes their thinking is being kept somewhere it is not.
  late final ObsidianJournalWriter? journal;

  /// Whether finished exchanges are appended to the user's own notes.
  final ValueNotifier<bool> obsidianJournal;

  /// What a day's page in the vault is called, in the user's own language.
  ///
  /// A notifier written by the shell for the same reason the menu bar's
  /// labels are pushed: the words come from `AppLocalizations`, which needs a
  /// context, and this graph is built before there is one.
  final ValueNotifier<String> vaultHeading;

  /// Where a trigger becomes, or fails to become, a quietly lit orb.
  ///
  /// The default one never lights — its resting answer is always no — so a
  /// preview or a widget test that builds the app without asking for the
  /// feature measures nothing and shows nothing.
  final PresenceNoticeCenter noticeCenter;

  /// Whether the presence is idle, kept current by the shell that owns it.
  ///
  /// The notice center's resting answer reads this: a light must not compete
  /// with an answer being thought about or spoken, even while the orb rests.
  final ValueNotifier<bool> presenceIdle;

  /// Work that borrows the runtime between turns, or null when nothing does.
  ///
  /// One object, shared by every conversation the app opens, because what it
  /// is borrowing is the runtime's single generation slot — one per view
  /// model would be several things queueing for a resource there is one of.
  final BetweenTurns? betweenTurns;

  /// Bumped whenever something outside the conversation asks it to listen.
  ///
  /// A counter rather than a flag because the answer to "start listening" is
  /// the same every time it is asked, and a flag would only fire once. The
  /// conversation view owns the microphone — it is the only thing that knows
  /// whether one is already open — so the request travels to it rather than
  /// the state travelling out.
  final ValueNotifier<int> voiceRequests;

  /// The newest thing asked of the agent from the strip under its resting orb.
  ///
  /// Carries a sequence number beside the action so that pressing the same
  /// button twice arrives twice — a notifier holding only the action would go
  /// quiet the second time, which is exactly when the user is pressing it
  /// again because the first press looked like it did nothing.
  final ValueNotifier<(OrbActionKind, int)?> orbActionRequests;

  /// Whether the microphone is currently open, written by whoever owns it.
  ///
  /// The strip under the resting orb draws its microphone lit or unlit from
  /// this. A control that cannot show which way it is pointing is a control
  /// the user has to guess at, and guessing wrong here means talking to
  /// something that is not listening.
  final ValueNotifier<bool> voiceEngaged;

  /// How far the model may roam, read by the inference service on every
  /// question.
  ///
  /// A notifier rather than a value passed at construction, for the same
  /// reason `ttsVoice` is one: the setting can change while the model stays
  /// loaded, and reloading it to move a slider would cost seconds.
  final ValueNotifier<AnswerStyle> answerStyle;

  /// Which language the conversation is held in, kept current by settings.
  ///
  /// Only the spoken half reads it: the recogniser is monolingual and has to
  /// be opened on one locale before anybody has spoken. A typed question
  /// still carries its own language, and is answered in it.
  final ValueNotifier<AgentLanguage> conversationLanguage;

  /// Whether finished turns are read for facts about the user.
  ///
  /// Off by default and surfaced beside [shareFrontmostApp], because it is
  /// the same kind of permission: the profile is local but plaintext, and
  /// `docs/features/agent-profile.md` makes a privacy slice the precondition
  /// for writing to it automatically.
  final ValueNotifier<bool> rememberFacts;

  /// Whether each question carries the name of the app the user is in.
  ///
  /// Fed from settings the way [answerStyle] is, and read by the context
  /// provider at compose time — so flipping it applies to the next
  /// question without anything reloading.
  final ValueNotifier<bool> shareFrontmostApp;

  /// How Lulo talks, and where the user changes it.
  ///
  /// The same store the prompt, the recogniser and the endpointer already
  /// read from, so a change made in settings is in force on the next turn
  /// without anything having to be told about it.
  final AgentProfileStore agentProfile;

  /// Drives the desktop window between its orb and conversation forms.
  ///
  /// Null when there is no desktop host to talk to, which is the case for the
  /// deterministic preview and for widget tests. The shell then stays in the
  /// conversation form so those surfaces are unaffected.
  final DesktopPresentationHost? presentationHost;

  /// Where the user's choices about the desktop presence are kept.
  final SettingsStore settingsStore;

  /// Download state for the curated models, alive for as long as the app.
  final ModelDownloadManager modelDownloads;

  /// The models on offer, the recommended one first.
  final List<ModelCatalogEntry> catalog;

  /// The ears and mouth, or null where the surface cannot listen — widget
  /// tests, the preview, and the native test host.
  final VoiceService? voiceService;

  /// Refines final voice transcripts before conversation submission.
  final TranscriptRefiner transcriptRefiner;

  /// Optional developer-only proposal path; null keeps shadowing disabled.
  final TranscriptShadowCoordinator? transcriptShadow;

  /// Bounded, in-memory developer evidence; null when shadowing is disabled.
  final TranscriptShadowEvidence? transcriptShadowEvidence;

  /// Latest profile vocabulary, read at the moment an utterance settles.
  final List<String> Function() protectedVocabulary;

  /// Corrections the user has taught, read at the moment an utterance
  /// settles rather than captured — the profile is a watched file.
  final List<MisheardWord> Function() misheard;

  /// How to ask whether the two helper processes are running, or null on a
  /// surface that should not ask.
  ///
  /// Null in tests by default: the real probe opens a socket with a real
  /// timeout, and a widget test that merely builds the app must not be left
  /// holding a pending timer for a question it never asked.
  final SidecarHealthProbe? sidecarProbe;

  /// The text of the file questions are currently answered out of, empty
  /// when there is none.
  ///
  /// Shared with the context provider, which reads it at the moment a
  /// question is composed. Only the passages a question turns out to be
  /// about are sent, so a file left open that the next question has nothing
  /// to do with costs nothing — which is what makes leaving one open safe.
  final ValueNotifier<String> openDocument;

  /// Whether the local model is still loading.
  ///
  /// Owned here rather than read off the inference service, because the thing
  /// that knows is the warm-up the composition root starts: the service is
  /// swappable and the readiness would have to be forwarded across a swap for
  /// no gain. False by default — the preview runtime has no model to load, so
  /// nothing about it is ever loading.
  final ValueNotifier<bool> modelLoading;

  /// What that file is called, for the app to say what it is reading.
  final ValueNotifier<String?> openDocumentName;

  /// Who has the floor, read again at every ruling.
  ///
  /// A closure rather than a value because the profile is a watched file:
  /// a word the user adds while the app is running has to take effect on
  /// the next thing said.
  final FloorControl Function() floorControl;

  /// The user's own ways of leaving a sentence unfinished, pushed to the
  /// native endpointer whenever they change.
  final List<String> Function() unfinishedEndings;

  /// Who speaks the answers aloud right now; settings keep it current.
  final ValueNotifier<String> ttsVoice;

  /// The default manager, for compositions that never really download:
  /// nothing is created on disk until something is actually fetched.
  static ModelDownloadManager _downloadsNowhere() => ModelDownloadManager(
    files: ModelFileService(
      modelsDirectory: Directory('${Directory.systemTemp.path}/lulo-models'),
    ),
  );

  final FutureOr<void> Function() _disposeServices;
  final Future<void> Function(String modelPath) _changeModel;
  late final ConversationRepository _conversationRepository;
  int _nextConversation = 1;
  bool _disposed = false;

  /// Settles anything the last process left mid-answer.
  ///
  /// Awaited before the first surface reads a conversation, so a recovered
  /// turn is there when the history is first drawn rather than appearing
  /// under the user a moment later. On a clean start it is one query that
  /// returns nothing.
  Future<void> recoverInterruptedRuns() =>
      _conversationRepository.recoverInterruptedRuns();

  /// Loads [modelPath] in place of whatever the agent is currently thinking
  /// with, so choosing a model does not mean restarting.
  ///
  /// An empty path returns the agent to its built-in preview. Does nothing
  /// where there is no runtime to change, which is the case in widget tests.
  Future<void> useModel(String modelPath) async {
    if (_disposed) {
      throw StateError('The application composition is disposed.');
    }
    await _changeModel(modelPath);
  }

  /// What a composition with no runtime behind it does with a chosen model.
  static Future<void> _keepThePreview(String modelPath) async {}

  /// Creates one ViewModel owned by one conversation View.
  ///
  /// Given a [conversationId] it opens that conversation; given none it
  /// resumes the most recently spoken-in one, or starts fresh when nothing is
  /// stored. [startFresh] skips the store deliberately: a new conversation on
  /// the user's say-so. New identities carry the launch instant, so two runs
  /// of the app can never mint the same conversation.
  ConversationViewModel createConversationViewModel({
    ConversationId? conversationId,
    bool startFresh = false,
  }) {
    if (_disposed) {
      throw StateError('The application composition is disposed.');
    }
    return ConversationViewModel(
      repository: _conversationRepository,
      idFactory: () => ConversationId(
        'conversation-${DateTime.now().millisecondsSinceEpoch}-'
        '${_nextConversation++}',
      ),
      conversationId: conversationId,
      startFresh: startFresh,
      betweenTurns: betweenTurns,
    );
  }

  /// Every stored conversation, most recently spoken-in first.
  Future<List<ConversationSummary>> listConversations() =>
      _conversationRepository.listConversations();

  /// Every stored conversation containing [query], most recent first.
  Future<List<ConversationSummary>> searchConversations(String query) =>
      _conversationRepository.searchConversations(query);

  /// Gives [conversationId] a name of the user's own, or restores the
  /// derived one.
  Future<void> renameConversation(
    ConversationId conversationId,
    String title,
  ) => _conversationRepository.renameConversation(conversationId, title);

  /// Keeps [conversationId] at the top of the list, or lets it go.
  Future<void> setConversationPinned(
    ConversationId conversationId, {
    required bool pinned,
  }) => _conversationRepository.setConversationPinned(
    conversationId,
    pinned: pinned,
  );

  /// Reads back every stored turn of [conversationId].
  Future<List<Turn>> loadTurns(ConversationId conversationId) =>
      _conversationRepository.loadTurns(conversationId);

  /// Forgets [conversationId] and everything said in it.
  Future<void> deleteConversation(ConversationId conversationId) =>
      _conversationRepository.deleteConversation(conversationId);

  /// Releases app-scoped services.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    noticeCenter.dispose();
    modelDownloads.dispose();
    transcriptShadow?.dispose();
    await _disposeServices();
  }

  static bool _neverResting() => false;
}

List<String> _emptyVocabulary() => const <String>[];

FloorControl _builtInFloorControl() => FloorControl.standard;

List<MisheardWord> _nothingMisheard() => const <MisheardWord>[];
