import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('refinement owns immutable request and result collections', () async {
    final List<String> vocabulary = <String>['Flutter'];
    final TranscriptRefinementRequest request = TranscriptRefinementRequest(
      rawTranscript: '用 flutter',
      locale: 'zh-TW',
      protectedVocabulary: vocabulary,
      deadline: const Duration(milliseconds: 250),
    );
    vocabulary.add('MLX');

    expect(request.protectedVocabulary, <String>['Flutter']);
    expect(
      () => request.protectedVocabulary.add('Dart'),
      throwsUnsupportedError,
    );

    final TranscriptRefinement result = TranscriptRefinement(
      rawTranscript: '用 flutter',
      proposedTranscript: '用 Flutter',
      selectedTranscript: '用 Flutter',
      status: TranscriptRefinementStatus.applied,
      edits: const <TranscriptEdit>[
        TranscriptEdit(
          rawStart: 2,
          rawEnd: 9,
          replacement: 'Flutter',
          kind: TranscriptEditKind.vocabulary,
        ),
      ],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: 'deterministic',
      refinerVersion: '1',
      elapsed: Duration.zero,
    );

    expect(() => result.edits.clear(), throwsUnsupportedError);
    expect(result.selectedTranscript, '用 Flutter');
  });

  test('non-applied statuses must select exact raw text', () {
    expect(
      () => TranscriptRefinement(
        rawTranscript: '原文',
        proposedTranscript: '改寫',
        selectedTranscript: '改寫',
        status: TranscriptRefinementStatus.rejected,
        edits: const <TranscriptEdit>[],
        rejectionReasons: const <TranscriptRejectionReason>[
          TranscriptRejectionReason.excessiveChange,
        ],
        refinerId: 'test',
        refinerVersion: '1',
        elapsed: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
