/// Normalizes spacing while preserving punctuation and Latin letter case.
String normalizeLiteral(String text) =>
    text.trim().replaceAll(RegExp(r'\s+', unicode: true), ' ');

/// Normalizes text for spoken-content comparison.
String normalizeSpoken(String text) => normalizeLiteral(
  text,
).replaceAll(RegExp(r'[\p{P}\p{S}\s]+', unicode: true), '').toLowerCase();

/// Every character that is unambiguously part of a number.
///
/// Both scripts, because a recogniser writes `12,000` where the corpus
/// spells 一萬二 and the two have to fold onto each other.
const String _numerals = '0123456789０１２３４５６７８９零〇一二三四五六七八九十百千萬万億亿兩两';

/// Characters that join or qualify a number but are ordinary words alone.
///
/// 點 is half of 三點半 and all of 重點; 半 is half of 三點半 and all of 一半.
/// They are folded only inside a run that also holds a real numeral, so a
/// word the recogniser did hear is never quietly deleted.
const String _numeralJoiners = '點半.．,，:：';

/// Every English word that is unambiguously part of a number.
///
/// The class above is characters, which is enough for two scripts that write
/// numbers as characters. English writes them as words, so `21` and
/// `twenty-one` fold onto each other only if the words are named. Added when
/// `corpus/en-spoken-v1.json` charged 67.2% to a case whose only genuine
/// error was one ordinary word.
const List<String> _englishNumerals = <String>[
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
  'hundred',
  'thousand',
  'million',
  'billion',
];

/// English words that join a number but are ordinary words alone.
///
/// `point` is half of `three point five` and all of `that is the point`, so
/// it folds only inside a run that also holds a real numeral — the same rule
/// 點 follows above.
const List<String> _englishJoiners = <String>['point'];

/// A maximal run of numeral and joining characters, spacing included.
///
/// Whitespace joins because recognisers disagree about it inside a number:
/// Breeze-ASR-25 writes 「3 點半」 where the corpus writes 「三點半」, and
/// without this the 點半 folded on one side and survived on the other,
/// charging 28.6% to a model that heard the time perfectly. Hyphens join for
/// the same reason in English, where `forty-four` is one number. A run still
/// has to contain a real numeral, so ordinary spaced words are untouched.
final RegExp _numberRun = RegExp(
  '(?:[$_numerals$_numeralJoiners\\s-]|'
  '\\b(?:${<String>[..._englishNumerals, ..._englishJoiners].join('|')})\\b)+',
  caseSensitive: false,
);

/// Whether [run] holds anything that is definitely a number.
bool _isANumber(String run) =>
    run.runes.any(
      (int rune) => _numerals.contains(String.fromCharCode(rune)),
    ) ||
    _englishNumeral.hasMatch(run);

final RegExp _englishNumeral = RegExp(
  '\\b(?:${_englishNumerals.join('|')})\\b',
  caseSensitive: false,
);

/// Normalizes text for comparing what was *heard*, folding how numbers are
/// written on top of everything [normalizeSpoken] folds.
///
/// Spoken CER folds punctuation, whitespace and Latin case but not numerals,
/// so a recogniser that heard 一萬二 perfectly and wrote `12,000` is charged
/// for every character of the difference — 61.5% and 41.7% on the two corpus
/// cases that contain numbers, against a 14.6% mean over twelve. That is a
/// disagreement about writing, not about hearing, and it made the aggregate
/// a floor on quality rather than a measure of it.
///
/// The fold is removal rather than conversion. Converting 一萬二 to 12000
/// needs a Chinese number parser and a way to know that 三點五 is 3.5 while
/// 三點半 is half past three — a real piece of work, and one whose bugs would
/// be invisible inside an aggregate. Removing both sides' numbers instead
/// measures exactly what is left, and says plainly that it is not measuring
/// the numbers at all. Read it beside [normalizeSpoken], never instead of
/// it: a recogniser that hears every word and every number wrongly scores
/// perfectly here.
String normalizeHeard(String text) => normalizeSpoken(
  normalizeLiteral(text).replaceAllMapped(
    _numberRun,
    (Match match) => _isANumber(match[0]!) ? ' ' : match[0]!,
  ),
);
