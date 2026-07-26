import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_painter.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

void main() {
  test('uploads the documented uniform indices 0 through 12 in order', () {
    final _RecordingUniformSink sink = _RecordingUniformSink();
    final AgentPresenceSnapshot listening = const AgentPresenceReducer().reduce(
      const AgentPresenceSnapshot.idle(),
      event: AgentPresenceEvent.listeningStarted,
      now: Duration.zero,
    );
    final AgentPresenceVisualInput input = AgentPresenceVisualInput(
      snapshot: listening,
      amplitude: 0.375,
      sampledAt: const Duration(milliseconds: 90),
    );

    const AgentPresenceUniformBinder().write(
      sink,
      size: const Size(56, 48),
      visualInput: input,
      now: const Duration(milliseconds: 90),
      timeSeconds: 4098.25,
      motionEnabled: true,
      colorStrength: 0.72,
    );

    expect(sink.indices, <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    expect(sink.values, <double>[
      56,
      48,
      2.25,
      0.5,
      0.5,
      0,
      0,
      0,
      0,
      0.375,
      1,
      0.72,
      0.6180339887,
    ]);
  });

  test('reduced motion uploads a still phase with no audio deformation', () {
    final _RecordingUniformSink sink = _RecordingUniformSink();

    const AgentPresenceUniformBinder().write(
      sink,
      size: const Size.square(56),
      visualInput: const AgentPresenceVisualInput(
        snapshot: AgentPresenceSnapshot.idle(),
        amplitude: 0.8,
        sampledAt: Duration.zero,
      ),
      now: Duration.zero,
      timeSeconds: 30,
      motionEnabled: false,
      colorStrength: 1,
    );

    expect(sink.valueAt(9), 0);
    expect(sink.valueAt(10), 0);
  });

  testWidgets(
    'loaded fragment program paints non-uniform premultiplied pixels',
    (WidgetTester tester) async {
      final ui.FragmentProgram program = (await tester.runAsync(
        () => ui.FragmentProgram.fromAsset('shaders/agent_presence.frag'),
      ))!;
      final ValueNotifier<AgentPresenceVisualInput> input =
          ValueNotifier<AgentPresenceVisualInput>(
            const AgentPresenceVisualInput(
              snapshot: AgentPresenceSnapshot.idle(),
              amplitude: 0,
              sampledAt: Duration.zero,
            ),
          );
      addTearDown(input.dispose);

      await tester.pumpWidget(
        _imageFixture(
          AgentPresencePainter(
            program: program,
            visualInput: input,
            phase: const AlwaysStoppedAnimation<double>(0.25),
            repaint: input,
            now: () => Duration.zero,
            motionEnabled: const AlwaysStoppedAnimation<bool>(true),
          ),
        ),
      );

      final ui.Image image = await _capture(tester);
      addTearDown(image.dispose);
      final ByteData? capturedRgba = await tester.runAsync(
        () async =>
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
      );
      final ByteData rgba = capturedRgba!;
      final _Rgba center = _rgbaAt(rgba, image.width, 28, 28);
      final _Rgba corner = _rgbaAt(rgba, image.width, 0, 0);
      final _Rgba rim = _rgbaAt(rgba, image.width, 8, 28);

      expect(center, isNot(rim));
      expect(center.alpha, greaterThan(0));
      expect(corner.alpha, 0);
      for (final _Rgba pixel in <_Rgba>[center, rim, corner]) {
        expect(pixel.red, lessThanOrEqualTo(pixel.alpha));
        expect(pixel.green, lessThanOrEqualTo(pixel.alpha));
        expect(pixel.blue, lessThanOrEqualTo(pixel.alpha));
      }
    },
  );

  testWidgets('working rendering repeats every 1.6 seconds', (
    WidgetTester tester,
  ) async {
    final ui.FragmentProgram program = (await tester.runAsync(
      () => ui.FragmentProgram.fromAsset('shaders/agent_presence.frag'),
    ))!;

    final Uint8List first = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.working,
      elapsedSeconds: 0.35,
    );
    final Uint8List nextCycle = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.working,
      elapsedSeconds: 1.95,
    );

    expect(nextCycle, orderedEquals(first));
  });

  testWidgets('idle rendering repeats every 5.6 seconds', (
    WidgetTester tester,
  ) async {
    final ui.FragmentProgram program = (await tester.runAsync(
      () => ui.FragmentProgram.fromAsset('shaders/agent_presence.frag'),
    ))!;

    final Uint8List first = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.idle,
      elapsedSeconds: 0.7,
    );
    final Uint8List nextCycle = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.idle,
      elapsedSeconds: 6.3,
    );

    expect(nextCycle, orderedEquals(first));
  });

  testWidgets('speaking rendering repeats every 2.4 seconds', (
    WidgetTester tester,
  ) async {
    final ui.FragmentProgram program = (await tester.runAsync(
      () => ui.FragmentProgram.fromAsset('shaders/agent_presence.frag'),
    ))!;

    final Uint8List first = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.speaking,
      elapsedSeconds: 0.45,
    );
    final Uint8List nextCycle = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.speaking,
      elapsedSeconds: 2.85,
    );

    expect(nextCycle, orderedEquals(first));
  });

  testWidgets('working stays continuous across the former 5.6 second reset', (
    WidgetTester tester,
  ) async {
    final ui.FragmentProgram program = (await tester.runAsync(
      () => ui.FragmentProgram.fromAsset('shaders/agent_presence.frag'),
    ))!;

    final Uint8List before = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.working,
      elapsedSeconds: 5.599,
      controllerPhaseSeconds: 5.599,
    );
    final Uint8List after = await _captureStateAt(
      tester,
      program: program,
      state: AgentPresenceState.working,
      elapsedSeconds: 5.601,
      controllerPhaseSeconds: 0.001,
    );

    expect(_meanAbsoluteDifference(before, after), lessThan(0.5));
  });
}

Widget _imageFixture(CustomPainter painter) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: const Key('shader-image'),
        child: CustomPaint(size: const Size.square(56), painter: painter),
      ),
    ),
  );
}

Future<ui.Image> _capture(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(const Key('shader-image')),
  );
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
}

Future<Uint8List> _captureStateAt(
  WidgetTester tester, {
  required ui.FragmentProgram program,
  required AgentPresenceState state,
  required double elapsedSeconds,
  double? controllerPhaseSeconds,
}) async {
  final Duration now = Duration(
    microseconds: (elapsedSeconds * Duration.microsecondsPerSecond).round(),
  );
  final ValueNotifier<AgentPresenceVisualInput> input =
      ValueNotifier<AgentPresenceVisualInput>(
        AgentPresenceVisualInput(
          snapshot: _settledSnapshot(state, now),
          amplitude: 0.42,
          sampledAt: now,
        ),
      );
  await tester.pumpWidget(
    _imageFixture(
      AgentPresencePainter(
        program: program,
        visualInput: input,
        phase: AlwaysStoppedAnimation<double>(
          (controllerPhaseSeconds ?? elapsedSeconds) / 5.6,
        ),
        repaint: input,
        now: () => now,
        motionEnabled: const AlwaysStoppedAnimation<bool>(true),
      ),
    ),
  );
  final ui.Image image = await _capture(tester);
  final ByteData data = (await tester.runAsync(
    () async => (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
  ))!;
  image.dispose();
  input.dispose();
  return data.buffer.asUint8List();
}

double _meanAbsoluteDifference(Uint8List first, Uint8List second) {
  var difference = 0;
  for (var index = 0; index < first.length; index += 1) {
    difference += (first[index] - second[index]).abs();
  }
  return difference / first.length;
}

AgentPresenceSnapshot _settledSnapshot(AgentPresenceState state, Duration now) {
  const AgentPresenceReducer reducer = AgentPresenceReducer();
  AgentPresenceSnapshot snapshot = const AgentPresenceSnapshot.idle();
  if (state == AgentPresenceState.speaking ||
      state == AgentPresenceState.working) {
    snapshot = reducer.reduce(
      snapshot,
      event: AgentPresenceEvent.listeningStarted,
      now: Duration.zero,
    );
    snapshot = reducer.reduce(
      snapshot,
      event: AgentPresenceEvent.transcriptCommitted,
      now: const Duration(milliseconds: 200),
    );
  }
  if (state == AgentPresenceState.speaking) {
    snapshot = reducer.reduce(
      snapshot,
      event: AgentPresenceEvent.speechStarted,
      now: const Duration(milliseconds: 400),
    );
  }
  if (state == AgentPresenceState.working) {
    snapshot = reducer.reduce(
      snapshot,
      event: AgentPresenceEvent.workStarted,
      now: const Duration(milliseconds: 400),
    );
  }
  return snapshot.settledAt(now);
}

_Rgba _rgbaAt(ByteData data, int width, int x, int y) {
  final int offset = (y * width + x) * 4;
  return _Rgba(
    red: data.getUint8(offset),
    green: data.getUint8(offset + 1),
    blue: data.getUint8(offset + 2),
    alpha: data.getUint8(offset + 3),
  );
}

final class _RecordingUniformSink implements AgentPresenceUniformSink {
  final List<int> indices = <int>[];
  final List<double> values = <double>[];

  @override
  void setFloat(int index, double value) {
    indices.add(index);
    values.add(value);
  }

  double valueAt(int index) => values[indices.indexOf(index)];
}

final class _Rgba {
  const _Rgba({
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });

  final int red;
  final int green;
  final int blue;
  final int alpha;

  @override
  bool operator ==(Object other) {
    return other is _Rgba &&
        other.red == red &&
        other.green == green &&
        other.blue == blue &&
        other.alpha == alpha;
  }

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);

  @override
  String toString() => 'rgba($red, $green, $blue, $alpha)';
}
