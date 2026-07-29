import 'dart:async';

import 'package:agent_core/agent_core.dart';

import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/inference_service.dart';

/// Session-scoped storage used until the benchmark-selected SQLite adapter lands.
final class InMemoryConversationStorageService
    implements ConversationStorageService {
  final Map<ConversationId, List<Turn>> _turns = <ConversationId, List<Turn>>{};
  Turn? _pendingUserTurn;

  @override
  Future<List<Turn>> loadTurns(ConversationId conversationId) async {
    return List<Turn>.unmodifiable(_turns[conversationId] ?? const <Turn>[]);
  }

  @override
  Future<void> saveUserTurn(Turn turn) async {
    _pendingUserTurn = turn;
  }

  @override
  Future<void> saveTerminalAssistantTurn(
    Turn turn,
    Generation generation,
  ) async {
    final List<Turn> conversationTurns = _turns.putIfAbsent(
      generation.request.conversationId,
      () => <Turn>[],
    );
    final Turn? userTurn = _pendingUserTurn;
    if (userTurn != null) {
      conversationTurns.add(userTurn);
      _pendingUserTurn = null;
    }
    conversationTurns.add(turn);
  }

  /// Releases session-only data when the application composition is disposed.
  void dispose() {
    _turns.clear();
    _pendingUserTurn = null;
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
