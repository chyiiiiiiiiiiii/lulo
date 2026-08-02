import 'transcript_proposal_gate.dart';

/// Terminal outcome of one shadow-only transcript proposal attempt.
enum TranscriptShadowStatus {
  /// The safety gate accepted the proposal as evaluation evidence.
  accepted,

  /// The provider returned text that the safety gate rejected.
  rejected,

  /// The provider or its protocol failed.
  failed,

  /// The provider exceeded the request deadline.
  timedOut,

  /// Another request already owned the single shadow slot.
  skippedBusy,
}

/// Minimal input allowed to leave the live transcript pipeline for shadowing.
final class TranscriptProposalRequest {
  /// Creates an immutable shadow request.
  factory TranscriptProposalRequest({
    required String requestId,
    required String rawTranscript,
    required String locale,
    required List<String> protectedVocabulary,
    required Duration deadline,
    String? caseId,
  }) {
    if (requestId.trim().isEmpty ||
        rawTranscript.trim().isEmpty ||
        locale.trim().isEmpty ||
        deadline <= Duration.zero ||
        (caseId != null && caseId.trim().isEmpty)) {
      throw ArgumentError('proposal request fields must be non-empty');
    }
    return TranscriptProposalRequest._(
      requestId: requestId,
      rawTranscript: rawTranscript,
      locale: locale,
      protectedVocabulary: List<String>.unmodifiable(protectedVocabulary),
      deadline: deadline,
      caseId: caseId,
    );
  }

  const TranscriptProposalRequest._({
    required this.requestId,
    required this.rawTranscript,
    required this.locale,
    required this.protectedVocabulary,
    required this.deadline,
    required this.caseId,
  });

  /// Opaque identity used to reject mismatched responses.
  final String requestId;

  /// Exact finalized recognizer output for this utterance only.
  final String rawTranscript;

  /// BCP-47 speech locale.
  final String locale;

  /// Vocabulary relevant to this utterance.
  final List<String> protectedVocabulary;

  /// Maximum provider time for this request.
  final Duration deadline;

  /// Explicit private-corpus identity, absent during ordinary use.
  final String? caseId;

  @override
  bool operator ==(Object other) =>
      other is TranscriptProposalRequest &&
      other.requestId == requestId &&
      other.rawTranscript == rawTranscript &&
      other.locale == locale &&
      _sameStrings(other.protectedVocabulary, protectedVocabulary) &&
      other.deadline == deadline &&
      other.caseId == caseId;

  @override
  int get hashCode => Object.hash(
    requestId,
    rawTranscript,
    locale,
    Object.hashAll(protectedVocabulary),
    deadline,
    caseId,
  );
}

/// Text returned by one local shadow proposal provider.
final class TranscriptProposal {
  /// Creates validated provider evidence.
  factory TranscriptProposal({
    required String requestId,
    required String refinedTranscript,
    required String providerId,
    required String providerVersion,
    required Duration elapsed,
  }) {
    if (requestId.trim().isEmpty ||
        refinedTranscript.trim().isEmpty ||
        providerId.trim().isEmpty ||
        providerVersion.trim().isEmpty ||
        elapsed.isNegative) {
      throw ArgumentError('proposal fields must be non-empty and valid');
    }
    return TranscriptProposal._(
      requestId: requestId,
      refinedTranscript: refinedTranscript,
      providerId: providerId,
      providerVersion: providerVersion,
      elapsed: elapsed,
    );
  }

  const TranscriptProposal._({
    required this.requestId,
    required this.refinedTranscript,
    required this.providerId,
    required this.providerVersion,
    required this.elapsed,
  });

  /// Request identity echoed by the provider.
  final String requestId;

  /// Proposed transcript, never automatically selected.
  final String refinedTranscript;

  /// Stable provider or model identity.
  final String providerId;

  /// Provider implementation or model version.
  final String providerVersion;

  /// Provider-reported end-to-end duration.
  final Duration elapsed;
}

/// Complete typed evidence from a shadow attempt.
final class TranscriptShadowResult {
  /// Creates a result whose fields agree with [status].
  factory TranscriptShadowResult({
    required TranscriptProposalRequest request,
    required TranscriptProposal? proposal,
    required TranscriptProposalDecision? gateDecision,
    required TranscriptShadowStatus status,
    required Duration elapsed,
  }) {
    final bool accepted = status == TranscriptShadowStatus.accepted;
    final bool rejected = status == TranscriptShadowStatus.rejected;
    final bool hasEvidence = proposal != null && gateDecision != null;
    if (elapsed.isNegative ||
        ((accepted || rejected) && !hasEvidence) ||
        (accepted && !gateDecision!.accepted) ||
        (rejected && gateDecision!.accepted) ||
        (!accepted &&
            !rejected &&
            (proposal != null || gateDecision != null))) {
      throw ArgumentError('shadow result fields are inconsistent with status');
    }
    return TranscriptShadowResult._(
      request: request,
      proposal: proposal,
      gateDecision: gateDecision,
      status: status,
      elapsed: elapsed,
    );
  }

  const TranscriptShadowResult._({
    required this.request,
    required this.proposal,
    required this.gateDecision,
    required this.status,
    required this.elapsed,
  });

  /// Original minimal request.
  final TranscriptProposalRequest request;

  /// Provider evidence for accepted or rejected outcomes.
  final TranscriptProposal? proposal;

  /// Safety decision for accepted or rejected outcomes.
  final TranscriptProposalDecision? gateDecision;

  /// Terminal outcome.
  final TranscriptShadowStatus status;

  /// Coordinator-observed duration.
  final Duration elapsed;
}

/// Produces one local transcript proposal without selecting it.
abstract interface class TranscriptProposalProvider {
  /// Returns provider evidence for [request].
  Future<TranscriptProposal> propose(TranscriptProposalRequest request);
}

bool _sameStrings(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
