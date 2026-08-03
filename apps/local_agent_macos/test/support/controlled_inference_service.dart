import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';

final class ControlledInferenceService implements InferenceService {
  /// What a run opened during this test records as its model.
  @override
  String modelId = 'test-model';

  final StreamController<GenerationEvent> _events =
      StreamController<GenerationEvent>.broadcast();
  final List<GenerationRequest> requests = <GenerationRequest>[];
  final List<GenerationId> cancellations = <GenerationId>[];
  final List<ConversationId> releasedSessions = <ConversationId>[];
  final Completer<GenerationRequest> _requestReceived =
      Completer<GenerationRequest>();

  /// Set to make cancelling a listener fail, the way the native boundary can
  /// when the host cannot answer for the generation being cancelled.
  Object? listenerCancellationFailure;

  Future<GenerationRequest> get requestReceived => _requestReceived.future;

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    requests.add(request);
    if (!_requestReceived.isCompleted) {
      _requestReceived.complete(request);
    }
    final Object? failure = listenerCancellationFailure;
    if (failure == null) {
      return _events.stream;
    }
    return _failingOnCancel(failure);
  }

  Stream<GenerationEvent> _failingOnCancel(Object failure) {
    late final StreamController<GenerationEvent> controller;
    StreamSubscription<GenerationEvent>? source;
    controller = StreamController<GenerationEvent>(
      onListen: () {
        source = _events.stream.listen(
          controller.add,
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await source?.cancel();
        throw failure;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> cancel(GenerationId generationId) async {
    cancellations.add(generationId);
  }

  @override
  Future<void> releaseSession(ConversationId conversationId) async {
    releasedSessions.add(conversationId);
  }

  void emit(GenerationEvent event) {
    _events.add(event);
  }

  void emitError(Object error, StackTrace stackTrace) {
    _events.addError(error, stackTrace);
  }

  Future<void> dispose() => _events.close();
}
