import 'package:characters/characters.dart';

/// What the words say about whether the speaker has finished.
///
/// The other half of [FloorControl]'s question. `FloorControl` decides who
/// has the floor while the agent is speaking; this decides how long to wait
/// before deciding the user has stopped. Both are read off the words rather
/// than off their length, and for the same reason: a threshold on duration
/// gets 「等一下」 and 「這樣可以嗎」 wrong in opposite directions.
///
/// Lives here rather than beside the microphone because it is pure. Given
/// the text, the answer is the same every time and can be checked against a
/// corpus of things people actually say — which is what
/// `turn_completion_test.dart` does, sentence by sentence, with the same
/// table the Swift endpointer is checked against.
///
/// **This is the only copy of the lexicon.** The endpointer that actually
/// runs is native, because it is consulted on a 50ms tick inside the audio
/// path where a hop across the platform channel per tick would cost more
/// than the decision saves — `pigeons/voice_host_api.dart` says so, and a
/// second platform's endpointer will sit in its own audio loop for the same
/// reason. So the *matcher* is written once per platform and the *words* are
/// written once here: `tool/generate_turn_taking_lexicon.dart` emits them
/// into `macos/Runner/GeneratedTurnTakingLexicon.swift`, which is committed
/// like the l10n and drift output beside it, and `verify.dart` regenerates
/// and diffs so a list edited on one side and not the other fails the gate
/// rather than the conversation.
///
/// Adding a word therefore means editing this file and re-running the
/// generator. Adding a *rule* means editing every matcher — and the corpus
/// table in `turn_completion_test.dart` and `SpeechTurnTests.swift` is what
/// says whether they still agree.
enum TurnCompletion {
  /// The words carry no signal either way; the ordinary silence applies.
  unknown,

  /// A thought still in progress — give it longer before submitting.
  continuing,

  /// A question or statement that has visibly landed — submit sooner.
  settled;

  /// How much longer a half-finished thought is given.
  ///
  /// Sized to clear the corpus's longest mid-utterance pause: 0.8 + 0.6 is
  /// 1.4s, against the 1.02s of `short-answer-not-yet` in
  /// `docs/decisions/voice-turn-latency.md`.
  static const Duration continuingGrace = Duration(milliseconds: 600);

  /// How much sooner a visibly finished question is submitted.
  ///
  /// Deliberately small. Every millisecond taken off the wait is a
  /// millisecond of a user's trailing word that can be cut off, and being
  /// cut off is a worse failure than being answered a quarter-second late.
  static const Duration settledSaving = Duration(milliseconds: 250);

  /// How much has to have been said before "finished" is believable.
  ///
  /// A bare 「嗎」 is one misheard syllable, not a question, and shortening
  /// the endpoint on a mishearing is how a user gets cut off mid-word.
  static const int syllablesToBeFinished = 4;

  /// Endings that introduce more words after a pause.
  ///
  /// Connectives, hesitations, and the framing phrases a speaker uses to
  /// announce a question before asking it. The first three of these were the
  /// whole list, hardcoded, and everything else here is a pause this agent
  /// has had to be interrupted through.
  static const List<String> continuingSuffixes = <String>[
    '等一下',
    '我想問的是',
    '我想說的是',
    '我的意思是',
    '我是說',
    '我覺得',
    '我想說',
    '我想',
    '但是',
    '可是',
    '不過',
    '然後',
    '而且',
    '因為',
    '所以',
    '如果',
    '要是',
    '除非',
    '雖然',
    '既然',
    '或是',
    '還有',
    '還是',
    '就是',
    '那個',
    '這個',
    '譬如',
    '例如',
    '比如',
    '像是',
    '至於',
    '另外',
    '首先',
    '再來',
    '接下來',
    '反正',
    '其實',
    '的話',
    '的時候',
  ];

  /// The same, in Latin script, matched as a whole final word.
  ///
  /// By word rather than by suffix: "also" ends in "so" and is not a speaker
  /// trailing off.
  static const Set<String> continuingWords = <String>{
    'and',
    'but',
    'so',
    'because',
    'if',
    'then',
    'or',
    'like',
    'um',
    'uh',
    'well',
    'actually',
    'the',
    'a',
    'an',
    'to',
    'of',
    'for',
    'with',
    'that',
    'which',
    'when',
    'while',
    'however',
    'although',
  };

  /// Endings that mean the question has been asked.
  ///
  /// Only the particles that do not double as hesitations. 「了」「吧」「啦」 are
  /// all common mid-sentence — 「我吃了飯就出門」 — and are deliberately absent:
  /// including them buys a quarter-second and pays for it by cutting people
  /// off.
  static const List<String> settledSuffixes = <String>[
    '嗎',
    '呢',
    '嘛',
    '沒有',
    '好不好',
    '對不對',
  ];

  /// What the recogniser writes when it believes the sentence ended.
  static const Set<String> terminalPunctuation = <String>{
    '。',
    '？',
    '！',
    '．',
    '｡',
    '?',
    '!',
  };

  /// Whitespace, punctuation, and symbols — everything that is not speech.
  static final RegExp _notSpeech = RegExp(
    r'[\p{Z}\p{P}\p{S}\s]',
    unicode: true,
  );

  /// The same, anchored, for trimming both ends of a transcript.
  static final RegExp _notSpeechEnds = RegExp(
    r'^[\p{Z}\p{P}\p{S}\s]+|[\p{Z}\p{P}\p{S}\s]+$',
    unicode: true,
  );

  /// One ASCII letter or digit — a run of these is one syllable.
  static final RegExp _latin = RegExp(r'[0-9A-Za-z]');

  /// What [text] says about whether the speaker has finished.
  ///
  /// [alsoUnfinished] is the user's own way of trailing off, from the agent
  /// profile. The built-in list is a guess at how people pause mid-thought; a
  /// filler nobody else uses is exactly what decides whether being cut off
  /// mid-sentence ever stops happening, and it cannot be guessed from here.
  static TurnCompletion of(
    String text, {
    List<String> alsoUnfinished = const <String>[],
  }) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return TurnCompletion.unknown;
    }
    final String last = trimmed.characters.last;
    final String bare = trimmed.replaceAll(_notSpeechEnds, '');
    if (bare.isEmpty) {
      return TurnCompletion.unknown;
    }
    if (_isContinuing(bare, alsoUnfinished)) {
      return TurnCompletion.continuing;
    }
    if (syllablesOf(bare) < syllablesToBeFinished) {
      return TurnCompletion.unknown;
    }
    if (terminalPunctuation.contains(last)) {
      return TurnCompletion.settled;
    }
    if (settledSuffixes.any(bare.endsWith)) {
      return TurnCompletion.settled;
    }
    return TurnCompletion.unknown;
  }

  /// How long [text] has to stay quiet before the turn is submitted.
  ///
  /// [endpointSilence] is the ordinary wait; what this returns is that wait
  /// adjusted by what was heard. The saving never takes the wait below zero.
  static Duration requiredSilence({
    required String after,
    required Duration endpointSilence,
    List<String> alsoUnfinished = const <String>[],
  }) => switch (of(after, alsoUnfinished: alsoUnfinished)) {
    TurnCompletion.continuing => endpointSilence + continuingGrace,
    TurnCompletion.settled =>
      endpointSilence > settledSaving
          ? endpointSilence - settledSaving
          : Duration.zero,
    TurnCompletion.unknown => endpointSilence,
  };

  static bool _isContinuing(String bare, List<String> alsoUnfinished) {
    if (continuingSuffixes.any(bare.endsWith)) {
      return true;
    }
    // An empty entry is a suffix of every string, which would hold every turn
    // open for an extra 0.6s and read exactly like the model being slow.
    for (final String entry in alsoUnfinished) {
      final String written = entry.trim();
      if (written.isNotEmpty && bare.endsWith(written)) {
        return true;
      }
    }
    final List<String> words = bare
        .toLowerCase()
        .split(' ')
        .where((String word) => word.isNotEmpty)
        .toList();
    return words.isNotEmpty && continuingWords.contains(words.last);
  }

  /// Roughly how much speech [text] is.
  ///
  /// A CJK character is one syllable; a run of Latin letters or digits is one
  /// however long it is. Counting characters instead makes "the" three times
  /// the utterance that 「嗎」 is, which is backwards.
  static int syllablesOf(String text) {
    int count = 0;
    bool inLatinRun = false;
    for (final String character in text.characters) {
      // The comma the recogniser writes between clauses is not speech, and
      // counting it made a two-syllable scrap look long enough to shorten on.
      if (_notSpeech.hasMatch(character)) {
        inLatinRun = false;
        continue;
      }
      if (_latin.hasMatch(character)) {
        if (!inLatinRun) {
          count += 1;
          inLatinRun = true;
        }
        continue;
      }
      inLatinRun = false;
      count += 1;
    }
    return count;
  }
}
