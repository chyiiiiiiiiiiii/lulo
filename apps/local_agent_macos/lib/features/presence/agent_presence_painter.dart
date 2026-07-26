import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_state.dart';

/// Receives scalar runtime-shader uniforms by their declared float index.
abstract interface class AgentPresenceUniformSink {
  /// Writes one scalar [value] at [index].
  void setFloat(int index, double value);
}

/// Creates one mutable backend for a mounted shader painter.
typedef AgentPresenceShaderBackendFactory =
    AgentPresenceShaderBackend Function();

/// Creates the production runtime-effect backend.
AgentPresenceShaderBackend createAgentPresenceShaderBackend() =>
    _RuntimeAgentPresenceShaderBackend();

/// Testable frame boundary around shader instantiation, upload, and draw.
abstract interface class AgentPresenceShaderBackend
    implements AgentPresenceUniformSink {
  /// Instantiates the fragment shader for one frame.
  void beginFrame(ui.FragmentProgram program);

  /// Draws the prepared frame inside [clipPath].
  void draw(Canvas canvas, Size size, Path clipPath);
}

/// Receives a latched first-paint failure after the failed frame completes.
typedef AgentPresencePaintFailureCallback = void Function(Object error);

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
    required this.motionEnabled,
    AgentPresenceShaderBackend? backend,
    this.failurePainter,
    this.onFailure,
    this.colorStrength = 1,
    this.onPaint,
  }) : _backend = backend ?? createAgentPresenceShaderBackend(),
       super(repaint: repaint);

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

  /// Live narrow input controlling motion and amplitude deformation.
  final ValueListenable<bool> motionEnabled;

  /// Dark-ramp colour intensity, normally one.
  final double colorStrength;

  /// Optional paint instrumentation used by isolation tests.
  final VoidCallback? onPaint;

  /// Canvas fallback used for the first failed shader frame.
  final CustomPainter? failurePainter;

  /// Reports the first setup/upload/draw failure after the frame.
  final AgentPresencePaintFailureCallback? onFailure;

  final AgentPresenceShaderBackend _backend;
  final Path _clipPath = Path();
  Size _clipSize = Size.zero;
  bool _failureLatched = false;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint?.call();
    if (_clipSize != size) {
      _clipPath
        ..reset()
        ..addOval(Offset.zero & size);
      _clipSize = size;
    }
    if (_failureLatched) {
      failurePainter?.paint(canvas, size);
      return;
    }
    try {
      _backend.beginFrame(program);
      writeUniforms(_backend, size);
      _backend.draw(canvas, size, _clipPath);
    } on Object catch (error) {
      _failureLatched = true;
      failurePainter?.paint(canvas, size);
      final AgentPresencePaintFailureCallback? callback = onFailure;
      if (callback != null) {
        SchedulerBinding.instance.addPostFrameCallback((Duration _) {
          callback(error);
        });
      }
    }
  }

  @override
  bool shouldRepaint(AgentPresencePainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.visualInput != visualInput ||
        oldDelegate.phase != phase ||
        oldDelegate.now != now ||
        oldDelegate.motionEnabled != motionEnabled ||
        oldDelegate._backend != _backend ||
        oldDelegate.failurePainter != failurePainter ||
        oldDelegate.onFailure != onFailure ||
        oldDelegate.colorStrength != colorStrength ||
        oldDelegate.onPaint != onPaint;
  }

  /// Uploads one deterministic frame to [sink].
  void writeUniforms(AgentPresenceUniformSink sink, Size size) {
    final Duration frameNow = now();
    _uniformBinder.write(
      sink,
      size: size,
      visualInput: visualInput.value,
      now: frameNow,
      timeSeconds: frameNow.inMicroseconds / Duration.microsecondsPerSecond,
      motionEnabled: motionEnabled.value,
      colorStrength: colorStrength,
    );
  }
}

final class _RuntimeAgentPresenceShaderBackend
    implements AgentPresenceShaderBackend {
  late ui.FragmentShader shader;
  final Paint _paint = Paint();

  @override
  void beginFrame(ui.FragmentProgram program) {
    shader = program.fragmentShader();
  }

  @override
  void draw(Canvas canvas, Size size, Path clipPath) {
    _paint.shader = shader;
    canvas
      ..save()
      ..clipPath(clipPath)
      ..drawPaint(_paint)
      ..restore();
  }

  @override
  void setFloat(int index, double value) {
    shader.setFloat(index, value);
  }
}
