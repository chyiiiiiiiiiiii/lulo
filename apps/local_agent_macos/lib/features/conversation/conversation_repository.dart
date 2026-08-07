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
  ///
  /// [checkpointInterval] is how often a still-streaming answer is written
  /// down. It is a floor on how much of an answer a crash can cost and a
  /// ceiling on how many writes a long answer pays for: a checkpoint per
  /// token would be thousands of updates on the path that is streaming.
  ConversationRepository({
    required ConversationStorageService storageService,
    required InferenceService inferenceService,
    DateTime Function()? clock,
    Duration checkpointInterval = const Duration(milliseconds: 500),
  }) : this._(
         storageService,
         inferenceService,
         clock ?? DateTime.now,
         checkpointInterval,
       );

  ConversationRepository._(
    this._storageService,
    this._inferenceService,
    this._clock,
    this._checkpointInterval,
  );

  final ConversationStorageService _storageService;
  final InferenceService _inferenceService;
  final DateTime Function() _clock;
  final Duration _checkpointInterval;
  _GenerationOperation? _activeOperation;

  /// Every operation not yet fully torn down, including ones cancelling.
  final Set<_GenerationOperation> _liveOperations = <_GenerationOperation>{};

  /// Completes when the operation before the next one has fully finished.
  Future<void> _previousOperationDone = Future<void>.value();

  /// Loads the stored history of [conversationId].
  Future<List<Turn>> loadTurns(ConversationId conversationId) =>
      _storageService.loadTurns(conversationId);

  /// Every stored conversation containing [query], most recent first.
  Future<List<ConversationSummary>> searchConversations(String query) =>
      _storageService.searchConversations(query);

  /// Gives [conversationId] a name of the user's own.
  Future<void> renameConversation(
    ConversationId conversationId,
    String title,
  ) => _storageService.renameConversation(conversationId, title);

  /// Keeps [conversationId] at the top of the list, or lets it go.
  Future<void> setConversationPinned(
    ConversationId conversationId, {
    required bool pinned,
  }) => _storageService.setConversationPinned(conversationId, pinned: pinned);

  /// Turns runs the last process did not finish into the turns they were.
  ///
  /// Call once at startup, before anything reads a conversation. On a clean
  /// exit there is nothing to do: a run is closed as its terminal turn is
  /// written, so anything still open is the residue of a process that went
  /// away mid-answer. What it had checkpointed becomes an assistant turn
  /// marked [TurnStatus.interrupted] — the answer stops where the record
  /// stops, rather than the whole thing vanishing.
  ///
  /// Every run is closed either way, including ones with nothing to show, so
  /// the same wreckage is not reconsidered on every launch.
  Future<void> recoverInterruptedRuns() async {
    final List<RunRecord> interrupted = await _storageService
        .loadUnfinishedRuns();
    for (final RunRecord run in interrupted) {
      // An empty turn is worse than no turn: it renders as a blank bubble
      // the user cannot account for.
      if (run.partialText.isNotEmpty) {
        await _storageService.saveTerminalAssistantTurn(
          Turn(
            role: TurnRole.assistant,
            text: run.partialText,
            status: TurnStatus.interrupted,
          ),
          Generation(
            id: run.id,
            request: GenerationRequest(
              conversationId: run.conversationId,
              prompt: '',
            ),
          ),
        );
      }
      await _storageService.endRun(run.id, TurnStatus.interrupted);
    }
  }

  /// Every stored conversation, most recently spoken-in first.
  Future<List<ConversationSummary>> listConversations() =>
      _storageService.listConversations();

  /// Forgets [conversationId] and everything said in it.
  ///
  /// An operation still speaking in it is told to forget too: its
  /// cancellation would otherwise write a terminal turn back into the store,
  /// and in this schema rows *are* the conversation, so the forgotten
  /// conversation would stand back up as a ghost with a blank title.
  ///
  /// The runtime is told last. It keeps one live conversation per session id,
  /// each holding its own KV cache, and nothing evicts them — so deleting the
  /// rows alone left the cost of a forgotten conversation resident until the
  /// model was swapped or the app exited.
  Future<void> deleteConversation(ConversationId conversationId) async {
    for (final _GenerationOperation operation in _liveOperations) {
      if (operation.conversationId == conversationId) {
        operation.forget();
      }
    }
    await _storageService.deleteConversation(conversationId);
    await _inferenceService.releaseSession(conversationId);
  }

  /// Takes [conversationId] back to before its last question.
  ///
  /// The runtime is told as well as the store, for the reason
  /// [deleteConversation] tells it: it holds a live conversation per session
  /// id, and that session's KV cache still contains the question and the
  /// answer being replaced. Left alone, the retry would be conditioned on the
  /// answer the user just rejected and would see the question asked twice.
  /// Released, the next generation re-seeds from the history it is handed.
  Future<void> dropFromLastQuestion(ConversationId conversationId) async {
    await _storageService.dropFromLastQuestion(conversationId);
    await _inferenceService.releaseSession(conversationId);
  }

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

    // One generation at a time, but "at a time" is measured against the
    // previous operation's *whole* teardown: a cancelled answer still has a
    // native cancel round trip to finish, and the next message queues behind
    // it rather than being refused for arriving during it.
    final Future<void> previousDone = _previousOperationDone;

    late final _GenerationOperation operation;
    final StreamController<GenerationEvent> controller =
        StreamController<GenerationEvent>(
          onListen: () =>
              unawaited(previousDone.then((void _) => operation.start())),
          onCancel: () => operation.onListenerCancelled(),
        );
    operation = _GenerationOperation(
      _storageService,
      _inferenceService,
      userTurn,
      request,
      controller,
      () => _release(operation),
      _clock,
      _checkpointInterval,
    );
    _activeOperation = operation;
    _liveOperations.add(operation);
    _previousOperationDone = operation.done;
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
    _liveOperations.remove(operation);
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
    this._clock,
    this._checkpointInterval,
  );

  final ConversationStorageService _storageService;
  final InferenceService _inferenceService;
  final Turn _userTurn;
  final GenerationRequest _request;
  final StreamController<GenerationEvent> _controller;
  final void Function() _onFinished;
  final DateTime Function() _clock;
  final Duration _checkpointInterval;

  /// When the answer so far was last written down, absent until it has been.
  DateTime? _checkpointedAt;

  StreamSubscription<GenerationEvent>? _subscription;
  Generation? _generation;
  String _assistantText = '';
  bool _started = false;
  bool _terminal = false;
  bool _finished = false;
  bool _forgotten = false;
  final Completer<void> _done = Completer<void>();

  GenerationId? get generationId => _generation?.id;

  /// The conversation this operation is speaking in.
  ConversationId get conversationId => _request.conversationId;

  /// Completes once this operation has fully finished, teardown included.
  Future<void> get done => _done.future;

  /// The conversation was deleted out from under this operation: say nothing
  /// more to the store on its behalf.
  void forget() {
    _forgotten = true;
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    try {
      if (_forgotten) {
        _terminal = true;
        await _finish();
        return;
      }
      await _storageService.saveUserTurn(_request.conversationId, _userTurn);
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
      try {
        await _inferenceService.cancel(generation.id);
      } finally {
        await _subscription?.cancel();
      }
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
      // Opened before any answer text exists. A crash during the first token
      // must still leave a record that a generation was under way.
      await _openRun(generation);
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
        // Handed to the stream before the checkpoint is awaited, so the write
        // is never what the next frame waits on. Not an ordering guarantee
        // against the listener: delivery is asynchronous and a store that
        // records synchronously will be seen to act first. What is guaranteed
        // is that the delta is already on its way.
        _controller.add(event);
        await _checkpoint(generation);
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
  }) async {
    if (_forgotten) {
      return;
    }
    await _storageService.saveTerminalAssistantTurn(
      Turn(role: TurnRole.assistant, text: _assistantText, status: status),
      generation,
    );
    // The turn is the durable record once it exists, so the run is closed
    // behind it. Left open it would look to the next launch like an answer
    // that never finished, and be recovered on top of the one that did.
    await _storageService.endRun(generation.id, status);
  }

  Future<void> _openRun(Generation generation) async {
    if (_forgotten) {
      return;
    }
    await _storageService.beginRun(
      RunRecord(
        id: generation.id,
        conversationId: _request.conversationId,
        modelId: _inferenceService.modelId,
        startedAt: _clock(),
      ),
    );
  }

  Future<void> _checkpoint(Generation generation) async {
    if (_forgotten) {
      return;
    }
    final DateTime now = _clock();
    final DateTime? last = _checkpointedAt;
    // The first delta always writes, so a crash on the first token still
    // leaves a word behind rather than an empty run.
    if (last != null && now.difference(last) < _checkpointInterval) {
      return;
    }
    _checkpointedAt = now;
    await _storageService.checkpointRun(generation.id, _assistantText);
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
    try {
      await _subscription?.cancel();
      if (!_controller.isClosed) {
        await _controller.close();
      }
    } finally {
      if (!_done.isCompleted) {
        _done.complete();
      }
    }
  }
}
