import 'dart:math' as math;

const double _p95GateMillis = 8.33;
const double _p99GateMillis = 12;
const double _singleFrameHardGateMillis = 24;
const double _jankThresholdMillis = 16.67;
const double _maximumJankRatio = 0.01;
const double _minimumSampleCoverageRatio = 0.8;

const List<String> _states = <String>[
  'idle',
  'listening',
  'thinking',
  'speaking',
  'working',
  'error',
];

const List<String> _requiredMetadata = <String>[
  'renderer',
  'flutter_version',
  'dart_version',
  'build_mode',
  'macos_version',
  'device',
  'display_model',
  'display_refresh_hz',
  'display_resolution',
  'display_scale',
  'power_mode',
  'machine',
  'ambient_workload',
  'warmup_duration_ms',
  'state_duration_ms',
];

/// The two Flutter engine stages that must be measured independently.
enum AgentPresenceFrameStage {
  /// Flutter UI-thread build work.
  build,

  /// Flutter raster-thread work.
  raster,
}

/// Evaluates raw post-warmup presence samples without using widget timing.
AgentPresenceFrameEvaluation evaluateAgentPresenceFrameReport(
  Map<String, Object?> report,
) {
  final Map<String, Object?>? metadata = _stringMap(report['metadata']);
  final bool metadataComplete = _hasCompleteMetadata(metadata);
  final double? refreshRate = _positiveDouble(metadata?['display_refresh_hz']);
  final int? stateDurationMillis = _positiveInt(metadata?['state_duration_ms']);
  final int minimumSamples = refreshRate == null || stateDurationMillis == null
      ? 1
      : math.max(
          1,
          (refreshRate *
                  (stateDurationMillis / Duration.millisecondsPerSecond) *
                  _minimumSampleCoverageRatio)
              .ceil(),
        );

  final Map<String, Map<String, Object?>> statesByName =
      <String, Map<String, Object?>>{};
  final Object? rawStates = report['states'];
  if (rawStates is List<Object?>) {
    for (final Object? rawState in rawStates) {
      final Map<String, Object?>? state = _stringMap(rawState);
      final Object? name = state?['state'];
      if (name is String && _states.contains(name)) {
        statesByName[name] = state!;
      }
    }
  }

  final List<AgentPresenceStageEvaluation> stageEvaluations =
      <AgentPresenceStageEvaluation>[
        for (final String state in _states)
          for (final AgentPresenceFrameStage stage
              in AgentPresenceFrameStage.values)
            _evaluateStage(
              state: state,
              stage: stage,
              samples: _samples(
                statesByName[state]?[switch (stage) {
                  AgentPresenceFrameStage.build => 'build_times_micros',
                  AgentPresenceFrameStage.raster => 'raster_times_micros',
                }],
              ),
              minimumSamples: minimumSamples,
            ),
      ];

  return AgentPresenceFrameEvaluation(
    metadataComplete: metadataComplete,
    minimumSamplesPerStagePerState: minimumSamples,
    stageEvaluations: stageEvaluations,
    displayRefreshHz: refreshRate,
  );
}

/// Immutable result for the full six-state presence profile report.
final class AgentPresenceFrameEvaluation {
  /// Creates one complete report evaluation.
  const AgentPresenceFrameEvaluation({
    required this.metadataComplete,
    required this.minimumSamplesPerStagePerState,
    required this.stageEvaluations,
    required this.displayRefreshHz,
  });

  /// Whether all environment and measurement metadata is present and valid.
  final bool metadataComplete;

  /// Minimum raw samples required for each state and each engine stage.
  final int minimumSamplesPerStagePerState;

  /// Twelve independent results: build and raster for each of six states.
  final List<AgentPresenceStageEvaluation> stageEvaluations;

  /// Actual connected display cadence reported by Flutter, when valid.
  final double? displayRefreshHz;

  /// Whether every state and stage has enough post-warmup samples.
  bool get hasSufficientSamples => stageEvaluations.every(
    (AgentPresenceStageEvaluation stage) => stage.hasSufficientSamples,
  );

  /// Whether this report proves the approved raw frame-timing gates.
  bool get isAccepted =>
      metadataComplete &&
      hasSufficientSamples &&
      stageEvaluations.every(
        (AgentPresenceStageEvaluation stage) => stage.meetsTimingGates,
      );

  /// Finds one state/stage result without merging UI and raster samples.
  AgentPresenceStageEvaluation stageFor(
    String state,
    AgentPresenceFrameStage stage,
  ) {
    return stageEvaluations.singleWhere(
      (AgentPresenceStageEvaluation candidate) =>
          candidate.state == state && candidate.stage == stage,
    );
  }

  /// Converts the derived evaluation to machine-readable report data.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metadata_complete': metadataComplete,
      'minimum_samples_per_stage_per_state': minimumSamplesPerStagePerState,
      'has_sufficient_samples': hasSufficientSamples,
      'is_accepted': isAccepted,
      'display_refresh_hz': displayRefreshHz,
      'stages': <Object?>[
        for (final AgentPresenceStageEvaluation stage in stageEvaluations)
          stage.toJson(),
      ],
    };
  }
}

/// Derived metrics for one state and one Flutter engine stage.
final class AgentPresenceStageEvaluation {
  /// Creates a stage evaluation from raw, independently measured samples.
  const AgentPresenceStageEvaluation({
    required this.state,
    required this.stage,
    required this.count,
    required this.minimumSampleCount,
    required this.p95Millis,
    required this.p99Millis,
    required this.maximumMillis,
    required this.over16Point67Count,
  });

  /// Presence state attributed to these raw samples.
  final String state;

  /// Flutter engine stage attributed to these raw samples.
  final AgentPresenceFrameStage stage;

  /// Number of valid, raw post-warmup samples.
  final int count;

  /// Required sample count derived from measured duration and refresh rate.
  final int minimumSampleCount;

  /// Nearest-rank 95th percentile in milliseconds.
  final double? p95Millis;

  /// Nearest-rank 99th percentile in milliseconds.
  final double? p99Millis;

  /// Maximum sample duration in milliseconds.
  final double? maximumMillis;

  /// Count of raw samples strictly above the 16.67 ms jank threshold.
  final int over16Point67Count;

  /// Whether enough samples were retained after warmup for this stage.
  bool get hasSufficientSamples => count >= minimumSampleCount;

  /// Ratio of samples strictly above the 16.67 ms jank threshold.
  double get over16Point67Ratio => count == 0 ? 0 : over16Point67Count / count;

  /// Whether no raw sample exceeded the 24 ms hard guardrail.
  bool get hasNoSampleAbove24Millis =>
      maximumMillis != null && maximumMillis! <= _singleFrameHardGateMillis;

  /// Whether at most one percent of samples exceeded 16.67 ms.
  bool get hasAtMostOnePercentOver16Point67Millis =>
      count > 0 && over16Point67Ratio <= _maximumJankRatio;

  /// Whether all percentile, single-frame, jank, and coverage gates pass.
  bool get meetsTimingGates =>
      hasSufficientSamples &&
      p95Millis != null &&
      p95Millis! <= _p95GateMillis &&
      p99Millis != null &&
      p99Millis! <= _p99GateMillis &&
      hasNoSampleAbove24Millis &&
      hasAtMostOnePercentOver16Point67Millis;

  /// Converts this stage result to machine-readable report data.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state,
      'stage': stage.name,
      'count': count,
      'minimum_sample_count': minimumSampleCount,
      'p95_millis': p95Millis,
      'p99_millis': p99Millis,
      'maximum_millis': maximumMillis,
      'over_16_67_millis_count': over16Point67Count,
      'over_16_67_millis_ratio': over16Point67Ratio,
      'has_sufficient_samples': hasSufficientSamples,
      'meets_timing_gates': meetsTimingGates,
    };
  }
}

AgentPresenceStageEvaluation _evaluateStage({
  required String state,
  required AgentPresenceFrameStage stage,
  required List<int> samples,
  required int minimumSamples,
}) {
  final List<int> sorted = List<int>.of(samples)..sort();
  return AgentPresenceStageEvaluation(
    state: state,
    stage: stage,
    count: sorted.length,
    minimumSampleCount: minimumSamples,
    p95Millis: _nearestRankMicros(sorted, 0.95),
    p99Millis: _nearestRankMicros(sorted, 0.99),
    maximumMillis: sorted.isEmpty ? null : sorted.last / 1000,
    over16Point67Count: sorted
        .where((int sample) => sample > _jankThresholdMillis * 1000)
        .length,
  );
}

double? _nearestRankMicros(List<int> sortedSamples, double percentile) {
  if (sortedSamples.isEmpty) {
    return null;
  }
  final int index = (percentile * sortedSamples.length).ceil() - 1;
  return sortedSamples[index] / 1000;
}

List<int> _samples(Object? value) {
  if (value is! List<Object?>) {
    return const <int>[];
  }
  final List<int> samples = <int>[];
  for (final Object? sample in value) {
    if (sample is int && sample >= 0) {
      samples.add(sample);
    } else if (sample is num && sample.isFinite && sample >= 0) {
      samples.add(sample.round());
    } else {
      return const <int>[];
    }
  }
  return samples;
}

bool _hasCompleteMetadata(Map<String, Object?>? metadata) {
  if (metadata == null) {
    return false;
  }
  for (final String key in _requiredMetadata) {
    final Object? value = metadata[key];
    if (value == null || value is String && value.trim().isEmpty) {
      return false;
    }
  }
  final String? buildMode = metadata['build_mode'] as String?;
  if (buildMode != 'profile' && buildMode != 'release') {
    return false;
  }
  return _positiveDouble(metadata['display_refresh_hz']) != null &&
      _positiveDouble(metadata['display_scale']) != null &&
      _positiveInt(metadata['warmup_duration_ms']) != null &&
      _positiveInt(metadata['state_duration_ms']) != null;
}

Map<String, Object?>? _stringMap(Object? value) {
  return value is Map<String, Object?> ? value : null;
}

double? _positiveDouble(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) {
    return null;
  }
  return value.toDouble();
}

int? _positiveInt(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) {
    return null;
  }
  return value.round();
}
