import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  const TranscriptProposalGate gate = TranscriptProposalGate();

  test('accepts conservative punctuation and vocabulary casing', () {
    final TranscriptProposalDecision decision = gate.evaluate(
      raw: '我用 flutter 開發',
      proposal: '我用 Flutter 開發。',
      protectedVocabulary: const <String>['Flutter'],
    );

    expect(decision.accepted, isTrue);
    expect(decision.rejectionReasons, isEmpty);
  });

  final List<
    ({
      String name,
      String raw,
      String proposal,
      TranscriptRejectionReason reason,
    })
  >
  protectedCases =
      <
        ({
          String name,
          String raw,
          String proposal,
          TranscriptRejectionReason reason,
        })
      >[
        (
          name: 'number',
          raw: '版本 3.5 預算１２％',
          proposal: '版本 3.6 預算１２％',
          reason: TranscriptRejectionReason.protectedNumberChanged,
        ),
        (
          name: 'negation',
          raw: '我不要刪掉',
          proposal: '我要刪掉',
          reason: TranscriptRejectionReason.negationChanged,
        ),
        (
          name: 'URL',
          raw: '開 https://lulo.local/a',
          proposal: '開 https://lulo.local/b',
          reason: TranscriptRejectionReason.urlChanged,
        ),
        (
          name: 'email',
          raw: '寄到 dev@lulo.local',
          proposal: '寄到 hi@lulo.local',
          reason: TranscriptRejectionReason.emailChanged,
        ),
        (
          name: 'vocabulary',
          raw: 'Flutter 配 MLX',
          proposal: 'Flutter 配 ML',
          reason: TranscriptRejectionReason.vocabularyChanged,
        ),
      ];

  for (final example in protectedCases) {
    test(
      'rejects changed protected ${example.name} without leaking values',
      () {
        final TranscriptProposalDecision decision = gate.evaluate(
          raw: example.raw,
          proposal: example.proposal,
          protectedVocabulary: const <String>['Flutter', 'MLX', 'ML'],
        );

        expect(decision.accepted, isFalse);
        expect(decision.rejectionReasons, contains(example.reason));
        expect(decision.toString(), isNot(contains('3.5')));
        expect(decision.toString(), isNot(contains('lulo.local')));
      },
    );
  }

  test('rejects protected token reordering', () {
    final TranscriptProposalDecision decision = gate.evaluate(
      raw: '不是 3 再來 4',
      proposal: '不是 4 再來 3',
      protectedVocabulary: const <String>[],
    );

    expect(
      decision.rejectionReasons,
      contains(TranscriptRejectionReason.protectedNumberChanged),
    );
  });

  test('rejects empty and excessive proposals', () {
    expect(
      gate
          .evaluate(
            raw: '原始內容',
            proposal: '',
            protectedVocabulary: const <String>[],
          )
          .rejectionReasons,
      contains(TranscriptRejectionReason.emptyProposal),
    );
    expect(
      gate
          .evaluate(
            raw: '這是一段原始內容',
            proposal: '完全不同而且多出非常多沒有說過的文字',
            protectedVocabulary: const <String>[],
          )
          .rejectionReasons,
      contains(TranscriptRejectionReason.excessiveChange),
    );
  });
}
