/// Describes a generation failure that can be presented by a conversation.
final class ConversationFailure {
  /// Creates a failure with its user-safe [message].
  const ConversationFailure(this.message);

  /// The user-safe explanation of the failure.
  final String message;
}
