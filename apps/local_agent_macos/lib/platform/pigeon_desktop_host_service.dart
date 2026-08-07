import 'dart:async';
import 'dart:collection';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../generated/desktop_host_api.g.dart';
import 'desktop_host_service.dart';

/// Pigeon adapter that owns schema validation and native event ordering.
final class PigeonDesktopHostService extends DesktopHostEventApi
    implements DesktopHostService {
  /// Creates the adapter around an injectable generated [hostApi].
  PigeonDesktopHostService({
    DesktopHostApi? hostApi,
    DateTime Function()? now,
    bool registerEventApi = true,
  }) : _hostApi = hostApi ?? DesktopHostApi(),
       _now = now ?? DateTime.now,
       _eventApiRegistered = registerEventApi {
    if (registerEventApi) {
      DesktopHostEventApi.setUp(this);
    }
  }

  final DesktopHostApi _hostApi;
  final DateTime Function() _now;
  final bool _eventApiRegistered;
  final StreamController<DesktopGenerationEvent> _events =
      StreamController<DesktopGenerationEvent>.broadcast(sync: true);
  final Queue<String> _staleGenerationIds = Queue<String>();
  String? _activeGenerationId;
  int? _lastActiveSequence;
  int _nextRequest = 0;
  bool _disposed = false;
  final ValueNotifier<DesktopPresentation> _presentation =
      ValueNotifier<DesktopPresentation>(DesktopPresentation.orb);

  @override
  Stream<DesktopGenerationEvent> get generationEvents => _events.stream;

  @override
  Future<DesktopRuntimeCapabilities> handshake() async {
    final HostHandshakeResult result = await _invokeResult(_hostApi.handshake);
    if (result.schemaVersion != DesktopHostService.schemaVersion) {
      throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
    }
    return DesktopRuntimeCapabilities(
      schemaVersion: result.schemaVersion,
      runtimeName: result.runtimeName,
      supportsStreaming: result.supportsStreaming,
      supportsCancellation: result.supportsCancellation,
    );
  }

  @override
  Future<DesktopModelLoadResult> loadModel(DesktopModelRequest model) async {
    final HostModelLoadResult result = await _invokeResult(
      (HostRequest request) => _hostApi.loadModel(
        request,
        HostModelRequest(
          modelId: model.modelId,
          modelPath: model.modelPath,
          contextSize: model.contextSize,
        ),
      ),
    );
    return DesktopModelLoadResult(
      modelId: result.modelId,
      loaded: result.loaded,
    );
  }

  @override
  Future<DesktopGenerationAcknowledgement> startGeneration(
    DesktopGenerationRequest generation,
  ) async {
    final HostGenerationAcknowledgement result = await _invokeResult(
      (HostRequest request) => _hostApi.startGeneration(
        request,
        HostGenerationRequest(
          generationId: generation.generationId,
          sessionId: generation.sessionId,
          systemInstruction: generation.systemInstruction,
          prompt: generation.prompt,
          context: generation.context,
          history: <HostConversationTurn>[
            for (final DesktopConversationTurn turn in generation.history)
              HostConversationTurn(
                role: switch (turn.role) {
                  TurnRole.user => HostTurnRole.user,
                  TurnRole.assistant => HostTurnRole.assistant,
                },
                text: turn.text,
              ),
          ],
          temperature: generation.temperature,
          topP: generation.topP,
          maxTokens: generation.maxTokens,
          seed: generation.seed,
        ),
      ),
    );
    return DesktopGenerationAcknowledgement(
      generationId: result.generationId,
      accepted: result.accepted,
    );
  }

  @override
  Future<DesktopCancellationAcknowledgement> cancelGeneration(
    String generationId,
  ) async {
    final HostCancellationAcknowledgement result = await _invokeResult(
      (HostRequest request) => _hostApi.cancelGeneration(request, generationId),
    );
    return DesktopCancellationAcknowledgement(
      generationId: result.generationId,
      acknowledged: result.acknowledged,
    );
  }

  @override
  Future<DesktopOperationCompletion> resetSession(String sessionId) async {
    final HostOperationCompletion result = await _invokeResult(
      (HostRequest request) => _hostApi.resetSession(request, sessionId),
    );
    return DesktopOperationCompletion(completed: result.completed);
  }

  @override
  Future<DesktopOperationCompletion> unloadModel() async {
    final HostOperationCompletion result = await _invokeResult(
      _hostApi.unloadModel,
    );
    return DesktopOperationCompletion(completed: result.completed);
  }

  @override
  Future<void> showPanel() => _invoke(_hostApi.showPanel);

  @override
  Future<void> hidePanel() => _invoke(_hostApi.hidePanel);

  @override
  Future<void> togglePanel() => _invoke(_hostApi.togglePanel);

  @override
  ValueListenable<DesktopPresentation> get presentation => _presentation;

  @override
  Future<void> setPresentation(DesktopPresentation mode) {
    return _invoke(
      (HostRequest request) =>
          _hostApi.setPresentationMode(request, _hostMode(mode)),
    );
  }

  final StreamController<DesktopPresentation> _presentationRequests =
      StreamController<DesktopPresentation>.broadcast();

  @override
  Stream<DesktopPresentation> get presentationRequests =>
      _presentationRequests.stream;

  final StreamController<ConversationId> _menuConversationRequests =
      StreamController<ConversationId>.broadcast();

  /// Selections sent in before anything was listening.
  ///
  /// `NSApp.servicesProvider` is set in `applicationDidFinishLaunching`, so
  /// the system can deliver a message on the next runloop turn — while the
  /// Dart listener is only attached after `runApp`, which bootstrap reaches
  /// after recovering interrupted runs. Invoking the service on an app that
  /// was not running therefore launched it onto an empty composer. A
  /// broadcast stream drops what arrives with nobody listening, so what
  /// arrives early waits here.
  final List<String> _serviceTextBeforeAnyone = <String>[];

  late final StreamController<String> _serviceText =
      StreamController<String>.broadcast(
        onListen: () {
          // Flushed after this turn, so the subscription that triggered it
          // is established before anything is delivered to it.
          final List<String> waiting = List<String>.of(
            _serviceTextBeforeAnyone,
          );
          _serviceTextBeforeAnyone.clear();
          for (final String text in waiting) {
            scheduleMicrotask(() {
              if (!_disposed && _serviceText.hasListener) {
                _serviceText.add(text);
              }
            });
          }
        },
      );

  final StreamController<void> _menuVoiceRequests =
      StreamController<void>.broadcast();

  @override
  Stream<ConversationId> get menuConversationRequests =>
      _menuConversationRequests.stream;

  @override
  Stream<void> get menuVoiceRequests => _menuVoiceRequests.stream;

  @override
  Stream<String> get serviceText => _serviceText.stream;

  @override
  void onMenuBarConversationChosen(String conversationId) {
    if (_disposed) {
      return;
    }
    _menuConversationRequests.add(ConversationId(conversationId));
  }

  @override
  void onMenuBarVoiceRequested() {
    if (_disposed) {
      return;
    }
    _menuVoiceRequests.add(null);
  }

  @override
  void onServiceTextReceived(String text) {
    if (_disposed) {
      return;
    }
    if (!_serviceText.hasListener) {
      // Held rather than dropped: this is the cold-start case, where the
      // system delivered the selection before the app finished starting.
      _serviceTextBeforeAnyone.add(text);
      return;
    }
    _serviceText.add(text);
  }

  @override
  Future<void> setMenuBarState({
    required List<({ConversationId id, String title})> conversations,
    required String modelName,
    required DesktopAgentActivity activity,
    required bool canStartVoice,
    required DesktopMenuBarLabels labels,
  }) {
    return _invoke(
      (HostRequest request) => _hostApi.setMenuBarState(
        request,
        HostMenuBarState(
          conversations: <HostMenuConversation>[
            for (final ({ConversationId id, String title}) conversation
                in conversations)
              HostMenuConversation(
                conversationId: conversation.id.value,
                title: conversation.title,
              ),
          ],
          modelName: modelName,
          canStartVoice: canStartVoice,
          labels: HostMenuBarLabels(
            show: labels.show,
            hide: labels.hide,
            talk: labels.talk,
            recent: labels.recent,
            quit: labels.quit,
            activity: labels.activity,
          ),
        ),
      ),
    );
  }

  @override
  void onPresentationChangeRequested(HostPresentationMode target) {
    if (_disposed) {
      return;
    }
    _presentationRequests.add(
      target == HostPresentationMode.orb
          ? DesktopPresentation.orb
          : DesktopPresentation.expanded,
    );
  }

  @override
  void onPresentationModeChanged(HostPresentationMode mode) {
    if (_disposed) {
      return;
    }
    _presentation.value = mode == HostPresentationMode.orb
        ? DesktopPresentation.orb
        : DesktopPresentation.expanded;
  }

  @override
  Future<void> moveWindowBy(Offset delta) {
    return _invoke(
      (HostRequest request) =>
          _hostApi.moveWindowBy(request, delta.dx, delta.dy),
    );
  }

  final StreamController<void> _settingsRequests =
      StreamController<void>.broadcast();

  @override
  Stream<void> get settingsRequests => _settingsRequests.stream;

  @override
  void onSettingsRequested() {
    if (_disposed) {
      return;
    }
    _settingsRequests.add(null);
  }

  final StreamController<DesktopTransitionGeometry> _geometryChanges =
      StreamController<DesktopTransitionGeometry>.broadcast();

  @override
  Stream<DesktopTransitionGeometry> get geometryChanges =>
      _geometryChanges.stream;

  @override
  void onPresentationGeometryChanged(HostTransitionGeometry geometry) {
    if (_disposed) {
      return;
    }
    _geometryChanges.add(_geometry(geometry));
  }

  @override
  Future<String> chooseModelFile() => _invokeResult(_hostApi.chooseModelFile);

  @override
  Future<String> chooseTextFile() => _invokeResult(_hostApi.chooseTextFile);

  @override
  Future<String> saveTextFile({
    required String suggestedName,
    required String contents,
  }) {
    return _invokeResult(
      (HostRequest request) =>
          _hostApi.saveTextFile(request, suggestedName, contents),
    );
  }

  @override
  Future<DesktopLoginItem> loginItem() async {
    final HostLoginItemStatus status = await _invokeResult(
      _hostApi.loginItemStatus,
    );
    return _loginItemOf(status);
  }

  @override
  Future<DesktopLoginItem> setLaunchAtLogin({required bool enabled}) async {
    final HostLoginItemStatus status = await _invokeResult(
      (HostRequest request) => _hostApi.setLaunchAtLogin(request, enabled),
    );
    return _loginItemOf(status);
  }

  @override
  Future<void> setWindowBehaviour({
    required bool keepOrbOnTop,
    required bool followAcrossSpaces,
  }) {
    return _invoke(
      (HostRequest request) => _hostApi.setWindowBehaviour(
        request,
        keepOrbOnTop,
        followAcrossSpaces,
      ),
    );
  }

  @override
  Future<DesktopTransitionGeometry> presentationGeometry() {
    return _invokeResult((HostRequest request) async {
      return _geometry(await _hostApi.presentationGeometry(request));
    });
  }

  /// Restates a host geometry in the app's own vocabulary.
  static DesktopTransitionGeometry _geometry(HostTransitionGeometry geometry) {
    return DesktopTransitionGeometry(
      size: Size(geometry.width, geometry.height),
      conversation: Rect.fromLTWH(
        geometry.conversationLeft,
        geometry.conversationTop,
        geometry.conversationWidth,
        geometry.conversationHeight,
      ),
      fullScreen: geometry.fullScreen,
      orb: Rect.fromLTWH(
        geometry.orbLeft,
        geometry.orbTop,
        geometry.orbExtent,
        geometry.orbExtent,
      ),
    );
  }

  @override
  Future<DesktopTransitionGeometry> beginPresentationTransition(
    DesktopPresentation target,
  ) {
    return _invokeResult((HostRequest request) async {
      return _geometry(
        await _hostApi.beginPresentationTransition(request, _hostMode(target)),
      );
    });
  }

  @override
  Future<void> endPresentationTransition(DesktopPresentation mode) {
    return _invoke(
      (HostRequest request) =>
          _hostApi.endPresentationTransition(request, _hostMode(mode)),
    );
  }

  static HostPresentationMode _hostMode(DesktopPresentation mode) {
    return mode == DesktopPresentation.orb
        ? HostPresentationMode.orb
        : HostPresentationMode.expanded;
  }

  @override
  void onGenerationEvent(HostGenerationEvent event) {
    try {
      _events.add(acceptGenerationEvent(event));
    } on DesktopHostFailure catch (failure) {
      throw PlatformException(
        code: failure.code.pigeonCode,
        message: failure.message,
      );
    }
  }

  /// Validates and converts one generated native event.
  DesktopGenerationEvent acceptGenerationEvent(HostGenerationEvent event) {
    _ensureAvailable();
    if (event.schemaVersion != DesktopHostService.schemaVersion) {
      throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
    }
    if (event.generationId.isEmpty || event.sequence < 0) {
      throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
    }
    if (event.type == HostGenerationEventType.started) {
      if (_activeGenerationId != null ||
          _staleGenerationIds.contains(event.generationId)) {
        throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
      }
    } else if (_activeGenerationId != event.generationId) {
      throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
    }
    final int? previous = _lastActiveSequence;
    if (previous != null && event.sequence <= previous) {
      throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
    }
    if (event.type == HostGenerationEventType.delta && event.delta == null) {
      throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
    }
    if (event.type == HostGenerationEventType.failed &&
        event.failureCode == null) {
      throw const DesktopHostFailure(DesktopHostFailureCode.protocolMismatch);
    }

    _lastActiveSequence = event.sequence;
    if (event.type == HostGenerationEventType.started) {
      _activeGenerationId = event.generationId;
    } else if (_isTerminal(event.type)) {
      _recordStaleGeneration(event.generationId);
      _activeGenerationId = null;
      _lastActiveSequence = null;
    }
    final DesktopHostFailureCode? failureCode = event.failureCode?.appCode;
    return DesktopGenerationEvent(
      generationId: event.generationId,
      sequence: event.sequence,
      type: event.type,
      delta: event.delta,
      failureCode: failureCode,
      message: failureCode?.userSafeMessage,
    );
  }

  void _recordStaleGeneration(String generationId) {
    _staleGenerationIds.addLast(generationId);
    if (_staleGenerationIds.length > _staleGenerationCapacity) {
      _staleGenerationIds.removeFirst();
    }
  }

  bool _isTerminal(HostGenerationEventType type) {
    return switch (type) {
      HostGenerationEventType.completed ||
      HostGenerationEventType.cancelled ||
      HostGenerationEventType.failed => true,
      HostGenerationEventType.started || HostGenerationEventType.delta => false,
    };
  }

  Future<void> _invoke(
    Future<void> Function(HostRequest request) operation,
  ) async {
    _ensureAvailable();
    try {
      await operation(_nextRequestEnvelope());
    } on PlatformException catch (error) {
      final DesktopHostFailureCode code = DesktopHostFailureCode.fromPigeonCode(
        error.code,
      );
      throw DesktopHostFailure(code);
    }
  }

  Future<T> _invokeResult<T>(
    Future<T> Function(HostRequest request) operation,
  ) async {
    _ensureAvailable();
    try {
      return await operation(_nextRequestEnvelope());
    } on PlatformException catch (error) {
      final DesktopHostFailureCode code = DesktopHostFailureCode.fromPigeonCode(
        error.code,
      );
      throw DesktopHostFailure(code);
    }
  }

  HostRequest _nextRequestEnvelope() {
    final DateTime timestamp = _now().toUtc();
    _nextRequest += 1;
    return HostRequest(
      schemaVersion: DesktopHostService.schemaVersion,
      requestId: '${timestamp.microsecondsSinceEpoch}-$_nextRequest',
      timestampMicros: timestamp.microsecondsSinceEpoch,
    );
  }

  void _ensureAvailable() {
    if (_disposed) {
      throw StateError('The desktop host service is disposed.');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_eventApiRegistered) {
      DesktopHostEventApi.setUp(null);
    }
    await _events.close();
    await _presentationRequests.close();
    await _settingsRequests.close();
    await _menuConversationRequests.close();
    await _menuVoiceRequests.close();
    await _geometryChanges.close();
  }
}

const int _staleGenerationCapacity = 32;

extension on HostFailureCode {
  DesktopHostFailureCode get appCode {
    return switch (this) {
      HostFailureCode.modelNotInstalled =>
        DesktopHostFailureCode.modelNotInstalled,
      HostFailureCode.modelLoadFailed => DesktopHostFailureCode.modelLoadFailed,
      HostFailureCode.runtimeUnavailable =>
        DesktopHostFailureCode.runtimeUnavailable,
      HostFailureCode.generationBusy => DesktopHostFailureCode.generationBusy,
      HostFailureCode.generationFailed =>
        DesktopHostFailureCode.generationFailed,
      HostFailureCode.cancelled => DesktopHostFailureCode.cancelled,
      HostFailureCode.protocolMismatch =>
        DesktopHostFailureCode.protocolMismatch,
    };
  }
}

/// The host's answer as the app's own enum.
DesktopLoginItem _loginItemOf(HostLoginItemStatus status) => switch (status) {
  HostLoginItemStatus.on => DesktopLoginItem.on,
  HostLoginItemStatus.off => DesktopLoginItem.off,
  HostLoginItemStatus.needsApproval => DesktopLoginItem.needsApproval,
  HostLoginItemStatus.refused => DesktopLoginItem.refused,
  HostLoginItemStatus.unavailable => DesktopLoginItem.unavailable,
};
