import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/transition_frame_probe.dart';

FrameTiming _frame({required int buildMicros, required int rasterMicros}) {
  const int vsync = 1000;
  return FrameTiming(
    vsyncStart: vsync,
    buildStart: vsync,
    buildFinish: vsync + buildMicros,
    rasterStart: vsync + buildMicros,
    rasterFinish: vsync + buildMicros + rasterMicros,
    rasterFinishWallTime: vsync + buildMicros + rasterMicros,
    frameNumber: 1,
  );
}

void main() {
  test('describes a transition by its worst moments, not its average', () {
    // Jank is felt at the p95 and the worst frame; an average buries both.
    final List<FrameTiming> timings = <FrameTiming>[
      for (int i = 0; i < 19; i++)
        _frame(buildMicros: 2000, rasterMicros: 4000),
      _frame(buildMicros: 3000, rasterMicros: 30000),
    ];

    final String report = TransitionFrameProbe.describe('collapse', timings);

    expect(report, contains('collapse'));
    expect(report, contains('20 frames'));
    expect(report, contains('worst 33.0ms'));
    // One frame of twenty runs past the 120Hz budget.
    expect(report, contains('1 over 8.3ms'));
  });

  test('an empty transition says so instead of dividing by zero', () {
    expect(
      TransitionFrameProbe.describe('expand', const <FrameTiming>[]),
      contains('no frames'),
    );
  });

  test('reports totals per stage so the guilty thread is named', () {
    final List<FrameTiming> timings = <FrameTiming>[
      _frame(buildMicros: 12000, rasterMicros: 1000),
      _frame(buildMicros: 1000, rasterMicros: 12000),
    ];

    final String report = TransitionFrameProbe.describe('expand', timings);

    expect(report, contains('build p95 12.0ms'));
    expect(report, contains('raster p95 12.0ms'));
  });
}
