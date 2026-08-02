import 'package:agent_core/agent_core.dart';

import 'transcript_shadow_evidence.dart';

/// Builds one development-only transcript candidate for the voice eval tool.
///
/// This is deliberately a pure data conversion. The caller chooses whether
/// and where to encode the result, so production startup cannot silently
/// export private transcripts.
Map<String, Object?> buildTranscriptCandidateExport({
  required String runId,
  required String adapterName,
  required String adapterVersion,
  required String corpusId,
  required Map<String, TranscriptRefinement> refinements,
}) {
  final List<String> caseIds = refinements.keys.toList()..sort();
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'transcript',
    'runId': runId,
    'adapter': <String, Object?>{
      'name': adapterName,
      'version': adapterVersion,
    },
    'corpusId': corpusId,
    'cases': caseIds
        .map((String caseId) {
          final TranscriptRefinement refinement = refinements[caseId]!;
          return <String, Object?>{
            'caseId': caseId,
            'rawTranscript': refinement.rawTranscript,
            if (refinement.status == TranscriptRefinementStatus.applied &&
                refinement.proposedTranscript != null)
              'refinedTranscript': refinement.proposedTranscript,
            'partialEvents': <Object?>[],
            'finalAtMs': 0,
          };
        })
        .toList(growable: false),
  };
}

/// Converts explicitly retained shadow cases to the existing eval envelope.
Map<String, Object?> buildTranscriptShadowCandidateExport({
  required String runId,
  required String adapterName,
  required String adapterVersion,
  required String corpusId,
  required TranscriptShadowEvidenceSnapshot evidence,
}) {
  final Map<String, TranscriptRefinement> refinements =
      <String, TranscriptRefinement>{};
  for (final MapEntry<String, TranscriptShadowResult> entry
      in evidence.cases.entries) {
    final TranscriptShadowResult result = entry.value;
    final bool accepted = result.status == TranscriptShadowStatus.accepted;
    refinements[entry.key] = TranscriptRefinement(
      rawTranscript: result.request.rawTranscript,
      proposedTranscript: result.proposal?.refinedTranscript,
      selectedTranscript: accepted
          ? result.proposal!.refinedTranscript
          : result.request.rawTranscript,
      status: switch (result.status) {
        TranscriptShadowStatus.accepted => TranscriptRefinementStatus.applied,
        TranscriptShadowStatus.rejected => TranscriptRefinementStatus.rejected,
        TranscriptShadowStatus.timedOut => TranscriptRefinementStatus.timedOut,
        TranscriptShadowStatus.failed ||
        TranscriptShadowStatus.skippedBusy => TranscriptRefinementStatus.failed,
      },
      edits: const <TranscriptEdit>[],
      rejectionReasons:
          result.gateDecision?.rejectionReasons ??
          const <TranscriptRejectionReason>[],
      refinerId: result.proposal?.providerId ?? adapterName,
      refinerVersion: result.proposal?.providerVersion ?? adapterVersion,
      elapsed: result.elapsed,
    );
  }
  return buildTranscriptCandidateExport(
    runId: runId,
    adapterName: adapterName,
    adapterVersion: adapterVersion,
    corpusId: corpusId,
    refinements: refinements,
  );
}
