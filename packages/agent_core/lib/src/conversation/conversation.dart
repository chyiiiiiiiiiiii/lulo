import 'conversation_id.dart';
import 'turn.dart';

/// A conversation and its stored turns.
final class Conversation {
  /// Creates a conversation with its stable [id] and immutable [turns].
  Conversation({required this.id, List<Turn> turns = const <Turn>[]})
    : turns = List<Turn>.unmodifiable(turns);

  /// The stable conversation identifier.
  final ConversationId id;

  /// The immutable turns that belong to this conversation.
  final List<Turn> turns;
}

/// A conversation state with completed history and an optional active turn.
final class ConversationProjection {
  /// Creates a projection from immutable [completedTurns] and [activeTurn].
  factory ConversationProjection({
    required List<Turn> completedTurns,
    Turn? activeTurn,
  }) {
    _validateCompletedTurns(completedTurns);
    _validateActiveTurn(activeTurn);
    return ConversationProjection._(
      completedTurns: List<Turn>.unmodifiable(completedTurns),
      activeTurn: activeTurn,
    );
  }

  ConversationProjection._({required this.completedTurns, this.activeTurn});

  /// The immutable completed conversation history.
  final List<Turn> completedTurns;

  /// The turn currently receiving streamed content, if any.
  final Turn? activeTurn;

  static void _validateCompletedTurns(List<Turn> turns) {
    for (final Turn turn in turns) {
      if (!_isTerminal(turn.status)) {
        throw ArgumentError.value(
          turn.status,
          'completedTurns',
          'must contain only terminal turns',
        );
      }
    }
  }

  static void _validateActiveTurn(Turn? activeTurn) {
    if (activeTurn != null && activeTurn.status != TurnStatus.streaming) {
      throw ArgumentError.value(
        activeTurn.status,
        'activeTurn',
        'must be streaming',
      );
    }
  }

  static bool _isTerminal(TurnStatus status) => switch (status) {
    TurnStatus.completed => true,
    TurnStatus.cancelled => true,
    TurnStatus.failed => true,
    TurnStatus.streaming => false,
  };
}
