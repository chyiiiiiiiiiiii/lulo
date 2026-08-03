import 'dart:async';

import 'package:agent_core/agent_core.dart';

import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/inference_service.dart';

/// Session-scoped storage, for tests and the preview.
///
/// Runs the same contract suite as the durable store, so the two cannot
/// drift apart in behaviour.
final class InMemoryConversationStorageService
    implements ConversationStorageService {
  final Map<ConversationId, List<Turn>> _turns = <ConversationId, List<Turn>>{};
  final Map<ConversationId, int> _lastTouch = <ConversationId, int>{};
  final Map<ConversationId, DateTime> _updatedAt = <ConversationId, DateTime>{};
  final Map<GenerationId, RunRecord> _runs = <GenerationId, RunRecord>{};
  int _touches = 0;

  @override
  Future<List<Turn>> loadTurns(ConversationId conversationId) async {
    return List<Turn>.unmodifiable(_turns[conversationId] ?? const <Turn>[]);
  }

  @override
  Future<void> saveUserTurn(ConversationId conversationId, Turn turn) async {
    _save(conversationId, turn);
  }

  @override
  Future<void> saveTerminalAssistantTurn(
    Turn turn,
    Generation generation,
  ) async {
    _save(generation.request.conversationId, turn);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final List<ConversationId> ids = _turns.keys.toList()
      ..sort(
        (ConversationId a, ConversationId b) =>
            _lastTouch[b]!.compareTo(_lastTouch[a]!),
      );
    return List<ConversationSummary>.unmodifiable(
      ids.map(
        (ConversationId id) => ConversationSummary(
          id: id,
          title:
              _turns[id]!
                  .where((Turn turn) => turn.role == TurnRole.user)
                  .map((Turn turn) => turn.text)
                  .firstOrNull ??
              '',
          updatedAt: _updatedAt[id]!,
        ),
      ),
    );
  }

  @override
  Future<void> deleteConversation(ConversationId conversationId) async {
    _turns.remove(conversationId);
    _lastTouch.remove(conversationId);
    _updatedAt.remove(conversationId);
    _runs.removeWhere(
      (GenerationId _, RunRecord run) => run.conversationId == conversationId,
    );
  }

  @override
  Future<void> beginRun(RunRecord run) async {
    _runs[run.id] = run;
  }

  @override
  Future<void> checkpointRun(
    GenerationId generationId,
    String partialText,
  ) async {
    final RunRecord? run = _runs[generationId];
    if (run == null || run.isFinished) {
      return;
    }
    _runs[generationId] = RunRecord(
      id: run.id,
      conversationId: run.conversationId,
      modelId: run.modelId,
      startedAt: run.startedAt,
      partialText: partialText,
    );
  }

  @override
  Future<void> endRun(GenerationId generationId, TurnStatus outcome) async {
    final RunRecord? run = _runs[generationId];
    if (run == null || run.isFinished) {
      return;
    }
    _runs[generationId] = RunRecord(
      id: run.id,
      conversationId: run.conversationId,
      modelId: run.modelId,
      startedAt: run.startedAt,
      endedAt: DateTime.now(),
      outcome: outcome,
      partialText: run.partialText,
    );
  }

  @override
  Future<List<RunRecord>> loadUnfinishedRuns() async {
    final List<RunRecord> unfinished =
        _runs.values.where((RunRecord run) => !run.isFinished).toList()..sort(
          (RunRecord a, RunRecord b) => a.startedAt.compareTo(b.startedAt),
        );
    return List<RunRecord>.unmodifiable(unfinished);
  }

  void _save(ConversationId conversationId, Turn turn) {
    _turns.putIfAbsent(conversationId, () => <Turn>[]).add(turn);
    _lastTouch[conversationId] = _touches++;
    _updatedAt[conversationId] = DateTime.now();
  }

  /// Releases session-only data when the application composition is disposed.
  void dispose() {
    _turns.clear();
    _lastTouch.clear();
    _updatedAt.clear();
    _runs.clear();
  }
}

/// Deterministic local stand-in that exercises the complete streaming path.
final class DeterministicFakeInferenceService implements InferenceService {
  final Map<GenerationId, _FakeGenerationOperation> _operations =
      <GenerationId, _FakeGenerationOperation>{};
  int _nextGeneration = 1;
  bool _disposed = false;

  static const List<String> _chunks = <String>[
    'Local inference ',
    'is streaming through the real app pipeline. ',
    'This preview is deterministic and runs without a network connection.',
  ];

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    if (_disposed) {
      return Stream<GenerationEvent>.error(
        StateError('The fake inference service is disposed.'),
      );
    }

    final Generation generation = Generation(
      id: GenerationId('fake-generation-${_nextGeneration++}'),
      request: request,
    );
    late final _FakeGenerationOperation operation;
    late final StreamController<GenerationEvent> controller;
    controller = StreamController<GenerationEvent>(
      onListen: () => operation.start(),
      onCancel: () => operation.pause(),
    );
    operation = _FakeGenerationOperation(
      generation: generation,
      controller: controller,
      chunks: _chunks,
      onFinished: () => _operations.remove(generation.id),
    );
    _operations[generation.id] = operation;
    return controller.stream;
  }

  @override
  Future<void> cancel(GenerationId generationId) async {
    await _operations[generationId]?.cancel();
  }

  /// Holds no per-session runtime state, so there is nothing to let go of.
  @override
  Future<void> releaseSession(ConversationId conversationId) async {}

  /// Cancels all operation-scoped resources owned by this service.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final List<_FakeGenerationOperation> operations = _operations.values.toList(
      growable: false,
    );
    await Future.wait(
      operations.map((_FakeGenerationOperation operation) => operation.close()),
    );
    _operations.clear();
  }
}

final class _FakeGenerationOperation {
  _FakeGenerationOperation({
    required this.generation,
    required this.controller,
    required this.chunks,
    required this.onFinished,
  });

  final Generation generation;
  final StreamController<GenerationEvent> controller;
  final List<String> chunks;
  final void Function() onFinished;
  final List<Timer> _timers = <Timer>[];
  bool _terminal = false;

  /// How long the preview takes to say its piece.
  ///
  /// Deliberately about a second rather than the fifth of one it used to be.
  /// The preview exists to show what a local answer arriving looks like, and
  /// at the old pace the whole response landed before a person could see it
  /// stream — the stop button appeared and vanished inside a single frame on a
  /// busy machine, which is a thing neither a user nor a test can catch.
  static const Duration _firstChunk = Duration(milliseconds: 140);
  static const Duration _betweenChunks = Duration(milliseconds: 300);

  void start() {
    if (_terminal) {
      return;
    }
    controller.add(GenerationStarted(generation));
    for (int index = 0; index < chunks.length; index += 1) {
      _timers.add(
        Timer(_firstChunk + (_betweenChunks * index), () {
          if (!_terminal) {
            controller.add(
              GenerationDelta(
                generationId: generation.id,
                delta: chunks[index],
              ),
            );
          }
        }),
      );
    }
    _timers.add(
      Timer(_firstChunk + (_betweenChunks * chunks.length), () async {
        if (_terminal) {
          return;
        }
        _terminal = true;
        controller.add(GenerationCompleted(generation.id));
        await _finish();
      }),
    );
  }

  void pause() {
    for (final Timer timer in _timers) {
      timer.cancel();
    }
  }

  Future<void> cancel() async {
    if (_terminal) {
      return;
    }
    _terminal = true;
    pause();
    if (!controller.isClosed) {
      controller.add(GenerationCancelled(generation.id));
    }
    await _finish();
  }

  Future<void> close() async {
    if (_terminal && controller.isClosed) {
      return;
    }
    _terminal = true;
    pause();
    await _finish();
  }

  Future<void> _finish() async {
    onFinished();
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}
