import 'package:agent_core/agent_core.dart';

/// One conversation as the list shows it, without its turns.
final class ConversationSummary {
  /// Creates a summary of one stored conversation.
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  /// The conversation's stable identity.
  final ConversationId id;

  /// What the list calls it: the first thing the user said in it.
  final String title;

  /// When something was last said in it.
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is ConversationSummary &&
      other.id == id &&
      other.title == title &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, title, updatedAt);

  @override
  String toString() =>
      'ConversationSummary(id: ${id.value}, title: $title, '
      'updatedAt: $updatedAt)';
}

/// Persists durable conversation turns independently of a storage backend.
abstract interface class ConversationStorageService {
  /// Loads the terminal history for [conversationId].
  Future<List<Turn>> loadTurns(ConversationId conversationId);

  /// Persists a completed user [turn] belonging to [conversationId].
  ///
  /// The turn itself carries no conversation identity, so the caller names
  /// it — recorded in ADR-003, which found the earlier shape unable to say
  /// which conversation a user turn belonged to.
  Future<void> saveUserTurn(ConversationId conversationId, Turn turn);

  /// Persists one terminal assistant [turn] and its owning [generation].
  Future<void> saveTerminalAssistantTurn(Turn turn, Generation generation);

  /// Every stored conversation, most recently spoken-in first.
  ///
  /// A conversation exists once something has been said in it; an id that was
  /// only ever minted does not appear.
  Future<List<ConversationSummary>> listConversations();

  /// Forgets [conversationId] and every turn in it.
  Future<void> deleteConversation(ConversationId conversationId);
}
