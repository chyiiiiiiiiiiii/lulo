import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_frame_metrics.dart';
import 'package:local_agent_macos/features/presence/agent_presence_orb.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

const bool _isSmoke = bool.fromEnvironment('PRESENCE_PROFILE_SMOKE');
const Duration _profileWarmup = Duration(seconds: 2);
const Duration _profileStateDuration = Duration(seconds: 10);
const Duration _smokeWarmup = Duration(milliseconds: 100);
const Duration _smokeStateDuration = Duration(milliseconds: 500);
const Duration _amplitudeInterval = Duration(microseconds: 33333);

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('records raw presence build and raster timings by state', (
    WidgetTester tester,
  ) async {
    final Duration warmup = _isSmoke ? _smokeWarmup : _profileWarmup;
    final Duration stateDuration = _isSmoke
        ? _smokeStateDuration
        : _profileStateDuration;
    final AgentPresenceController controller = AgentPresenceController();
    final Stopwatch clock = Stopwatch()..start();
    addTearDown(() {
      clock.stop();
      controller.dispose();
    });

    await tester.pumpWidget(_ProfileHarness(controller: controller));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(warmup));

    final Map<String, _RawStateSamples> samples = <String, _RawStateSamples>{
      for (final AgentPresenceState state in AgentPresenceState.values)
        state.name: _RawStateSamples(state.name),
    };
    String? activeState;
    void timingCallback(List<FrameTiming> timings) {
      final _RawStateSamples? bucket = samples[activeState];
      if (bucket == null) {
        return;
      }
      for (final FrameTiming timing in timings) {
        bucket.buildTimesMicros.add(timing.buildDuration.inMicroseconds);
        bucket.rasterTimesMicros.add(timing.rasterDuration.inMicroseconds);
      }
    }

    binding.addTimingsCallback(timingCallback);
    addTearDown(() => binding.removeTimingsCallback(timingCallback));

    for (final AgentPresenceState state in AgentPresenceState.values) {
      _dispatchState(controller, state, clock.elapsed);
      activeState = state.name;
      await tester.runAsync(
        () => _holdState(
          controller: controller,
          state: state,
          clock: clock,
          duration: stateDuration,
        ),
      );
      activeState = null;
    }
    final FlutterView view =
        WidgetsBinding.instance.platformDispatcher.views.single;
    final Map<String, Object?> report = <String, Object?>{
      'schema_version': 1,
      'evidence_kind': _isSmoke ? 'integration_smoke' : 'hardware_profile',
      'metadata': <String, Object?>{
        'renderer': const String.fromEnvironment(
          'PRESENCE_RENDERER',
          defaultValue: 'unknown',
        ),
        'flutter_version': const String.fromEnvironment(
          'PRESENCE_FLUTTER_VERSION',
          defaultValue: 'unknown',
        ),
        'dart_version': const String.fromEnvironment(
          'PRESENCE_DART_VERSION',
          defaultValue: 'unknown',
        ),
        'build_mode': _buildMode,
        'macos_version': Platform.operatingSystemVersion,
        'device': Platform.operatingSystem,
        'display_model': const String.fromEnvironment(
          'PRESENCE_DISPLAY_MODEL',
          defaultValue: 'unknown',
        ),
        'display_refresh_hz': view.display.refreshRate,
        'display_resolution':
            '${view.physicalSize.width.round()}x'
            '${view.physicalSize.height.round()}',
        'display_scale': view.devicePixelRatio,
        'power_mode': const String.fromEnvironment(
          'PRESENCE_POWER_MODE',
          defaultValue: 'unknown',
        ),
        'machine': const String.fromEnvironment(
          'PRESENCE_MACHINE',
          defaultValue: 'unknown',
        ),
        'ambient_workload': const String.fromEnvironment(
          'PRESENCE_AMBIENT_WORKLOAD',
          defaultValue: 'controlled, benchmark app foreground',
        ),
        'warmup_duration_ms': warmup.inMilliseconds,
        'state_duration_ms': stateDuration.inMilliseconds,
        'run_duration_ms':
            stateDuration.inMilliseconds * AgentPresenceState.values.length,
      },
      'states': <Object?>[
        for (final AgentPresenceState state in AgentPresenceState.values)
          samples[state.name]!.toJson(),
      ],
    };
    final AgentPresenceFrameEvaluation evaluation =
        evaluateAgentPresenceFrameReport(report);
    binding.reportData = <String, dynamic>{
      'agent_presence_frame_report': report,
      'agent_presence_frame_evaluation': evaluation.toJson(),
    };

    expect(samples.keys, hasLength(AgentPresenceState.values.length));
    expect(
      samples.values.every(
        (_RawStateSamples value) =>
            value.buildTimesMicros.length == value.rasterTimesMicros.length,
      ),
      isTrue,
    );
    expect(
      samples.values.every(
        (_RawStateSamples value) =>
            value.buildTimesMicros.isNotEmpty &&
            value.rasterTimesMicros.isNotEmpty,
      ),
      isTrue,
      reason: 'Every state must collect raw engine timing samples.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

String get _buildMode {
  if (kProfileMode) {
    return 'profile';
  }
  if (kReleaseMode) {
    return 'release';
  }
  return 'debug';
}

Future<void> _holdState({
  required AgentPresenceController controller,
  required AgentPresenceState state,
  required Stopwatch clock,
  required Duration duration,
}) async {
  if (state != AgentPresenceState.listening &&
      state != AgentPresenceState.speaking) {
    await Future<void>.delayed(duration);
    return;
  }

  final int sampleCount =
      (duration.inMicroseconds / _amplitudeInterval.inMicroseconds).floor();
  final Stopwatch window = Stopwatch()..start();
  for (var index = 0; index < sampleCount; index += 1) {
    final Duration target = _amplitudeInterval * (index + 1);
    final Duration remaining = target - window.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    final double phase = index * 2 * math.pi / 30;
    final double rms = 0.18 + 0.14 * math.sin(phase);
    controller.acceptAudioRms(rms, clock.elapsed);
  }
  final Duration remaining = duration - window.elapsed;
  if (remaining > Duration.zero) {
    await Future<void>.delayed(remaining);
  }
  window.stop();
}

void _dispatchState(
  AgentPresenceController controller,
  AgentPresenceState state,
  Duration now,
) {
  switch (state) {
    case AgentPresenceState.idle:
      controller.dispatch(AgentPresenceEvent.idleRequested, now);
    case AgentPresenceState.listening:
      controller.dispatch(AgentPresenceEvent.listeningStarted, now);
    case AgentPresenceState.thinking:
      controller.dispatch(AgentPresenceEvent.transcriptCommitted, now);
    case AgentPresenceState.speaking:
      controller.dispatch(AgentPresenceEvent.speechStarted, now);
    case AgentPresenceState.working:
      controller.dispatch(AgentPresenceEvent.workStarted, now);
    case AgentPresenceState.error:
      controller.dispatch(AgentPresenceEvent.failed, now);
  }
}

final class _RawStateSamples {
  _RawStateSamples(this.state);

  final String state;
  final List<int> buildTimesMicros = <int>[];
  final List<int> rasterTimesMicros = <int>[];

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state,
      'build_times_micros': buildTimesMicros,
      'raster_times_micros': rasterTimesMicros,
    };
  }
}

final class _ProfileHarness extends StatefulWidget {
  const _ProfileHarness({required this.controller});

  final AgentPresenceController controller;

  @override
  State<_ProfileHarness> createState() => _ProfileHarnessState();
}

final class _ProfileHarnessState extends State<_ProfileHarness>
    with SingleTickerProviderStateMixin {
  late final AnimationController _framePump;

  @override
  void initState() {
    super.initState();
    _framePump = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _framePump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xff111318),
        body: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CustomPaint(
              size: const Size.square(1),
              painter: _BenchmarkFrameDriverPainter(repaint: _framePump),
            ),
            AgentPresenceOrb(controller: widget.controller),
          ],
        ),
      ),
    );
  }
}

final class _BenchmarkFrameDriverPainter extends CustomPainter {
  _BenchmarkFrameDriverPainter({required super.repaint});

  final Paint _paint = Paint()..color = const Color(0xff111318);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(_BenchmarkFrameDriverPainter oldDelegate) => false;
}
