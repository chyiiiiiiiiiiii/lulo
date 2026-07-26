import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
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
}
