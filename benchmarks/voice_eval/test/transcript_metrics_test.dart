import 'package:lulo_voice_eval/voice_eval.dart';
import 'package:test/test.dart';

void main() {
  group('transcript normalization', () {
    test(
      'literal normalization collapses whitespace but keeps punctuation',
      () {
        expect(normalizeLiteral('  好，\n  可以  了。 '), '好， 可以 了。');
      },
    );

    test(
      'spoken normalization ignores punctuation whitespace and Latin case',
      () {
        expect(normalizeSpoken('Flutter， 好！'), 'flutter好');
        expect(normalizeSpoken('臺灣，不轉成台湾。'), '臺灣不轉成台湾');
      },
    );
  });

  group('scoreTranscript', () {
    test('reports one substitution', () {
      final TranscriptScore score = scoreTranscript(
        reference: '我要開會',
        candidate: '我要開水',
      );

      expect(score.distance, 1);
      expect(score.substitutions, 1);
      expect(score.deletions, 0);
      expect(score.insertions, 0);
      expect(score.cer, closeTo(0.25, 0.0001));
    });

    test('reports deletion and insertion independently', () {
      final TranscriptScore deletion = scoreTranscript(
        reference: '臺灣華語',
        candidate: '臺灣語',
      );
      final TranscriptScore insertion = scoreTranscript(
        reference: '臺灣語',
        candidate: '臺灣華語',
      );

      expect(deletion.deletions, 1);
      expect(insertion.insertions, 1);
    });

    test('counts an emoji grapheme as one character', () {
      final TranscriptScore score = scoreTranscript(
        reference: '好👍🏽',
        candidate: '好',
      );

      expect(score.referenceLength, 2);
      expect(score.deletions, 1);
      expect(score.cer, 0.5);
    });

    test('defines both empty reference cases', () {
      expect(scoreTranscript(reference: '', candidate: '').cer, 0);

      final TranscriptScore inserted = scoreTranscript(
        reference: '',
        candidate: '好呀',
      );
      expect(inserted.cer, 1);
      expect(inserted.insertions, 2);
    });
  });

  test('raw and refined transcripts remain independently scored', () {
    final TranscriptComparison comparison = compareTranscripts(
      reference: '我用 Flutter 開發',
      rawTranscript: '我用 flutter 開發',
      refinedTranscript: '我用 Flutter 開發',
    );

    expect(comparison.rawTranscript, '我用 flutter 開發');
    expect(comparison.refinedTranscript, '我用 Flutter 開發');
    expect(comparison.raw.literal.distance, 1);
    expect(comparison.raw.spoken.distance, 0);
    expect(comparison.refined!.literal.distance, 0);
  });
}
