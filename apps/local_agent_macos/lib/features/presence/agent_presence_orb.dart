import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_state.dart';

/// Paint instrumentation used by rendering-isolation tests.
typedef AgentPresencePaintCallback = void Function();

/// The local repaint and animation boundary for agent-presence visuals.
final class AgentPresenceOrb extends StatefulWidget {
  /// Creates an orb driven by one feature-local [controller].
  const AgentPresenceOrb({
    required this.controller,
    this.onPaint,
    this.onSemanticBuild,
    super.key,
  });

  /// Supplies narrow semantic and visual presence updates.
  final AgentPresenceController controller;

  /// Optional paint instrumentation used by tests.
  final AgentPresencePaintCallback? onPaint;

  /// Optional semantic-build instrumentation used by tests.
  final VoidCallback? onSemanticBuild;

  @override
  State<AgentPresenceOrb> createState() => _AgentPresenceOrbState();
}

final class _AgentPresenceOrbState extends State<AgentPresenceOrb>
    with SingleTickerProviderStateMixin {
  static const Duration _placeholderCycle = Duration(milliseconds: 5600);
  static const double _orbExtent = 56;
  static const double _discExtent = 44;

  late final AnimationController _motion;
  late final Listenable _repaint;
  late final _AgentPresencePlaceholderPainter _painter;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController.unbounded(vsync: this);
    _repaint = Listenable.merge(<Listenable>[
      _motion,
      widget.controller.visualInputListenable,
    ]);
    _painter = _AgentPresencePlaceholderPainter(
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
                      child: CustomPaint(
                        key: const Key('agent-presence-canvas'),
                        painter: _painter,
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

final class _AgentPresencePlaceholderPainter extends CustomPainter {
  _AgentPresencePlaceholderPainter({
    required this.visualInput,
    required Listenable repaint,
    this.onPaint,
  }) : super(repaint: repaint);

  final ValueListenable<AgentPresenceVisualInput> visualInput;
  final AgentPresencePaintCallback? onPaint;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    onPaint?.call();
    _paint.color = _placeholderColor(visualInput.value.snapshot.state);
    canvas.drawCircle(
      size.center(Offset.zero),
      _AgentPresenceOrbState._discExtent / 2,
      _paint,
    );
  }

  @override
  bool shouldRepaint(_AgentPresencePlaceholderPainter oldDelegate) {
    return oldDelegate.visualInput != visualInput ||
        oldDelegate.onPaint != onPaint;
  }
}

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

Color _placeholderColor(AgentPresenceState state) {
  return switch (state) {
    AgentPresenceState.idle => const Color(0xFF4B4F82),
    AgentPresenceState.listening => const Color(0xFF3C817E),
    AgentPresenceState.thinking => const Color(0xFF54538E),
    AgentPresenceState.speaking => const Color(0xFF477690),
    AgentPresenceState.working => const Color(0xFF707452),
    AgentPresenceState.error => const Color(0xFF9A5C53),
  };
}
