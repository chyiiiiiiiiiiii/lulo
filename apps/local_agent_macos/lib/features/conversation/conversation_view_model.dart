import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import 'conversation_repository.dart';

/// Creates a stable conversation identifier for a new conversation.
typedef ConversationIdFactory = ConversationId Function();

/// Presentation state and user intents for one conversation view.
final class ConversationViewModel extends ChangeNotifier {
  /// Creates a feature-scoped ViewModel with explicit dependencies.
  ConversationViewModel({
    required ConversationRepository repository,
    required ConversationIdFactory idFactory,
  }) : this._(repository, idFactory);

  ConversationViewModel._(this._repository, this._idFactory);

  final ConversationRepository _repository;
  final ConversationIdFactory _idFactory;
  ConversationProjection _projection = ConversationProjection(
    completedTurns: const <Turn>[],
  );
  StreamSubscription<GenerationEvent>? _operationSubscription;
  ConversationId? _conversationId;
  GenerationId? _activeGenerationId;
  bool _stopRequested = false;
  bool _disposed = false;
  final ValueNotifier<List<Turn>> _completedTurns = ValueNotifier<List<Turn>>(
    const <Turn>[],
  );
  final ValueNotifier<Turn?> _activeTurn = ValueNotifier<Turn?>(null);
  final ValueNotifier<bool> _canSubmit = ValueNotifier<bool>(true);

  /// Immutable state consumed by the conversation view.
  ConversationProjection get projection => _projection;

  /// Whether a new user message may be submitted.
  bool get canSubmit => _operationSubscription == null;

  /// Stable listenable for history; token deltas never notify it.
  ValueListenable<List<Turn>> get completedTurnsListenable => _completedTurns;

  /// Stable listenable for the streaming assistant turn.
  ValueListenable<Turn?> get activeTurnListenable => _activeTurn;

  /// Stable listenable for composer availability.
  ValueListenable<bool> get canSubmitListenable => _canSubmit;

  /// Starts generation for a normalized non-empty user message.
  Future<void> submit(String text) async {
    final String prompt = text.trim();
    if (prompt.isEmpty || !canSubmit) {
      return;
    }
    _stopRequested = false;

    final ConversationId conversationId = _conversationId ??= _idFactory();
    final Turn userTurn = Turn(
      role: TurnRole.user,
      text: prompt,
      status: TurnStatus.completed,
    );
    _projection = ConversationProjection(
      completedTurns: <Turn>[..._projection.completedTurns, userTurn],
    );
    _completedTurns.value = _projection.completedTurns;
    notifyListeners();

    _operationSubscription = _repository
        .startGeneration(
          userTurn: userTurn,
          request: GenerationRequest(
            conversationId: conversationId,
            prompt: prompt,
          ),
        )
        .listen(_onEvent, onError: _onOperationError, onDone: _onOperationDone);
    _canSubmit.value = false;
  }

  void _onEvent(GenerationEvent event) {
    if (_disposed) {
      return;
    }
    switch (event) {
      case GenerationStarted(:final Generation generation):
        if (_activeGenerationId != null) {
          return;
        }
        _activeGenerationId = generation.id;
        _projection = ConversationProjection(
          completedTurns: _projection.completedTurns,
          activeTurn: const Turn(
            role: TurnRole.assistant,
            text: '',
            status: TurnStatus.streaming,
          ),
        );
        _activeTurn.value = _projection.activeTurn;
        notifyListeners();
      case GenerationDelta(:final GenerationId generationId, :final delta):
        final Turn? activeTurn = _projection.activeTurn;
        if (generationId != _activeGenerationId || activeTurn == null) {
          return;
        }
        _projection = ConversationProjection(
          completedTurns: _projection.completedTurns,
          activeTurn: activeTurn.append(delta),
        );
        _activeTurn.value = _projection.activeTurn;
        notifyListeners();
      case GenerationCompleted(:final GenerationId generationId):
        if (generationId != _activeGenerationId) {
          return;
        }
        _finishActiveTurn(TurnStatus.completed);
      case GenerationCancelled(:final GenerationId generationId):
        if (generationId != _activeGenerationId) {
          return;
        }
        _finishActiveTurn(TurnStatus.cancelled);
      case GenerationFailed(:final GenerationId generationId):
        if (generationId != _activeGenerationId) {
          return;
        }
        _finishActiveTurn(TurnStatus.failed);
    }
  }

  void _finishActiveTurn(
    TurnStatus status, {
    bool createWhenNotStarted = false,
  }) {
    if (_disposed) {
      return;
    }
    final Turn? projectedTurn = _projection.activeTurn;
    if (projectedTurn == null && !createWhenNotStarted) {
      return;
    }
    final Turn activeTurn =
        projectedTurn ??
        const Turn(
          role: TurnRole.assistant,
          text: '',
          status: TurnStatus.streaming,
        );
    _projection = ConversationProjection(
      completedTurns: <Turn>[
        ..._projection.completedTurns,
        activeTurn.copyWith(status: status),
      ],
    );
    _completedTurns.value = _projection.completedTurns;
    _activeTurn.value = null;
    _activeGenerationId = null;
    notifyListeners();
  }

  void _onOperationError(Object _, StackTrace _) {
    if (_disposed) {
      return;
    }
    _finishActiveTurn(TurnStatus.failed, createWhenNotStarted: true);
  }

  void _onOperationDone() {
    if (_disposed) {
      return;
    }
    _operationSubscription = null;
    _canSubmit.value = true;
    notifyListeners();
  }

  /// Stops the active generation.
  Future<void> stop() async {
    final GenerationId? generationId = _activeGenerationId;
    if (generationId != null) {
      await _repository.stop(generationId);
      return;
    }

    final StreamSubscription<GenerationEvent>? subscription =
        _operationSubscription;
    if (subscription == null || _stopRequested) {
      return;
    }
    _stopRequested = true;
    await subscription.cancel();
    if (_disposed) {
      return;
    }
    _operationSubscription = null;
    _finishActiveTurn(TurnStatus.cancelled, createWhenNotStarted: true);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_operationSubscription?.cancel());
    _operationSubscription = null;
    _completedTurns.dispose();
    _activeTurn.dispose();
    _canSubmit.dispose();
    super.dispose();
  }
}
