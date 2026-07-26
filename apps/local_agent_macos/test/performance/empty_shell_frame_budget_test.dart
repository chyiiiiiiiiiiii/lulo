import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/performance/empty_shell_frame_budget.dart';

void main() {
  test(
    'accepts non-empty build and raster measurements within the CP0 gate',
    () {
      final FrameTimingEvaluation evaluation = evaluateFrameTimingReport(
        <String, Object?>{
          'frame_build_times': <Object?>[1000, 2500],
          'frame_rasterizer_times': <Object?>[1200, 3000],
          '99th_percentile_frame_build_time_millis': 2.5,
          '99th_percentile_frame_rasterizer_time_millis': 3.0,
        },
      );

      expect(evaluation.hasFrameMeasurements, isTrue);
      expect(evaluation.meetsCp0PerStageGate, isTrue);
    },
  );

  test('rejects a report with no frame measurements', () {
    final FrameTimingEvaluation evaluation =
        evaluateFrameTimingReport(<String, Object?>{
          'frame_build_times': <Object?>[],
          'frame_rasterizer_times': <Object?>[],
          '99th_percentile_frame_build_time_millis': 0.0,
          '99th_percentile_frame_rasterizer_time_millis': 0.0,
        });

    expect(evaluation.hasFrameMeasurements, isFalse);
    expect(evaluation.meetsCp0PerStageGate, isFalse);
  });
}
