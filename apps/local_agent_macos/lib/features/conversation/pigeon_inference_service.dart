import 'dart:async';

import 'package:agent_core/agent_core.dart';

import '../../generated/desktop_host_api.g.dart';
import '../../platform/desktop_host_service.dart';
import 'inference_service.dart';

/// Immutable native model and sampling configuration.
final class LocalModelConfig {
  /// Creates the configuration used for every local generation.
  const LocalModelConfig({
    required this.modelId,
    required this.modelPath,
    required this.contextSize,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.seed,
  });

  /// Stable identity of the installed model.
  final String modelId;

  /// Absolute path to the installed LiteRT-LM model.
  final String modelPath;

  /// Maximum native context size.
  final int contextSize;

  /// Sampling temperature.
  final double temperature;

  /// Nucleus-sampling probability.
  final double topP;

  /// Maximum generated tokens.
  final int maxTokens;

  /// Deterministic sampler seed.
  final int seed;
}

/// Adapts the typed desktop host boundary to the conversation feature.
final class PigeonInferenceService implements InferenceService {
  /// Creates a feature adapter around an explicitly owned desktop host.
  PigeonInferenceService({
    required this._desktopHostService,
    required this._config,
  });

  final DesktopHostService _desktopHostService;
  final LocalModelConfig _config;
  int _nextGeneration = 0;
  Future<DesktopRuntimeCapabilities>? _handshakeAttempt;
  DesktopRuntimeCapabilities? _capabilities;
  Future<void>? _readinessAttempt;
  bool _ready = false;
  bool _disposed = false;
  Future<void>? _disposal;
  final Set<String> _startedSessionIds = <String>{};
  final Map<String, _PigeonGenerationOperation> _operations =
      <String, _PigeonGenerationOperation>{};

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    final generationId = GenerationId('litert-generation-${++_nextGeneration}');
    late final _PigeonGenerationOperation operation;
    late final StreamController<GenerationEvent> controller;
    controller = StreamController<GenerationEvent>(
      sync: true,
      onListen: () {
        _operations[generationId.value] = operation;
        unawaited(operation.start());
      },
      onCancel: () => operation.cancelForListener(),
    );
    operation = _PigeonGenerationOperation(
      host: _desktopHostService,
      config: _config,
      request: request,
      generationId: generationId,
      controller: controller,
      ensureReady: _ensureReady,
      onSessionStarted: _startedSessionIds.add,
      onFinished: () => _operations.remove(generationId.value),
    );
    if (_disposed) {
      return Stream<GenerationEvent>.error(
        StateError('The inference service is disposed.'),
      );
    }
    return controller.stream;
  }

  /// Performs the handshake and model load ahead of the first prompt.
  ///
  /// Loading a multi-gigabyte model takes seconds, and doing it lazily puts
  /// that cost in front of the user's first answer. Calling this at startup
  /// moves it off the critical path. It shares the single readiness attempt
  /// with [generate], so a prompt that arrives mid-warmup waits for the same
  /// load rather than starting a second one, and it surfaces failures to the
  /// caller instead of hiding them until the first prompt.
  Future<void> warmUp() => _ensureReady();

  Future<void> _ensureReady() async {
    if (_disposed) {
      throw StateError('The inference service is disposed.');
    }
    if (_ready) {
      return;
    }
    final existingAttempt = _readinessAttempt;
    if (existingAttempt != null) {
      return existingAttempt;
    }
    final attempt = _initialize();
    _readinessAttempt = attempt;
    try {
      await attempt;
      _ready = true;
    } finally {
      if (!_ready && identical(_readinessAttempt, attempt)) {
        _readinessAttempt = null;
      }
    }
  }

  Future<void> _initialize() async {
    final capabilities = await _ensureCapabilities();
    if (!capabilities.supportsStreaming || !capabilities.supportsCancellation) {
      throw const DesktopHostFailure(DesktopHostFailureCode.runtimeUnavailable);
    }
    final result = await _desktopHostService.loadModel(
      DesktopModelRequest(
        modelId: _config.modelId,
        modelPath: _config.modelPath,
        contextSize: _config.contextSize,
      ),
    );
    if (!result.loaded || result.modelId != _config.modelId) {
      throw const DesktopHostFailure(DesktopHostFailureCode.modelLoadFailed);
    }
  }

  Future<DesktopRuntimeCapabilities> _ensureCapabilities() async {
    final capabilities = _capabilities;
    if (capabilities != null) {
      return capabilities;
    }
    final existingAttempt = _handshakeAttempt;
    if (existingAttempt != null) {
      return existingAttempt;
    }
    final attempt = _desktopHostService.handshake();
    _handshakeAttempt = attempt;
    try {
      final result = await attempt;
      _capabilities = result;
      return result;
    } finally {
      if (_capabilities == null && identical(_handshakeAttempt, attempt)) {
        _handshakeAttempt = null;
      }
    }
  }

  @override
  Future<void> cancel(GenerationId generationId) async {
    await _operations[generationId.value]?.cancel();
  }

  /// Releases operation-scoped resources owned by this adapter.
  ///
  /// Fences new work immediately, awaits cancellation of the active
  /// generation, resets every session this adapter started, then unloads the
  /// model once. The injected [DesktopHostService] belongs to the Composition
  /// Root and is never disposed here. Repeated or overlapping calls share the
  /// single teardown started by the first call.
  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= _dispose();
  }

  Future<void> _dispose() async {
    final operations = List<_PigeonGenerationOperation>.of(_operations.values);
    for (final operation in operations) {
      await operation.cancel();
    }
    _operations.clear();
    for (final sessionId in _startedSessionIds) {
      await _desktopHostService.resetSession(sessionId);
    }
    _startedSessionIds.clear();
    if (_ready) {
      _ready = false;
      await _desktopHostService.unloadModel();
    }
  }
}

final class _PigeonGenerationOperation {
  _PigeonGenerationOperation({
    required this.host,
    required this.config,
    required this.request,
    required this.generationId,
    required this.controller,
    required this.ensureReady,
    required this.onSessionStarted,
    required this.onFinished,
  });

  final DesktopHostService host;
  final LocalModelConfig config;
  final GenerationRequest request;
  final GenerationId generationId;
  final StreamController<GenerationEvent> controller;
  final Future<void> Function() ensureReady;
  final void Function(String sessionId) onSessionStarted;
  final void Function() onFinished;
  StreamSubscription<DesktopGenerationEvent>? _subscription;
  Future<void>? _cancellation;
  bool _fenced = false;
  bool _terminal = false;

  Future<void> start() async {
    _subscription = host.generationEvents
        .where((event) => event.generationId == generationId.value)
        .listen(_receiveEvent);
    try {
      await ensureReady();
      onSessionStarted(request.conversationId.value);
      final acknowledgement = await host.startGeneration(
        DesktopGenerationRequest(
          generationId: generationId.value,
          sessionId: request.conversationId.value,
          prompt: request.prompt,
          context: const <String>[],
          history: <DesktopConversationTurn>[
            for (final Turn turn in request.history)
              DesktopConversationTurn(role: turn.role, text: turn.text),
          ],
          temperature: config.temperature,
          topP: config.topP,
          maxTokens: config.maxTokens,
          seed: config.seed,
        ),
      );
      if (acknowledgement.generationId != generationId.value) {
        throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
      }
      if (!acknowledgement.accepted) {
        throw const DesktopHostFailure(DesktopHostFailureCode.generationFailed);
      }
    } on Object catch (error, stackTrace) {
      if (!_terminal) {
        controller.addError(_safeConversationFailure(error), stackTrace);
        await _finish();
      }
    }
  }

  void _receiveEvent(DesktopGenerationEvent event) {
    if (_terminal || _fenced) {
      return;
    }
    switch (event.type) {
      case HostGenerationEventType.started:
        controller.add(
          GenerationStarted(Generation(id: generationId, request: request)),
        );
      case HostGenerationEventType.delta:
        controller.add(
          GenerationDelta(generationId: generationId, delta: event.delta ?? ''),
        );
      case HostGenerationEventType.completed:
        controller.add(GenerationCompleted(generationId));
        unawaited(_finish());
      case HostGenerationEventType.cancelled:
        controller.add(GenerationCancelled(generationId));
        unawaited(_finish());
      case HostGenerationEventType.failed:
        controller.add(
          GenerationFailed(
            generationId: generationId,
            failure: ConversationFailure(
              event.failureCode?.userSafeMessage ??
                  DesktopHostFailureCode.generationFailed.userSafeMessage,
            ),
          ),
        );
        unawaited(_finish());
    }
  }

  Future<void> cancel() {
    if (_terminal) {
      return Future<void>.value();
    }
    return _cancellation ??= _cancel();
  }

  Future<void> _cancel() async {
    _fenced = true;
    await _subscription?.cancel();
    try {
      final acknowledgement = await host.cancelGeneration(generationId.value);
      if (acknowledgement.generationId != generationId.value) {
        throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
      }
      if (!acknowledgement.acknowledged) {
        throw const DesktopHostFailure(DesktopHostFailureCode.generationBusy);
      }
      onFinished();
    } on Object catch (error, stackTrace) {
      if (!controller.isClosed) {
        controller.addError(_safeConversationFailure(error), stackTrace);
        await _finish();
      }
      rethrow;
    }
  }

  Future<void> cancelForListener() async {
    if (!_terminal) {
      await cancel();
    }
  }

  Future<void> _finish() async {
    if (_terminal) {
      return;
    }
    _terminal = true;
    await _subscription?.cancel();
    onFinished();
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

ConversationFailure _safeConversationFailure(Object error) {
  if (error case DesktopHostFailure(:final message)) {
    return ConversationFailure(message);
  }
  return ConversationFailure(
    DesktopHostFailureCode.runtimeUnavailable.userSafeMessage,
  );
}
