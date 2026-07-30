import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';

final class SavedAssistantTurn {
  const SavedAssistantTurn({required this.turn, required this.generation});

  final Turn turn;
  final Generation generation;
}

final class RecordingConversationStorageService
    implements ConversationStorageService {
  final List<Turn> loadedTurns = <Turn>[];
  final List<Turn> userTurns = <Turn>[];
  final List<SavedAssistantTurn> assistantTurns = <SavedAssistantTurn>[];
  final List<String> lifecycle = <String>[];

  Completer<void>? userSaveGate;
  Object? terminalSaveError;

  @override
  Future<List<Turn>> loadTurns(ConversationId conversationId) async {
    return List<Turn>.unmodifiable(loadedTurns);
  }

  @override
  Future<void> saveUserTurn(ConversationId conversationId, Turn turn) async {
    final Completer<void>? gate = userSaveGate;
    if (gate != null) {
      await gate.future;
    }

    userTurns.add(turn);
    lifecycle.add('user-saved');
  }

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<void> deleteConversation(ConversationId conversationId) async {}

  @override
  Future<void> saveTerminalAssistantTurn(
    Turn turn,
    Generation generation,
  ) async {
    final Object? error = terminalSaveError;
    if (error != null) {
      throw error;
    }
    assistantTurns.add(SavedAssistantTurn(turn: turn, generation: generation));
    lifecycle.add('assistant-saved');
  }
}
