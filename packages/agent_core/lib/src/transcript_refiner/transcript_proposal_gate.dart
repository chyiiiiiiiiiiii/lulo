import 'package:characters/characters.dart';

import 'transcript_refinement.dart';

/// Privacy-safe outcome of evaluating one proposed transcript.
final class TranscriptProposalDecision {
  /// Creates an immutable gate decision.
  TranscriptProposalDecision({
    required this.accepted,
    required List<TranscriptRejectionReason> rejectionReasons,
  }) : rejectionReasons = List<TranscriptRejectionReason>.unmodifiable(
         rejectionReasons,
       );

  /// Whether the proposal may be selected.
  final bool accepted;

  /// Categories that prevented selection, without token values.
  final List<TranscriptRejectionReason> rejectionReasons;

  @override
  String toString() =>
      'TranscriptProposalDecision(accepted: $accepted, '
      'rejectionReasons: ${rejectionReasons.map((value) => value.name).toList()})';
}

/// Rejects meaning-risking transcript proposals before selection.
final class TranscriptProposalGate {
  /// Creates the stateless gate.
  const TranscriptProposalGate({this.maximumEditRatio = 0.20});

  /// Maximum allowed grapheme edit distance divided by raw length.
  final double maximumEditRatio;

  /// Evaluates protected evidence and edit distance.
  TranscriptProposalDecision evaluate({
    required String raw,
    required String proposal,
    required List<String> protectedVocabulary,
  }) {
    final List<TranscriptRejectionReason> reasons =
        <TranscriptRejectionReason>[];
    if (raw.isNotEmpty && proposal.trim().isEmpty) {
      reasons.add(TranscriptRejectionReason.emptyProposal);
    }
    _compare(
      raw,
      proposal,
      _number,
      TranscriptRejectionReason.protectedNumberChanged,
      reasons,
    );
    _compare(
      raw,
      proposal,
      _negation,
      TranscriptRejectionReason.negationChanged,
      reasons,
    );
    _compare(
      raw,
      proposal,
      _url,
      TranscriptRejectionReason.urlChanged,
      reasons,
    );
    _compare(
      raw,
      proposal,
      _email,
      TranscriptRejectionReason.emailChanged,
      reasons,
    );
    final List<String> protected = protectedVocabulary
        .where(_latinFullMatch)
        .map((String value) => value.toLowerCase())
        .toSet()
        .toList(growable: false);
    final List<String> rawVocabulary = _latinToken
        .allMatches(raw)
        .map((Match value) => value.group(0)!.toLowerCase())
        .where(protected.contains)
        .toList(growable: false);
    final List<String> proposedVocabulary = _latinToken
        .allMatches(proposal)
        .map((Match value) => value.group(0)!.toLowerCase())
        .where(protected.contains)
        .toList(growable: false);
    if (!_same(rawVocabulary, proposedVocabulary)) {
      reasons.add(TranscriptRejectionReason.vocabularyChanged);
    }
    final int rawLength = raw.characters.length;
    final int distance = _distance(raw, proposal);
    final double ratio = rawLength == 0
        ? (proposal.isEmpty ? 0 : double.infinity)
        : distance / rawLength;
    if (ratio > maximumEditRatio) {
      reasons.add(TranscriptRejectionReason.excessiveChange);
    }
    final List<TranscriptRejectionReason> unique = reasons.toSet().toList();
    return TranscriptProposalDecision(
      accepted: unique.isEmpty,
      rejectionReasons: unique,
    );
  }
}

void _compare(
  String raw,
  String proposal,
  RegExp pattern,
  TranscriptRejectionReason reason,
  List<TranscriptRejectionReason> reasons,
) {
  final List<String> before = pattern
      .allMatches(raw)
      .map((Match value) => value.group(0)!.toLowerCase())
      .toList(growable: false);
  final List<String> after = pattern
      .allMatches(proposal)
      .map((Match value) => value.group(0)!.toLowerCase())
      .toList(growable: false);
  if (!_same(before, after)) {
    reasons.add(reason);
  }
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

int _distance(String raw, String proposal) {
  final List<String> a = raw.characters.toList(growable: false);
  final List<String> b = proposal.characters.toList(growable: false);
  List<int> previous = List<int>.generate(b.length + 1, (int index) => index);
  for (int row = 1; row <= a.length; row += 1) {
    final List<int> current = List<int>.filled(b.length + 1, 0)..[0] = row;
    for (int column = 1; column <= b.length; column += 1) {
      final int substitution =
          previous[column - 1] + (a[row - 1] == b[column - 1] ? 0 : 1);
      final int deletion = previous[column] + 1;
      final int insertion = current[column - 1] + 1;
      current[column] = <int>[
        substitution,
        deletion,
        insertion,
      ].reduce((int left, int right) => left < right ? left : right);
    }
    previous = current;
  }
  return previous.last;
}

bool _latinFullMatch(String value) =>
    _latinToken.firstMatch(value)?.group(0) == value;

final RegExp _number = RegExp(r'[0-9０-９]+(?:[.．:/：-][0-9０-９]+)*(?:[%％])?');
final RegExp _negation = RegExp(r'沒有|不是|不要|不|沒|別|未|無');
final RegExp _url = RegExp(r'https?://[^\s]+', caseSensitive: false);
final RegExp _email = RegExp(
  r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
  caseSensitive: false,
);
final RegExp _latinToken = RegExp(r'[A-Za-z][A-Za-z0-9+._-]*');
