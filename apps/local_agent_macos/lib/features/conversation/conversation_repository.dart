import 'dart:async';

import 'package:agent_core/agent_core.dart';

import 'conversation_storage_service.dart';
import 'inference_service.dart';

/// Coordinates conversation persistence with inference for one active operation.
///
/// Phase 1A intentionally permits only one active generation per repository.
/// Callers receive an error stream when they attempt to begin another operation.
final class ConversationRepository {
  /// Creates a repository with explicit persistence and inference dependencies.
  ConversationRepository({
    required ConversationStorageService storageService,
    required InferenceService inferenceService,
  }) : this._(storageService, inferenceService);

  ConversationRepository._(this._storageService, this._inferenceService);

  final ConversationStorageService _storageService;
  final InferenceService _inferenceService;
  _GenerationOperation? _activeOperation;

  /// Persists [userTurn], then exposes ordered events for [request].
  Stream<GenerationEvent> startGeneration({
    required Turn userTurn,
    required GenerationRequest request,
  }) {
    if (userTurn.role != TurnRole.user ||
        userTurn.status != TurnStatus.completed) {
      return Stream<GenerationEvent>.error(
        ArgumentError.value(
          userTurn,
          'userTurn',
          'must be a completed user turn',
        ),
      );
    }

    if (_activeOperation != null) {
      return Stream<GenerationEvent>.error(
        StateError('A generation is already active.'),
      );
    }

    late final _GenerationOperation operation;
    final StreamController<GenerationEvent> controller =
        StreamController<GenerationEvent>(
          onListen: () => unawaited(operation.start()),
          onCancel: () => operation.onListenerCancelled(),
        );
    operation = _GenerationOperation(
      _storageService,
      _inferenceService,
      userTurn,
      request,
      controller,
      () => _release(operation),
    );
    _activeOperation = operation;
    return controller.stream;
  }

  /// Stops the active generation identified by [generationId], if it matches.
  Future<void> stop(GenerationId generationId) async {
    final _GenerationOperation? operation = _activeOperation;
    if (operation == null || operation.generationId != generationId) {
      return;
    }

    await operation.stop();
  }

  void _release(_GenerationOperation operation) {
    if (identical(_activeOperation, operation)) {
      _activeOperation = null;
    }
  }
}

final class _GenerationOperation {
  _GenerationOperation(
    this._storageService,
    this._inferenceService,
    this._userTurn,
    this._request,
    this._controller,
    this._onFinished,
  );

  final ConversationStorageService _storageService;
  final InferenceService _inferenceService;
  final Turn _userTurn;
  final GenerationRequest _request;
  final StreamController<GenerationEvent> _controller;
  final void Function() _onFinished;

  StreamSubscription<GenerationEvent>? _subscription;
  Generation? _generation;
  String _assistantText = '';
  bool _started = false;
  bool _terminal = false;
  bool _finished = false;

  GenerationId? get generationId => _generation?.id;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    try {
      await _storageService.saveUserTurn(_userTurn);
      if (_terminal) {
        return;
      }
      _subscription = _inferenceService
          .generate(_request)
          .listen(_receiveEvent, onError: _receiveError, onDone: _receiveDone);
    } on Object catch (error, stackTrace) {
      await _finishWithError(error, stackTrace);
    }
  }

  Future<void> stop() async {
    final Generation? generation = _generation;
    if (_terminal || generation == null) {
      return;
    }

    _terminal = true;
    await _cancelGeneration(generation, publishCancellation: true);
  }

  Future<void> onListenerCancelled() async {
    if (_terminal || _finished) {
      return;
    }

    _terminal = true;
    final Generation? generation = _generation;
    if (generation != null) {
      await _cancelGeneration(generation, publishCancellation: false);
      return;
    }
    try {
      await _subscription?.cancel();
    } finally {
      await _finish();
    }
  }

  Future<void> _cancelGeneration(
    Generation generation, {
    required bool publishCancellation,
  }) async {
    try {
      await _subscription?.cancel();
      await _inferenceService.cancel(generation.id);
    } finally {
      try {
        await _persistTerminal(
          generation: generation,
          status: TurnStatus.cancelled,
        );
      } finally {
        if (publishCancellation && !_controller.isClosed) {
          _controller.add(GenerationCancelled(generation.id));
        }
        await _finish();
      }
    }
  }

  void _receiveEvent(GenerationEvent event) {
    unawaited(_handleEvent(event));
  }

  Future<void> _handleEvent(GenerationEvent event) async {
    if (_terminal) {
      return;
    }

    if (event case GenerationStarted(:final Generation generation)) {
      if (_generation != null || !_matchesRequest(generation.request)) {
        return;
      }
      _generation = generation;
      _controller.add(event);
      return;
    }

    final Generation? generation = _generation;
    if (generation == null || event.generationId != generation.id) {
      return;
    }

    switch (event) {
      case GenerationDelta(:final String delta):
        _assistantText += delta;
        _controller.add(event);
      case GenerationCompleted():
        await _finishFromEvent(event, TurnStatus.completed);
      case GenerationCancelled():
        await _finishFromEvent(event, TurnStatus.cancelled);
      case GenerationFailed():
        await _finishFromEvent(event, TurnStatus.failed);
      case GenerationStarted():
        return;
    }
  }

  bool _matchesRequest(GenerationRequest request) {
    return request.conversationId == _request.conversationId &&
        request.prompt == _request.prompt;
  }

  Future<void> _finishFromEvent(
    GenerationEvent terminalEvent,
    TurnStatus status,
  ) async {
    final Generation? generation = _generation;
    if (_terminal || generation == null) {
      return;
    }

    _terminal = true;
    try {
      await _persistTerminal(generation: generation, status: status);
      if (!_controller.isClosed) {
        _controller.add(terminalEvent);
      }
    } on Object catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      await _finish();
    }
  }

  Future<void> _persistTerminal({
    required Generation generation,
    required TurnStatus status,
  }) {
    return _storageService.saveTerminalAssistantTurn(
      Turn(role: TurnRole.assistant, text: _assistantText, status: status),
      generation,
    );
  }

  void _receiveError(Object error, StackTrace stackTrace) {
    unawaited(_finishWithError(error, stackTrace));
  }

  Future<void> _finishWithError(Object error, StackTrace stackTrace) async {
    if (_terminal) {
      return;
    }
    _terminal = true;

    final Generation? generation = _generation;
    try {
      if (generation != null) {
        await _persistTerminal(
          generation: generation,
          status: TurnStatus.failed,
        );
      }
    } on Object catch (storageError, storageStackTrace) {
      error = storageError;
      stackTrace = storageStackTrace;
    } finally {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
      await _finish();
    }
  }

  void _receiveDone() {
    if (_terminal) {
      return;
    }

    final Generation? generation = _generation;
    if (generation == null) {
      _terminal = true;
      unawaited(_finish());
      return;
    }

    unawaited(
      _finishFromEvent(
        GenerationFailed(
          generationId: generation.id,
          failure: const ConversationFailure(
            'Inference ended before a terminal event.',
          ),
        ),
        TurnStatus.failed,
      ),
    );
  }

  Future<void> _finish() async {
    if (_finished) {
      return;
    }
    _finished = true;
    _onFinished();
    await _subscription?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
