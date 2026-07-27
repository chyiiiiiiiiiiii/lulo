import 'dart:async';

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
  final Map<String, int> _lastSequenceByGeneration = <String, int>{};
  final Set<String> _startedGenerationIds = <String>{};
  String? _activeGenerationId;
  int _nextRequest = 0;
  bool _disposed = false;

  @override
  Stream<DesktopGenerationEvent> get generationEvents => _events.stream;

  @override
  Future<void> showPanel() => _invoke(_hostApi.showPanel);

  @override
  Future<void> hidePanel() => _invoke(_hostApi.hidePanel);

  @override
  Future<void> togglePanel() => _invoke(_hostApi.togglePanel);

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
      throw const DesktopHostFailure(
        DesktopHostFailureCode.protocolMismatch,
        'The desktop host schema is incompatible.',
      );
    }
    if (event.generationId.isEmpty || event.sequence < 0) {
      throw const DesktopHostFailure(
        DesktopHostFailureCode.protocolMismatch,
        'The desktop host sent an invalid generation event.',
      );
    }
    final int? previous = _lastSequenceByGeneration[event.generationId];
    if (previous != null && event.sequence <= previous) {
      throw const DesktopHostFailure(
        DesktopHostFailureCode.protocolMismatch,
        'The desktop host sent a stale generation event.',
      );
    }
    if (event.type == HostGenerationEventType.started) {
      if (_activeGenerationId != null ||
          _startedGenerationIds.contains(event.generationId)) {
        throw const DesktopHostFailure(
          DesktopHostFailureCode.protocolMismatch,
          'The desktop host sent a mismatched generation event.',
        );
      }
    } else if (_activeGenerationId != event.generationId) {
      throw const DesktopHostFailure(
        DesktopHostFailureCode.protocolMismatch,
        'A generation event arrived before its start.',
      );
    }
    if (event.type == HostGenerationEventType.delta && event.delta == null) {
      throw const DesktopHostFailure(
        DesktopHostFailureCode.protocolMismatch,
        'A generation delta did not contain text.',
      );
    }
    if (event.type == HostGenerationEventType.failed &&
        event.failureCode == null) {
      throw const DesktopHostFailure(
        DesktopHostFailureCode.protocolMismatch,
        'A failed generation did not contain an error code.',
      );
    }

    _lastSequenceByGeneration[event.generationId] = event.sequence;
    if (event.type == HostGenerationEventType.started) {
      _startedGenerationIds.add(event.generationId);
      _activeGenerationId = event.generationId;
    } else if (_isTerminal(event.type)) {
      _activeGenerationId = null;
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
      throw DesktopHostFailure(code, code.userSafeMessage);
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
  }
}

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
