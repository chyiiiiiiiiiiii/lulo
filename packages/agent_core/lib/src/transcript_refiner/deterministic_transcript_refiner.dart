import 'package:characters/characters.dart';

import '../agent_profile/misheard_word.dart';
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
    // Corrections run last, and the first version had this backwards. A
    // correction is what a person said this transcript should have been, so
    // nothing may rewrite it afterwards — with the casing pass second, a
    // term typed into the vocabulary list in the wrong case quietly undid a
    // correction whose whole point was exact restoration. Matching ignores
    // case, so running after the casing pass costs the correction nothing.
    final String corrected = applyMisheardWords(cased, request.misheard);
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
    final TranscriptEditKind kind = selected != cased
        ? TranscriptEditKind.correction
        : cased != whitespace
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

final RegExp _latinToken = RegExp(r'[A-Za-z][A-Za-z0-9+._-]*');
