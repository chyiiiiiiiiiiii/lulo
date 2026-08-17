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
    this.imagePath,
    this.instruction,
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

  /// A picture this question is about — the user's screen, when they asked
  /// for a look — or null for a question made of words alone.
  ///
  /// A path rather than bytes because the runtime reads the file itself,
  /// and megabytes of pixels have no business riding a message channel.
  final String? imagePath;

  /// The whole system instruction to send, instead of composing one from
  /// the profile — which makes this an **aside** rather than a turn.
  ///
  /// An aside is work the app does with the model that is not part of the
  /// conversation: the memory extraction pass, today, and whatever else
  /// wants the model to read something rather than to talk to someone.
  /// [prompt] travels as written, with no clock, no memories and no
  /// document around it.
  ///
  /// It also turns the toolbox off, and that is a measurement rather than
  /// tidiness — `RememberProbeTests` scored the extraction pass 15/15 with
  /// no tools registered, and offering tools it must not call would measure
  /// two things at once. The persona is off for a stronger reason still:
  /// `answer-length-should-follow-the-question.md` records it overriding an
  /// output format three separate times, and an aside is nothing *but* an
  /// output format.
  ///
  /// The runtime has one generation slot, so an aside in flight is a
  /// question refused as busy. Whoever starts one owns giving it up — see
  /// `AgentMemoryExtractor`.
  final String? instruction;

  /// Whether this is an aside rather than a turn in the conversation.
  bool get isAside => instruction != null;
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
