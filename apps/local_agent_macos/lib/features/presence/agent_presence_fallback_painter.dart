import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_state.dart';

/// Canvas-only agent-presence rendering used before or instead of a shader.
final class AgentPresenceFallbackPainter extends CustomPainter {
  /// Creates a fallback painter driven by the narrow visual input.
  AgentPresenceFallbackPainter({
    required this.visualInput,
    required Listenable repaint,
    this.onPaint,
  }) : super(repaint: repaint);

  /// Current state and filtered amplitude.
  final ValueListenable<AgentPresenceVisualInput> visualInput;

  /// Optional paint instrumentation used by tests.
  final VoidCallback? onPaint;

  final Paint _paint = Paint();
  final Path _clipPath = Path()
    ..addOval(Rect.fromCircle(center: const Offset(28, 28), radius: 27.5));
  late final Map<AgentPresenceState, ui.Gradient> _gradients =
      <AgentPresenceState, ui.Gradient>{
        AgentPresenceState.idle: _gradient(
          const Color(0xFF515986),
          const Color(0xFF282B45),
        ),
        AgentPresenceState.listening: _gradient(
          const Color(0xFF4C8582),
          const Color(0xFF253C43),
        ),
        AgentPresenceState.thinking: _gradient(
          const Color(0xFF5B5790),
          const Color(0xFF2B2D4B),
        ),
        AgentPresenceState.speaking: _gradient(
          const Color(0xFF4B7991),
          const Color(0xFF263A4A),
        ),
        AgentPresenceState.working: _gradient(
          const Color(0xFF77734F),
          const Color(0xFF304241),
        ),
        AgentPresenceState.error: _gradient(
          const Color(0xFF965E54),
          const Color(0xFF493432),
        ),
      };

  @override
  void paint(Canvas canvas, Size size) {
    onPaint?.call();
    _paint.shader = _gradients[visualInput.value.snapshot.state];
    canvas
      ..save()
      ..clipPath(_clipPath)
      ..drawCircle(size.center(Offset.zero), 27.5, _paint)
      ..restore();
  }

  @override
  bool shouldRepaint(AgentPresenceFallbackPainter oldDelegate) {
    return oldDelegate.visualInput != visualInput ||
        oldDelegate.onPaint != onPaint;
  }
}

ui.Gradient _gradient(Color center, Color middle) => ui.Gradient.radial(
  const Offset(25, 23),
  29,
  <Color>[center, middle, const Color(0x0010141B)],
  <double>[0, 0.62, 1],
);
