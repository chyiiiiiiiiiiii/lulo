import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_painter.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final _GoldenCase goldenCase in <_GoldenCase>[
    const _GoldenCase(AgentPresenceState.idle, 'agent_presence_idle.png'),
    const _GoldenCase(
      AgentPresenceState.listening,
      'agent_presence_listening.png',
    ),
    const _GoldenCase(
      AgentPresenceState.thinking,
      'agent_presence_thinking.png',
    ),
    const _GoldenCase(
      AgentPresenceState.speaking,
      'agent_presence_speaking.png',
    ),
    const _GoldenCase(AgentPresenceState.working, 'agent_presence_working.png'),
    const _GoldenCase(
      AgentPresenceState.error,
      'agent_presence_error_reduced_motion.png',
      motionEnabled: false,
    ),
  ]) {
    testWidgets('${goldenCase.state.name} has a frozen 56px shader image', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size.square(56)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ui.FragmentProgram program = (await tester.runAsync(
        () => ui.FragmentProgram.fromAsset('shaders/agent_presence.frag'),
      ))!;
      final ValueNotifier<AgentPresenceVisualInput> input =
          ValueNotifier<AgentPresenceVisualInput>(
            AgentPresenceVisualInput(
              snapshot: _settledSnapshot(goldenCase.state),
              amplitude: 0.42,
              sampledAt: _fixtureNow,
            ),
          );
      addTearDown(input.dispose);

      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('golden-orb'),
          child: CustomPaint(
            size: const Size.square(56),
            painter: AgentPresencePainter(
              program: program,
              visualInput: input,
              phase: const AlwaysStoppedAnimation<double>(0.3125),
              repaint: input,
              now: () => _fixtureNow,
              motionEnabled: AlwaysStoppedAnimation<bool>(
                goldenCase.motionEnabled,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('golden-orb'))),
        const Size.square(56),
      );
      await expectLater(
        find.byKey(const Key('golden-orb')),
        matchesGoldenFile('goldens/${goldenCase.fileName}'),
      );
      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byKey(const Key('golden-orb')),
      );
      final ui.Image retinaImage = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 2),
      ))!;
      expect(retinaImage.width, 112);
      expect(retinaImage.height, 112);
      final ByteData retinaRgba = (await tester.runAsync(
        () async =>
            (await retinaImage.toByteData(format: ui.ImageByteFormat.rawRgba))!,
      ))!;
      expect(retinaRgba.getUint8(3), 0);
      expect(
        retinaRgba.getUint8(((56 * retinaImage.width) + 56) * 4 + 3),
        greaterThan(0),
      );
      await expectLater(
        retinaImage,
        matchesGoldenFile('goldens/2x/${goldenCase.fileName}'),
      );
      retinaImage.dispose();
    });
  }
}

const Duration _fixtureNow = Duration(milliseconds: 1750);

AgentPresenceSnapshot _settledSnapshot(AgentPresenceState state) {
  const AgentPresenceReducer reducer = AgentPresenceReducer();
  AgentPresenceSnapshot snapshot = const AgentPresenceSnapshot.idle();
  switch (state) {
    case AgentPresenceState.idle:
      return snapshot;
    case AgentPresenceState.listening:
      snapshot = reducer.reduce(
        snapshot,
        event: AgentPresenceEvent.listeningStarted,
        now: Duration.zero,
      );
    case AgentPresenceState.thinking:
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
    case AgentPresenceState.speaking:
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
      snapshot = reducer.reduce(
        snapshot,
        event: AgentPresenceEvent.speechStarted,
        now: const Duration(milliseconds: 400),
      );
    case AgentPresenceState.working:
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
      snapshot = reducer.reduce(
        snapshot,
        event: AgentPresenceEvent.workStarted,
        now: const Duration(milliseconds: 400),
      );
    case AgentPresenceState.error:
      snapshot = reducer.reduce(
        snapshot,
        event: AgentPresenceEvent.failed,
        now: Duration.zero,
      );
  }
  return snapshot.settledAt(_fixtureNow);
}

final class _GoldenCase {
  const _GoldenCase(this.state, this.fileName, {this.motionEnabled = true});

  final AgentPresenceState state;
  final String fileName;
  final bool motionEnabled;
}
