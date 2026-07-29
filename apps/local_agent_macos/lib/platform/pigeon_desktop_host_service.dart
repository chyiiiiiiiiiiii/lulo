import 'dart:async';
import 'dart:collection';

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
          prompt: generation.prompt,
          context: generation.context,
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
