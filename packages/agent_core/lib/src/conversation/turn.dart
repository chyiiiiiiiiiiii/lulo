import '../transcript_refiner/transcript_refinement.dart';

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

  /// The process did not survive the generation.
  ///
  /// Distinct from [failed] and [cancelled] because neither is true: nothing
  /// failed and nobody stopped it — the app went away mid-answer, and what
  /// is stored is however much of it had been checkpointed. Recording it as
  /// either of the others would put a reason on the turn that never
  /// happened.
  interrupted,
}

/// An immutable unit of conversation text and lifecycle state.
final class Turn {
  /// Creates a turn with its [role], [text], and [status].
  const Turn({required this.role, required this.text, required this.status})
    : voiceInput = null;

  /// Creates a completed user turn from a validated voice refinement.
  factory Turn.voice({required TranscriptRefinement voiceInput}) => Turn._(
    role: TurnRole.user,
    text: voiceInput.selectedTranscript,
    status: TurnStatus.completed,
    voiceInput: voiceInput,
  );

  const Turn._({
    required this.role,
    required this.text,
    required this.status,
    required this.voiceInput,
  });

  /// The participant that authored this turn.
  final TurnRole role;

  /// The accumulated text in this turn.
  final String text;

  /// The current lifecycle state of this turn.
  final TurnStatus status;

  /// Raw and refined speech provenance, absent for typed and assistant turns.
  final TranscriptRefinement? voiceInput;

  /// Returns a new turn that adds [delta] to this turn's text.
  Turn append(String delta) => copyWith(text: '$text$delta');

  /// Returns a new turn with the supplied fields replacing existing values.
  Turn copyWith({TurnRole? role, String? text, TurnStatus? status}) {
    final TurnRole nextRole = role ?? this.role;
    final String nextText = text ?? this.text;
    final TurnStatus nextStatus = status ?? this.status;
    final TranscriptRefinement? provenance = voiceInput;
    if (provenance == null) {
      return Turn(role: nextRole, text: nextText, status: nextStatus);
    }
    if (nextRole != TurnRole.user ||
        nextStatus != TurnStatus.completed ||
        nextText != provenance.selectedTranscript) {
      throw ArgumentError('voice input is incompatible with copied turn');
    }
    return Turn._(
      role: nextRole,
      text: nextText,
      status: nextStatus,
      voiceInput: provenance,
    );
  }
}
