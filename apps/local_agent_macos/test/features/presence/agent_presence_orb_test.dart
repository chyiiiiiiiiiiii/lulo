import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_fallback_painter.dart';
import 'package:local_agent_macos/features/presence/agent_presence_orb.dart';
import 'package:local_agent_macos/features/presence/agent_presence_painter.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

void main() {
  group('AgentPresenceOrb', () {
    testWidgets('paints fallback immediately while shader load is pending', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      final Completer<ui.FragmentProgram> load =
          Completer<ui.FragmentProgram>();

      await tester.pumpWidget(
        _app(controller: controller, shaderLoader: () => load.future),
      );

      final CustomPaint canvas = tester.widget<CustomPaint>(
        find.byKey(const Key('agent-presence-canvas')),
      );
      expect(canvas.painter, isA<AgentPresenceFallbackPainter>());
      expect(
        tester.getSize(find.byKey(const Key('agent-presence-canvas'))),
        const Size.square(56),
      );
      expect(find.bySemanticsLabel('Agent ready'), findsOneWidget);
      expect(find.text('Agent ready'), findsOneWidget);
    });

    testWidgets('selects the loaded path after the shader loader succeeds', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      var attempts = 0;

      await tester.pumpWidget(
        _app(
          controller: controller,
          shaderLoader: () {
            attempts += 1;
            return ui.FragmentProgram.fromAsset('shaders/agent_presence.frag');
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(attempts, 1);
      expect(
        find.byKey(const Key('agent-presence-shader-ready')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CustomPaint>(find.byKey(const Key('agent-presence-canvas')))
            .painter,
        isA<AgentPresencePainter>(),
      );
      expect(find.bySemanticsLabel('Agent ready'), findsOneWidget);
      expect(find.text('Agent ready'), findsOneWidget);
    });

    testWidgets('deferred shader success is ignored after the orb unmounts', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      final Completer<ui.FragmentProgram> load =
          Completer<ui.FragmentProgram>();
      final ui.FragmentProgram program = (await tester.runAsync(
        loadAgentPresenceShader,
      ))!;
      var attempts = 0;
      final List<String> diagnostics = <String>[];
      final DebugPrintCallback originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        diagnostics.add(message ?? '');
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      try {
        await tester.pumpWidget(
          _app(
            controller: controller,
            shaderLoader: () {
              attempts += 1;
              return load.future;
            },
          ),
        );

        expect(attempts, 1);
        expect(
          tester
              .widget<CustomPaint>(
                find.byKey(const Key('agent-presence-canvas')),
              )
              .painter,
          isA<AgentPresenceFallbackPainter>(),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        load.complete(program);
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(diagnostics, isEmpty);
        expect(attempts, 1);
      } finally {
        debugPrint = originalDebugPrint;
      }
    });

    testWidgets('deferred shader failure is ignored after the orb unmounts', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      final Completer<ui.FragmentProgram> load =
          Completer<ui.FragmentProgram>();
      var attempts = 0;
      final List<String> diagnostics = <String>[];
      final DebugPrintCallback originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        diagnostics.add(message ?? '');
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      try {
        await tester.pumpWidget(
          _app(
            controller: controller,
            shaderLoader: () {
              attempts += 1;
              return load.future;
            },
          ),
        );

        expect(attempts, 1);
        expect(
          tester
              .widget<CustomPaint>(
                find.byKey(const Key('agent-presence-canvas')),
              )
              .painter,
          isA<AgentPresenceFallbackPainter>(),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        load.completeError(
          StateError('must not log /private/path, prompt, or audio samples'),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(diagnostics, isEmpty);
        expect(attempts, 1);
      } finally {
        debugPrint = originalDebugPrint;
      }
    });

    testWidgets('loader exception latches one same-size semantic fallback', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      _dispatchState(controller, AgentPresenceState.working);
      var attempts = 0;
      final List<String> diagnostics = <String>[];
      final DebugPrintCallback originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        diagnostics.add(message ?? '');
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      try {
        await tester.pumpWidget(
          _app(
            controller: controller,
            shaderLoader: () async {
              attempts += 1;
              throw StateError(
                'must not log /private/path, prompt, or audio samples',
              );
            },
          ),
        );
        await tester.pump();

        expect(attempts, 1);
        expect(
          find.byKey(const Key('agent-presence-fallback')),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(const Key('agent-presence-canvas'))),
          const Size.square(56),
        );
        expect(find.bySemanticsLabel('Working'), findsOneWidget);
        expect(find.text('Working'), findsOneWidget);
        expect(diagnostics, <String>[
          'presence_shader_fallback exception_type=StateError',
        ]);
      } finally {
        debugPrint = originalDebugPrint;
      }
    });

    testWidgets('fallback repaints never retry shader compilation', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      var attempts = 0;
      await tester.pumpWidget(
        _app(
          controller: controller,
          shaderLoader: () async {
            attempts += 1;
            throw UnsupportedError('shader unavailable');
          },
        ),
      );
      await tester.pump();
      final CustomPainter? selectedPainter = tester
          .widget<CustomPaint>(find.byKey(const Key('agent-presence-canvas')))
          .painter;

      controller.dispatch(
        AgentPresenceEvent.listeningStarted,
        const Duration(milliseconds: 1),
      );
      controller.acceptAudioRms(0, const Duration(milliseconds: 16));
      controller.acceptAudioRms(0.42, const Duration(milliseconds: 71));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(attempts, 1);
      expect(
        tester
            .widget<CustomPaint>(find.byKey(const Key('agent-presence-canvas')))
            .painter,
        same(selectedPainter),
      );
      expect(find.byKey(const Key('agent-presence-fallback')), findsOneWidget);
    });

    testWidgets('a remounted orb may retry shader compilation', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      var attempts = 0;
      Future<ui.FragmentProgram> failLoad() async {
        attempts += 1;
        throw UnsupportedError('shader unavailable');
      }

      await tester.pumpWidget(
        _app(
          controller: controller,
          shaderLoader: failLoad,
          orbKey: const ValueKey<String>('first-orb'),
        ),
      );
      await tester.pump();
      expect(attempts, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(
          controller: controller,
          shaderLoader: failLoad,
          orbKey: const ValueKey<String>('second-orb'),
        ),
      );
      await tester.pump();

      expect(attempts, 2);
      expect(find.byKey(const Key('agent-presence-fallback')), findsOneWidget);
    });

    for (final _ShaderFailureStage stage in _ShaderFailureStage.values) {
      testWidgets(
        '${stage.name} paint failure latches fallback without retry',
        (WidgetTester tester) async {
          final AgentPresenceController controller = AgentPresenceController();
          addTearDown(controller.dispose);
          final _FailingShaderBackend backend = _FailingShaderBackend(stage);

          await tester.pumpWidget(
            _app(controller: controller, shaderBackendFactory: () => backend),
          );
          await tester.pump();
          await tester.pump();
          await tester.pump();

          expect(
            find.byKey(const Key('agent-presence-fallback')),
            findsOneWidget,
          );
          expect(backend.frameAttempts, 1);
          expect(find.bySemanticsLabel('Agent ready'), findsOneWidget);

          controller.dispatch(
            AgentPresenceEvent.listeningStarted,
            const Duration(milliseconds: 1),
          );
          controller.acceptAudioRms(0, const Duration(milliseconds: 16));
          controller.acceptAudioRms(0.42, const Duration(milliseconds: 71));
          await tester.pump(const Duration(milliseconds: 32));

          expect(backend.frameAttempts, 1);
          expect(
            find.byKey(const Key('agent-presence-fallback')),
            findsOneWidget,
          );
        },
      );
    }

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

          await tester.pumpWidget(
            _app(controller: controller, disableAnimations: true),
          );

          expect(find.bySemanticsLabel(semanticCase.label), findsOneWidget);
          expect(find.text(semanticCase.label), findsOneWidget);
        },
      );
    }

    testWidgets('idle schedules breathing paints while motion is enabled', (
      WidgetTester tester,
    ) async {
      final AgentPresenceController controller = AgentPresenceController();
      addTearDown(controller.dispose);
      var paints = 0;
      await tester.pumpWidget(
        _app(controller: controller, onPaint: () => paints += 1),
      );
      await tester.pump();
      paints = 0;

      await tester.pump(const Duration(milliseconds: 100));

      expect(paints, greaterThan(0));
    });

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

    testWidgets(
      'reduced motion renders a shader state target immediately at arrival',
      (WidgetTester tester) async {
        final AgentPresenceController controller = AgentPresenceController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _app(controller: controller, disableAnimations: true),
        );
        await tester.pump();
        await tester.pump();

        controller.dispatch(
          AgentPresenceEvent.listeningStarted,
          const Duration(milliseconds: 1),
        );
        controller.acceptAudioRms(0, const Duration(milliseconds: 16));
        controller.acceptAudioRms(0.42, const Duration(milliseconds: 71));
        await tester.pump();

        final AgentPresencePainter painter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('agent-presence-canvas')),
                    )
                    .painter!
                as AgentPresencePainter;
        final _RecordingUniformSink uniforms = _RecordingUniformSink();
        painter.writeUniforms(uniforms, const Size.square(56));

        expect(uniforms.valueAt(3), 0);
        expect(uniforms.valueAt(4), 1);
        expect(uniforms.valueAt(9), 0);
        expect(uniforms.valueAt(10), 0);
        expect(find.bySemanticsLabel('Listening'), findsOneWidget);
        expect(find.text('Listening'), findsOneWidget);
      },
    );

    testWidgets(
      'reduced motion fallback stays semantic and parked after amplitude input',
      (WidgetTester tester) async {
        final AgentPresenceController controller = AgentPresenceController();
        addTearDown(controller.dispose);
        var paints = 0;

        await tester.pumpWidget(
          _app(
            controller: controller,
            disableAnimations: true,
            onPaint: () => paints += 1,
            shaderLoader: () async {
              throw UnsupportedError('shader unavailable');
            },
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const Key('agent-presence-fallback')),
          findsOneWidget,
        );

        controller.dispatch(
          AgentPresenceEvent.listeningStarted,
          const Duration(milliseconds: 1),
        );
        controller.acceptAudioRms(0, const Duration(milliseconds: 16));
        controller.acceptAudioRms(0.42, const Duration(milliseconds: 71));
        await tester.pump();

        expect(find.bySemanticsLabel('Listening'), findsOneWidget);
        expect(find.text('Listening'), findsOneWidget);
        paints = 0;
        await tester.pump(const Duration(seconds: 1));
        expect(paints, 0);
      },
    );

    testWidgets(
      'loaded shader follows a reduced-motion toggle and resumes safely',
      (WidgetTester tester) async {
        final AgentPresenceController controller = AgentPresenceController();
        addTearDown(controller.dispose);
        _dispatchState(controller, AgentPresenceState.speaking);
        controller.acceptAudioRms(0, const Duration(milliseconds: 416));
        controller.acceptAudioRms(0.42, const Duration(milliseconds: 471));
        var paints = 0;
        var semanticBuilds = 0;

        await tester.pumpWidget(
          _app(
            controller: controller,
            onPaint: () => paints += 1,
            onSemanticBuild: () => semanticBuilds += 1,
          ),
        );
        await tester.pump();
        await tester.pump();
        final AgentPresencePainter painter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('agent-presence-canvas')),
                    )
                    .painter!
                as AgentPresencePainter;
        expect(painter.motionEnabled.value, isTrue);

        await tester.pumpWidget(
          _app(
            controller: controller,
            disableAnimations: true,
            onPaint: () => paints += 1,
            onSemanticBuild: () => semanticBuilds += 1,
          ),
        );
        await tester.pump();
        final _RecordingUniformSink reduced = _RecordingUniformSink();
        painter.writeUniforms(reduced, const Size.square(56));
        expect(reduced.valueAt(9), 0);
        expect(reduced.valueAt(10), 0);
        paints = 0;
        semanticBuilds = 0;

        await tester.pump(const Duration(seconds: 1));

        expect(paints, 0);
        expect(semanticBuilds, 0);

        await tester.pumpWidget(
          _app(
            controller: controller,
            onPaint: () => paints += 1,
            onSemanticBuild: () => semanticBuilds += 1,
          ),
        );
        await tester.pump();
        expect(painter.motionEnabled.value, isTrue);
        paints = 0;
        semanticBuilds = 0;

        await tester.pump(const Duration(milliseconds: 100));

        expect(paints, greaterThan(0));
        expect(semanticBuilds, 0);
      },
    );

    for (final _MotionCase motionCase in <_MotionCase>[
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
  VoidCallback? onSemanticBuild,
  AgentPresenceShaderLoader shaderLoader = loadAgentPresenceShader,
  AgentPresenceShaderBackendFactory shaderBackendFactory =
      createAgentPresenceShaderBackend,
  Key? orbKey,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: AgentPresenceOrb(
          key: orbKey,
          controller: controller,
          onPaint: onPaint,
          onSemanticBuild: onSemanticBuild,
          shaderLoader: shaderLoader,
          shaderBackendFactory: shaderBackendFactory,
        ),
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

final class _RecordingUniformSink implements AgentPresenceUniformSink {
  final Map<int, double> _values = <int, double>{};

  @override
  void setFloat(int index, double value) {
    _values[index] = value;
  }

  double? valueAt(int index) => _values[index];
}

enum _ShaderFailureStage { instantiation, uniformUpload, draw }

final class _FailingShaderBackend implements AgentPresenceShaderBackend {
  _FailingShaderBackend(this.stage);

  final _ShaderFailureStage stage;
  var frameAttempts = 0;

  @override
  void beginFrame(ui.FragmentProgram program) {
    frameAttempts += 1;
    if (stage == _ShaderFailureStage.instantiation) {
      throw StateError('fragment shader instantiation failed');
    }
  }

  @override
  void draw(Canvas canvas, Size size, Path clipPath) {
    if (stage == _ShaderFailureStage.draw) {
      throw StateError('shader draw failed');
    }
  }

  @override
  void setFloat(int index, double value) {
    if (stage == _ShaderFailureStage.uniformUpload) {
      throw StateError('uniform upload failed');
    }
  }
}
