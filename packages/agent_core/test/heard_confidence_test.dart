import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('HeardConfidence.isDoubtful', () {
    test('every word the recogniser got right is trusted', () {
      // The corpus's correctly heard spans scored 0.88 to 1.00; see
      // docs/decisions/voice-turn-latency.md.
      for (final double score in <double>[0.88, 0.92, 0.97, 1.0]) {
        expect(
          HeardConfidence.isDoubtful(score),
          isFalse,
          reason: '$score is what being right looks like.',
        );
      }
    });

    test('every word the recogniser got wrong is doubted', () {
      // 忍 in a misheard clause, Flater for Flutter, 的 in the same clause,
      // and NLX for MLX — the four real errors in the measured corpus.
      for (final double score in <double>[0.69, 0.48, 0.31, 0.78]) {
        expect(
          HeardConfidence.isDoubtful(score),
          isTrue,
          reason: '$score is what being wrong looked like.',
        );
      }
    });

    test('a span that was right but unsure is doubted too', () {
      // codex, heard correctly but unsure of its capitalisation, scored
      // 0.79. Marking it costs a caveat on a correct word; not marking it
      // would mean missing NLX at 0.78, which is a wrong one. The marking
      // is advisory, so the cheap mistake is the one to make.
      expect(HeardConfidence.isDoubtful(0.79), isTrue);
    });

    test('an unscored transcript is not doubted', () {
      // Nothing was measured, so nothing is being claimed. A caveat on
      // every sentence is a caveat on none of them.
      expect(HeardConfidence.isDoubtful(null), isFalse);
    });

    test('the threshold sits in the gap the corpus left', () {
      expect(HeardConfidence.trusted, greaterThan(0.79));
      expect(HeardConfidence.trusted, lessThanOrEqualTo(0.88));
    });
  });
}
