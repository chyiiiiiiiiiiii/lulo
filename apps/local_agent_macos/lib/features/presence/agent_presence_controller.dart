import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'agent_presence_state.dart';

/// Immutable visual data consumed by the agent-presence painter.
final class AgentPresenceVisualInput {
  /// Creates visual data sampled at an injected monotonic [sampledAt] time.
  const AgentPresenceVisualInput({
    required this.snapshot,
    required this.amplitude,
    required this.sampledAt,
  });

  /// The current state-transition snapshot.
  final AgentPresenceSnapshot snapshot;

  /// The filtered, normalized amplitude supplied to the painter.
  final double amplitude;

  /// The monotonic time at which this input was published.
  final Duration sampledAt;
}

/// Feature-local state reducer and filtered audio-input adapter for presence.
final class AgentPresenceController {
  /// Creates a controller with deterministic idle presentation state.
  AgentPresenceController()
    : _semanticStateNotifier = ValueNotifier<AgentPresenceState>(
        AgentPresenceState.idle,
      ),
      _visualInputNotifier = ValueNotifier<AgentPresenceVisualInput>(
        const AgentPresenceVisualInput(
          snapshot: AgentPresenceSnapshot.idle(),
          amplitude: 0,
          sampledAt: Duration.zero,
        ),
      );

  static const Duration _minimumSampleInterval = Duration(milliseconds: 16);
  static const Duration _maximumEnvelopeDelta = Duration(milliseconds: 100);
  static const Duration _attack = Duration(milliseconds: 55);
  static const Duration _release = Duration(milliseconds: 180);
  static const double _noiseFloor = 0.018;
  static const double _ceiling = 0.42;
  static const double _silenceSnap = 0.012;

  final AgentPresenceReducer _reducer = const AgentPresenceReducer();
  final ValueNotifier<AgentPresenceState> _semanticStateNotifier;
  final ValueNotifier<AgentPresenceVisualInput> _visualInputNotifier;
  AgentPresenceSnapshot _snapshot = const AgentPresenceSnapshot.idle();
  Duration? _lastAudioSampleAt;
  double _amplitude = 0;
  bool _isDisposed = false;

  /// Notifies only when the semantic target state changes.
  ValueListenable<AgentPresenceState> get semanticStateListenable =>
      _semanticStateNotifier;

  /// Notifies on semantic transitions and accepted audio samples only.
  ValueListenable<AgentPresenceVisualInput> get visualInputListenable =>
      _visualInputNotifier;

  /// Reduces an explicit [event] at the injected monotonic [now] time.
  void dispatch(AgentPresenceEvent event, Duration now) {
    if (_isDisposed) {
      return;
    }

    final AgentPresenceSnapshot next = _reducer.reduce(
      _snapshot,
      event: event,
      now: now,
    );
    if (identical(next, _snapshot)) {
      return;
    }
    _applySnapshot(next, now);
  }

  /// Projects a conversation-derived state without fabricating event states.
  void projectConversationState(
    AgentPresenceProjectionState state,
    Duration now,
  ) {
    if (_isDisposed) {
      return;
    }

    final AgentPresenceSnapshot next = _reducer.projectConversationState(
      _snapshot,
      state: state,
      now: now,
    );
    if (identical(next, _snapshot)) {
      return;
    }
    _applySnapshot(next, now);
  }

  /// Accepts one normalized RMS [rms] sample at monotonic [now].
  ///
  /// Non-finite, stale, and backwards-time samples are ignored. Other finite
  /// samples are clamped to the normalized range before envelope filtering.
  void acceptAudioRms(double rms, Duration now) {
    if (_isDisposed || !rms.isFinite) {
      return;
    }

    final Duration? previousSampleAt = _lastAudioSampleAt;
    if (previousSampleAt != null) {
      final Duration elapsed = now - previousSampleAt;
      if (elapsed < _minimumSampleInterval) {
        return;
      }
    }

    final Duration elapsed = previousSampleAt == null
        ? Duration.zero
        : now - previousSampleAt;
    _lastAudioSampleAt = now;
    final double normalizedRms = rms.clamp(0.0, 1.0).toDouble();
    final double target =
        ((normalizedRms - _noiseFloor) / (_ceiling - _noiseFloor))
            .clamp(0.0, 1.0)
            .toDouble();
    final Duration boundedElapsed = elapsed > _maximumEnvelopeDelta
        ? _maximumEnvelopeDelta
        : elapsed;
    final Duration timeConstant = target > _amplitude ? _attack : _release;
    final double smoothing =
        1 -
        math.exp(-boundedElapsed.inMicroseconds / timeConstant.inMicroseconds);
    double next = _amplitude + (target - _amplitude) * smoothing;
    if (target < _amplitude && next < _silenceSnap) {
      next = 0;
    }
    _amplitude = next;
    _publishVisual(now);
  }

  /// Disposes both narrow listenables and ignores all later input.
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _semanticStateNotifier.dispose();
    _visualInputNotifier.dispose();
  }

  void _publishVisual(Duration now) {
    _visualInputNotifier.value = AgentPresenceVisualInput(
      snapshot: _snapshot,
      amplitude: _amplitude,
      sampledAt: now,
    );
  }

  void _applySnapshot(AgentPresenceSnapshot next, Duration now) {
    _snapshot = next;
    if (_semanticStateNotifier.value != next.state) {
      _semanticStateNotifier.value = next.state;
    }
    _publishVisual(now);
  }
}
