import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_fallback_painter.dart';
import 'agent_presence_state.dart';

/// Paint instrumentation used by rendering-isolation tests.
typedef AgentPresencePaintCallback = void Function();

/// Loads the feature-local runtime shader program.
typedef AgentPresenceShaderLoader = Future<ui.FragmentProgram> Function();

/// Loads the bundled presence fragment program.
Future<ui.FragmentProgram> loadAgentPresenceShader() =>
    ui.FragmentProgram.fromAsset('shaders/agent_presence.frag');

/// The local repaint and animation boundary for agent-presence visuals.
final class AgentPresenceOrb extends StatefulWidget {
  /// Creates an orb driven by one feature-local [controller].
  const AgentPresenceOrb({
    required this.controller,
    this.onPaint,
    this.onSemanticBuild,
    this.shaderLoader = loadAgentPresenceShader,
    super.key,
  });

  /// Supplies narrow semantic and visual presence updates.
  final AgentPresenceController controller;

  /// Optional paint instrumentation used by tests.
  final AgentPresencePaintCallback? onPaint;

  /// Optional semantic-build instrumentation used by tests.
  final VoidCallback? onSemanticBuild;

  /// Shader loader injected by focused lifecycle tests.
  final AgentPresenceShaderLoader shaderLoader;

  @override
  State<AgentPresenceOrb> createState() => _AgentPresenceOrbState();
}

final class _AgentPresenceOrbState extends State<AgentPresenceOrb>
    with SingleTickerProviderStateMixin {
  static const Duration _placeholderCycle = Duration(milliseconds: 5600);
  static const double _orbExtent = 56;

  late final AnimationController _motion;
  late final Listenable _repaint;
  late final AgentPresenceFallbackPainter _painter;
  bool _disableAnimations = false;
  _ShaderLoadPhase _shaderLoadPhase = _ShaderLoadPhase.pending;
  ui.FragmentProgram? _fragmentProgram;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController.unbounded(vsync: this);
    _repaint = Listenable.merge(<Listenable>[
      _motion,
      widget.controller.visualInputListenable,
    ]);
    _painter = AgentPresenceFallbackPainter(
      visualInput: widget.controller.visualInputListenable,
      repaint: _repaint,
      onPaint: widget.onPaint,
    );
    widget.controller.semanticStateListenable.addListener(
      _updateMotionLifecycle,
    );
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _loadShader();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    _updateMotionLifecycle();
  }

  @override
  void dispose() {
    widget.controller.semanticStateListenable.removeListener(
      _updateMotionLifecycle,
    );
    _motion.dispose();
    super.dispose();
  }

  void _updateMotionLifecycle() {
    final AgentPresenceState state =
        widget.controller.semanticStateListenable.value;
    final bool shouldAnimate =
        !_disableAnimations &&
        state != AgentPresenceState.idle &&
        state != AgentPresenceState.error;
    if (shouldAnimate) {
      if (!_motion.isAnimating) {
        _motion.repeat(min: 0, max: 1, period: _placeholderCycle);
      }
      return;
    }
    _motion.stop();
    _motion.value = 0;
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
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _fragmentProgram = program;
      _shaderLoadPhase = _ShaderLoadPhase.ready;
    });
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox.square(
                      dimension: _orbExtent,
                      child: KeyedSubtree(
                        key:
                            _shaderLoadPhase == _ShaderLoadPhase.ready &&
                                _fragmentProgram != null
                            ? const Key('agent-presence-shader-ready')
                            : _shaderLoadPhase == _ShaderLoadPhase.fallback
                            ? const Key('agent-presence-fallback')
                            : const Key('agent-presence-shader-pending'),
                        child: CustomPaint(
                          key: const Key('agent-presence-canvas'),
                          painter: _painter,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(label),
                  ],
                ),
              );
            },
      ),
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
