import 'package:characters/characters.dart';

/// One thing the recogniser gets wrong, and what it should have been.
///
/// The recogniser hears product names as the ordinary words they sound like.
/// `benchmarks/voice_eval` has 「Dart test」 coming back as 「Dark text」 and
/// 「Swift tests」 as 「sweep test」 — both perfectly ordinary English, so
/// nothing downstream can tell they are wrong.
///
/// The textbook remedy is contextual biasing, and this app has it wired:
/// `AgentProfile.vocabulary` reaches Apple's `contextualStrings`. But
/// `SpokenVocabularyBook` carries a measurement of a thirty-two term bias
/// changing the transcript by not one character, so the remedy nobody has
/// shown to work is not the one to lean on. Putting back exactly what the
/// user said it should have been cannot fail the same way: it is not a hint
/// to a model, it is a substitution.
final class MisheardWord {
  /// Creates a correction from what was [heard] to what was [meant].
  const MisheardWord({required this.heard, required this.meant});

  /// What the recogniser produced.
  final String heard;

  /// What the user actually said.
  final String meant;

  /// Whether this rule can do anything.
  ///
  /// A blank [heard] would match between every pair of characters, and a
  /// rule that replaces something with itself is a row somebody started
  /// typing and left. Both come from a half-filled editor rather than from
  /// anything the user meant.
  bool get isUsable => heard.trim().isNotEmpty && heard.trim() != meant.trim();

  @override
  bool operator ==(Object other) =>
      other is MisheardWord && other.heard == heard && other.meant == meant;

  @override
  int get hashCode => Object.hash(heard, meant);

  @override
  String toString() => 'MisheardWord($heard → $meant)';
}

/// Puts back what [rules] say the recogniser should have heard in [text].
///
/// One pass, left to right. Four properties are load bearing and each is
/// pinned by a test:
///
/// * **What a rule puts back is never read by another rule.** Two chaining
///   corrections would rewrite a sentence into something nobody asked for,
///   and the result would depend on the order they were added in.
/// * **Longest first, then exact case, then alphabetical.** Length alone
///   left two same-length rules resolving by whichever was typed first,
///   which is not something a user can reason about; and it let a rule that
///   matched only by ignoring case beat one that matched exactly. Exact
///   case breaks the tie and never outranks length — asking for every exact
///   match before any inexact one inverted that.
/// * **Word breaks are checked per end, not for the rule as a whole.** The
///   first version required the rule's first *and* last character to be
///   Latin before checking anything, so every mixed-script rule — 「台中
///   weather」, `open 台中`, the ones this app is actually for — got no
///   boundary check at all and fired inside longer words.
/// * **Characters, not code units.** A combining mark after a match used to
///   read as a word break and end up re-based onto whatever the rule put
///   there: `cat` → `cache` over `cat` + a combining acute produced
///   `caché`, with the accent moved from the `t` to the `e`.
String applyMisheardWords(String text, List<MisheardWord> rules) {
  final List<_Rule> usable =
      rules.where((MisheardWord rule) => rule.isUsable).map(_Rule.new).toList()
        ..sort((_Rule a, _Rule b) {
          final int byLength = b.heard.length.compareTo(a.heard.length);
          return byLength != 0 ? byLength : a.heard.compareTo(b.heard);
        });
  if (usable.isEmpty) {
    return text;
  }
  final List<String> letters = text.characters.toList();
  final StringBuffer out = StringBuffer();
  // What was last emitted, so a start boundary is judged against the text
  // being written rather than the text being read: a rule that replaced the
  // characters just before this position changed what precedes it.
  String? emitted;
  int at = 0;
  while (at < letters.length) {
    final _Rule? hit = _match(letters, at, usable, after: emitted);
    if (hit == null) {
      out.write(letters[at]);
      emitted = letters[at];
      at += 1;
      continue;
    }
    out.write(hit.meant);
    emitted = hit.meant.characters.isEmpty
        ? emitted
        : hit.meant.characters.last;
    at += hit.letters.length;
  }
  return out.toString();
}

/// The rule that applies at [at], or null when none does.
///
/// Longest first; among rules of the same length, one written in exactly the
/// case the recogniser produced beats one that only matches by ignoring it.
/// An earlier version asked for every exact-case match before considering
/// any inexact one, which made case outrank length — so a three-letter rule
/// could take a span a nine-letter rule was written for, the opposite of
/// what this function's own contract says.
_Rule? _match(
  List<String> letters,
  int at,
  List<_Rule> rules, {
  required String? after,
}) {
  _Rule? best;
  bool bestIsExact = false;
  for (final _Rule rule in rules) {
    if (best != null && rule.letters.length < best.letters.length) {
      // Sorted longest first, so nothing after this can beat what is held.
      break;
    }
    final int end = at + rule.letters.length;
    if (end > letters.length) {
      continue;
    }
    bool exact = true;
    bool loose = true;
    for (int i = 0; i < rule.letters.length; i++) {
      final String here = letters[at + i];
      final String want = rule.letters[i];
      if (here != want) {
        exact = false;
        if (here.toLowerCase() != want.toLowerCase()) {
          loose = false;
          break;
        }
      }
    }
    if (!loose) {
      continue;
    }
    // Checked per end. A rule beginning in a script with word breaks must
    // not start mid-word; one beginning in Han has no word to be in the
    // middle of, because Han is written without breaks.
    if (_isWordish(rule.letters.first) && after != null && _isWordish(after)) {
      continue;
    }
    if (_isWordish(rule.letters.last) &&
        end < letters.length &&
        _isWordish(letters[end])) {
      continue;
    }
    if (best == null || (exact && !bestIsExact)) {
      best = rule;
      bestIsExact = exact;
    }
  }
  return best;
}

/// One rule with the work that does not change per position done once.
final class _Rule {
  _Rule(MisheardWord word)
    : heard = word.heard.trim(),
      meant = word.meant.trim(),
      letters = word.heard.trim().characters.toList();

  final String heard;
  final String meant;
  final List<String> letters;
}

/// Whether [cluster] is part of a word that is written with breaks.
///
/// Judged on the cluster's base character, not on any code point in it. The
/// first version asked `[A-Za-z0-9]` of the whole cluster, which answered
/// two different things wrongly: a decomposed 「á」 contains an `a` and read
/// as a word character, while a precomposed one contains no ASCII at all and
/// read as a break — so a rule fired inside 「caté」 written the second way,
/// which is how most text arrives, and orphaned the accent onto the
/// replacement.
///
/// Han, kana and Hangul are deliberately not word characters here. They are
/// written without breaks, so requiring one around a rule would mean no rule
/// ever fired in the language this app is mostly used in — the same
/// asymmetry `searchConversations` documents for its substring search.
bool _isWordish(String cluster) {
  final String base = String.fromCharCode(cluster.runes.first);
  return !_unbroken.hasMatch(base) && _letterOrDigit.hasMatch(base);
}

final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The scripts written without spaces between words.
final RegExp _unbroken = RegExp(
  r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af\uf900-\ufaff]',
);
