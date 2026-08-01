import 'package:characters/characters.dart';

import 'text_normalizer.dart';

/// Character-edit metrics for one normalized transcript pair.
final class TranscriptScore {
  /// Creates a complete edit score.
  const TranscriptScore({
    required this.referenceLength,
    required this.candidateLength,
    required this.substitutions,
    required this.deletions,
    required this.insertions,
    required this.cer,
  });

  /// Grapheme count of the reference.
  final int referenceLength;

  /// Grapheme count of the candidate.
  final int candidateLength;

  /// Replacement operations in the deterministic minimum edit path.
  final int substitutions;

  /// Reference graphemes absent from the candidate.
  final int deletions;

  /// Candidate graphemes absent from the reference.
  final int insertions;

  /// Character error rate under the documented empty-reference policy.
  final double cer;

  /// Total Levenshtein edit distance.
  int get distance => substitutions + deletions + insertions;
}

/// Literal and spoken-content scores for one candidate transcript.
final class NormalizedTranscriptScore {
  /// Creates both normalization views.
  const NormalizedTranscriptScore({
    required this.literal,
    required this.spoken,
  });

  /// Score with punctuation and Latin case retained.
  final TranscriptScore literal;

  /// Score with punctuation, whitespace, and Latin case ignored.
  final TranscriptScore spoken;
}

/// Keeps raw evidence beside an optional independently scored refinement.
final class TranscriptComparison {
  /// Creates an immutable transcript comparison.
  const TranscriptComparison({
    required this.rawTranscript,
    required this.refinedTranscript,
    required this.raw,
    required this.refined,
  });

  /// Original adapter output, never replaced by refinement.
  final String rawTranscript;

  /// Optional refined output.
  final String? refinedTranscript;

  /// Scores for [rawTranscript].
  final NormalizedTranscriptScore raw;

  /// Scores for [refinedTranscript], when present.
  final NormalizedTranscriptScore? refined;
}

/// Scores one string using Unicode grapheme clusters.
TranscriptScore scoreTranscript({
  required String reference,
  required String candidate,
}) {
  final List<String> expected = reference.characters.toList(growable: false);
  final List<String> actual = candidate.characters.toList(growable: false);
  final List<List<_EditCell>> rows = List<List<_EditCell>>.generate(
    expected.length + 1,
    (int index) => List<_EditCell>.filled(
      actual.length + 1,
      const _EditCell.zero(),
      growable: false,
    ),
    growable: false,
  );
  for (int i = 1; i <= expected.length; i += 1) {
    rows[i][0] = _EditCell(cost: i, deletions: i);
  }
  for (int j = 1; j <= actual.length; j += 1) {
    rows[0][j] = _EditCell(cost: j, insertions: j);
  }
  for (int i = 1; i <= expected.length; i += 1) {
    for (int j = 1; j <= actual.length; j += 1) {
      if (expected[i - 1] == actual[j - 1]) {
        rows[i][j] = rows[i - 1][j - 1];
        continue;
      }
      final List<_EditCell> choices = <_EditCell>[
        rows[i - 1][j - 1].substitute(),
        rows[i - 1][j].delete(),
        rows[i][j - 1].insert(),
      ];
      rows[i][j] = choices.reduce(
        (_EditCell best, _EditCell next) => next.cost < best.cost ? next : best,
      );
    }
  }
  final _EditCell result = rows.last.last;
  final double cer = expected.isEmpty
      ? (actual.isEmpty ? 0 : 1)
      : result.cost / expected.length;
  return TranscriptScore(
    referenceLength: expected.length,
    candidateLength: actual.length,
    substitutions: result.substitutions,
    deletions: result.deletions,
    insertions: result.insertions,
    cer: cer,
  );
}

/// Scores raw and optional refined text without mutating either value.
TranscriptComparison compareTranscripts({
  required String reference,
  required String rawTranscript,
  String? refinedTranscript,
}) => TranscriptComparison(
  rawTranscript: rawTranscript,
  refinedTranscript: refinedTranscript,
  raw: _scoreBoth(reference, rawTranscript),
  refined: refinedTranscript == null
      ? null
      : _scoreBoth(reference, refinedTranscript),
);

NormalizedTranscriptScore _scoreBoth(String reference, String candidate) =>
    NormalizedTranscriptScore(
      literal: scoreTranscript(
        reference: normalizeLiteral(reference),
        candidate: normalizeLiteral(candidate),
      ),
      spoken: scoreTranscript(
        reference: normalizeSpoken(reference),
        candidate: normalizeSpoken(candidate),
      ),
    );

final class _EditCell {
  const _EditCell({
    required this.cost,
    this.substitutions = 0,
    this.deletions = 0,
    this.insertions = 0,
  });

  const _EditCell.zero()
    : cost = 0,
      substitutions = 0,
      deletions = 0,
      insertions = 0;

  final int cost;
  final int substitutions;
  final int deletions;
  final int insertions;

  _EditCell substitute() => _EditCell(
    cost: cost + 1,
    substitutions: substitutions + 1,
    deletions: deletions,
    insertions: insertions,
  );

  _EditCell delete() => _EditCell(
    cost: cost + 1,
    substitutions: substitutions,
    deletions: deletions + 1,
    insertions: insertions,
  );

  _EditCell insert() => _EditCell(
    cost: cost + 1,
    substitutions: substitutions,
    deletions: deletions,
    insertions: insertions + 1,
  );
}
