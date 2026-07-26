import 'conversation_id.dart';

/// Identifies one generation independently of any inference implementation.
final class GenerationId {
  /// Creates an identifier with the given stable [value].
  const GenerationId(this.value);

  /// The stable identifier value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GenerationId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// A request to generate an assistant response for one conversation.
final class GenerationRequest {
  /// Creates a request for [conversationId] using the supplied [prompt].
  const GenerationRequest({required this.conversationId, required this.prompt});

  /// The conversation that owns the request.
  final ConversationId conversationId;

  /// The input supplied to the inference implementation.
  final String prompt;
}

/// A generation tracked independently from its inference implementation.
final class Generation {
  /// Creates a generation with a stable [id] and immutable [request].
  const Generation({required this.id, required this.request});

  /// The stable generation identifier.
  final GenerationId id;

  /// The request that started this generation.
  final GenerationRequest request;
}
