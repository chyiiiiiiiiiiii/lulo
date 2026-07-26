import 'package:agent_core/agent_core.dart';

/// Persists durable conversation turns independently of a storage backend.
abstract interface class ConversationStorageService {
  /// Loads the terminal history for [conversationId].
  Future<List<Turn>> loadTurns(ConversationId conversationId);

  /// Persists a completed user [turn].
  Future<void> saveUserTurn(Turn turn);

  /// Persists one terminal assistant [turn] and its owning [generation].
  Future<void> saveTerminalAssistantTurn(Turn turn, Generation generation);
}
