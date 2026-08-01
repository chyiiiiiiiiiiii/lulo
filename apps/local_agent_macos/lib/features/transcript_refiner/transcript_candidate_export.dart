import 'package:agent_core/agent_core.dart';

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
