import 'package:agent_core/agent_core.dart';

/// Streams inference events independently of a local model implementation.
abstract interface class InferenceService {
  /// Starts inference for [request].
  Stream<GenerationEvent> generate(GenerationRequest request);

  /// Requests cancellation of the identified generation.
  Future<void> cancel(GenerationId generationId);
}
