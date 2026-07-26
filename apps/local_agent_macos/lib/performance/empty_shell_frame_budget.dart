const double _cp0PerStageHardGateMillis = 12.0;

/// Evaluates Flutter engine frame statistics against the CP0 per-stage gate.
FrameTimingEvaluation evaluateFrameTimingReport(Map<String, Object?> report) {
  final int buildFrameCount = _frameCount(report['frame_build_times']);
  final int rasterFrameCount = _frameCount(report['frame_rasterizer_times']);
  final double? p99BuildMillis = _asDouble(
    report['99th_percentile_frame_build_time_millis'],
  );
  final double? p99RasterMillis = _asDouble(
    report['99th_percentile_frame_rasterizer_time_millis'],
  );

  return FrameTimingEvaluation(
    buildFrameCount: buildFrameCount,
    rasterFrameCount: rasterFrameCount,
    p99BuildMillis: p99BuildMillis,
    p99RasterMillis: p99RasterMillis,
  );
}

/// Immutable result of evaluating one profile-mode frame timing report.
final class FrameTimingEvaluation {
  /// Creates an evaluation from Flutter engine frame statistics.
  const FrameTimingEvaluation({
    required this.buildFrameCount,
    required this.rasterFrameCount,
    required this.p99BuildMillis,
    required this.p99RasterMillis,
  });

  /// Number of engine build-stage timing samples.
  final int buildFrameCount;

  /// Number of engine raster-stage timing samples.
  final int rasterFrameCount;

  /// Build-stage p99 timing in milliseconds, when reported by Flutter.
  final double? p99BuildMillis;

  /// Raster-stage p99 timing in milliseconds, when reported by Flutter.
  final double? p99RasterMillis;

  /// Whether both Flutter engine stages provided at least one timing sample.
  bool get hasFrameMeasurements =>
      buildFrameCount > 0 &&
      rasterFrameCount > 0 &&
      p99BuildMillis != null &&
      p99RasterMillis != null;

  /// Whether both measured stages satisfy the CP0 12 ms hard-gate guardrail.
  bool get meetsCp0PerStageGate =>
      hasFrameMeasurements &&
      p99BuildMillis! <= _cp0PerStageHardGateMillis &&
      p99RasterMillis! <= _cp0PerStageHardGateMillis;

  /// Converts the evaluation to machine-readable integration-test metadata.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'build_frame_count': buildFrameCount,
      'raster_frame_count': rasterFrameCount,
      'p99_build_millis': p99BuildMillis,
      'p99_raster_millis': p99RasterMillis,
      'cp0_per_stage_hard_gate_millis': _cp0PerStageHardGateMillis,
      'has_frame_measurements': hasFrameMeasurements,
      'meets_cp0_per_stage_gate': meetsCp0PerStageGate,
    };
  }
}

int _frameCount(Object? value) {
  return value is List<Object?> ? value.length : 0;
}

double? _asDouble(Object? value) {
  return value is num ? value.toDouble() : null;
}
