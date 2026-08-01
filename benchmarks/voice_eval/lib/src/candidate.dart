import 'turn_metrics.dart';

/// Candidate artifact family.
enum CandidateKind {
  /// ASR and optional refinement output.
  transcript,

  /// Baseline and shadow endpoint evidence.
  turn,

  /// Rendered speech timing evidence.
  tts,
}

/// Name and version of the producer under evaluation.
final class CandidateAdapter {
  /// Creates an adapter identity.
  const CandidateAdapter({required this.name, required this.version});

  /// Stable adapter name.
  final String name;

  /// Model, operating-system, or implementation version.
  final String version;
}

/// One timestamped volatile transcript.
final class PartialTranscriptEvent {
  /// Creates a partial transcript event.
  const PartialTranscriptEvent({required this.atMs, required this.text});

  /// Monotonic milliseconds from source-audio start.
  final int atMs;

  /// Raw partial text.
  final String text;
}

/// Common identity for one candidate case.
sealed class CandidateCase {
  /// Creates a candidate case.
  const CandidateCase({required this.caseId});

  /// Matching corpus case.
  final String caseId;
}

/// Raw and optional refined transcript evidence.
final class TranscriptCandidateCase extends CandidateCase {
  /// Creates transcript evidence.
  const TranscriptCandidateCase({
    required super.caseId,
    required this.rawTranscript,
    required this.refinedTranscript,
    required this.partialEvents,
    required this.finalAtMs,
  });

  /// Original ASR output.
  final String rawTranscript;

  /// Optional reversible refinement output.
  final String? refinedTranscript;

  /// Ordered volatile outputs.
  final List<PartialTranscriptEvent> partialEvents;

  /// Time the adapter declared the transcript final.
  final int finalAtMs;
}

/// Timestamp evidence for one endpoint candidate.
final class TurnCandidateCase extends CandidateCase {
  /// Creates endpoint evidence.
  const TurnCandidateCase({required super.caseId, required this.turn});

  /// Pure shadow candidate consumed by [scoreTurn].
  final TurnCandidate turn;
}

/// Timing and artifact evidence for one rendered utterance.
final class TtsCandidateCase extends CandidateCase {
  /// Creates TTS evidence.
  const TtsCandidateCase({
    required super.caseId,
    required this.text,
    required this.voice,
    required this.requestStartedAtMs,
    required this.firstAudioAtMs,
    required this.completedAtMs,
    required this.audioDurationMs,
    required this.audioPath,
  });

  /// Input text sent to the adapter.
  final String text;

  /// Requested voice identity.
  final String voice;

  /// Request start on the run's monotonic clock.
  final int requestStartedAtMs;

  /// First received audio on the same clock.
  final int firstAudioAtMs;

  /// Completed render on the same clock.
  final int completedAtMs;

  /// Duration of the rendered WAV.
  final int audioDurationMs;

  /// Relative path to the generated WAV within the run root.
  final String audioPath;
}

/// One validated producer run against a specific corpus.
final class CandidateRun {
  CandidateRun._({
    required this.schemaVersion,
    required this.kind,
    required this.runId,
    required this.adapter,
    required this.corpusId,
    required List<CandidateCase> cases,
  }) : cases = List<CandidateCase>.unmodifiable(cases);

  /// Decodes the kind-specific candidate envelope.
  factory CandidateRun.fromJson(
    Map<String, Object?> json, {
    required String source,
  }) {
    final String safeSource = _redactHome(source);
    final int schemaVersion = _field<int>(json, 'schemaVersion', safeSource);
    if (schemaVersion != 1) {
      throw FormatException('$safeSource: invalid schemaVersion');
    }
    final String rawKind = _nonEmpty(json, 'kind', safeSource);
    final CandidateKind kind = switch (rawKind) {
      'transcript' => CandidateKind.transcript,
      'turn' => CandidateKind.turn,
      'tts' => CandidateKind.tts,
      _ => throw FormatException('$safeSource: invalid kind'),
    };
    final Map<String, Object?> adapterJson = _map(json, 'adapter', safeSource);
    final CandidateAdapter adapter = CandidateAdapter(
      name: _nonEmpty(adapterJson, 'name', safeSource),
      version: _nonEmpty(adapterJson, 'version', safeSource),
    );
    final Object? rawCases = json['cases'];
    if (rawCases is! List<Object?>) {
      throw FormatException('$safeSource: invalid cases');
    }
    final List<CandidateCase> cases = <CandidateCase>[];
    final Set<String> caseIds = <String>{};
    for (final Object? value in rawCases) {
      if (value is! Map<String, Object?>) {
        throw FormatException('$safeSource: invalid case');
      }
      final String caseId = _nonEmpty(value, 'caseId', safeSource);
      if (!caseIds.add(caseId)) {
        throw FormatException('$safeSource: case $caseId: duplicate caseId');
      }
      cases.add(switch (kind) {
        CandidateKind.transcript => _decodeTranscript(
          value,
          safeSource,
          caseId,
        ),
        CandidateKind.turn => _decodeTurn(value, safeSource, caseId),
        CandidateKind.tts => _decodeTts(value, safeSource, caseId),
      });
    }
    return CandidateRun._(
      schemaVersion: schemaVersion,
      kind: kind,
      runId: _nonEmpty(json, 'runId', safeSource),
      adapter: adapter,
      corpusId: _nonEmpty(json, 'corpusId', safeSource),
      cases: cases,
    );
  }

  /// Candidate schema version.
  final int schemaVersion;

  /// Candidate artifact family.
  final CandidateKind kind;

  /// Stable run identity.
  final String runId;

  /// Producer name and version.
  final CandidateAdapter adapter;

  /// Corpus this evidence targets.
  final String corpusId;

  /// Validated kind-specific evidence.
  final List<CandidateCase> cases;

  /// Unique identity within a combined report.
  String get identity => '${kind.name}:$runId';
}

TranscriptCandidateCase _decodeTranscript(
  Map<String, Object?> json,
  String source,
  String caseId,
) {
  final Object? rawEvents = json['partialEvents'];
  if (rawEvents is! List<Object?>) {
    throw FormatException('$source: case $caseId: invalid partialEvents');
  }
  final List<PartialTranscriptEvent> events = <PartialTranscriptEvent>[];
  int previousAt = -1;
  for (final Object? value in rawEvents) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$source: case $caseId: invalid partialEvents');
    }
    final int atMs = _field<int>(value, 'atMs', source);
    if (atMs < previousAt) {
      throw FormatException('$source: case $caseId: invalid partialEvents');
    }
    previousAt = atMs;
    events.add(
      PartialTranscriptEvent(
        atMs: atMs,
        text: _field<String>(value, 'text', source),
      ),
    );
  }
  final Object? refined = json['refinedTranscript'];
  if (refined != null && refined is! String) {
    throw FormatException('$source: case $caseId: invalid refinedTranscript');
  }
  return TranscriptCandidateCase(
    caseId: caseId,
    rawTranscript: _field<String>(json, 'rawTranscript', source),
    refinedTranscript: refined as String?,
    partialEvents: List<PartialTranscriptEvent>.unmodifiable(events),
    finalAtMs: _field<int>(json, 'finalAtMs', source),
  );
}

TurnCandidateCase _decodeTurn(
  Map<String, Object?> json,
  String source,
  String caseId,
) {
  final Object? rawSegments = json['speechSegments'];
  if (rawSegments is! List<Object?>) {
    throw FormatException('$source: case $caseId: invalid speechSegments');
  }
  final List<SpeechSegment> segments = rawSegments
      .map((Object? value) {
        if (value is! Map<String, Object?>) {
          throw FormatException(
            '$source: case $caseId: invalid speechSegments',
          );
        }
        return SpeechSegment(
          startMs: _field<int>(value, 'startMs', source),
          endMs: _field<int>(value, 'endMs', source),
        );
      })
      .toList(growable: false);
  final Map<String, Object?> window = _map(
    json,
    'expectedSubmitWindowMs',
    source,
  );
  final Object? candidateAt = json['candidateSubmitAtMs'];
  if (candidateAt != null && candidateAt is! int) {
    throw FormatException('$source: case $caseId: invalid candidateSubmitAtMs');
  }
  try {
    return TurnCandidateCase(
      caseId: caseId,
      turn: TurnCandidate(
        caseId: caseId,
        speechSegments: segments,
        baselineSubmitAtMs: _field<int>(json, 'baselineSubmitAtMs', source),
        candidateSubmitAtMs: candidateAt as int?,
        expectedSubmitWindow: SubmitWindow(
          startMs: _field<int>(window, 'start', source),
          endMs: _field<int>(window, 'end', source),
        ),
      ),
    );
  } on ArgumentError {
    throw FormatException('$source: case $caseId: invalid turn timestamps');
  }
}

TtsCandidateCase _decodeTts(
  Map<String, Object?> json,
  String source,
  String caseId,
) {
  final String audioPath = _nonEmpty(json, 'audioPath', source);
  if (!RegExp(
    r'^artifacts/(?!.*(?:^|/)\.\.(?:/|$)).+\.wav$',
  ).hasMatch(audioPath)) {
    throw FormatException('$source: case $caseId: invalid audioPath');
  }
  return TtsCandidateCase(
    caseId: caseId,
    text: _field<String>(json, 'text', source),
    voice: _nonEmpty(json, 'voice', source),
    requestStartedAtMs: _field<int>(json, 'requestStartedAtMs', source),
    firstAudioAtMs: _field<int>(json, 'firstAudioAtMs', source),
    completedAtMs: _field<int>(json, 'completedAtMs', source),
    audioDurationMs: _field<int>(json, 'audioDurationMs', source),
    audioPath: audioPath,
  );
}

T _field<T>(Map<String, Object?> json, String name, String source) {
  final Object? value = json[name];
  if (value is! T) {
    throw FormatException('$source: invalid $name');
  }
  return value;
}

String _nonEmpty(Map<String, Object?> json, String name, String source) {
  final String value = _field<String>(json, name, source);
  if (value.trim().isEmpty) {
    throw FormatException('$source: invalid $name');
  }
  return value;
}

Map<String, Object?> _map(
  Map<String, Object?> json,
  String name,
  String source,
) {
  final Object? value = json[name];
  if (value is! Map<String, Object?>) {
    throw FormatException('$source: invalid $name');
  }
  return value;
}

String _redactHome(String source) =>
    source.replaceFirst(RegExp(r'^/Users/[^/]+/'), '~/');
