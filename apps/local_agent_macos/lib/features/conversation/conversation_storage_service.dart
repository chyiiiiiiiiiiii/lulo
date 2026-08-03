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

/// One generation as it was recorded while it was still running.
///
/// A turn is written once, when it is over. That leaves the whole of a long
/// answer in memory until the moment it finishes, so a crash or a force-quit
/// loses every word of it and leaves nothing behind to say a generation ever
/// happened. A run is the record that survives: opened when generation
/// starts, overwritten with the answer so far as it streams, and closed when
/// it reaches a terminal state.
final class RunRecord {
  /// Creates a record of one generation.
  const RunRecord({
    required this.id,
    required this.conversationId,
    required this.modelId,
    required this.startedAt,
    this.endedAt,
    this.outcome,
    this.partialText = '',
  });

  /// The generation this run records.
  final GenerationId id;

  /// The conversation the generation belongs to.
  final ConversationId conversationId;

  /// What produced it, so an answer can be read in the light of the model
  /// that wrote it rather than whichever one is installed now.
  final String modelId;

  /// When generation started.
  final DateTime startedAt;

  /// When it reached a terminal state, absent while it is still running.
  final DateTime? endedAt;

  /// How it ended, absent while it is still running.
  final TurnStatus? outcome;

  /// The answer as of the last checkpoint.
  ///
  /// The whole answer so far, not the last delta: a checkpoint overwrites.
  final String partialText;

  /// Whether this run reached a terminal state.
  bool get isFinished => endedAt != null;

  @override
  String toString() =>
      'RunRecord(id: ${id.value}, conversation: ${conversationId.value}, '
      'model: $modelId, startedAt: $startedAt, endedAt: $endedAt, '
      'outcome: $outcome, partialText: ${partialText.length} chars)';
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

  /// Opens a durable record for a generation that has just started.
  Future<void> beginRun(RunRecord run);

  /// Overwrites the recorded answer for [generationId] with [partialText].
  ///
  /// Overwrites rather than appends: [partialText] is the whole answer so
  /// far. A run that was never begun, or has already been cleaned up, is
  /// ignored rather than reported — checkpoints arrive on a timer, and one
  /// landing late must not take the generation down with it.
  Future<void> checkpointRun(GenerationId generationId, String partialText);

  /// Closes the record for [generationId] with how it ended.
  ///
  /// Closing a run that is already closed, or was never begun, is ignored
  /// for the same reason as [checkpointRun].
  Future<void> endRun(GenerationId generationId, TurnStatus outcome);

  /// Every run that was opened and never closed, oldest first.
  ///
  /// On a clean run this is empty. Anything in it is the residue of a
  /// process that did not survive its own generation.
  Future<List<RunRecord>> loadUnfinishedRuns();
}
