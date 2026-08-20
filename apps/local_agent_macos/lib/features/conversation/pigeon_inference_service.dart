import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

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
    required this.maxTokens,
    required this.seed,
  });

  /// Stable identity of the installed model.
  final String modelId;

  /// Absolute path to the installed LiteRT-LM model.
  final String modelPath;

  /// Maximum native context size.
  final int contextSize;

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
    AnswerStyle Function()? answerStyle,
    this.toolbox,
  }) : _agentContext =
           agentContext ?? ProfileAgentContextProvider(AgentProfile.builtIn),
       _answerStyle = answerStyle ?? _balanced;

  static AnswerStyle _balanced() => AnswerStyle.balanced;

  final DesktopHostService _desktopHostService;
  final LocalModelConfig _config;
  final AgentContextProvider _agentContext;

  /// How far the model may roam, read again for every generation.
  ///
  /// A function rather than a value because the user can change it while the
  /// model stays loaded: the sampler travels in the request the host already
  /// receives, so this costs nothing and never reloads anything.
  final AnswerStyle Function() _answerStyle;

  /// The tools this conversation offers, read again for every generation.
  ///
  /// A function for the same reason [_answerStyle] is: the set can change
  /// while the model stays loaded, and the native side already rebuilds the
  /// conversation when the declarations it was built with have changed.
  /// Null means no tools, which must cost what no toolbox ever cost.
  final AgentToolbox Function()? toolbox;
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
      // Read here rather than held, so a style the user changes mid-session
      // applies to the next question without reloading anything.
      style: _answerStyle(),
      toolbox: toolbox?.call(),
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
    required this.style,
    this.toolbox,
  });

  /// How many tool continuations one turn is allowed before it is cut off.
  ///
  /// A model looping on tools would otherwise hold the machine forever —
  /// the vendored runtime's own automatic loop caps at 25, but three is
  /// already more than any turn this app composes has a use for.
  static const int maxToolRounds = 3;

  final DesktopHostService host;
  final LocalModelConfig config;
  final AnswerStyle style;
  final GenerationRequest request;
  final GenerationId generationId;
  final StreamController<GenerationEvent> controller;
  final Future<void> Function() ensureReady;
  final AgentContextProvider agentContext;
  final void Function(String sessionId) onSessionStarted;
  final void Function() onFinished;

  /// The tools this turn may use, or null for a turn without any.
  final AgentToolbox? toolbox;
  StreamSubscription<DesktopGenerationEvent>? _subscription;
  Future<void>? _cancellation;
  bool _fenced = false;
  bool _terminal = false;
  bool _hostAcknowledgedCancellation = false;

  /// Which host generation this operation is currently listening for.
  ///
  /// The first phase reuses [generationId]; each tool continuation is a new
  /// host generation on the same session, because the host treats the
  /// tool-call event as terminal and refuses an id it has already seen.
  late String _hostGenerationId = generationId.value;

  /// Whether [GenerationStarted] already went upward. One turn starts once,
  /// however many host generations its tool loop spends.
  bool _startedEmitted = false;

  /// The system instruction the first phase was built with. Continuations
  /// must repeat it verbatim: the native side rebuilds a conversation whose
  /// instruction has changed, and a rebuilt conversation has forgotten the
  /// tool calls it was answering.
  String _systemInstruction = '';

  /// The declarations the first phase sent, repeated on continuations for
  /// the same reason as [_systemInstruction].
  String? _toolsJson;
  int _toolRounds = 0;

  Future<void> start() async {
    _subscription = host.generationEvents
        .where((event) => event.generationId == _hostGenerationId)
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
      // An aside brings its own instruction and is not a conversation turn:
      // no persona around it, no memories, no clock, and — see
      // `GenerationRequest.instruction` — no tools either.
      final String? aside = request.instruction;
      final AgentPromptContext context = aside == null
          ? agentContext.compose(request.prompt, channel: request.channel)
          : AgentPromptContext(
              systemInstruction: aside,
              turnInstruction: request.prompt,
              selectedMemoryIds: const <String>[],
              profileCharacterCount: aside.length,
            );
      _systemInstruction = context.systemInstruction;
      final AgentToolbox? tools = aside == null ? toolbox : null;
      _toolsJson = tools == null || tools.isEmpty
          ? null
          : tools.declarationsJson;
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
          temperature: style.temperature,
          topP: style.topP,
          maxTokens: config.maxTokens,
          seed: config.seed,
          toolsJson: _toolsJson,
          imagePath: request.imagePath,
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
        // One turn starts once, however many host generations its tool
        // loop spends underneath it.
        if (!_startedEmitted) {
          _startedEmitted = true;
          controller.add(
            GenerationStarted(Generation(id: generationId, request: request)),
          );
        }
      case HostGenerationEventType.toolCall:
        unawaited(_continueWithTools(event.toolCallsJson ?? '[]'));
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
        // The bubble says "回答失敗" and nothing else on purpose; this line
        // is where the reason survives for whoever reads the log.
        debugPrint(
          'Lulo turn: host reported failure — '
          '${event.failureCode?.name ?? 'no failure code'}',
        );
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

  /// Runs the model's tool calls and continues the turn with the results.
  ///
  /// The host has already ended the previous generation — its tool-call
  /// event is terminal on that side — so the continuation is a fresh host
  /// generation on the same session, and this operation re-aims its event
  /// filter at the new id. The turn the caller sees never notices.
  Future<void> _continueWithTools(String callsJson) async {
    final AgentToolbox? tools = toolbox;
    final List<AgentToolCall> calls = AgentToolCall.listFromJson(callsJson);
    _toolRounds += 1;
    if (tools == null || calls.isEmpty || _toolRounds > maxToolRounds) {
      // A tool call with no toolbox is a protocol breach, an empty list is
      // a runtime bug, and a fourth round is a model stuck in a loop. All
      // three end the turn as a failure rather than hanging it.
      if (!_terminal) {
        controller.add(
          GenerationFailed(
            generationId: generationId,
            failure: ConversationFailure(
              DesktopHostFailureCode.generationFailed.userSafeMessage,
            ),
          ),
        );
        await _finish();
      }
      return;
    }
    final List<AgentToolResult> results = <AgentToolResult>[
      for (final AgentToolCall call in calls) await tools.call(call),
    ];
    if (_fenced || _terminal) {
      // Cancelled while a tool was running. The host holds no generation
      // right now — the tool-call event ended the last one — so there is
      // nothing to take back; not starting the continuation is the whole
      // job.
      return;
    }
    final String continuationId = '${generationId.value}-tools-$_toolRounds';
    _hostGenerationId = continuationId;
    try {
      final acknowledgement = await host.startGeneration(
        DesktopGenerationRequest(
          generationId: continuationId,
          sessionId: request.conversationId.value,
          systemInstruction: _systemInstruction,
          prompt: '',
          context: const <String>[],
          temperature: style.temperature,
          topP: style.topP,
          maxTokens: config.maxTokens,
          seed: config.seed,
          toolsJson: _toolsJson,
          toolResponsesJson: encodeAgentToolResults(results),
        ),
      );
      if (_fenced) {
        await _cancellation;
        if (!_hostAcknowledgedCancellation &&
            acknowledgement.accepted &&
            acknowledgement.generationId == continuationId) {
          await host.cancelGeneration(continuationId);
        }
        return;
      }
      if (acknowledgement.generationId != continuationId) {
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
    // The current host generation, which after a tool round is not the one
    // this operation was born with.
    final String hostGenerationId = _hostGenerationId;
    try {
      final acknowledgement = await host.cancelGeneration(hostGenerationId);
      if (acknowledgement.generationId != hostGenerationId) {
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
  // The failure the user sees deliberately says almost nothing, which
  // twice made a live "回答失敗" undiagnosable: the log held no trace of
  // what actually threw. The truncated original goes to the log — error
  // types and protocol codes, not conversation content, are what land
  // here — and the sanitized message goes to the screen.
  final String detail = error.toString();
  debugPrint(
    'Lulo turn: failure sanitized — ${error.runtimeType}: '
    '${detail.length > 300 ? detail.substring(0, 300) : detail}',
  );
  if (error case DesktopHostFailure(:final message)) {
    return ConversationFailure(message);
  }
  return ConversationFailure(
    DesktopHostFailureCode.runtimeUnavailable.userSafeMessage,
  );
}
