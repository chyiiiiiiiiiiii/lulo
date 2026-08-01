import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('a completed user turn can retain voice refinement provenance', () {
    final TranscriptRefinement refinement = TranscriptRefinement(
      rawTranscript: '我用 flutter',
      proposedTranscript: '我用 Flutter',
      selectedTranscript: '我用 Flutter',
      status: TranscriptRefinementStatus.applied,
      edits: const <TranscriptEdit>[
        TranscriptEdit(
          rawStart: 3,
          rawEnd: 10,
          replacement: 'Flutter',
          kind: TranscriptEditKind.vocabulary,
        ),
      ],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: 'deterministic',
      refinerVersion: '1',
      elapsed: const Duration(milliseconds: 2),
    );
    final Turn turn = Turn.voice(voiceInput: refinement);

    expect(turn.voiceInput?.rawTranscript, '我用 flutter');
    expect(turn.copyWith().voiceInput, same(refinement));
  });

  test('voice provenance is rejected on incompatible turns', () {
    final TranscriptRefinement refinement = TranscriptRefinement(
      rawTranscript: 'raw',
      proposedTranscript: null,
      selectedTranscript: 'raw',
      status: TranscriptRefinementStatus.unchanged,
      edits: const <TranscriptEdit>[],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: 'deterministic',
      refinerVersion: '1',
      elapsed: Duration.zero,
    );

    expect(
      () =>
          Turn.voice(voiceInput: refinement).copyWith(role: TurnRole.assistant),
      throwsArgumentError,
    );
  });

  test('appending a streaming assistant turn leaves completed turns unchanged', () {
    // Mutation caught: changing Turn.append to mutate shared state or append to
    // the wrong turn would alter the completed user text or leave the delta out.
    final Turn completedTurn = Turn(
      role: TurnRole.user,
      text: 'Summarize today.',
      status: TurnStatus.completed,
    );
    final Turn activeTurn = Turn(
      role: TurnRole.assistant,
      text: 'Today was ',
      status: TurnStatus.streaming,
    );
    final ConversationProjection projection = ConversationProjection(
      completedTurns: <Turn>[completedTurn],
      activeTurn: activeTurn,
    );

    final Turn appendedTurn = projection.activeTurn!.append('productive.');

    expect(appendedTurn.text, 'Today was productive.');
    expect(projection.activeTurn!.text, 'Today was ');
    expect(projection.completedTurns.single.text, 'Summarize today.');
    expect(projection.completedTurns.single.status, TurnStatus.completed);
  });

  test('terminal status transitions retain streamed assistant text', () {
    // Mutation caught: rebuilding a turn for a terminal status with an empty
    // text value would discard a response that was already streamed.
    const Turn streamingTurn = Turn(
      role: TurnRole.assistant,
      text: 'The local model is ready.',
      status: TurnStatus.streaming,
    );

    for (final TurnStatus terminalStatus in <TurnStatus>[
      TurnStatus.completed,
      TurnStatus.cancelled,
      TurnStatus.failed,
    ]) {
      final Turn terminalTurn = streamingTurn.copyWith(status: terminalStatus);

      expect(terminalTurn.text, 'The local model is ready.');
      expect(terminalTurn.status, terminalStatus);
      expect(streamingTurn.status, TurnStatus.streaming);
    }
  });

  test('GenerationId compares equal when its value is equal', () {
    // Mutation caught: comparing GenerationId instances by identity would make
    // the same stable generation value fail to match across boundaries.
    expect(GenerationId('generation-1'), equals(GenerationId('generation-1')));
  });

  test(
    'projection rejects streaming history and owns an immutable snapshot',
    () {
      // Mutation caught: accepting streaming history would make completed state
      // contradictory; retaining or exposing the caller list would let later
      // mutations rewrite completed history.
      const Turn streamingTurn = Turn(
        role: TurnRole.assistant,
        text: 'Working',
        status: TurnStatus.streaming,
      );

      expect(
        () => ConversationProjection(completedTurns: <Turn>[streamingTurn]),
        throwsA(isA<ArgumentError>()),
      );

      final List<Turn> callerTurns = <Turn>[
        const Turn(
          role: TurnRole.user,
          text: 'Keep this.',
          status: TurnStatus.completed,
        ),
      ];
      final ConversationProjection projection = ConversationProjection(
        completedTurns: callerTurns,
      );

      callerTurns.add(
        const Turn(
          role: TurnRole.assistant,
          text: 'Do not leak this.',
          status: TurnStatus.cancelled,
        ),
      );

      expect(projection.completedTurns, hasLength(1));
      expect(projection.completedTurns.single.text, 'Keep this.');
      expect(
        () => projection.completedTurns.add(streamingTurn),
        throwsUnsupportedError,
      );
    },
  );

  test('projection rejects terminal turns as active state', () {
    // Mutation caught: dropping active-turn status validation would allow a
    // completed, cancelled, or failed response to be represented as streaming.
    for (final TurnStatus terminalStatus in <TurnStatus>[
      TurnStatus.completed,
      TurnStatus.cancelled,
      TurnStatus.failed,
    ]) {
      final Turn terminalTurn = Turn(
        role: TurnRole.assistant,
        text: 'Already terminal.',
        status: terminalStatus,
      );

      expect(
        () => ConversationProjection(
          completedTurns: const <Turn>[],
          activeTurn: terminalTurn,
        ),
        throwsA(isA<ArgumentError>()),
      );
    }
  });
}
