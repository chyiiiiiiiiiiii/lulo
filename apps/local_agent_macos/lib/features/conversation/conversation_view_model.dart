import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import 'conversation_repository.dart';
import 'conversation_storage_service.dart';
import 'token_batcher.dart';

/// Creates a stable conversation identifier for a new conversation.
typedef ConversationIdFactory = ConversationId Function();

/// Presentation state and user intents for one conversation view.
final class ConversationViewModel extends ChangeNotifier {
  /// Creates a feature-scoped ViewModel with explicit dependencies.
  ///
  /// Given a [conversationId] it restores that conversation; given none it
  /// resumes the most recently spoken-in one, because a resident agent that
  /// forgot yesterday on every launch would make each restart an amnesia. A
  /// store with nothing in it starts fresh, and [startFresh] asks for that
  /// deliberately: the store is left alone and the first message begins a
  /// newly minted conversation.
  ConversationViewModel({
    required ConversationRepository repository,
    required ConversationIdFactory idFactory,
    ConversationId? conversationId,
    bool startFresh = false,
    BatchScheduler batchScheduler = const TimerBatchScheduler(),
  }) : this._(
         repository,
         idFactory,
         conversationId,
         startFresh,
         batchScheduler,
       );

  ConversationViewModel._(
    this._repository,
    this._idFactory,
    ConversationId? conversationId,
    bool startFresh,
    BatchScheduler batchScheduler,
  ) {
    // Tokens arrive on the model's clock; the view repaints on the display's.
    // The batcher aligns the two so one frame of deltas is one rebuild.
    _tokenBatcher = TokenBatcher(
      onBatch: _applyBatchedDelta,
      scheduler: batchScheduler,
    );
    _restored = startFresh ? Future<void>.value() : _restore(conversationId);
  }

  final ConversationRepository _repository;
  final ConversationIdFactory _idFactory;
  ConversationProjection _projection = ConversationProjection(
    completedTurns: const <Turn>[],
  );
  StreamSubscription<GenerationEvent>? _operationSubscription;
  ConversationId? _conversationId;
  GenerationId? _activeGenerationId;
  bool _stopRequested = false;
  Future<void>? _stopOperation;
  bool _disposed = false;
  late final Future<void> _restored;
  late final TokenBatcher _tokenBatcher;
  final ValueNotifier<List<Turn>> _completedTurns = ValueNotifier<List<Turn>>(
    const <Turn>[],
  );
  final ValueNotifier<Turn?> _activeTurn = ValueNotifier<Turn?>(null);
  final ValueNotifier<bool> _canSubmit = ValueNotifier<bool>(true);

  /// Immutable state consumed by the conversation view.
  ConversationProjection get projection => _projection;

  /// Completes once stored history has been placed into the view.
  ///
  /// Never throws: a store that cannot be read starts a fresh conversation
  /// rather than stopping this one.
  Future<void> get restored => _restored;

  Future<void> _restore(ConversationId? requested) async {
    try {
      ConversationId? id = requested;
      id ??= (await _repository.listConversations())
          .map((ConversationSummary summary) => summary.id)
          .firstOrNull;
      if (id == null || _disposed) {
        return;
      }
      final List<Turn> history = await _repository.loadTurns(id);
      if (_disposed) {
        return;
      }
      _conversationId = id;
      if (history.isEmpty) {
        return;
      }
      // Before whatever has been said since: submit waits for this restore,
      // so nothing can be there yet — but the shape stays correct even if
      // that ordering ever loosens.
      _projection = ConversationProjection(
        completedTurns: <Turn>[...history, ..._projection.completedTurns],
        activeTurn: _projection.activeTurn,
      );
      _completedTurns.value = _projection.completedTurns;
      notifyListeners();
    } on Object {
      // Reading yesterday must never stop today.
    }
  }

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
    // History lands first, and the message joins the restored conversation
    // instead of racing it into a freshly minted one.
    await _restored;
    if (_disposed || !canSubmit) {
      return;
    }
    _stopRequested = false;
    _stopOperation = null;

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
        if (generationId != _activeGenerationId ||
            _projection.activeTurn == null) {
          return;
        }
        _tokenBatcher.add(delta);
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

  /// Puts one frame's worth of tokens into the projection, as one update.
  void _applyBatchedDelta(String combined) {
    if (_disposed) {
      return;
    }
    final Turn? activeTurn = _projection.activeTurn;
    if (activeTurn == null) {
      return;
    }
    _projection = ConversationProjection(
      completedTurns: _projection.completedTurns,
      activeTurn: activeTurn.append(combined),
    );
    _activeTurn.value = _projection.activeTurn;
  }

  void _finishActiveTurn(
    TurnStatus status, {
    bool createWhenNotStarted = false,
  }) {
    if (_disposed) {
      return;
    }
    // Whatever the current frame still owes lands first, so the completed
    // turn carries every token that was ever streamed.
    _tokenBatcher.flush();
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
  Future<void> stop() => _stopOperation ??= _stop();

  Future<void> _stop() async {
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
    _tokenBatcher.dispose();
    unawaited(_operationSubscription?.cancel());
    _operationSubscription = null;
    _completedTurns.dispose();
    _activeTurn.dispose();
    _canSubmit.dispose();
    super.dispose();
  }
}
