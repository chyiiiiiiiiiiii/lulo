import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';

final class ControlledInferenceService implements InferenceService {
  final StreamController<GenerationEvent> _events =
      StreamController<GenerationEvent>.broadcast();
  final List<GenerationRequest> requests = <GenerationRequest>[];
  final List<GenerationId> cancellations = <GenerationId>[];
  final Completer<GenerationRequest> _requestReceived =
      Completer<GenerationRequest>();

  Future<GenerationRequest> get requestReceived => _requestReceived.future;

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    requests.add(request);
    if (!_requestReceived.isCompleted) {
      _requestReceived.complete(request);
    }
    return _events.stream;
  }

  @override
  Future<void> cancel(GenerationId generationId) async {
    cancellations.add(generationId);
  }

  void emit(GenerationEvent event) {
    _events.add(event);
  }

  void emitError(Object error, StackTrace stackTrace) {
    _events.addError(error, stackTrace);
  }

  Future<void> dispose() => _events.close();
}
