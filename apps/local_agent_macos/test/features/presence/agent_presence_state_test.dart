import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

void main() {
  group('AgentPresenceReducer', () {
    test(
      'documented transitions select the target state and arrival duration',
      () {
        final AgentPresenceReducer reducer = AgentPresenceReducer();
        final List<_TransitionCase> cases = <_TransitionCase>[
          _TransitionCase(
            from: AgentPresenceState.idle,
            event: AgentPresenceEvent.listeningStarted,
            to: AgentPresenceState.listening,
            duration: const Duration(milliseconds: 180),
          ),
          _TransitionCase(
            from: AgentPresenceState.listening,
            event: AgentPresenceEvent.transcriptCommitted,
            to: AgentPresenceState.thinking,
            duration: const Duration(milliseconds: 150),
          ),
          _TransitionCase(
            from: AgentPresenceState.listening,
            event: AgentPresenceEvent.speechStopped,
            to: AgentPresenceState.idle,
            duration: const Duration(milliseconds: 180),
          ),
          _TransitionCase(
            from: AgentPresenceState.thinking,
            event: AgentPresenceEvent.speechStarted,
            to: AgentPresenceState.speaking,
            duration: const Duration(milliseconds: 180),
          ),
          _TransitionCase(
            from: AgentPresenceState.thinking,
            event: AgentPresenceEvent.workStarted,
            to: AgentPresenceState.working,
            duration: const Duration(milliseconds: 140),
          ),
          _TransitionCase(
            from: AgentPresenceState.speaking,
            event: AgentPresenceEvent.speechStopped,
            to: AgentPresenceState.idle,
            duration: const Duration(milliseconds: 180),
          ),
          _TransitionCase(
            from: AgentPresenceState.speaking,
            event: AgentPresenceEvent.workStarted,
            to: AgentPresenceState.working,
            duration: const Duration(milliseconds: 140),
          ),
          _TransitionCase(
            from: AgentPresenceState.working,
            event: AgentPresenceEvent.workCompleted,
            to: AgentPresenceState.thinking,
            duration: const Duration(milliseconds: 140),
          ),
        ];

        for (final _TransitionCase testCase in cases) {
          final Duration now = const Duration(seconds: 10);
          final AgentPresenceSnapshot next = reducer.reduce(
            _settledSnapshot(reducer, testCase.from),
            event: testCase.event,
            now: now,
          );

          expect(next.state, testCase.to, reason: '$testCase');
          expect(
            next.transitionDuration,
            testCase.duration,
            reason: '$testCase',
          );
          expect(
            next.weightsAt(now).forState(testCase.from),
            1,
            reason: '$testCase',
          );
          expect(
            next.weightsAt(now + testCase.duration).forState(testCase.to),
            1,
            reason: '$testCase',
          );
        }
      },
    );

    test('any non-error state enters error in 160 milliseconds', () {
      final AgentPresenceReducer reducer = AgentPresenceReducer();

      for (final AgentPresenceState state in AgentPresenceState.values) {
        if (state == AgentPresenceState.error) {
          continue;
        }
        final Duration now = const Duration(seconds: 10);
        final AgentPresenceSnapshot next = reducer.reduce(
          _settledSnapshot(reducer, state),
          event: AgentPresenceEvent.failed,
          now: now,
        );

        expect(next.state, AgentPresenceState.error);
        expect(next.transitionDuration, const Duration(milliseconds: 160));
        expect(
          next.weightsAt(now + const Duration(milliseconds: 160)).error,
          1,
        );
      }
    });

    test(
      'error acknowledgement and meaningful activity recover to their targets',
      () {
        final AgentPresenceReducer reducer = AgentPresenceReducer();
        final AgentPresenceSnapshot error = reducer.reduce(
          _settledSnapshot(reducer, AgentPresenceState.thinking),
          event: AgentPresenceEvent.failed,
          now: const Duration(seconds: 1),
        );
        final List<_RecoveryCase> cases = <_RecoveryCase>[
          _RecoveryCase(
            AgentPresenceEvent.errorAcknowledged,
            AgentPresenceState.idle,
            const Duration(milliseconds: 180),
          ),
          _RecoveryCase(
            AgentPresenceEvent.listeningStarted,
            AgentPresenceState.listening,
            const Duration(milliseconds: 180),
          ),
          _RecoveryCase(
            AgentPresenceEvent.transcriptCommitted,
            AgentPresenceState.thinking,
            const Duration(milliseconds: 150),
          ),
          _RecoveryCase(
            AgentPresenceEvent.speechStarted,
            AgentPresenceState.speaking,
            const Duration(milliseconds: 180),
          ),
          _RecoveryCase(
            AgentPresenceEvent.workStarted,
            AgentPresenceState.working,
            const Duration(milliseconds: 140),
          ),
        ];

        for (final _RecoveryCase testCase in cases) {
          final AgentPresenceSnapshot next = reducer.reduce(
            error,
            event: testCase.event,
            now: const Duration(seconds: 2),
          );

          expect(next.state, testCase.state, reason: '$testCase');
          expect(
            next.transitionDuration,
            testCase.duration,
            reason: '$testCase',
          );
        }
      },
    );

    test('repeating an event for the current target is a no-op', () {
      final AgentPresenceReducer reducer = AgentPresenceReducer();
      final AgentPresenceSnapshot listening = reducer.reduce(
        const AgentPresenceSnapshot.idle(),
        event: AgentPresenceEvent.listeningStarted,
        now: Duration.zero,
      );

      final AgentPresenceSnapshot repeated = reducer.reduce(
        listening,
        event: AgentPresenceEvent.listeningStarted,
        now: const Duration(milliseconds: 90),
      );

      expect(identical(repeated, listening), isTrue);
    });

    test('error remains until acknowledgement or meaningful activity', () {
      final AgentPresenceReducer reducer = AgentPresenceReducer();
      final AgentPresenceSnapshot error = reducer.reduce(
        const AgentPresenceSnapshot.idle(),
        event: AgentPresenceEvent.failed,
        now: Duration.zero,
      );

      final AgentPresenceSnapshot idleRequest = reducer.reduce(
        error,
        event: AgentPresenceEvent.idleRequested,
        now: const Duration(seconds: 1),
      );
      final AgentPresenceSnapshot stopRequest = reducer.reduce(
        error,
        event: AgentPresenceEvent.speechStopped,
        now: const Duration(seconds: 1),
      );

      expect(identical(idleRequest, error), isTrue);
      expect(identical(stopRequest, error), isTrue);
      expect(error.weightsAt(const Duration(seconds: 5)).error, 1);
    });

    test(
      'interrupting listening through thinking into working keeps weights normalized',
      () {
        final AgentPresenceReducer reducer = AgentPresenceReducer();
        final AgentPresenceSnapshot listening = reducer.reduce(
          const AgentPresenceSnapshot.idle(),
          event: AgentPresenceEvent.listeningStarted,
          now: Duration.zero,
        );
        final AgentPresenceSnapshot thinking = reducer.reduce(
          listening,
          event: AgentPresenceEvent.transcriptCommitted,
          now: const Duration(milliseconds: 90),
        );
        final AgentPresenceSnapshot working = reducer.reduce(
          thinking,
          event: AgentPresenceEvent.workStarted,
          now: const Duration(milliseconds: 180),
        );

        for (final Duration sample in <Duration>[
          const Duration(milliseconds: 90),
          const Duration(milliseconds: 180),
          const Duration(milliseconds: 250),
          const Duration(milliseconds: 320),
        ]) {
          final AgentPresenceWeights weights = working.weightsAt(sample);

          for (final double value in weights.values) {
            expect(value, greaterThanOrEqualTo(0), reason: 'at $sample');
          }
          expect(
            weights.values.reduce((double a, double b) => a + b),
            closeTo(1, 1e-12),
          );
        }
        expect(working.weightsAt(const Duration(milliseconds: 320)).working, 1);
      },
    );
  });
}

AgentPresenceSnapshot _settledSnapshot(
  AgentPresenceReducer reducer,
  AgentPresenceState state,
) {
  switch (state) {
    case AgentPresenceState.idle:
      return const AgentPresenceSnapshot.idle();
    case AgentPresenceState.listening:
      return _settle(
        reducer.reduce(
          const AgentPresenceSnapshot.idle(),
          event: AgentPresenceEvent.listeningStarted,
          now: Duration.zero,
        ),
      );
    case AgentPresenceState.thinking:
      return _settle(
        reducer.reduce(
          _settledSnapshot(reducer, AgentPresenceState.listening),
          event: AgentPresenceEvent.transcriptCommitted,
          now: Duration.zero,
        ),
      );
    case AgentPresenceState.speaking:
      return _settle(
        reducer.reduce(
          _settledSnapshot(reducer, AgentPresenceState.thinking),
          event: AgentPresenceEvent.speechStarted,
          now: Duration.zero,
        ),
      );
    case AgentPresenceState.working:
      return _settle(
        reducer.reduce(
          _settledSnapshot(reducer, AgentPresenceState.thinking),
          event: AgentPresenceEvent.workStarted,
          now: Duration.zero,
        ),
      );
    case AgentPresenceState.error:
      return _settle(
        reducer.reduce(
          const AgentPresenceSnapshot.idle(),
          event: AgentPresenceEvent.failed,
          now: Duration.zero,
        ),
      );
  }
}

AgentPresenceSnapshot _settle(AgentPresenceSnapshot snapshot) {
  return snapshot.settledAt(
    snapshot.transitionStartedAt + snapshot.transitionDuration,
  );
}

final class _TransitionCase {
  const _TransitionCase({
    required this.from,
    required this.event,
    required this.to,
    required this.duration,
  });

  final AgentPresenceState from;
  final AgentPresenceEvent event;
  final AgentPresenceState to;
  final Duration duration;

  @override
  String toString() => '$from + $event -> $to';
}

final class _RecoveryCase {
  const _RecoveryCase(this.event, this.state, this.duration);

  final AgentPresenceEvent event;
  final AgentPresenceState state;
  final Duration duration;

  @override
  String toString() => 'error + $event -> $state';
}
