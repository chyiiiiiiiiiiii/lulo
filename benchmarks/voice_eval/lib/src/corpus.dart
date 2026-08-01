/// Whether private source audio is available to the evaluator.
enum AudioStatus {
  /// The referenced private WAV exists locally.
  available,

  /// The referenced private WAV is not present locally.
  missing,
}

/// One immutable Taiwan Mandarin evaluation case.
final class VoiceEvalCase {
  /// Creates a validated evaluation case.
  const VoiceEvalCase({
    required this.id,
    required this.category,
    required this.prompt,
    required this.expectedTranscript,
    required this.audioPath,
    required this.tags,
    required this.expectedPausesMs,
    required this.notes,
    required this.audioStatus,
  });

  /// Stable kebab-case identity across evaluation runs.
  final String id;

  /// Evaluation category used for grouped summaries.
  final String category;

  /// Synthetic script shown to the person recording this case.
  final String prompt;

  /// Human-verified reference transcript.
  final String expectedTranscript;

  /// Repository-relative private WAV path below `corpus/audio`.
  final String audioPath;

  /// Searchable scenario labels.
  final List<String> tags;

  /// Intended internal pauses measured from the script recording.
  final List<int> expectedPausesMs;

  /// Non-private explanation of what this case exercises.
  final String notes;

  /// Whether the private WAV was present when this corpus was loaded.
  final AudioStatus audioStatus;
}

/// A versioned, immutable collection of voice evaluation cases.
final class VoiceCorpus {
  VoiceCorpus._({
    required this.schemaVersion,
    required this.corpusId,
    required this.locale,
    required List<VoiceEvalCase> cases,
  }) : cases = List<VoiceEvalCase>.unmodifiable(cases);

  /// Decodes and validates a corpus without exposing corpus text in errors.
  factory VoiceCorpus.fromJson(
    Map<String, Object?> json, {
    required String source,
    bool Function(String relativePath)? audioExists,
  }) {
    final int schemaVersion = _required<int>(json, 'schemaVersion', source);
    if (schemaVersion != 1) {
      throw FormatException('$source: invalid schemaVersion');
    }
    final String corpusId = _nonEmpty(json, 'corpusId', source);
    final String locale = _nonEmpty(json, 'locale', source);
    final Object? rawCases = json['cases'];
    if (rawCases is! List<Object?>) {
      throw FormatException('$source: invalid cases');
    }

    final Set<String> ids = <String>{};
    final List<VoiceEvalCase> cases = <VoiceEvalCase>[];
    for (final Object? rawCase in rawCases) {
      if (rawCase is! Map<String, Object?>) {
        throw FormatException('$source: invalid case');
      }
      final String id = _nonEmpty(rawCase, 'id', source, caseId: 'unknown');
      if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) {
        throw FormatException('$source: case $id: invalid id');
      }
      if (!ids.add(id)) {
        throw FormatException('$source: case $id: duplicate id');
      }
      final String audioPath = _nonEmpty(
        rawCase,
        'audioPath',
        source,
        caseId: id,
      );
      if (!_safeAudioPath.hasMatch(audioPath)) {
        throw FormatException('$source: case $id: invalid audioPath');
      }
      final List<String> tags = _stringList(rawCase, 'tags', source, id);
      final List<int> expectedPausesMs = _intList(
        rawCase,
        'expectedPausesMs',
        source,
        id,
      );
      cases.add(
        VoiceEvalCase(
          id: id,
          category: _nonEmpty(rawCase, 'category', source, caseId: id),
          prompt: _nonEmpty(rawCase, 'prompt', source, caseId: id),
          expectedTranscript: _nonEmpty(
            rawCase,
            'expectedTranscript',
            source,
            caseId: id,
          ),
          audioPath: audioPath,
          tags: List<String>.unmodifiable(tags),
          expectedPausesMs: List<int>.unmodifiable(expectedPausesMs),
          notes: _required<String>(rawCase, 'notes', source, caseId: id),
          audioStatus: (audioExists?.call(audioPath) ?? false)
              ? AudioStatus.available
              : AudioStatus.missing,
        ),
      );
    }
    return VoiceCorpus._(
      schemaVersion: schemaVersion,
      corpusId: corpusId,
      locale: locale,
      cases: cases,
    );
  }

  /// Corpus schema version, currently `1`.
  final int schemaVersion;

  /// Stable identity shared by compatible candidate runs.
  final String corpusId;

  /// BCP-47 locale of the scripts and reference transcripts.
  final String locale;

  /// Validated cases in manifest order.
  final List<VoiceEvalCase> cases;
}

final RegExp _safeAudioPath = RegExp(
  r'^audio/[a-zA-Z0-9][a-zA-Z0-9._/-]*\.wav$',
);

T _required<T>(
  Map<String, Object?> json,
  String field,
  String source, {
  String? caseId,
}) {
  final Object? value = json[field];
  if (value is! T) {
    final String scope = caseId == null ? source : '$source: case $caseId';
    throw FormatException('$scope: invalid $field');
  }
  return value;
}

String _nonEmpty(
  Map<String, Object?> json,
  String field,
  String source, {
  String? caseId,
}) {
  final String value = _required<String>(json, field, source, caseId: caseId);
  if (value.trim().isEmpty) {
    final String scope = caseId == null ? source : '$source: case $caseId';
    throw FormatException('$scope: invalid $field');
  }
  return value;
}

List<String> _stringList(
  Map<String, Object?> json,
  String field,
  String source,
  String caseId,
) {
  final Object? value = json[field];
  if (value is! List<Object?> || value.any((Object? item) => item is! String)) {
    throw FormatException('$source: case $caseId: invalid $field');
  }
  return value.cast<String>();
}

List<int> _intList(
  Map<String, Object?> json,
  String field,
  String source,
  String caseId,
) {
  final Object? value = json[field];
  if (value is! List<Object?> ||
      value.any((Object? item) => item is! int || item < 0)) {
    throw FormatException('$source: case $caseId: invalid $field');
  }
  return value.cast<int>();
}
