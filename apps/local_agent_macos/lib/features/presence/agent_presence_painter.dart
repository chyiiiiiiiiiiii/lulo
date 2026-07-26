import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_state.dart';

/// Receives scalar runtime-shader uniforms by their declared float index.
abstract interface class AgentPresenceUniformSink {
  /// Writes one scalar [value] at [index].
  void setFloat(int index, double value);
}

/// Owns the single ordered upload site for the presence shader contract.
final class AgentPresenceUniformBinder {
  /// Creates the stateless uniform binder.
  const AgentPresenceUniformBinder();

  static const double _timeWrapSeconds = 4096;

  /// Writes all thirteen float slots in shader declaration order.
  void write(
    AgentPresenceUniformSink sink, {
    required Size size,
    required AgentPresenceVisualInput visualInput,
    required Duration now,
    required double timeSeconds,
    required bool motionEnabled,
    required double colorStrength,
  }) {
    final AgentPresenceWeights weights = visualInput.snapshot.weightsAt(now);
    final bool hasMotion =
        motionEnabled && visualInput.snapshot.state != AgentPresenceState.error;
    sink
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, timeSeconds % _timeWrapSeconds)
      ..setFloat(3, weights.idle)
      ..setFloat(4, weights.listening)
      ..setFloat(5, weights.thinking)
      ..setFloat(6, weights.speaking)
      ..setFloat(7, weights.working)
      ..setFloat(8, weights.error)
      ..setFloat(9, hasMotion ? visualInput.amplitude : 0)
      ..setFloat(10, hasMotion ? 1 : 0)
      ..setFloat(11, colorStrength.clamp(0.0, 1.0).toDouble())
      ..setFloat(12, 0.6180339887);
  }
}

/// Runtime-shader painter for one isolated agent-presence orb.
final class AgentPresencePainter extends CustomPainter {
  /// Creates a painter with cached paint, path, and shader instances.
  AgentPresencePainter({
    required this.program,
    required this.visualInput,
    required this.phase,
    required Listenable repaint,
    required this.now,
    this.motionEnabled = true,
    this.colorStrength = 1,
    this.onPaint,
  }) : super(repaint: repaint);

  static const double _cycleSeconds = 5.6;
  static const AgentPresenceUniformBinder _uniformBinder =
      AgentPresenceUniformBinder();

  /// Loaded program selected for this mounted orb.
  final ui.FragmentProgram program;

  /// Current state transition and filtered amplitude.
  final ValueListenable<AgentPresenceVisualInput> visualInput;

  /// Deterministic normalized animation phase.
  final Animation<double> phase;

  /// Supplies the monotonic transition sampling time.
  final Duration Function() now;

  /// Whether periodic motion and amplitude deformation are permitted.
  final bool motionEnabled;

  /// Dark-ramp colour intensity, normally one.
  final double colorStrength;

  /// Optional paint instrumentation used by isolation tests.
  final VoidCallback? onPaint;

  final Paint _paint = Paint();
  final Path _clipPath = Path();
  final _FragmentShaderUniformSink _uniformSink = _FragmentShaderUniformSink();
  Size _clipSize = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint?.call();
    if (_clipSize != size) {
      _clipPath
        ..reset()
        ..addOval(Offset.zero & size);
      _clipSize = size;
    }
    final ui.FragmentShader shader = program.fragmentShader();
    _uniformSink.shader = shader;
    _uniformBinder.write(
      _uniformSink,
      size: size,
      visualInput: visualInput.value,
      now: now(),
      timeSeconds: phase.value * _cycleSeconds,
      motionEnabled: motionEnabled,
      colorStrength: colorStrength,
    );
    _paint.shader = shader;
    canvas
      ..save()
      ..clipPath(_clipPath)
      ..drawPaint(_paint)
      ..restore();
  }

  @override
  bool shouldRepaint(AgentPresencePainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.visualInput != visualInput ||
        oldDelegate.phase != phase ||
        oldDelegate.now != now ||
        oldDelegate.motionEnabled != motionEnabled ||
        oldDelegate.colorStrength != colorStrength ||
        oldDelegate.onPaint != onPaint;
  }
}

final class _FragmentShaderUniformSink implements AgentPresenceUniformSink {
  late ui.FragmentShader shader;

  @override
  void setFloat(int index, double value) {
    shader.setFloat(index, value);
  }
}
