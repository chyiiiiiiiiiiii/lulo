/// What an utterance is doing to a conversation that is already in progress.
///
/// The distinction that matters is not how long the words are. "對對對對對"
/// is five characters of pure agreement and "不對" is two characters that
/// have to land immediately; a threshold on length gets both of them wrong
/// in the direction that costs the most.
enum FloorClaim {
  /// Nothing sayable was heard — whitespace, or punctuation on its own.
  silence,

  /// The listener signalling that they are still there: 嗯, 對對, OK.
  ///
  /// This is the sound of someone being talked *to*, and taking it as a
  /// request to stop is what ends an answer 571 characters into being read
  /// aloud for saying the one thing that means "carry on".
  backchannel,

  /// A request to stop, whatever its length: 不對, 等等, stop.
  correction,

  /// Words that are neither of the above — a question, an instruction,
  /// anything with content of its own.
  substance,
}

/// Who has the floor, decided from the words rather than their length.
///
/// Split out of the voice controller because it is the one part of
/// interruption handling that is pure: given the text and whether the agent
/// is mid-sentence, the answer is the same every time and can be checked
/// against a list of things people actually say.
///
/// The built-in lists are a guess at how people say "carry on" and "stop".
/// A user's own habits are not a guess, so [alsoAcknowledgements] and
/// [alsoCorrections] extend them from the agent profile — which is watched
/// and reloaded, so a word added while the app is running takes effect on
/// the next thing said.
final class FloorControl {
  /// Creates a policy that adds the user's own words to the built-in ones.
  ///
  /// The entries are normalized and sorted into their matching kinds here,
  /// once, rather than on every partial — this runs a few times a second for
  /// as long as the microphone is open.
  factory FloorControl({
    List<String> alsoAcknowledgements = const <String>[],
    List<String> alsoCorrections = const <String>[],
  }) {
    final StringBuffer repeatable = StringBuffer(_backchannelRunes);
    final Set<String> phrases = <String>{};
    for (final String entry in alsoAcknowledgements) {
      final String written = _normalize(entry).replaceAll(' ', '');
      if (written.isEmpty) {
        continue;
      }
      if (written.runes.length == 1) {
        repeatable.write(written);
      } else {
        phrases.add(written);
      }
    }
    final Set<String> openings = <String>{};
    final Set<String> words = <String>{};
    for (final String entry in alsoCorrections) {
      final String written = _normalize(entry);
      if (written.isEmpty) {
        continue;
      }
      if (_latinOnly.hasMatch(written)) {
        words.add(written.split(' ').first);
      } else {
        openings.add(written.replaceAll(' ', ''));
      }
    }
    return FloorControl._(
      alsoAcknowledgements: List<String>.unmodifiable(alsoAcknowledgements),
      alsoCorrections: List<String>.unmodifiable(alsoCorrections),
      repeatableRunes: repeatable.toString(),
      extraPhrases: Set<String>.unmodifiable(phrases),
      extraOpenings: Set<String>.unmodifiable(openings),
      extraWords: Set<String>.unmodifiable(words),
    );
  }

  const FloorControl._({
    required this.alsoAcknowledgements,
    required this.alsoCorrections,
    required this._repeatableRunes,
    required this._extraPhrases,
    required this._extraOpenings,
    required this._extraWords,
  });

  /// The policy a profile that says nothing about turn-taking gets.
  static final FloorControl standard = FloorControl();

  final String _repeatableRunes;
  final Set<String> _extraPhrases;
  final Set<String> _extraOpenings;
  final Set<String> _extraWords;

  /// The user's own ways of saying "carry on".
  ///
  /// A single-character entry joins the repeatable set, so adding 「蛤」 also
  /// covers 「蛤蛤蛤」 the way 嗯 covers 嗯嗯. Anything longer is matched whole,
  /// because a phrase with words after it is no longer that phrase.
  final List<String> alsoAcknowledgements;

  /// The user's own ways of saying "stop".
  ///
  /// Matched the way the built-ins are: an entry containing Han is a prefix,
  /// so 「先停一下我想想」 still stops the agent; an entry in Latin contributes
  /// its first word, so "hang on" matches "hang" and not "hanging".
  final List<String> alsoCorrections;

  /// How much substance it takes to interrupt an agent that is speaking.
  ///
  /// Measured in syllables rather than characters: a CJK character is one,
  /// and a run of Latin letters or digits is one however long it is. Counting
  /// runes charged "the" as three units of interruption and "你可以解釋" as
  /// five, which are not remotely the same amount of speech.
  ///
  /// Three is roughly where a mishearing stops being plausible. One stray
  /// syllable used to be enough, and 計 for 肌 could end an answer.
  static const int charactersOfSubstance = 3;

  /// Every rune that can stand alone as agreement, and can be repeated.
  ///
  /// Repetition is the whole point: 嗯嗯, 對對對, 哈哈哈 are the same signal
  /// said longer, and a length threshold reads them as more insistent when
  /// they are only more relaxed. An utterance built entirely out of these is
  /// agreement no matter how many of them there are.
  static const String _backchannelRunes = '嗯恩喔哦噢唔對好是啊呀耶哈呵嘿哼';

  /// Whole utterances that mean "carry on" but are not built from
  /// [_backchannelRunes]. Matched exactly: the moment anything follows them,
  /// the utterance is about something.
  static const List<String> _backchannelPhrases = <String>[
    '好的',
    '是的',
    '了解',
    '知道了',
    '我知道',
    '原來',
    '原來如此',
    '沒錯',
    '真的假的',
    '真的喔',
    '有道理',
    'isee',
    'gotit',
    'uhhuh',
    'mmhmm',
    'mhm',
    'mm',
    'yeah',
    'yep',
    'yes',
    'right',
    'sure',
    'ok',
    'okay',
    'cool',
    'nice',
    'exactly',
    'makessense',
  ];

  /// Openings that mean stop, matched as a prefix.
  ///
  /// A prefix rather than the whole utterance because a correction rarely
  /// arrives alone — "不對，我是說……" is the common shape, and waiting for it
  /// to finish is waiting through the sentence it is trying to stop.
  static const List<String> _correctionOpenings = <String>[
    '不對',
    '不是',
    '不要',
    '等等',
    '等一下',
    '等下',
    '停',
    '慢著',
    '錯了',
    '夠了',
    '重來',
    '別說',
    '再說一次',
  ];

  /// First words in Latin script that mean stop.
  ///
  /// Matched by word rather than by prefix: "no" has to interrupt and
  /// "nothing" must not, which prefix matching cannot tell apart.
  static const List<String> _correctionWords = <String>[
    'wait',
    'stop',
    'no',
    'nope',
    'hold',
    'actually',
  ];

  /// Anything that is not a letter, a digit, or CJK — the punctuation the
  /// recogniser writes and the spacing it guesses at.
  static final RegExp _notWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// A maximal run of Latin letters or digits: one syllable's worth for
  /// counting purposes, however long the word is.
  static final RegExp _latinRun = RegExp(r'[A-Za-z0-9]+');

  /// Whether a normalized entry is written wholly in Latin script.
  static final RegExp _latinOnly = RegExp(r'^[a-z0-9 ]+$');

  /// What [heard] is doing to a conversation already in progress.
  FloorClaim classify(String heard) {
    final String normalized = _normalize(heard);
    if (normalized.isEmpty) {
      return FloorClaim.silence;
    }
    final String compact = normalized.replaceAll(' ', '');
    // Corrections first: being unable to stop the agent is the worse of the
    // two failures, so a word the user listed as both wins here.
    if (_isCorrection(normalized, compact)) {
      return FloorClaim.correction;
    }
    if (_isBackchannel(compact)) {
      return FloorClaim.backchannel;
    }
    return FloorClaim.substance;
  }

  /// Whether [heard] is enough to take the floor.
  ///
  /// With nothing being said there is nothing to take away, so any word at
  /// all claims a free floor — a correction has to land as fast as it is
  /// spoken. The thresholds exist only for speech in progress.
  bool takesTheFloor(String heard, {required bool agentIsSpeaking}) {
    final FloorClaim claim = classify(heard);
    if (claim == FloorClaim.silence) {
      return false;
    }
    if (!agentIsSpeaking) {
      return true;
    }
    return switch (claim) {
      FloorClaim.silence => false,
      FloorClaim.backchannel => false,
      FloorClaim.correction => true,
      FloorClaim.substance => syllablesOf(heard) >= charactersOfSubstance,
    };
  }

  /// Roughly how much speech [heard] is, in syllables.
  ///
  /// A CJK character is one syllable and a run of Latin letters or digits is
  /// one — near enough for a threshold, and far closer than counting runes,
  /// which is wrong by a factor of three between the two scripts.
  static int syllablesOf(String heard) {
    final String normalized = _normalize(heard);
    if (normalized.isEmpty) {
      return 0;
    }
    // Latin runs are collapsed to one apiece; everything else that is not
    // the spacing left behind by punctuation counts itself.
    final int latinRuns = _latinRun.allMatches(normalized).length;
    final String withoutLatin = normalized.replaceAll(_latinRun, '');
    final int others = withoutLatin.runes
        .where((int rune) => rune != 0x20)
        .length;
    return others + latinRuns;
  }

  /// [heard] with its punctuation turned into single spaces and its Latin
  /// lower-cased, so "OK。" and "ok" are the same utterance.
  static String _normalize(String heard) =>
      heard.toLowerCase().replaceAll(_notWords, ' ').trim();

  bool _isCorrection(String normalized, String compact) {
    for (final String opening in _correctionOpenings) {
      if (compact.startsWith(opening)) {
        return true;
      }
    }
    for (final String opening in _extraOpenings) {
      if (compact.startsWith(opening)) {
        return true;
      }
    }
    final String firstWord = normalized.split(' ').first;
    return _correctionWords.contains(firstWord) ||
        _extraWords.contains(firstWord);
  }

  bool _isBackchannel(String compact) {
    if (_backchannelPhrases.contains(compact) ||
        _extraPhrases.contains(compact)) {
      return true;
    }
    for (final int rune in compact.runes) {
      if (!_repeatableRunes.contains(String.fromCharCode(rune))) {
        return false;
      }
    }
    return true;
  }
}
