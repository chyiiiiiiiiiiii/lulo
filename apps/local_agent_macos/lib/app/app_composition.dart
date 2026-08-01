import 'dart:async';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../features/conversation/conversation_repository.dart';
import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/conversation_view_model.dart';
import '../features/conversation/inference_service.dart';
import '../features/model/model_catalog.dart';
import '../features/model/model_download_manager.dart';
import '../features/model/model_file_service.dart';
import '../features/settings/app_settings.dart';
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
    List<String> Function()? protectedVocabulary,
    ValueNotifier<String>? ttsVoice,
  }) : ttsVoice = ttsVoice ?? ValueNotifier<String>('ryan'),
       transcriptRefiner =
           transcriptRefiner ?? const DeterministicTranscriptRefiner(),
       protectedVocabulary = protectedVocabulary ?? _emptyVocabulary,
       _changeModel = changeModel ?? _keepThePreview,
       settingsStore = settingsStore ?? InMemorySettingsStore(),
       modelDownloads = modelDownloads ?? _downloadsNowhere(),
       _conversationRepository = ConversationRepository(
         storageService: storageService,
         inferenceService: inferenceService,
       );

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

  /// Latest profile vocabulary, read at the moment an utterance settles.
  final List<String> Function() protectedVocabulary;

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
  final ConversationRepository _conversationRepository;
  int _nextConversation = 1;
  bool _disposed = false;

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
    );
  }

  /// Every stored conversation, most recently spoken-in first.
  Future<List<ConversationSummary>> listConversations() =>
      _conversationRepository.listConversations();

  /// Forgets [conversationId] and everything said in it.
  Future<void> deleteConversation(ConversationId conversationId) =>
      _conversationRepository.deleteConversation(conversationId);

  /// Releases app-scoped services.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    modelDownloads.dispose();
    await _disposeServices();
  }
}

List<String> _emptyVocabulary() => const <String>[];
