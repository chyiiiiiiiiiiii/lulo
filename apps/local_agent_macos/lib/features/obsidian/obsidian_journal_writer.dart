import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../../platform/desktop_host_service.dart';
import '../conversation/conversation_storage_service.dart';

/// Appends one entry to a day's page in the user's own notes.
typedef AppendToVault =
    Future<DesktopVaultStatus> Function({
      required String fileName,
      required String header,
      required String entry,
    });

/// The store, with every finished exchange also written into the user's notes.
///
/// A decorator rather than a hook inside the repository, because this is a
/// storage concern and it has to be possible to have the app without it: with
/// the setting off, or with no folder chosen, the composition root simply does
/// not wrap. Nothing downstream knows it is there.
///
/// The rules it keeps, in the order they matter:
///
/// **The vault never decides whether a turn is stored.** Everything delegates
/// first and mirrors afterwards, and a vault on a dead network share, a
/// deleted folder, or a revoked grant is recorded in [lastWrite] and
/// otherwise ignored. Losing the app's own record because somebody's Dropbox
/// was unmounted would be a far worse failure than not mirroring.
///
/// **Only finished answers.** A cancelled or failed turn is a decision the
/// user made or a fault they saw, not something to file in their notes a year
/// from now — and a journal that cannot retract must not write what it would
/// want to take back.
///
/// See `agent_core`'s `obsidian_journal.dart` for why the page is a day, and
/// why nothing already written is ever rewritten.
final class ObsidianJournalWriter implements ConversationStorageService {
  /// Wraps [inner], mirroring finished exchanges through [append].
  ObsidianJournalWriter({
    required ConversationStorageService inner,
    required AppendToVault append,
    required ValueListenable<bool> enabled,
    required ValueListenable<String> heading,
    DateTime Function() clock = DateTime.now,
  }) : this._(inner, append, enabled, heading, clock);

  ObsidianJournalWriter._(
    this._inner,
    this._append,
    this._enabled,
    this._heading,
    this._clock,
  );

  final ConversationStorageService _inner;
  final AppendToVault _append;
  final ValueListenable<bool> _enabled;
  final ValueListenable<String> _heading;
  final DateTime Function() _clock;

  /// How the last attempt to write into the vault ended, or null before any.
  ///
  /// Read by Settings. A mirror that has quietly stopped working is worse
  /// than one that was never turned on, because the user believes their
  /// thinking is being kept somewhere it is not.
  final ValueNotifier<DesktopVaultStatus?> lastWrite =
      ValueNotifier<DesktopVaultStatus?>(null);

  @override
  Future<void> saveTerminalAssistantTurn(
    Turn turn,
    Generation generation,
  ) async {
    await _inner.saveTerminalAssistantTurn(turn, generation);
    if (!_enabled.value ||
        turn.status != TurnStatus.completed ||
        turn.text.trim().isEmpty) {
      return;
    }
    final DateTime at = _clock();
    try {
      lastWrite.value = await _append(
        fileName: obsidianJournalFileName(at),
        header: obsidianJournalHeader(at, heading: _heading.value),
        entry: obsidianJournalEntry(
          at: at,
          question: generation.request.prompt,
          answer: turn.text,
        ),
      );
    } on Object {
      // Whatever went wrong out there, the turn is already stored.
      lastWrite.value = DesktopVaultStatus.failed;
    }
  }

  @override
  Future<List<Turn>> loadTurns(ConversationId conversationId) =>
      _inner.loadTurns(conversationId);

  @override
  Future<void> saveUserTurn(ConversationId conversationId, Turn turn) =>
      _inner.saveUserTurn(conversationId, turn);

  @override
  Future<List<ConversationSummary>> listConversations() =>
      _inner.listConversations();

  @override
  Future<List<ConversationSummary>> searchConversations(String query) =>
      _inner.searchConversations(query);

  @override
  Future<void> renameConversation(
    ConversationId conversationId,
    String title,
  ) => _inner.renameConversation(conversationId, title);

  @override
  Future<void> setConversationPinned(
    ConversationId conversationId, {
    required bool pinned,
  }) => _inner.setConversationPinned(conversationId, pinned: pinned);

  @override
  Future<void> deleteConversation(ConversationId conversationId) =>
      _inner.deleteConversation(conversationId);

  @override
  Future<void> dropFromLastQuestion(ConversationId conversationId) =>
      _inner.dropFromLastQuestion(conversationId);

  @override
  Future<void> beginRun(RunRecord run) => _inner.beginRun(run);

  @override
  Future<void> checkpointRun(GenerationId generationId, String partialText) =>
      _inner.checkpointRun(generationId, partialText);

  @override
  Future<void> endRun(GenerationId generationId, TurnStatus outcome) =>
      _inner.endRun(generationId, outcome);

  @override
  Future<List<RunRecord>> loadUnfinishedRuns() => _inner.loadUnfinishedRuns();
}
