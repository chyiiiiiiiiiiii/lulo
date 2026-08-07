import 'package:characters/characters.dart';

/// The parts of one document a question turned out to be about.
final class DocumentPassages {
  /// Creates the selection.
  DocumentPassages(List<String> passages)
    : passages = List<String>.unmodifiable(passages);

  /// The passages, in the order they appear in the document.
  ///
  /// Whole passages rather than fragments: a sentence cut out of a clause it
  /// depends on is how a model ends up confidently answering the opposite.
  final List<String> passages;

  /// How much of the budget they spent, as the prompt will see it.
  ///
  /// Reported so the app can say which part of the document it used. Without
  /// that the app is asserting something about a file the user can read for
  /// themselves, and they have no way to check it.
  int get usedCharacters => passages.isEmpty ? 0 : passages.join('\n\n').length;
}

/// The passages of [document] that [question] is about, within a budget.
///
/// Deliberately not retrieval-augmented generation. Real RAG means an
/// embedding model, chunking, and a vector store — all in this process,
/// because the sandbox cannot spawn one, and all competing for memory with a
/// resident Gemma. Then the retrieved chunks have to fit a 4096-token window
/// alongside the question and the reserved answer, which leaves room for two
/// or three of them, which means retrieval quality decides everything and
/// there is no room to recover from a bad hit.
///
/// This is the version that fits: one document the user picked, passages
/// located by the words in the question, and the app saying which it used.
/// It answers "他們保固幾年" out of a lease without pretending to be a
/// knowledge base.
///
/// Matching is by substring and not by word, for the reason
/// `searchConversations` documents: Han is written without spaces, so a
/// matcher that required them would never fire in the language this app is
/// mostly used in.
DocumentPassages passagesFor({
  required String question,
  required String document,
  required int maxCharacters,
}) {
  final List<String> terms = _termsOf(question);
  if (terms.isEmpty || document.trim().isEmpty) {
    return DocumentPassages(const <String>[]);
  }
  final List<String> paragraphs = document
      .split(RegExp(r'\n\s*\n'))
      .map((String p) => p.trim())
      .where((String p) => p.isNotEmpty)
      .toList();

  // Scored, then taken best-first, then put back in document order — a
  // document read out of order reads as a different document.
  final List<({int at, int score, String text})> scored =
      <({int at, int score, String text})>[];
  for (int at = 0; at < paragraphs.length; at++) {
    final String lower = paragraphs[at].toLowerCase();
    int score = 0;
    for (final String term in terms) {
      if (lower.contains(term)) {
        // Longer terms are worth more: 「保固」 says more about what is being
        // asked than 「幾」 does.
        score += term.characters.length;
      }
    }
    if (score > 0) {
      scored.add((at: at, score: score, text: paragraphs[at]));
    }
  }
  scored.sort((a, b) {
    final int byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.at.compareTo(b.at);
  });

  final List<({int at, String text})> taken = <({int at, String text})>[];
  int spent = 0;
  for (final ({int at, int score, String text}) candidate in scored) {
    // Two characters for the blank line that will join them.
    final int cost = candidate.text.length + (taken.isEmpty ? 0 : 2);
    if (spent + cost > maxCharacters) {
      // Whole passages only. A truncated one is the fragment problem again.
      continue;
    }
    spent += cost;
    taken.add((at: candidate.at, text: candidate.text));
  }
  taken.sort((a, b) => a.at.compareTo(b.at));
  return DocumentPassages(taken.map((r) => r.text).toList());
}

/// The words of [question] worth looking for.
///
/// Latin words are taken whole. Han is taken as every run of two or three
/// characters, because it has no word breaks and two characters is the
/// ordinary length of a Chinese word — 「保固」, 「修繕」, 「租賃」.
///
/// Single characters are dropped in both scripts. Matching on 「的」 or "the"
/// makes every passage relevant, which is the same as none of them being
/// relevant and costs the whole budget to discover.
List<String> _termsOf(String question) {
  final String text = question.trim().toLowerCase();
  final Set<String> terms = <String>{};
  for (final RegExpMatch match in _latin.allMatches(text)) {
    final String word = match.group(0)!;
    if (word.length > 2 && !_tooCommon.contains(word)) {
      terms.add(word);
    }
  }
  for (final RegExpMatch run in _han.allMatches(text)) {
    final List<String> letters = run.group(0)!.characters.toList();
    for (int size = 2; size <= 3; size++) {
      for (int at = 0; at + size <= letters.length; at++) {
        terms.add(letters.sublist(at, at + size).join());
      }
    }
  }
  return terms.toList();
}

final RegExp _latin = RegExp(r'[a-z][a-z0-9]*');
final RegExp _han = RegExp(r'[㐀-鿿]+');

/// English words that appear in every document and mean nothing here.
const Set<String> _tooCommon = <String>{
  'the',
  'and',
  'for',
  'are',
  'was',
  'how',
  'what',
  'when',
  'why',
  'does',
  'this',
  'that',
  'with',
  'from',
  'have',
  'has',
  'long',
  'much',
  'many',
  'you',
  'your',
  'its',
  'their',
  'not',
  'but',
  'can',
  'will',
  'shall',
};
