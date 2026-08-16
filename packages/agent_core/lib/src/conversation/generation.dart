import '../agent_profile/agent_prompt_composer.dart' show AnswerChannel;
import 'conversation_id.dart';
import 'turn.dart';

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
  const GenerationRequest({
    required this.conversationId,
    required this.prompt,
    this.history = const <Turn>[],
    this.channel = AnswerChannel.spoken,
  });

  /// The conversation that owns the request.
  final ConversationId conversationId;

  /// The input supplied to the inference implementation.
  final String prompt;

  /// What was already said in this conversation, oldest first, excluding
  /// [prompt].
  ///
  /// A conversation read back from storage exists on screen before it
  /// exists in the runtime; carrying its turns here is what lets an
  /// implementation that has forgotten them start from where the user
  /// thinks it is.
  final List<Turn> history;

  /// The way this question came in, which decides the shape of the answer.
  ///
  /// Spoken by default because every measured preface was taken in that
  /// shape; the caller who knows the question was typed says so.
  final AnswerChannel channel;
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
