import 'package:agent_core/agent_core.dart';

/// Streams inference events independently of a local model implementation.
abstract interface class InferenceService {
  /// Starts inference for [request].
  Stream<GenerationEvent> generate(GenerationRequest request);

  /// Requests cancellation of the identified generation.
  Future<void> cancel(GenerationId generationId);

  /// Releases whatever runtime state is still held for [conversationId].
  ///
  /// The local runtime keeps one live conversation per session id, each with
  /// its own KV cache, and nothing evicts them. Callers that know a
  /// conversation is over — it was deleted — say so here, or its cost stays
  /// resident for the life of the process.
  Future<void> releaseSession(ConversationId conversationId);
}
