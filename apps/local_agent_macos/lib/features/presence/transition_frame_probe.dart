import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Measures the frames of one change of form, and says what they cost.
///
/// The orb's steady states have a whole harness with hard gates
/// (`agent_presence_frame_metrics.dart`); the transition between forms had
/// nothing, and it is exactly where the jank was felt. This is the
/// instrument, not the gate: it watches the frames between `start` and
/// `stop` and logs their p95, their worst, and how many ran past the 120Hz
/// budget — numbers only, safe for a log that keeps conversations out.
final class TransitionFrameProbe {
  /// Frames at or under this fit a 120Hz display.
  static const double budgetMillis = 8.33;

  final List<FrameTiming> _timings = <FrameTiming>[];
  TimingsCallback? _listening;
  String _label = '';

  /// Starts collecting frames for the transition called [label].
  void start(String label) {
    stop();
    _label = label;
    _timings.clear();
    _listening = (List<FrameTiming> timings) => _timings.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(_listening!);
  }

  /// Stops collecting and logs what the transition cost.
  void stop() {
    final TimingsCallback? listening = _listening;
    if (listening == null) {
      return;
    }
    _listening = null;
    SchedulerBinding.instance.removeTimingsCallback(listening);
    debugPrint(describe(_label, _timings));
    _timings.clear();
  }

  /// The report for [timings], worded by its worst moments.
  ///
  /// Jank is felt at the p95 and at the single worst frame; an average
  /// buries both under the many cheap frames around them.
  static String describe(String label, List<FrameTiming> timings) {
    if (timings.isEmpty) {
      return 'Lulo frames: $label — no frames measured';
    }
    List<double> millis(Duration Function(FrameTiming) of) =>
        (timings.map((FrameTiming t) => of(t).inMicroseconds / 1000).toList()
          ..sort());
    final List<double> build = millis((FrameTiming t) => t.buildDuration);
    final List<double> raster = millis((FrameTiming t) => t.rasterDuration);
    final List<double> total = millis((FrameTiming t) => t.totalSpan);
    double p95(List<double> sorted) =>
        sorted[((sorted.length - 1) * 0.95).round()];
    final int over = total.where((double t) => t > budgetMillis).length;
    return 'Lulo frames: $label — ${timings.length} frames, '
        'build p95 ${p95(build).toStringAsFixed(1)}ms, '
        'raster p95 ${p95(raster).toStringAsFixed(1)}ms, '
        'worst ${total.last.toStringAsFixed(1)}ms, '
        '$over over ${budgetMillis.toStringAsFixed(1)}ms';
  }
}
