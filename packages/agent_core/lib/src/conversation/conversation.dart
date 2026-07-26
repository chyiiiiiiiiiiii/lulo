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
  ConversationProjection({required List<Turn> completedTurns, this.activeTurn})
    : completedTurns = List<Turn>.unmodifiable(completedTurns);

  /// The immutable completed conversation history.
  final List<Turn> completedTurns;

  /// The turn currently receiving streamed content, if any.
  final Turn? activeTurn;
}
