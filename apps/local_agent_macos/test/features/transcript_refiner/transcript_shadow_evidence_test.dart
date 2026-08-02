import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/transcript_refiner/transcript_shadow_evidence.dart';

void main() {
  test('ordinary use keeps counters but no transcript evidence', () {
    final TranscriptShadowEvidence evidence = TranscriptShadowEvidence(
      capacity: 2,
    );

    evidence.record(_accepted(caseId: null));
    final TranscriptShadowEvidenceSnapshot snapshot = evidence.snapshot();

    expect(snapshot.counts[TranscriptShadowStatus.accepted], 1);
    expect(snapshot.cases, isEmpty);
  });

  test(
    'explicit cases are bounded oldest-first and snapshots are immutable',
    () {
      final TranscriptShadowEvidence evidence = TranscriptShadowEvidence(
        capacity: 2,
      );

      evidence.record(_accepted(caseId: 'case-a'));
      evidence.record(_accepted(caseId: 'case-b'));
      evidence.record(_accepted(caseId: 'case-c'));
      final TranscriptShadowEvidenceSnapshot snapshot = evidence.snapshot();

      expect(snapshot.cases.keys, <String>['case-b', 'case-c']);
      expect(() => snapshot.cases.clear(), throwsUnsupportedError);
      expect(() => snapshot.counts.clear(), throwsUnsupportedError);

      evidence.clear();
      expect(evidence.snapshot().cases, isEmpty);
      expect(evidence.snapshot().counts, isEmpty);
    },
  );
}

TranscriptShadowResult _accepted({required String? caseId}) {
  final TranscriptProposalRequest request = TranscriptProposalRequest(
    requestId: 'request-${caseId ?? 'ordinary'}',
    rawTranscript: '我用 flutter',
    locale: 'zh-TW',
    protectedVocabulary: const <String>['Flutter'],
    deadline: const Duration(milliseconds: 250),
    caseId: caseId,
  );
  return TranscriptShadowResult(
    request: request,
    proposal: TranscriptProposal(
      requestId: request.requestId,
      refinedTranscript: '我用 Flutter',
      providerId: 'qwen',
      providerVersion: '1',
      elapsed: const Duration(milliseconds: 8),
    ),
    gateDecision: TranscriptProposalDecision(
      accepted: true,
      rejectionReasons: const <TranscriptRejectionReason>[],
    ),
    status: TranscriptShadowStatus.accepted,
    elapsed: const Duration(milliseconds: 9),
  );
}
