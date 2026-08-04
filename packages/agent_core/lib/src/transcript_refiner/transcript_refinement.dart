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
    double? heardConfidence,
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
      heardConfidence: heardConfidence,
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
    this.heardConfidence,
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

  /// How sure the recogniser was of the weakest span of [rawTranscript],
  /// or null where it scored nothing.
  ///
  /// Provenance of the hearing rather than of the refinement, which is why
  /// it sits here: the turn keeps this object precisely so the sentence can
  /// be shown with everything known about where it came from. Deliberately
  /// not persisted — a caveat is worth reading in the moment and worth
  /// nothing a day later, and storing it would cost a schema migration for
  /// a mark nobody would go back and look at. Restored turns carry null.
  final double? heardConfidence;

  /// This result with [heardConfidence] attached.
  ///
  /// A separate step because the two facts are produced by different things
  /// at different times: the recogniser scores the sentence, and the refiner
  /// — which never sees the audio — decides what to submit. Making every
  /// refiner thread a score it cannot know would be asking the wrong
  /// component for it.
  TranscriptRefinement withHeardConfidence(double? heardConfidence) =>
      TranscriptRefinement._(
        rawTranscript: rawTranscript,
        proposedTranscript: proposedTranscript,
        selectedTranscript: selectedTranscript,
        status: status,
        edits: edits,
        rejectionReasons: rejectionReasons,
        refinerId: refinerId,
        refinerVersion: refinerVersion,
        elapsed: elapsed,
        heardConfidence: heardConfidence,
      );
}

/// Refines one finalized transcript without changing partial transcription.
abstract interface class TranscriptRefiner {
  /// Returns selected text and reversible provenance.
  Future<TranscriptRefinement> refine(TranscriptRefinementRequest request);
}
