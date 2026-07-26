/// The participant that authored a turn.
enum TurnRole {
  /// A turn supplied by the user.
  user,

  /// A turn supplied by the assistant.
  assistant,
}

/// The lifecycle state of a conversation turn.
enum TurnStatus {
  /// The assistant response is receiving incremental content.
  streaming,

  /// The turn reached a successful terminal state.
  completed,

  /// The turn was stopped before completion.
  cancelled,

  /// The turn stopped because generation failed.
  failed,
}

/// An immutable unit of conversation text and lifecycle state.
final class Turn {
  /// Creates a turn with its [role], [text], and [status].
  const Turn({required this.role, required this.text, required this.status});

  /// The participant that authored this turn.
  final TurnRole role;

  /// The accumulated text in this turn.
  final String text;

  /// The current lifecycle state of this turn.
  final TurnStatus status;

  /// Returns a new turn that adds [delta] to this turn's text.
  Turn append(String delta) => copyWith(text: '$text$delta');

  /// Returns a new turn with the supplied fields replacing existing values.
  Turn copyWith({TurnRole? role, String? text, TurnStatus? status}) => Turn(
    role: role ?? this.role,
    text: text ?? this.text,
    status: status ?? this.status,
  );
}
