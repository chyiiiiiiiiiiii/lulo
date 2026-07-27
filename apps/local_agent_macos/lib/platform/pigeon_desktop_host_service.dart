import 'dart:async';
import 'dart:collection';

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
