import 'dart:async';

import 'package:agent_core/agent_core.dart';

import '../features/conversation/conversation_repository.dart';
import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/conversation_view_model.dart';
import '../features/conversation/inference_service.dart';
import '../features/settings/app_settings.dart';
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
  }) : settingsStore = settingsStore ?? InMemorySettingsStore(),
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

  final FutureOr<void> Function() _disposeServices;
  final ConversationRepository _conversationRepository;
  int _nextConversation = 1;
  bool _disposed = false;

  /// Creates one ViewModel owned by one conversation View.
  ConversationViewModel createConversationViewModel() {
    if (_disposed) {
      throw StateError('The application composition is disposed.');
    }
    return ConversationViewModel(
      repository: _conversationRepository,
      idFactory: () =>
          ConversationId('session-conversation-${_nextConversation++}'),
    );
  }

  /// Releases app-scoped services.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _disposeServices();
  }
}
