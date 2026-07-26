import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/main.dart' as app;
import 'package:local_agent_macos/performance/empty_shell_frame_budget.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('measures empty-shell engine frame timings in profile mode', (
    WidgetTester tester,
  ) async {
    final List<FrameTiming> frameTimings = <FrameTiming>[];
    final TimingsCallback timingCallback = frameTimings.addAll;
    binding.addTimingsCallback(timingCallback);
    addTearDown(() => binding.removeTimingsCallback(timingCallback));

    app.main();
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 2));

    final Map<String, Object?> report = Map<String, Object?>.from(
      FrameTimingSummarizer(frameTimings).summary,
    );
    final FrameTimingEvaluation evaluation = evaluateFrameTimingReport(report);
    binding.reportData = <String, dynamic>{
      'empty_shell_frames': report,
      'empty_shell_frame_evaluation': evaluation.toJson(),
    };

    expect(evaluation.hasFrameMeasurements, isTrue);
    expect(evaluation.meetsCp0PerStageGate, isTrue);
  });
}
