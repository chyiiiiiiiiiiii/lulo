import 'dart:async';
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
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

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

  testWidgets(
    'records raw presence build and raster timings by state',
    (WidgetTester tester) async {
      final Duration warmup = _isSmoke ? _smokeWarmup : _profileWarmup;
      final Duration stateDuration = _isSmoke
          ? _smokeStateDuration
          : _profileStateDuration;
      final AgentPresenceController controller = AgentPresenceController();
      final Stopwatch clock = Stopwatch()..start();
      final GlobalKey<_ProfileHarnessState> harnessKey =
          GlobalKey<_ProfileHarnessState>();
      AgentPresenceRenderingPath renderingPath =
          AgentPresenceRenderingPath.loading;
      final Completer<AgentPresenceRenderingPath> shaderReadiness =
          Completer<AgentPresenceRenderingPath>();
      addTearDown(() {
        clock.stop();
        controller.dispose();
      });

      final _ProfileHarness harness = _ProfileHarness(
        key: harnessKey,
        controller: controller,
        onRenderingPathChanged: (AgentPresenceRenderingPath path) {
          renderingPath = path;
          if (path != AgentPresenceRenderingPath.loading &&
              !shaderReadiness.isCompleted) {
            shaderReadiness.complete(path);
          }
        },
      );
      runApp(harness);
      debugPrint('presence_profile_stage=widget_attached');
      await tester.runAsync(
        () => shaderReadiness.future.timeout(const Duration(seconds: 5)),
      );
      await tester.runAsync(() => Future<void>.delayed(warmup));
      debugPrint('presence_profile_stage=warmup_complete');

      expect(
        renderingPath,
        AgentPresenceRenderingPath.loadedShader,
        reason: 'Hardware evidence requires the loaded FragmentProgram path.',
      );

      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final List<AgentPresenceRawFrameSample> rawFrames =
          <AgentPresenceRawFrameSample>[];
      final _FrameBoundaryCapture boundaryCapture = _FrameBoundaryCapture();
      void timingCallback(List<FrameTiming> timings) {
        final List<FrameTiming> orderedTimings = List<FrameTiming>.of(timings)
          ..sort(
            (FrameTiming left, FrameTiming right) => left
                .timestampInMicroseconds(FramePhase.buildStart)
                .compareTo(
                  right.timestampInMicroseconds(FramePhase.buildStart),
                ),
          );
        boundaryCapture.accept(orderedTimings);
        for (final FrameTiming timing in orderedTimings) {
          rawFrames.add(
            AgentPresenceRawFrameSample(
              timestampMicros: timing.timestampInMicroseconds(
                FramePhase.buildStart,
              ),
              buildMicros: timing.buildDuration.inMicroseconds,
              rasterMicros: timing.rasterDuration.inMicroseconds,
            ),
          );
        }
      }

      binding.addTimingsCallback(timingCallback);
      addTearDown(() => binding.removeTimingsCallback(timingCallback));

      final List<({String state, int startMicros})> stateStarts =
          <({String state, int startMicros})>[];
      for (final AgentPresenceState state in AgentPresenceState.values) {
        _dispatchState(controller, state, clock.elapsed);
        debugPrint('presence_profile_stage=${state.name}_boundary_wait');
        final int startMicros = await boundaryCapture.next(binding);
        debugPrint('presence_profile_stage=${state.name}_boundary_ready');
        stateStarts.add((state: state.name, startMicros: startMicros));
        final Future<void> heldState = tester.runAsync(
          () => _holdState(
            controller: controller,
            state: state,
            clock: clock,
            duration: stateDuration,
          ),
        );
        await _drainTimingBoundary();
        await heldState;
        debugPrint('presence_profile_stage=${state.name}_held');
      }
      debugPrint('presence_profile_stage=end_boundary_wait');
      final int measurementEndMicros = await boundaryCapture.next(binding);
      harnessKey.currentState!.stopFrameDriver();
      debugPrint('presence_profile_stage=frame_driver_stopped');
      await _drainTimingCallbacks();
      debugPrint('presence_profile_stage=timings_drained');

      final List<AgentPresenceFrameWindow> windows = <AgentPresenceFrameWindow>[
        for (var index = 0; index < stateStarts.length; index += 1)
          AgentPresenceFrameWindow(
            state: stateStarts[index].state,
            startMicrosInclusive: stateStarts[index].startMicros,
            endMicrosExclusive: index + 1 < stateStarts.length
                ? stateStarts[index + 1].startMicros
                : measurementEndMicros,
          ),
      ];
      final AgentPresenceFrameAttribution attribution =
          attributeAgentPresenceFrameSamples(
            windows: windows,
            frames: rawFrames,
          );
      final int framesInsideMeasurement = rawFrames
          .where(
            (AgentPresenceRawFrameSample frame) =>
                frame.timestampMicros >= windows.first.startMicrosInclusive &&
                frame.timestampMicros < windows.last.endMicrosExclusive,
          )
          .length;

      expect(renderingPath, AgentPresenceRenderingPath.loadedShader);
      expect(attribution.assignedFrameCount, framesInsideMeasurement);
      final FlutterView view =
          WidgetsBinding.instance.platformDispatcher.views.single;
      final Map<String, Object?> report = <String, Object?>{
        'schema_version': 1,
        'evidence_kind': _isSmoke ? 'smoke' : 'hardware_profile',
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
          'physical_display_resolution': const String.fromEnvironment(
            'PRESENCE_PHYSICAL_DISPLAY_RESOLUTION',
            defaultValue: 'unknown',
          ),
          'test_surface_resolution':
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
          'shader_path':
              renderingPath == AgentPresenceRenderingPath.loadedShader
              ? 'fragmentProgram'
              : 'fallback',
          'shader_compile_ready':
              renderingPath == AgentPresenceRenderingPath.loadedShader,
          'frame_stage_scope': 'Flutter build/raster only',
          'still_state_frame_driver': 'cached 1px CustomPainter',
        },
        'states': <Object?>[
          for (final AgentPresenceFrameWindow window in windows)
            serializeAgentPresenceStateFrames(
              window: window,
              frames: attribution.framesFor(window.state),
            ),
        ],
        'attribution': <String, Object?>{
          'timestamp_phase': 'buildStart',
          'window_policy': 'startInclusive_endExclusive',
          'assigned_frame_count': attribution.assignedFrameCount,
          'unassigned_frame_count': attribution.unassignedFrameCount,
        },
      };
      final AgentPresenceFrameEvaluation evaluation =
          evaluateAgentPresenceFrameReport(report);
      binding.reportData = <String, dynamic>{
        'agent_presence_frame_report': report,
        'agent_presence_frame_evaluation': evaluation.toJson(),
      };
      debugPrint('presence_profile_stage=report_ready');

      expect(
        windows.every(
          (AgentPresenceFrameWindow window) =>
              attribution.framesFor(window.state).isNotEmpty,
        ),
        isTrue,
        reason: 'Every state must collect raw engine timing samples.',
      );

      debugPrint('presence_profile_stage=before_unmount_pump');
      runApp(const SizedBox.shrink());
      debugPrint('presence_profile_stage=after_unmount_pump');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      debugPrint('presence_profile_stage=body_complete');
      report['harness_completion_stage'] = 'complete';
    },
    timeout: Timeout(
      _isSmoke ? const Duration(seconds: 20) : const Duration(seconds: 90),
    ),
  );
}

Future<void> _drainTimingBoundary() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Future<void> _drainTimingCallbacks() =>
    Future<void>.delayed(const Duration(milliseconds: 250));

final class _FrameBoundaryCapture {
  Completer<int>? _pendingBoundary;
  int _timestampFloorMicros = -1;

  Future<int> next(IntegrationTestWidgetsFlutterBinding binding) {
    if (_pendingBoundary != null) {
      throw StateError('A frame boundary request is already pending.');
    }
    _timestampFloorMicros = binding.currentSystemFrameTimeStamp.inMicroseconds;
    final Completer<int> boundary = Completer<int>();
    _pendingBoundary = boundary;
    binding.scheduleFrame();
    return boundary.future.timeout(const Duration(seconds: 2));
  }

  void accept(List<FrameTiming> timings) {
    final Completer<int>? boundary = _pendingBoundary;
    if (boundary == null) {
      return;
    }
    for (final FrameTiming timing in timings) {
      final int timestampMicros = timing.timestampInMicroseconds(
        FramePhase.buildStart,
      );
      if (timestampMicros <= _timestampFloorMicros) {
        continue;
      }
      _pendingBoundary = null;
      boundary.complete(timestampMicros);
      return;
    }
  }
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

final class _ProfileHarness extends StatefulWidget {
  const _ProfileHarness({
    required this.controller,
    required this.onRenderingPathChanged,
    super.key,
  });

  final AgentPresenceController controller;
  final ValueChanged<AgentPresenceRenderingPath> onRenderingPathChanged;

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

  void stopFrameDriver() {
    _framePump.stop();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xff111318),
        body: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CustomPaint(
              size: const Size.square(1),
              painter: _BenchmarkFrameDriverPainter(repaint: _framePump),
            ),
            AgentPresenceOrb(
              controller: widget.controller,
              onRenderingPathChanged: widget.onRenderingPathChanged,
            ),
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
