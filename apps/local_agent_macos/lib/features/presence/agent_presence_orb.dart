import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_fallback_painter.dart';
import 'agent_presence_painter.dart';
import 'agent_presence_state.dart';

/// Paint instrumentation used by rendering-isolation tests.
typedef AgentPresencePaintCallback = void Function();

/// Loads the feature-local runtime shader program.
typedef AgentPresenceShaderLoader = Future<ui.FragmentProgram> Function();

/// Loads the bundled presence fragment program.
Future<ui.FragmentProgram> loadAgentPresenceShader() =>
    ui.FragmentProgram.fromAsset('shaders/agent_presence.frag');

/// Observable rendering path used by integration evidence and focused tests.
enum AgentPresenceRenderingPath {
  /// The bundled fragment program has not resolved yet.
  loading,

  /// The bundled fragment program loaded and its painter was constructed.
  loadedShader,

  /// This mounted orb latched the Canvas fallback.
  fallback,
}

/// The local repaint and animation boundary for agent-presence visuals.
final class AgentPresenceOrb extends StatefulWidget {
  /// Creates an orb driven by one feature-local [controller].
  const AgentPresenceOrb({
    required this.controller,
    this.onPaint,
    this.onSemanticBuild,
    this.shaderLoader = loadAgentPresenceShader,
    this.shaderBackendFactory = createAgentPresenceShaderBackend,
    this.onRenderingPathChanged,
    this.extent = defaultOrbExtent,
    this.showLabel = true,
    this.continuousMotion = false,
    super.key,
  });

  /// Whether idle motion runs on every frame instead of a low-rate timer.
  ///
  /// The inline presence is a small ornament beside a conversation, so when it
  /// is idle it steps a few times a second to stay cheap. The desktop presence
  /// is the only thing on screen and that stepping reads as a stutter, so it
  /// animates on the display's own cadence instead.
  final bool continuousMotion;

  /// Whether the state name is drawn beside the orb.
  ///
  /// The inline presence pairs the orb with a readable label. The desktop
  /// presence is the orb alone, so the label is omitted there and the state is
  /// carried by semantics only.
  final bool showLabel;

  /// Edge length used when no [extent] is supplied.
  static const double defaultOrbExtent = 56;

  /// Edge length of the orb, in logical pixels.
  ///
  /// The shader renders at this size rather than being scaled afterwards, so a
  /// large desktop presence stays as crisp as the small inline one.
  final double extent;

  /// Supplies narrow semantic and visual presence updates.
  final AgentPresenceController controller;

  /// Optional paint instrumentation used by tests.
  final AgentPresencePaintCallback? onPaint;

  /// Optional semantic-build instrumentation used by tests.
  final VoidCallback? onSemanticBuild;

  /// Shader loader injected by focused lifecycle tests.
  final AgentPresenceShaderLoader shaderLoader;

  /// Creates one shader backend for this mounted orb.
  final AgentPresenceShaderBackendFactory shaderBackendFactory;

  /// Reports rendering readiness without exposing shader ownership.
  final ValueChanged<AgentPresenceRenderingPath>? onRenderingPathChanged;

  @override
  State<AgentPresenceOrb> createState() => _AgentPresenceOrbState();
}

final class _AgentPresenceOrbState extends State<AgentPresenceOrb>
    with SingleTickerProviderStateMixin {
  static const Duration _placeholderCycle = Duration(milliseconds: 5600);
  static const Duration _idleFrameInterval = Duration(milliseconds: 200);

  late final AnimationController _motion;
  late final ValueNotifier<bool> _motionEnabled;
  late Listenable _repaint;
  late final Stopwatch _clock;
  late AgentPresenceFallbackPainter _fallbackPainter;
  AgentPresencePainter? _shaderPainter;
  ui.FragmentProgram? _shaderProgram;
  Timer? _idleFrameTimer;
  bool _disableAnimations = false;
  bool _tickerModeEnabled = true;
  _ShaderLoadPhase _shaderLoadPhase = _ShaderLoadPhase.pending;

  @override
  void initState() {
    super.initState();
    _clock = Stopwatch()..start();
    _motion = AnimationController.unbounded(vsync: this);
    _motionEnabled = ValueNotifier<bool>(true);
    _bindController();
    widget.onRenderingPathChanged?.call(AgentPresenceRenderingPath.loading);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _loadShader();
    });
  }

  @override
  void didUpdateWidget(AgentPresenceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    // The painters hold the listenables they were built with, so a controller
    // handed over after the first build would keep the orb painting the state
    // of the one it replaced: it would report the new state through semantics
    // while still drawing the old one's colour.
    oldWidget.controller.semanticStateListenable.removeListener(
      _updateMotionLifecycle,
    );
    _bindController();
    if (_shaderPainter != null) {
      _rebuildShaderPainter();
    }
    _updateMotionLifecycle();
  }

  AgentPresencePainter _makeShaderPainter(ui.FragmentProgram program) {
    return AgentPresencePainter(
      program: program,
      visualInput: widget.controller.visualInputListenable,
      phase: _motion,
      repaint: _repaint,
      now: () => _clock.elapsed,
      motionEnabled: _motionEnabled,
      backend: widget.shaderBackendFactory(),
      failurePainter: _fallbackPainter,
      onFailure: _handleShaderPaintFailure,
      onPaint: widget.onPaint,
    );
  }

  /// Rebuilds the shader painter so it reads the current controller.
  void _rebuildShaderPainter() {
    final ui.FragmentProgram? program = _shaderProgram;
    if (program == null) {
      return;
    }
    setState(() {
      _shaderPainter = _makeShaderPainter(program);
    });
  }

  /// Points the repaint sources and painters at the current controller.
  void _bindController() {
    _repaint = Listenable.merge(<Listenable>[
      _motion,
      _motionEnabled,
      widget.controller.visualInputListenable,
    ]);
    _fallbackPainter = AgentPresenceFallbackPainter(
      visualInput: widget.controller.visualInputListenable,
      repaint: _repaint,
      onPaint: widget.onPaint,
    );
    widget.controller.semanticStateListenable.addListener(
      _updateMotionLifecycle,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    _tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    _motionEnabled.value = !_disableAnimations;
    _updateMotionLifecycle();
  }

  @override
  void dispose() {
    widget.controller.semanticStateListenable.removeListener(
      _updateMotionLifecycle,
    );
    _motion.dispose();
    _idleFrameTimer?.cancel();
    _motionEnabled.dispose();
    _clock.stop();
    super.dispose();
  }

  void _updateMotionLifecycle() {
    final AgentPresenceState state =
        widget.controller.semanticStateListenable.value;
    if (!_tickerModeEnabled ||
        _disableAnimations ||
        state == AgentPresenceState.error) {
      _idleFrameTimer?.cancel();
      _idleFrameTimer = null;
      _motion.stop();
      _motion.value = 0;
      return;
    }
    if (state == AgentPresenceState.idle && !widget.continuousMotion) {
      _motion.stop();
      _updateIdlePhase();
      _idleFrameTimer ??= Timer.periodic(
        _idleFrameInterval,
        (_) => _updateIdlePhase(),
      );
      return;
    }
    _idleFrameTimer?.cancel();
    _idleFrameTimer = null;
    if (!_motion.isAnimating) {
      _motion.repeat(min: 0, max: 1, period: _placeholderCycle);
    }
  }

  void _updateIdlePhase() {
    if (!mounted ||
        _disableAnimations ||
        !_tickerModeEnabled ||
        widget.controller.semanticStateListenable.value !=
            AgentPresenceState.idle) {
      return;
    }
    final int cycleMicros = _placeholderCycle.inMicroseconds;
    final int elapsedMicros = _clock.elapsedMicroseconds % cycleMicros;
    _motion.value = elapsedMicros / cycleMicros;
  }

  Future<void> _loadShader() async {
    late final ui.FragmentProgram program;
    try {
      program = await widget.shaderLoader();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (kDebugMode) {
        debugPrint(
          'presence_shader_fallback exception_type=${error.runtimeType}',
        );
      }
      setState(() {
        _shaderLoadPhase = _ShaderLoadPhase.fallback;
      });
      widget.onRenderingPathChanged?.call(AgentPresenceRenderingPath.fallback);
      return;
    }
    if (!mounted) {
      return;
    }
    try {
      _shaderProgram = program;
      final AgentPresencePainter painter = _makeShaderPainter(program);
      setState(() {
        _shaderPainter = painter;
        _shaderLoadPhase = _ShaderLoadPhase.ready;
      });
      widget.onRenderingPathChanged?.call(
        AgentPresenceRenderingPath.loadedShader,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (kDebugMode) {
        debugPrint(
          'presence_shader_fallback exception_type=${error.runtimeType}',
        );
      }
      setState(() {
        _shaderLoadPhase = _ShaderLoadPhase.fallback;
      });
      widget.onRenderingPathChanged?.call(AgentPresenceRenderingPath.fallback);
    }
  }

  void _handleShaderPaintFailure(Object error) {
    if (!mounted || _shaderLoadPhase != _ShaderLoadPhase.ready) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        'presence_shader_fallback exception_type=${error.runtimeType}',
      );
    }
    setState(() {
      _shaderLoadPhase = _ShaderLoadPhase.fallback;
    });
    widget.onRenderingPathChanged?.call(AgentPresenceRenderingPath.fallback);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('agent-presence-repaint-boundary'),
      child: ValueListenableBuilder<AgentPresenceState>(
        valueListenable: widget.controller.semanticStateListenable,
        builder:
            (BuildContext context, AgentPresenceState state, Widget? child) {
              widget.onSemanticBuild?.call();
              final String label = _semanticLabel(state);
              return Semantics(
                label: label,
                container: true,
                excludeSemantics: true,
                child: _wrapWithLabel(
                  label,
                  SizedBox.square(
                    dimension: widget.extent,
                    child: KeyedSubtree(
                      key:
                          _shaderLoadPhase == _ShaderLoadPhase.ready &&
                              _shaderPainter != null
                          ? const Key('agent-presence-shader-ready')
                          : _shaderLoadPhase == _ShaderLoadPhase.fallback
                          ? const Key('agent-presence-fallback')
                          : const Key('agent-presence-shader-pending'),
                      child: CustomPaint(
                        key: const Key('agent-presence-canvas'),
                        painter:
                            _shaderLoadPhase == _ShaderLoadPhase.ready &&
                                _shaderPainter != null
                            ? _shaderPainter
                            : _fallbackPainter,
                      ),
                    ),
                  ),
                ),
              );
            },
      ),
    );
  }

  /// Pairs the orb with its readable state, or returns it alone.
  Widget _wrapWithLabel(String label, Widget orb) {
    if (!widget.showLabel) {
      return orb;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[orb, const SizedBox(width: 8), Text(label)],
    );
  }
}

enum _ShaderLoadPhase { pending, ready, fallback }

String _semanticLabel(AgentPresenceState state) {
  return switch (state) {
    AgentPresenceState.idle => 'Agent ready',
    AgentPresenceState.listening => 'Listening',
    AgentPresenceState.thinking => 'Thinking',
    AgentPresenceState.speaking => 'Speaking',
    AgentPresenceState.working => 'Working',
    AgentPresenceState.error => 'Attention needed',
  };
}
