import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('proposal requests own vocabulary and compare by value', () {
    final List<String> vocabulary = <String>['Flutter'];
    final TranscriptProposalRequest first = TranscriptProposalRequest(
      requestId: 'request-1',
      rawTranscript: '我用 flutter',
      locale: 'zh-TW',
      protectedVocabulary: vocabulary,
      deadline: const Duration(milliseconds: 250),
      caseId: 'code-switch',
    );
    vocabulary.add('MLX');
    final TranscriptProposalRequest second = TranscriptProposalRequest(
      requestId: 'request-1',
      rawTranscript: '我用 flutter',
      locale: 'zh-TW',
      protectedVocabulary: const <String>['Flutter'],
      deadline: const Duration(milliseconds: 250),
      caseId: 'code-switch',
    );

    expect(first.protectedVocabulary, <String>['Flutter']);
    expect(() => first.protectedVocabulary.add('Dart'), throwsUnsupportedError);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('proposal identities and text must be non-empty', () {
    expect(
      () => TranscriptProposal(
        requestId: '',
        refinedTranscript: '內容',
        providerId: 'qwen',
        providerVersion: '1',
        elapsed: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => TranscriptProposal(
        requestId: 'request-1',
        refinedTranscript: '   ',
        providerId: 'qwen',
        providerVersion: '1',
        elapsed: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('accepted shadow evidence requires an accepted gated proposal', () {
    final TranscriptProposalRequest request = _request();
    final TranscriptProposal proposal = _proposal();
    final TranscriptProposalDecision accepted = TranscriptProposalDecision(
      accepted: true,
      rejectionReasons: const <TranscriptRejectionReason>[],
    );

    final TranscriptShadowResult result = TranscriptShadowResult(
      request: request,
      proposal: proposal,
      gateDecision: accepted,
      status: TranscriptShadowStatus.accepted,
      elapsed: const Duration(milliseconds: 12),
    );

    expect(result.proposal, proposal);
    expect(result.gateDecision?.accepted, isTrue);
  });

  test('failure shadow evidence cannot carry proposal text', () {
    expect(
      () => TranscriptShadowResult(
        request: _request(),
        proposal: _proposal(),
        gateDecision: null,
        status: TranscriptShadowStatus.failed,
        elapsed: const Duration(milliseconds: 2),
      ),
      throwsArgumentError,
    );

    final TranscriptShadowResult failed = TranscriptShadowResult(
      request: _request(),
      proposal: null,
      gateDecision: null,
      status: TranscriptShadowStatus.failed,
      elapsed: const Duration(milliseconds: 2),
    );
    expect(failed.proposal, isNull);
  });
}

TranscriptProposalRequest _request() => TranscriptProposalRequest(
  requestId: 'request-1',
  rawTranscript: '我用 flutter',
  locale: 'zh-TW',
  protectedVocabulary: const <String>['Flutter'],
  deadline: const Duration(milliseconds: 250),
  caseId: 'code-switch',
);

TranscriptProposal _proposal() => TranscriptProposal(
  requestId: 'request-1',
  refinedTranscript: '我用 Flutter',
  providerId: 'qwen3-0.6b',
  providerVersion: '1',
  elapsed: const Duration(milliseconds: 10),
);
