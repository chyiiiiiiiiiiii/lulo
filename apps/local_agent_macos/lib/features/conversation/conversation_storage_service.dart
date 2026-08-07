import 'package:agent_core/agent_core.dart';

/// One conversation as the list shows it, without its turns.
final class ConversationSummary {
  /// Creates a summary of one stored conversation.
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.isPinned = false,
  });

  /// The conversation's stable identity.
  final ConversationId id;

  /// What the list calls it: the first thing the user said in it.
  final String title;

  /// When something was last said in it.
  final DateTime updatedAt;

  /// Whether the user has kept it at the top of the list.
  final bool isPinned;

  @override
  bool operator ==(Object other) =>
      other is ConversationSummary &&
      other.id == id &&
      other.title == title &&
      other.updatedAt == updatedAt &&
      other.isPinned == isPinned;

  @override
  int get hashCode => Object.hash(id, title, updatedAt, isPinned);

  @override
  String toString() =>
      'ConversationSummary(id: ${id.value}, title: $title, '
      'updatedAt: $updatedAt, isPinned: $isPinned)';
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

  /// Every stored conversation containing [query], most recent first.
  ///
  /// Matches anywhere in any turn, not only in the title: the title is the
  /// first question, and a user often remembers a conversation by what it
  /// told them rather than by what they asked.
  ///
  /// Substring rather than whole word, and deliberately not a full-text
  /// index. FTS tokenizes on non-alphanumerics and Chinese has no word
  /// breaks, so 「台中天氣」 would be one token and 「中天」 would find nothing.
  /// A blank query is not a search and returns everything, so the field the
  /// user types into behaves like a filter.
  Future<List<ConversationSummary>> searchConversations(String query);

  /// Gives [conversationId] the name [title], or restores the derived one.
  ///
  /// A blank title clears the override rather than storing an empty name, so
  /// undoing a rename needs no second copy of what the user first said — the
  /// derived title was never overwritten, only shadowed.
  Future<void> renameConversation(ConversationId conversationId, String title);

  /// Keeps [conversationId] at the top of the list, or lets it go.
  ///
  /// Recorded as a time rather than a flag so the pinned ones keep an order
  /// of their own — most recently pinned first — instead of falling back to
  /// the recency the user pinned them to escape.
  Future<void> setConversationPinned(
    ConversationId conversationId, {
    required bool pinned,
  });

  /// Forgets [conversationId] and every turn in it.
  Future<void> deleteConversation(ConversationId conversationId);

  /// Forgets the last question in [conversationId] and everything after it.
  ///
  /// What a retry needs. Asking the last question again replaces the answer
  /// on screen, and rewriting the question replaces both it and its answer;
  /// either way what is being replaced has to leave the store too, or the
  /// next launch reads it back and shows the user a conversation they never
  /// had. The question goes with it because both callers put it back.
  ///
  /// Named by what it means rather than by a count of turns. Turns carry no
  /// identity, so a positional cut is the obvious alternative — but the view
  /// hides an answer that was cancelled before it said anything while the
  /// store keeps it, so a position counted from the screen is not a position
  /// in the store. The last question is the same turn in both.
  ///
  /// A conversation with no question in it is left alone.
  Future<void> dropFromLastQuestion(ConversationId conversationId);

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
