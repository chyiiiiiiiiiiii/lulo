import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/transcript_refiner/transcript_candidate_export.dart';
import 'package:local_agent_macos/features/transcript_refiner/transcript_shadow_evidence.dart';

void main() {
  test('builds a stable voice-eval candidate without hiding raw text', () {
    final Map<String, Object?> candidate = buildTranscriptCandidateExport(
      runId: 'deterministic-refiner-v1',
      adapterName: 'lulo-deterministic-refiner',
      adapterVersion: '1',
      corpusId: 'zh-TW-v1',
      refinements: <String, TranscriptRefinement>{
        'z-last': _refinement('原始二', '修訂二'),
        'a-first': _refinement('原始一', '修訂一'),
      },
    );

    expect(candidate['schemaVersion'], 1);
    expect(candidate['kind'], 'transcript');
    expect(candidate['runId'], 'deterministic-refiner-v1');
    expect(candidate['corpusId'], 'zh-TW-v1');
    expect(candidate['adapter'], <String, Object?>{
      'name': 'lulo-deterministic-refiner',
      'version': '1',
    });
    expect(candidate['cases'], <Map<String, Object?>>[
      <String, Object?>{
        'caseId': 'a-first',
        'rawTranscript': '原始一',
        'refinedTranscript': '修訂一',
        'partialEvents': <Object?>[],
        'finalAtMs': 0,
      },
      <String, Object?>{
        'caseId': 'z-last',
        'rawTranscript': '原始二',
        'refinedTranscript': '修訂二',
        'partialEvents': <Object?>[],
        'finalAtMs': 0,
      },
    ]);
  });

  test('omits a refined transcript when raw text was selected', () {
    final Map<String, Object?> candidate = buildTranscriptCandidateExport(
      runId: 'safe-fallback',
      adapterName: 'lulo-refiner',
      adapterVersion: '1',
      corpusId: 'zh-TW-v1',
      refinements: <String, TranscriptRefinement>{
        'fallback': _refinement(
          '保留原文',
          null,
          status: TranscriptRefinementStatus.rejected,
        ),
      },
    );

    final Map<String, Object?> exportedCase =
        (candidate['cases'] as List<Object?>).single as Map<String, Object?>;
    expect(exportedCase['rawTranscript'], '保留原文');
    expect(exportedCase.containsKey('refinedTranscript'), isFalse);
  });

  test('exports accepted and rejected explicit shadow evidence', () {
    final TranscriptShadowEvidence evidence = TranscriptShadowEvidence(
      capacity: 3,
    );
    evidence.record(_shadow('z-rejected', accepted: false));
    evidence.record(_shadow('a-accepted', accepted: true));

    final Map<String, Object?> candidate = buildTranscriptShadowCandidateExport(
      runId: 'qwen-shadow-v1',
      adapterName: 'qwen3-0.6b',
      adapterVersion: 'mlx-1',
      corpusId: 'zh-TW-v1',
      evidence: evidence.snapshot(),
    );

    expect(candidate['cases'], <Map<String, Object?>>[
      <String, Object?>{
        'caseId': 'a-accepted',
        'rawTranscript': '我用 flutter',
        'refinedTranscript': '我用 Flutter',
        'partialEvents': <Object?>[],
        'finalAtMs': 0,
      },
      <String, Object?>{
        'caseId': 'z-rejected',
        'rawTranscript': '我用 flutter',
        'partialEvents': <Object?>[],
        'finalAtMs': 0,
      },
    ]);
  });
}

TranscriptRefinement _refinement(
  String raw,
  String? proposed, {
  TranscriptRefinementStatus status = TranscriptRefinementStatus.applied,
}) => TranscriptRefinement(
  rawTranscript: raw,
  proposedTranscript: proposed,
  selectedTranscript: proposed ?? raw,
  status: status,
  edits: const <TranscriptEdit>[],
  rejectionReasons: const <TranscriptRejectionReason>[],
  refinerId: 'deterministic',
  refinerVersion: '1',
  elapsed: const Duration(milliseconds: 2),
);

TranscriptShadowResult _shadow(String caseId, {required bool accepted}) {
  final TranscriptProposalRequest request = TranscriptProposalRequest(
    requestId: 'request-$caseId',
    rawTranscript: '我用 flutter',
    locale: 'zh-TW',
    protectedVocabulary: const <String>['Flutter'],
    deadline: const Duration(milliseconds: 250),
    caseId: caseId,
  );
  final TranscriptProposalDecision decision = TranscriptProposalDecision(
    accepted: accepted,
    rejectionReasons: accepted
        ? const <TranscriptRejectionReason>[]
        : const <TranscriptRejectionReason>[
            TranscriptRejectionReason.excessiveChange,
          ],
  );
  return TranscriptShadowResult(
    request: request,
    proposal: TranscriptProposal(
      requestId: request.requestId,
      refinedTranscript: '我用 Flutter',
      providerId: 'qwen3-0.6b',
      providerVersion: 'mlx-1',
      elapsed: const Duration(milliseconds: 8),
    ),
    gateDecision: decision,
    status: accepted
        ? TranscriptShadowStatus.accepted
        : TranscriptShadowStatus.rejected,
    elapsed: const Duration(milliseconds: 9),
  );
}
