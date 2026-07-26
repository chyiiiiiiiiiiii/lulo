/// The semantic presentation state of the local agent presence indicator.
enum AgentPresenceState {
  /// The agent has no active presentation work.
  idle,

  /// The agent is waiting for a user transcript.
  listening,

  /// The agent is processing a committed transcript.
  thinking,

  /// The agent is visibly producing a response.
  speaking,

  /// The agent is performing a user-meaningful operation.
  working,

  /// The agent needs acknowledgement or a meaningful recovery event.
  error,
}

/// An explicit presentation input for [AgentPresenceReducer].
enum AgentPresenceEvent {
  /// Requests the idle state when the current state permits it.
  idleRequested,

  /// Starts listening for a user transcript.
  listeningStarted,

  /// Records that a transcript was committed.
  transcriptCommitted,

  /// Starts visible response production.
  speechStarted,

  /// Stops visible response production.
  speechStopped,

  /// Starts a user-meaningful operation.
  workStarted,

  /// Completes the current user-meaningful operation.
  workCompleted,

  /// Records a presentation failure.
  failed,

  /// Acknowledges a visible failure.
  errorAcknowledged,
}

/// Immutable six-state blend weights for the presence visual.
final class AgentPresenceWeights {
  /// Creates a six-state blend vector.
  const AgentPresenceWeights({
    required this.idle,
    required this.listening,
    required this.thinking,
    required this.speaking,
    required this.working,
    required this.error,
  });

  /// A one-hot vector for [AgentPresenceState.idle].
  static const AgentPresenceWeights idleOnly = AgentPresenceWeights(
    idle: 1,
    listening: 0,
    thinking: 0,
    speaking: 0,
    working: 0,
    error: 0,
  );

  /// A one-hot vector for [AgentPresenceState.listening].
  static const AgentPresenceWeights listeningOnly = AgentPresenceWeights(
    idle: 0,
    listening: 1,
    thinking: 0,
    speaking: 0,
    working: 0,
    error: 0,
  );

  /// A one-hot vector for [AgentPresenceState.thinking].
  static const AgentPresenceWeights thinkingOnly = AgentPresenceWeights(
    idle: 0,
    listening: 0,
    thinking: 1,
    speaking: 0,
    working: 0,
    error: 0,
  );

  /// A one-hot vector for [AgentPresenceState.speaking].
  static const AgentPresenceWeights speakingOnly = AgentPresenceWeights(
    idle: 0,
    listening: 0,
    thinking: 0,
    speaking: 1,
    working: 0,
    error: 0,
  );

  /// A one-hot vector for [AgentPresenceState.working].
  static const AgentPresenceWeights workingOnly = AgentPresenceWeights(
    idle: 0,
    listening: 0,
    thinking: 0,
    speaking: 0,
    working: 1,
    error: 0,
  );

  /// A one-hot vector for [AgentPresenceState.error].
  static const AgentPresenceWeights errorOnly = AgentPresenceWeights(
    idle: 0,
    listening: 0,
    thinking: 0,
    speaking: 0,
    working: 0,
    error: 1,
  );

  /// Idle-state blend weight.
  final double idle;

  /// Listening-state blend weight.
  final double listening;

  /// Thinking-state blend weight.
  final double thinking;

  /// Speaking-state blend weight.
  final double speaking;

  /// Working-state blend weight.
  final double working;

  /// Error-state blend weight.
  final double error;

  /// The weights in [AgentPresenceState.values] order.
  List<double> get values => <double>[
    idle,
    listening,
    thinking,
    speaking,
    working,
    error,
  ];

  /// Returns the weight for [state].
  double forState(AgentPresenceState state) {
    switch (state) {
      case AgentPresenceState.idle:
        return idle;
      case AgentPresenceState.listening:
        return listening;
      case AgentPresenceState.thinking:
        return thinking;
      case AgentPresenceState.speaking:
        return speaking;
      case AgentPresenceState.working:
        return working;
      case AgentPresenceState.error:
        return error;
    }
  }

  AgentPresenceWeights _blendTo(AgentPresenceState state, double progress) {
    final AgentPresenceWeights target = _oneHot(state);
    return AgentPresenceWeights(
      idle: _interpolate(idle, target.idle, progress),
      listening: _interpolate(listening, target.listening, progress),
      thinking: _interpolate(thinking, target.thinking, progress),
      speaking: _interpolate(speaking, target.speaking, progress),
      working: _interpolate(working, target.working, progress),
      error: _interpolate(error, target.error, progress),
    );
  }
}

/// Immutable reducer output for one semantic state transition.
final class AgentPresenceSnapshot {
  /// Creates the initial settled idle snapshot.
  const AgentPresenceSnapshot.idle()
    : state = AgentPresenceState.idle,
      sourceWeights = AgentPresenceWeights.idleOnly,
      transitionStartedAt = Duration.zero,
      transitionDuration = Duration.zero;

  const AgentPresenceSnapshot._({
    required this.state,
    required this.sourceWeights,
    required this.transitionStartedAt,
    required this.transitionDuration,
  });

  /// The current semantic target state.
  final AgentPresenceState state;

  /// The blend vector captured at the start of this transition.
  final AgentPresenceWeights sourceWeights;

  /// The injected monotonic time at which this transition began.
  final Duration transitionStartedAt;

  /// The fixed duration for this transition.
  final Duration transitionDuration;

  /// Computes the deterministic blend vector at a monotonic [now].
  AgentPresenceWeights weightsAt(Duration now) {
    if (transitionDuration == Duration.zero) {
      return _oneHot(state);
    }
    final Duration elapsed = now - transitionStartedAt;
    if (elapsed <= Duration.zero) {
      return sourceWeights;
    }
    if (elapsed >= transitionDuration) {
      return _oneHot(state);
    }
    final double progress =
        elapsed.inMicroseconds / transitionDuration.inMicroseconds;
    return sourceWeights._blendTo(state, progress);
  }

  /// Returns an equivalent settled snapshot sampled at monotonic [now].
  AgentPresenceSnapshot settledAt(Duration now) {
    return AgentPresenceSnapshot._(
      state: state,
      sourceWeights: _oneHot(state),
      transitionStartedAt: now,
      transitionDuration: Duration.zero,
    );
  }
}

/// Pure reducer for explicit agent-presence state transitions.
final class AgentPresenceReducer {
  /// Creates a pure reducer with the documented transition table.
  const AgentPresenceReducer();

  static const Map<AgentPresenceState, Map<AgentPresenceEvent, _Transition>>
  _transitionTable = <AgentPresenceState, Map<AgentPresenceEvent, _Transition>>{
    AgentPresenceState.idle: <AgentPresenceEvent, _Transition>{
      AgentPresenceEvent.listeningStarted: _Transition.listening,
      AgentPresenceEvent.failed: _Transition.error,
    },
    AgentPresenceState.listening: <AgentPresenceEvent, _Transition>{
      AgentPresenceEvent.transcriptCommitted:
          _Transition.thinkingFromTranscript,
      AgentPresenceEvent.speechStopped: _Transition.idle,
      AgentPresenceEvent.failed: _Transition.error,
    },
    AgentPresenceState.thinking: <AgentPresenceEvent, _Transition>{
      AgentPresenceEvent.speechStarted: _Transition.speaking,
      AgentPresenceEvent.workStarted: _Transition.working,
      AgentPresenceEvent.failed: _Transition.error,
    },
    AgentPresenceState.speaking: <AgentPresenceEvent, _Transition>{
      AgentPresenceEvent.speechStopped: _Transition.idle,
      AgentPresenceEvent.workStarted: _Transition.working,
      AgentPresenceEvent.failed: _Transition.error,
    },
    AgentPresenceState.working: <AgentPresenceEvent, _Transition>{
      AgentPresenceEvent.workCompleted: _Transition.thinkingFromWork,
      AgentPresenceEvent.failed: _Transition.error,
    },
    AgentPresenceState.error: <AgentPresenceEvent, _Transition>{
      AgentPresenceEvent.errorAcknowledged: _Transition.idle,
      AgentPresenceEvent.listeningStarted: _Transition.listening,
      AgentPresenceEvent.transcriptCommitted:
          _Transition.thinkingFromTranscript,
      AgentPresenceEvent.speechStarted: _Transition.speaking,
      AgentPresenceEvent.workStarted: _Transition.working,
    },
  };

  /// Reduces [snapshot] with [event] sampled at monotonic [now].
  ///
  /// Unknown transitions and repeated target requests preserve [snapshot].
  AgentPresenceSnapshot reduce(
    AgentPresenceSnapshot snapshot, {
    required AgentPresenceEvent event,
    required Duration now,
  }) {
    final _Transition? transition = _transitionTable[snapshot.state]?[event];
    if (transition == null || transition.state == snapshot.state) {
      return snapshot;
    }
    return AgentPresenceSnapshot._(
      state: transition.state,
      sourceWeights: snapshot.weightsAt(now),
      transitionStartedAt: now,
      transitionDuration: transition.duration,
    );
  }
}

final class _Transition {
  const _Transition(this.state, this.duration);

  static const Duration _short = Duration(milliseconds: 140);
  static const Duration _standard = Duration(milliseconds: 180);
  static const Duration _transcript = Duration(milliseconds: 150);
  static const Duration _errorArrival = Duration(milliseconds: 160);

  static const _Transition idle = _Transition(
    AgentPresenceState.idle,
    _standard,
  );
  static const _Transition listening = _Transition(
    AgentPresenceState.listening,
    _standard,
  );
  static const _Transition thinkingFromTranscript = _Transition(
    AgentPresenceState.thinking,
    _transcript,
  );
  static const _Transition thinkingFromWork = _Transition(
    AgentPresenceState.thinking,
    _short,
  );
  static const _Transition speaking = _Transition(
    AgentPresenceState.speaking,
    _standard,
  );
  static const _Transition working = _Transition(
    AgentPresenceState.working,
    _short,
  );
  static const _Transition error = _Transition(
    AgentPresenceState.error,
    _errorArrival,
  );

  final AgentPresenceState state;
  final Duration duration;
}

AgentPresenceWeights _oneHot(AgentPresenceState state) {
  switch (state) {
    case AgentPresenceState.idle:
      return AgentPresenceWeights.idleOnly;
    case AgentPresenceState.listening:
      return AgentPresenceWeights.listeningOnly;
    case AgentPresenceState.thinking:
      return AgentPresenceWeights.thinkingOnly;
    case AgentPresenceState.speaking:
      return AgentPresenceWeights.speakingOnly;
    case AgentPresenceState.working:
      return AgentPresenceWeights.workingOnly;
    case AgentPresenceState.error:
      return AgentPresenceWeights.errorOnly;
  }
}

double _interpolate(double from, double to, double progress) =>
    from + (to - from) * progress;
