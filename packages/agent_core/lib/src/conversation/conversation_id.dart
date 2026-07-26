/// Identifies one conversation independently of any storage implementation.
final class ConversationId {
  /// Creates an identifier with the given stable [value].
  const ConversationId(this.value);

  /// The stable identifier value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConversationId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
