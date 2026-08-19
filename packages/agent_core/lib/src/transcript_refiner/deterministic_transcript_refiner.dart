import 'package:characters/characters.dart';

import '../agent_profile/misheard_word.dart';
import '../voice/heard_confidence.dart';
import 'transcript_refinement.dart';

/// Fast production refiner limited to whitespace and configured token casing.
final class DeterministicTranscriptRefiner implements TranscriptRefiner {
  /// Creates the stateless deterministic refiner.
  const DeterministicTranscriptRefiner();

  static const String _id = 'lulo-deterministic-refiner';
  static const String _version = '1';

  @override
  Future<TranscriptRefinement> refine(
    TranscriptRefinementRequest request,
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final String whitespace = _normalizeWhitespace(request.rawTranscript);
    final String cased = _correctVocabulary(
      whitespace,
      request.protectedVocabulary,
    );
    final String repaired = _repairNearMisses(cased, request);
    // Corrections run last, and the first version had this backwards. A
    // correction is what a person said this transcript should have been, so
    // nothing may rewrite it afterwards — with the casing pass second, a
    // term typed into the vocabulary list in the wrong case quietly undid a
    // correction whose whole point was exact restoration. Matching ignores
    // case, so running after the casing pass costs the correction nothing.
    final String corrected = applyMisheardWords(repaired, request.misheard);
    // Again, because a correction may remove words: deleting one leaves the
    // gap on either side of it, and the first pass ran before the deletion
    // existed. Idempotent on text that needs nothing.
    final String selected = _normalizeWhitespace(corrected);
    stopwatch.stop();
    if (selected == request.rawTranscript) {
      return TranscriptRefinement(
        rawTranscript: request.rawTranscript,
        proposedTranscript: null,
        selectedTranscript: request.rawTranscript,
        status: TranscriptRefinementStatus.unchanged,
        edits: const <TranscriptEdit>[],
        rejectionReasons: const <TranscriptRejectionReason>[],
        refinerId: _id,
        refinerVersion: _version,
        elapsed: stopwatch.elapsed,
      );
    }
    // Named for the most specific thing that survived into what is stored,
    // not for the most specific pass that ran. A correction whose only
    // effect was to undo the casing pass leaves a transcript differing from
    // the raw one in spacing alone, and calling that a correction is a
    // wrong label written durably.
    final TranscriptEditKind kind = selected != repaired
        ? TranscriptEditKind.correction
        : repaired != whitespace
        ? TranscriptEditKind.vocabulary
        : TranscriptEditKind.whitespace;
    return TranscriptRefinement(
      rawTranscript: request.rawTranscript,
      proposedTranscript: selected,
      selectedTranscript: selected,
      status: TranscriptRefinementStatus.applied,
      edits: <TranscriptEdit>[
        TranscriptEdit(
          rawStart: 0,
          rawEnd: request.rawTranscript.characters.length,
          replacement: selected,
          kind: kind,
        ),
      ],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: _id,
      refinerVersion: _version,
      elapsed: stopwatch.elapsed,
    );
  }
}

String _normalizeWhitespace(String text) {
  final String collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return collapsed
      .replaceAllMapped(
        RegExp(r'([\u3400-\u9fff]) ([\u3400-\u9fff])'),
        (Match match) => '${match.group(1)}${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'([\u3400-\u9fff]) ([\u3400-\u9fff])'),
        (Match match) => '${match.group(1)}${match.group(2)}',
      );
}

String _correctVocabulary(String text, List<String> vocabulary) {
  final Map<String, String?> canonical = <String, String?>{};
  for (final String value in vocabulary) {
    if (!_latinToken.hasMatch(value)) {
      continue;
    }
    final String key = value.toLowerCase();
    final String? existing = canonical[key];
    canonical[key] = existing == null || existing == value ? value : '';
  }
  return text.replaceAllMapped(_latinToken, (Match match) {
    final String original = match.group(0)!;
    final String? replacement = canonical[original.toLowerCase()];
    return replacement == null || replacement.isEmpty ? original : replacement;
  });
}

/// Restores a protected term the recogniser almost wrote: Flater for
/// Flutter, NLX for MLX.
///
/// Bounded on purpose, because the LLM alternative was measured making the
/// transcript worse (`benchmarks/voice_eval/evidence/qwen-refiner-shadow`):
/// this pass can only restore a spelling from the protected list, and only
/// when three things line up. The recogniser doubted the sentence — correct
/// words score 0.88–1.00 and errors 0.78 or below, so a confident dark mode
/// must not become Dart beside a vocabulary that lists it. The sentence
/// contains CJK — the measured near-miss errors are zh code-switching, and
/// in an English sentence a word near the vocabulary is usually an English
/// word. And the token sits within one edit of the term (two for terms of
/// six letters or more, so Flater still reaches Flutter) with a unique
/// nearest term — codex stays codex two edits from Xcode, and a token torn
/// between two terms stays as heard.
String _repairNearMisses(String text, TranscriptRefinementRequest request) {
  if (!HeardConfidence.isDoubtful(request.heardConfidence)) {
    return text;
  }
  if (!_cjk.hasMatch(text)) {
    return text;
  }
  final List<String> terms = request.protectedVocabulary
      .where(
        (String term) => _latinToken.matchAsPrefix(term)?.end == term.length,
      )
      .toList();
  if (terms.isEmpty) {
    return text;
  }
  final Set<String> exact = terms
      .map((String term) => term.toLowerCase())
      .toSet();
  // A word the user has taught a correction for belongs to that correction,
  // which runs later and matches on what was heard: repairing it here would
  // erase the very text the correction looks for.
  final Set<String> taught = <String>{
    for (final MisheardWord word in request.misheard)
      for (final Match match in _latinToken.allMatches(word.heard))
        match.group(0)!.toLowerCase(),
  };
  return text.replaceAllMapped(_latinToken, (Match match) {
    final String token = match.group(0)!;
    final String lower = token.toLowerCase();
    if (token.length < 3 || exact.contains(lower) || taught.contains(lower)) {
      return token;
    }
    String? nearest;
    int nearestDistance = 0;
    bool tied = false;
    for (final String term in terms) {
      final int allowed = term.length >= 6 ? 2 : 1;
      final int distance = _levenshtein(lower, term.toLowerCase());
      if (distance == 0 || distance > allowed) {
        continue;
      }
      if (nearest == null || distance < nearestDistance) {
        nearest = term;
        nearestDistance = distance;
        tied = false;
      } else if (distance == nearestDistance) {
        tied = true;
      }
    }
    return nearest == null || tied ? token : nearest;
  });
}

int _levenshtein(String a, String b) {
  List<int> previous = List<int>.generate(b.length + 1, (int i) => i);
  for (int i = 0; i < a.length; i++) {
    final List<int> current = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final int substitution = previous[j] + (a[i] == b[j] ? 0 : 1);
      current[j + 1] = [
        substitution,
        previous[j + 1] + 1,
        current[j] + 1,
      ].reduce((int x, int y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}

final RegExp _cjk = RegExp(r'[㐀-鿿]');
final RegExp _latinToken = RegExp(r'[A-Za-z][A-Za-z0-9+._-]*');
