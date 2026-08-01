/// Result status of one finalized-transcript refinement attempt.
enum TranscriptRefinementStatus {
  /// The refiner selected the raw transcript without a change.
  unchanged,

  /// A validated proposal was selected.
  applied,

  /// A proposal existed but failed the safety policy.
  rejected,

  /// Refinement exceeded its caller-owned deadline.
  timedOut,

  /// Refinement failed and raw text was selected.
  failed,
}

/// Category of a reversible transcript edit.
enum TranscriptEditKind {
  /// Leading, trailing, or internal whitespace changed.
  whitespace,

  /// Punctuation changed.
  punctuation,

  /// Configured vocabulary casing changed.
  vocabulary,
}

/// Privacy-safe reason a proposal was rejected.
enum TranscriptRejectionReason {
  /// The proposed transcript was empty for non-empty raw input.
  emptyProposal,

  /// The proposal changed more than the configured edit ceiling.
  excessiveChange,

  /// Protected numeric evidence changed or moved.
  protectedNumberChanged,

  /// Taiwan Mandarin negation evidence changed or moved.
  negationChanged,

  /// A URL changed or moved.
  urlChanged,

  /// An email address changed or moved.
  emailChanged,

  /// Configured vocabulary changed or moved.
  vocabularyChanged,
}

/// One edit expressed in raw-transcript grapheme indexes.
final class TranscriptEdit {
  /// Creates a reversible edit.
  const TranscriptEdit({
    required this.rawStart,
    required this.rawEnd,
    required this.replacement,
    required this.kind,
  });

  /// Inclusive start in raw grapheme clusters.
  final int rawStart;

  /// Exclusive end in raw grapheme clusters.
  final int rawEnd;

  /// Replacement text.
  final String replacement;

  /// Why this edit was allowed.
  final TranscriptEditKind kind;
}

/// Inputs available to a transcript refiner for one final utterance.
final class TranscriptRefinementRequest {
  /// Creates an immutable request.
  TranscriptRefinementRequest({
    required this.rawTranscript,
    required this.locale,
    required List<String> protectedVocabulary,
    required this.deadline,
  }) : protectedVocabulary = List<String>.unmodifiable(protectedVocabulary);

  /// Exact final recognizer output.
  final String rawTranscript;

  /// BCP-47 speech locale.
  final String locale;

  /// Vocabulary tokens whose identity must remain stable.
  final List<String> protectedVocabulary;

  /// Maximum caller-approved refinement time.
  final Duration deadline;
}

/// Raw evidence, proposal, selected value, and its complete provenance.
final class TranscriptRefinement {
  /// Creates a validated immutable result.
  factory TranscriptRefinement({
    required String rawTranscript,
    required String? proposedTranscript,
    required String selectedTranscript,
    required TranscriptRefinementStatus status,
    required List<TranscriptEdit> edits,
    required List<TranscriptRejectionReason> rejectionReasons,
    required String refinerId,
    required String refinerVersion,
    required Duration elapsed,
  }) {
    final bool applied = status == TranscriptRefinementStatus.applied;
    if ((applied && proposedTranscript != selectedTranscript) ||
        (!applied && selectedTranscript != rawTranscript)) {
      throw ArgumentError('selected transcript is inconsistent with status');
    }
    return TranscriptRefinement._(
      rawTranscript: rawTranscript,
      proposedTranscript: proposedTranscript,
      selectedTranscript: selectedTranscript,
      status: status,
      edits: List<TranscriptEdit>.unmodifiable(edits),
      rejectionReasons: List<TranscriptRejectionReason>.unmodifiable(
        rejectionReasons,
      ),
      refinerId: refinerId,
      refinerVersion: refinerVersion,
      elapsed: elapsed,
    );
  }

  const TranscriptRefinement._({
    required this.rawTranscript,
    required this.proposedTranscript,
    required this.selectedTranscript,
    required this.status,
    required this.edits,
    required this.rejectionReasons,
    required this.refinerId,
    required this.refinerVersion,
    required this.elapsed,
  });

  /// Exact final recognizer output.
  final String rawTranscript;

  /// Candidate text, when one was produced.
  final String? proposedTranscript;

  /// Text submitted to the conversation.
  final String selectedTranscript;

  /// Policy outcome.
  final TranscriptRefinementStatus status;

  /// Reversible edits when a proposal was applied.
  final List<TranscriptEdit> edits;

  /// Privacy-safe rejection categories.
  final List<TranscriptRejectionReason> rejectionReasons;

  /// Stable implementation identity.
  final String refinerId;

  /// Implementation or model version.
  final String refinerVersion;

  /// Time spent producing this result.
  final Duration elapsed;
}

/// Refines one finalized transcript without changing partial transcription.
abstract interface class TranscriptRefiner {
  /// Returns selected text and reversible provenance.
  Future<TranscriptRefinement> refine(TranscriptRefinementRequest request);
}
