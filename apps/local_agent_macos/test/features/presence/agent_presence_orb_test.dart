import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_orb.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

void main() {
  group('AgentPresenceOrb', () {
    for (final _SemanticCase semanticCase in <_SemanticCase>[
      const _SemanticCase(state: AgentPresenceState.idle, label: 'Agent ready'),
      const _SemanticCase(
        state: AgentPresenceState.listening,
        label: 'Listening',
      ),
      const _SemanticCase(
        state: AgentPresenceState.thinking,
        label: 'Thinking',
      ),
      const _SemanticCase(
        state: AgentPresenceState.speaking,
        label: 'Speaking',
      ),
      const _SemanticCase(state: AgentPresenceState.working, label: 'Working'),
      const _SemanticCase(
        state: AgentPresenceState.error,
        label: 'Attention needed',
      ),
    ]) {
      testWidgets(
        '${semanticCase.state.name} exposes ${semanticCase.label} semantics',
        (WidgetTester tester) async {
          final AgentPresenceController controller = AgentPresenceController();
          addTearDown(controller.dispose);
          _dispatchState(controller, semanticCase.state);

          await tester.pumpWidget(_app(controller: controller));

          expect(find.bySemanticsLabel(semanticCase.label), findsOneWidget);
          expect(find.text(semanticCase.label), findsOneWidget);
        },
      );
    }

    testWidgets('reduced motion retains state semantics and visible text', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      controller.dispatch(AgentPresenceEvent.failed, Duration.zero);

      await tester.pumpWidget(
        _app(controller: controller, disableAnimations: true),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.bySemanticsLabel('Attention needed'), findsOneWidget);
      expect(find.text('Attention needed'), findsOneWidget);
    });

    for (final _MotionCase motionCase in <_MotionCase>[
      const _MotionCase(
        name: 'idle',
        state: AgentPresenceState.idle,
        disableAnimations: false,
      ),
      const _MotionCase(
        name: 'error',
        state: AgentPresenceState.error,
        disableAnimations: false,
      ),
      const _MotionCase(
        name: 'reduced motion',
        state: AgentPresenceState.listening,
        disableAnimations: true,
      ),
    ]) {
      testWidgets('${motionCase.name} does not schedule ticker paints', (
        WidgetTester tester,
      ) async {
        final AgentPresenceController controller = AgentPresenceController();
        addTearDown(controller.dispose);
        _dispatchState(controller, motionCase.state);
        var paints = 0;
        await tester.pumpWidget(
          _app(
            controller: controller,
            disableAnimations: motionCase.disableAnimations,
            onPaint: () => paints += 1,
          ),
        );
        await tester.pump();
        paints = 0;

        await tester.pump(const Duration(seconds: 1));

        expect(paints, 0);
      });
    }

    testWidgets('state and amplitude updates repaint only the orb boundary', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      var paints = 0;
      await tester.pumpWidget(
        _app(
          controller: controller,
          disableAnimations: true,
          onPaint: () => paints += 1,
        ),
      );
      paints = 0;

      controller.dispatch(
        AgentPresenceEvent.listeningStarted,
        const Duration(milliseconds: 1),
      );
      await tester.pump();
      expect(paints, 1);

      paints = 0;
      controller.acceptAudioRms(0, const Duration(milliseconds: 16));
      controller.acceptAudioRms(0.42, const Duration(milliseconds: 71));
      await tester.pump();
      expect(paints, 1);

      expect(
        find.descendant(
          of: find.byKey(const Key('agent-presence-repaint-boundary')),
          matching: find.byKey(const Key('agent-presence-canvas')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('animated ticker is disposed when the orb is removed', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      controller.dispatch(AgentPresenceEvent.listeningStarted, Duration.zero);
      await tester.pumpWidget(_app(controller: controller));
      await tester.pump(const Duration(milliseconds: 32));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 32));

      expect(tester.takeException(), isNull);
    });
  });
}

Widget _app({
  required AgentPresenceController controller,
  bool disableAnimations = false,
  VoidCallback? onPaint,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: AgentPresenceOrb(controller: controller, onPaint: onPaint),
      ),
    ),
  );
}

void _dispatchState(
  AgentPresenceController controller,
  AgentPresenceState state,
) {
  switch (state) {
    case AgentPresenceState.idle:
      return;
    case AgentPresenceState.listening:
      controller.dispatch(AgentPresenceEvent.listeningStarted, Duration.zero);
    case AgentPresenceState.thinking:
      controller.dispatch(AgentPresenceEvent.listeningStarted, Duration.zero);
      controller.dispatch(
        AgentPresenceEvent.transcriptCommitted,
        const Duration(milliseconds: 200),
      );
    case AgentPresenceState.speaking:
      controller.dispatch(AgentPresenceEvent.listeningStarted, Duration.zero);
      controller.dispatch(
        AgentPresenceEvent.transcriptCommitted,
        const Duration(milliseconds: 200),
      );
      controller.dispatch(
        AgentPresenceEvent.speechStarted,
        const Duration(milliseconds: 400),
      );
    case AgentPresenceState.working:
      controller.dispatch(AgentPresenceEvent.listeningStarted, Duration.zero);
      controller.dispatch(
        AgentPresenceEvent.transcriptCommitted,
        const Duration(milliseconds: 200),
      );
      controller.dispatch(
        AgentPresenceEvent.workStarted,
        const Duration(milliseconds: 400),
      );
    case AgentPresenceState.error:
      controller.dispatch(AgentPresenceEvent.failed, Duration.zero);
  }
}

final class _SemanticCase {
  const _SemanticCase({required this.state, required this.label});

  final AgentPresenceState state;
  final String label;
}

final class _MotionCase {
  const _MotionCase({
    required this.name,
    required this.state,
    required this.disableAnimations,
  });

  final String name;
  final AgentPresenceState state;
  final bool disableAnimations;
}
