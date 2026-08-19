import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  final DeterministicTranscriptRefiner refiner =
      const DeterministicTranscriptRefiner();

  test('trims and removes whitespace only between adjacent CJK', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('  我 想 用   Flutter 開發  '),
    );

    expect(result.selectedTranscript, '我想用 Flutter 開發');
    expect(result.rawTranscript, '  我 想 用   Flutter 開發  ');
    expect(result.status, TranscriptRefinementStatus.applied);
    expect(result.edits.single.kind, TranscriptEditKind.whitespace);
  });

  test('corrects configured vocabulary as whole Latin tokens', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('flutter 跟 mlx，不是 html。', <String>['Flutter', 'MLX', 'ML']),
    );

    expect(result.selectedTranscript, 'Flutter 跟 MLX，不是 html。');
    expect(result.edits.single.kind, TranscriptEditKind.vocabulary);
  });

  test('does not guess ambiguous configured casing', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('使用 mlx', <String>['MLX', 'Mlx']),
    );

    expect(result.selectedTranscript, '使用 mlx');
    expect(result.status, TranscriptRefinementStatus.unchanged);
  });

  test('does not add punctuation remove fillers or convert script', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('欸我在台湾沒有問題'),
    );

    expect(result.selectedTranscript, '欸我在台湾沒有問題');
  });

  test(
    'a correction the user made once is applied to the next transcript',
    () async {
      // The whole point of learning a mishearing: it has to reach the words
      // the conversation actually receives, not just sit in a settings file.
      const DeterministicTranscriptRefiner refiner =
          DeterministicTranscriptRefiner();

      final TranscriptRefinement result = await refiner.refine(
        TranscriptRefinementRequest(
          rawTranscript: '幫我跑 Dark text',
          locale: 'zh-TW',
          protectedVocabulary: const <String>[],
          misheard: const <MisheardWord>[
            MisheardWord(heard: 'Dark text', meant: 'Dart test'),
          ],
          deadline: const Duration(milliseconds: 50),
        ),
      );

      expect(result.selectedTranscript, '幫我跑 Dart test');
      expect(result.status, TranscriptRefinementStatus.applied);
    },
  );

  test('the casing pass cannot undo a correction', () async {
    // Both want to rewrite the same words, and the first version of this
    // ran corrections first — so the casing pass came afterwards and put
    // the correction straight back. The vocabulary list is editable in the
    // same settings sheet, so a term typed there in the wrong case quietly
    // defeated a correction whose whole point was exact restoration.
    //
    // The earlier version of this test used a vocabulary term that the
    // correction removed, so the casing pass had nothing left to act on and
    // it passed under either ordering. This one names terms that survive.
    const DeterministicTranscriptRefiner refiner =
        DeterministicTranscriptRefiner();

    final TranscriptRefinement result = await refiner.refine(
      TranscriptRefinementRequest(
        rawTranscript: 'run dark text',
        locale: 'en-US',
        protectedVocabulary: const <String>['dart', 'test'],
        misheard: const <MisheardWord>[
          MisheardWord(heard: 'dark text', meant: 'Dart test'),
        ],
        deadline: const Duration(milliseconds: 50),
      ),
    );

    expect(result.selectedTranscript, 'run Dart test');
    expect(result.edits.single.kind, TranscriptEditKind.correction);
  });

  test('removing a word does not leave the gap it sat in', () async {
    // A correction may delete: the recogniser inserts a word that was never
    // said and the user teaches it away. Whitespace was normalised before
    // the correction ran, so the two spaces either side of the removed word
    // survived into the question.
    const DeterministicTranscriptRefiner refiner =
        DeterministicTranscriptRefiner();

    final TranscriptRefinement result = await refiner.refine(
      TranscriptRefinementRequest(
        rawTranscript: 'say dark text now',
        locale: 'en-US',
        protectedVocabulary: const <String>[],
        misheard: const <MisheardWord>[
          MisheardWord(heard: 'dark text', meant: ''),
        ],
        deadline: const Duration(milliseconds: 50),
      ),
    );

    expect(result.selectedTranscript, 'say now');
  });

  test('repairs a near-miss of a protected term when unsure', () async {
    // The full-duplex recogniser's worst zh errors are phonetic neighbours
    // of the vocabulary: Flater for Flutter, NLX for MLX. Measured against
    // the corpus, an LLM refiner made these worse (it guessed); a bounded
    // edit-distance match against the protected list can only restore a
    // listed spelling, never invent one.
    final TranscriptRefinement result = await refiner.refine(
      _request('我剛剛把 Flater和 NLX的版本都更新了。', <String>['Flutter', 'MLX'], 0.31),
    );

    expect(result.selectedTranscript, '我剛剛把 Flutter和 MLX的版本都更新了。');
    expect(result.edits.single.kind, TranscriptEditKind.vocabulary);
  });

  test('a confident transcript is not second-guessed', () async {
    // Correct words score 0.88-1.00 and errors 0.78 or below, so a high
    // score means the recogniser heard what was said — a near-miss of the
    // vocabulary in it is a word the user actually chose, like dark mode
    // beside a vocabulary that lists Dart.
    final TranscriptRefinement result = await refiner.refine(
      _request('幫我開 dark mode。', <String>['Dart'], 0.95),
    );

    expect(result.selectedTranscript, '幫我開 dark mode。');
    expect(result.status, TranscriptRefinementStatus.unchanged);
  });

  test('an unscored transcript is not second-guessed either', () async {
    // The hold key's transcripts carry no confidence, and its recogniser's
    // errors are correctly spelled ordinary words — exactly the ones this
    // pass would damage. No score, no repair.
    final TranscriptRefinement result = await refiner.refine(
      _request('幫我開 dark mode。', <String>['Dart']),
    );

    expect(result.selectedTranscript, '幫我開 dark mode。');
  });

  test('a sentence with no CJK keeps its ordinary words', () async {
    // The measured near-miss errors are zh code-switching; in an English
    // sentence a word near the vocabulary is usually an English word.
    final TranscriptRefinement result = await refiner.refine(
      _request('I would never flatter you.', <String>['Flutter'], 0.31),
    );

    expect(result.selectedTranscript, 'I would never flatter you.');
  });

  test('two edits away is a different word, not a near-miss', () async {
    // codex sits two edits from Xcode and is a product the user actually
    // says. Short terms get one edit of slack; two would swallow it.
    final TranscriptRefinement result = await refiner.refine(
      _request('先用 codex檢查一次。', <String>['Xcode'], 0.31),
    );

    expect(result.selectedTranscript, '先用 codex檢查一次。');
  });

  test('a near-miss torn between two terms is left alone', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('打開 NLX看看。', <String>['MLX', 'NLS'], 0.31),
    );

    expect(result.selectedTranscript, '打開 NLX看看。');
  });

  test('a correction outranks a near-miss repair', () async {
    // The user has said what this word should be; the repair must not
    // rewrite it afterwards.
    final TranscriptRefinement result = await refiner.refine(
      TranscriptRefinementRequest(
        rawTranscript: '更新 Flater吧',
        locale: 'zh-TW',
        protectedVocabulary: const <String>['Flutter'],
        misheard: const <MisheardWord>[
          MisheardWord(heard: 'Flater', meant: 'Flet'),
        ],
        deadline: const Duration(milliseconds: 50),
        heardConfidence: 0.31,
      ),
    );

    expect(result.selectedTranscript, '更新 Flet吧');
    expect(result.edits.single.kind, TranscriptEditKind.correction);
  });

  test('no corrections leaves the transcript exactly as it was', () async {
    const DeterministicTranscriptRefiner refiner =
        DeterministicTranscriptRefiner();

    final TranscriptRefinement result = await refiner.refine(
      TranscriptRefinementRequest(
        rawTranscript: '幫我跑測試',
        locale: 'zh-TW',
        protectedVocabulary: const <String>[],
        deadline: const Duration(milliseconds: 50),
      ),
    );

    expect(result.selectedTranscript, '幫我跑測試');
    expect(result.status, TranscriptRefinementStatus.unchanged);
  });
}

TranscriptRefinementRequest _request(
  String raw, [
  List<String> vocabulary = const <String>[],
  double? heardConfidence,
]) => TranscriptRefinementRequest(
  rawTranscript: raw,
  locale: 'zh-TW',
  protectedVocabulary: vocabulary,
  deadline: const Duration(milliseconds: 250),
  heardConfidence: heardConfidence,
);
