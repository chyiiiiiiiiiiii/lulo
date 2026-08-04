import 'dart:async';

import 'package:agent_core/agent_core.dart';

import '../../generated/desktop_host_api.g.dart';
import '../../platform/desktop_host_service.dart';
import '../agent_profile/agent_context_provider.dart';
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
    AgentContextProvider? agentContext,
  }) : _agentContext =
           agentContext ?? ProfileAgentContextProvider(AgentProfile.builtIn);

  final DesktopHostService _desktopHostService;
  final LocalModelConfig _config;
  final AgentContextProvider _agentContext;
  int _nextGeneration = 0;

  @override
  String get modelId => _config.modelId;
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
      agentContext: _agentContext,
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

  /// Drops the runtime session started for [conversationId], if there was one.
  ///
  /// Sessions this adapter never started are not worth a boundary round trip,
  /// and forgetting the id here also keeps teardown from resetting it twice.
  ///
  /// A generation still running in the session is cancelled first, the way
  /// teardown has always done it. Resetting a session takes the runtime's
  /// active generation away without emitting a terminal event, and the
  /// coordinator releases its single generation slot only when it observes
  /// one — so reaching the reset first would refuse every later turn as busy
  /// for the lifetime of the process.
  @override
  Future<void> releaseSession(ConversationId conversationId) async {
    if (!_startedSessionIds.remove(conversationId.value)) {
      return;
    }
    final operations = List<_PigeonGenerationOperation>.of(_operations.values);
    for (final operation in operations) {
      if (operation.request.conversationId == conversationId) {
        await operation.cancel();
      }
    }
    await _desktopHostService.resetSession(conversationId.value);
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
    required this.agentContext,
    required this.onSessionStarted,
    required this.onFinished,
  });

  final DesktopHostService host;
  final LocalModelConfig config;
  final GenerationRequest request;
  final GenerationId generationId;
  final StreamController<GenerationEvent> controller;
  final Future<void> Function() ensureReady;
  final AgentContextProvider agentContext;
  final void Function(String sessionId) onSessionStarted;
  final void Function() onFinished;
  StreamSubscription<DesktopGenerationEvent>? _subscription;
  Future<void>? _cancellation;
  bool _fenced = false;
  bool _terminal = false;
  bool _hostAcknowledgedCancellation = false;

  Future<void> start() async {
    _subscription = host.generationEvents
        .where((event) => event.generationId == generationId.value)
        .listen(_receiveEvent);
    try {
      await ensureReady();
      if (_fenced) {
        // Cancelled while readiness was still loading the model — seconds,
        // for a multi-gigabyte one, and every barge-in during prefill lands
        // here. Sending the start now would put a generation on the runtime
        // that nothing is listening to and nothing will ever cancel: it holds
        // the single native slot until it burns its whole token budget, and
        // every turn behind it is refused as busy.
        return;
      }
      onSessionStarted(request.conversationId.value);
      final AgentPromptContext context = agentContext.compose(request.prompt);
      final acknowledgement = await host.startGeneration(
        DesktopGenerationRequest(
          generationId: generationId.value,
          sessionId: request.conversationId.value,
          systemInstruction: context.systemInstruction,
          prompt: context.turnInstruction,
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
      if (_fenced) {
        // Cancelled while this start was in flight. Usually the host had
        // already registered the generation and acknowledged the cancel, and
        // there is nothing left to do. When it did not — the cancel and the
        // start crossed on the wire, and the host accepted this one a moment
        // after answering "not mine" — this is the last code that knows the
        // generation exists, so taking it back is this call's job.
        await _cancellation;
        if (!_hostAcknowledgedCancellation &&
            acknowledgement.accepted &&
            acknowledgement.generationId == generationId.value) {
          await host.cancelGeneration(generationId.value);
        }
        return;
      }
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

  /// Stops the generation, and never throws doing it.
  ///
  /// Every caller of this reaches it through something that cannot catch:
  /// `unawaited(stop())` when the user talks over the agent, and a listener
  /// cancellation that carries the exception up through the composer's stop.
  /// A failure here is reported on the generation stream, which is the
  /// channel the conversation already watches, and the future still
  /// completes.
  Future<void> _cancel() async {
    _fenced = true;
    await _subscription?.cancel();
    try {
      final acknowledgement = await host.cancelGeneration(generationId.value);
      if (acknowledgement.generationId != generationId.value) {
        throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
      }
      // An unacknowledged cancellation has one meaning at this boundary: the
      // host is not running this generation. Either it already ended, or the
      // start has not reached it yet — and `start` compensates for that one.
      // Both are the state the caller asked for, so neither is a failure.
      _hostAcknowledgedCancellation = acknowledgement.acknowledged;
      onFinished();
    } on Object catch (error, stackTrace) {
      if (!controller.isClosed) {
        controller.addError(_safeConversationFailure(error), stackTrace);
        await _finish();
      }
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
