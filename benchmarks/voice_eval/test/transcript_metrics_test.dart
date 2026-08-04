import 'package:lulo_voice_eval/voice_eval.dart';
import 'package:test/test.dart';

void main() {
  _heardNumeralsGroup();
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

void _heardNumeralsGroup() {
  group('normalizeHeard', () {
    test('a number written two ways is not a hearing error', () {
      // Measured on Apple SpeechAnalyzer against corpus/zh-TW-v1.json: both
      // of these were heard perfectly and scored 61.5% and 41.7% spoken CER,
      // because the recogniser writes digits where the corpus spells them.
      expect(
        normalizeHeard('預算是一萬二，版本先用三點五。'),
        normalizeHeard('預算是12,000，版本先用3.5。'),
      );
      expect(
        normalizeHeard('八月二日下午三點半提醒我。'),
        normalizeHeard('8月 2日下午 3:30提醒我。'),
      );
    });

    test('a real mishearing is still charged for', () {
      expect(normalizeHeard('細節我等等再補'), isNot(normalizeHeard('細節我的忍在補')));
    });

    test('a word that merely contains a numeral character survives', () {
      // 點 is half of 三點半 and all of 重點. Stripping it wherever it
      // appears would quietly delete words the recogniser did hear.
      expect(normalizeHeard('這是重點'), contains('重點'));
      expect(normalizeHeard('十分鐘'), contains('分鐘'));
    });

    test('everything spoken normalization folds is still folded', () {
      expect(normalizeHeard('Hello, World!'), normalizeHeard('hello world'));
    });
  });

  group('the heard score sits beside the spoken one', () {
    test('a numeral disagreement costs spoken CER and not heard CER', () {
      final TranscriptComparison result = compareTranscripts(
        reference: '預算是一萬二。',
        rawTranscript: '預算是12,000。',
      );

      expect(result.raw.spoken.cer, greaterThan(0));
      expect(result.raw.heard.cer, 0);
    });

    test('a mishearing costs both', () {
      final TranscriptComparison result = compareTranscripts(
        reference: '細節我等等再補',
        rawTranscript: '細節我的忍在補',
      );

      expect(result.raw.spoken.cer, greaterThan(0));
      expect(result.raw.heard.cer, greaterThan(0));
    });
  });
}
