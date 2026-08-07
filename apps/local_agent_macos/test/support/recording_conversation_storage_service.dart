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

  /// Every query the fake was searched with, in order.
  final List<String> searches = <String>[];

  @override
  Future<List<ConversationSummary>> searchConversations(String query) async {
    searches.add(query);
    return const <ConversationSummary>[];
  }

  /// Every rename the fake was asked for, newest last.
  final List<({ConversationId id, String title})> renames =
      <({ConversationId id, String title})>[];

  /// Every pin change the fake was asked for, newest last.
  final List<({ConversationId id, bool pinned})> pins =
      <({ConversationId id, bool pinned})>[];

  @override
  Future<void> renameConversation(
    ConversationId conversationId,
    String title,
  ) async {
    renames.add((id: conversationId, title: title));
  }

  @override
  Future<void> setConversationPinned(
    ConversationId conversationId, {
    required bool pinned,
  }) async {
    pins.add((id: conversationId, pinned: pinned));
  }

  /// Every conversation taken back to its last question, in order.
  final List<ConversationId> droppedFromLastQuestion = <ConversationId>[];

  @override
  Future<void> dropFromLastQuestion(ConversationId conversationId) async {
    droppedFromLastQuestion.add(conversationId);
  }

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

  /// Runs opened, in the order they were opened.
  final List<RunRecord> begunRuns = <RunRecord>[];

  /// Every checkpoint written, in order, as the text it was given.
  final List<String> checkpoints = <String>[];

  /// How each closed run ended, in the order they closed.
  final List<TurnStatus> endedRuns = <TurnStatus>[];

  /// What [loadUnfinishedRuns] should return.
  List<RunRecord> unfinishedRuns = <RunRecord>[];

  @override
  Future<void> beginRun(RunRecord run) async {
    begunRuns.add(run);
    lifecycle.add('run-begun');
  }

  @override
  Future<void> checkpointRun(
    GenerationId generationId,
    String partialText,
  ) async {
    checkpoints.add(partialText);
    lifecycle.add('run-checkpointed');
  }

  @override
  Future<void> endRun(GenerationId generationId, TurnStatus outcome) async {
    endedRuns.add(outcome);
    lifecycle.add('run-ended');
  }

  @override
  Future<List<RunRecord>> loadUnfinishedRuns() async =>
      List<RunRecord>.unmodifiable(unfinishedRuns);
}
