import 'misheard_word.dart';

/// One word the voice says wrongly, spelled as a word it says correctly.
///
/// The voice — `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit` — mispronounces
/// a specific, small set of words badly enough that a listener notices and a
/// recogniser cannot recover them: 企業 comes out as 奇幼, 結構 as 極口, 危險
/// as 一會兒. Measured, not guessed, in
/// `docs/decisions/taiwan-mandarin-voice-candidates.md`, where the surprise
/// was that these are not tones slipping — the model says a different
/// syllable, which is why a listener hears "something is off" without being
/// able to say what.
///
/// The obvious fixes were tried and are all gone. The model does not accept
/// pinyin annotation (`qi1業` renders as 七一一 — it reads the digits). Its
/// unquantised build loses the same number of words, so the fault is the
/// model rather than its compression. The best-scoring alternative is better
/// on isolated words, no better on real sentences, twice as slow, and
/// occasionally unintelligible.
///
/// What works is spelling the word as a different word that sounds the same.
/// Writing 氣業 makes the voice say qì yè, which is what 企業 is.
///
/// Two rules this must never break.
///
/// **Render only.** A respelling exists between the text and the synthesiser.
/// It must never reach the conversation, storage, or the screen, or the user
/// reads 氣業 in their own transcript and rightly concludes the agent cannot
/// spell. [respellForSpeech] is called at exactly one place, the moment the
/// text leaves for the voice.
///
/// **Same sound, always.** An entry that changes the sound is not a
/// pronunciation fix, it is the voice saying a different word — worse than
/// the defect it replaces, because it is invisible in text.
final class SpokenRespelling {
  /// Creates a respelling of [word], which the voice should say as [saidAs].
  const SpokenRespelling({required this.word, required this.saidAs});

  /// The word as it is written everywhere the user can see it.
  final String word;

  /// The homophone handed to the synthesiser in its place.
  final String saidAs;

  /// Whether this rule can do anything.
  ///
  /// The same two half-filled-editor cases [MisheardWord.isUsable] refuses,
  /// for the same reason.
  bool get isUsable => word.trim().isNotEmpty && word.trim() != saidAs.trim();

  @override
  bool operator ==(Object other) =>
      other is SpokenRespelling && other.word == word && other.saidAs == saidAs;

  @override
  int get hashCode => Object.hash(word, saidAs);

  @override
  String toString() => 'SpokenRespelling($word → $saidAs)';
}

/// [text] with every respelling applied, on its way to the synthesiser.
///
/// Runs on [applyMisheardWords] rather than on a substitution of its own,
/// because it is the same problem: put one written form in place of another,
/// longest rule first, without letting what one rule wrote be read by the
/// next, and walking graphemes so a combining mark is not moved onto the
/// replacement. Every one of those properties is already pinned by a test
/// there, and a second implementation would be a second set of them to get
/// subtly wrong.
String respellForSpeech(String text, List<SpokenRespelling> rules) {
  if (rules.isEmpty) {
    return text;
  }
  return applyMisheardWords(text, <MisheardWord>[
    for (final SpokenRespelling rule in rules)
      MisheardWord(heard: rule.word, meant: rule.saidAs),
  ]);
}
