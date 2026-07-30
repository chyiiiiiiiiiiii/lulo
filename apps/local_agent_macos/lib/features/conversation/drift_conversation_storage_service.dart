import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'conversation_storage_service.dart';

part 'drift_conversation_storage_service.g.dart';

/// The stored turns, one row per thing said.
///
/// The only table there is: a conversation is whatever rows share a
/// `conversationId`, its title is the first user row, and its recency is its
/// newest row. Deriving the list this way leaves no second copy of the truth
/// to fall out of step with the turns themselves.
class TurnRows extends Table {
  /// Monotonic insertion order, which is also the order things were said.
  IntColumn get id => integer().autoIncrement()();

  /// The conversation this turn belongs to.
  TextColumn get conversationId => text()();

  /// Who said it: stored by name, so reordering the enum cannot silently
  /// rewrite history.
  TextColumn get role => text()();

  /// How the turn ended, stored by name for the same reason as [role].
  TextColumn get status => text()();

  /// What was said. Named `content` because `text` is the column builder.
  TextColumn get content => text()();

  /// When it was saved, in milliseconds since the epoch.
  IntColumn get savedAtMs => integer()();
}

/// The SQLite database holding every conversation.
@DriftDatabase(tables: <Type>[TurnRows])
final class ConversationDatabase extends _$ConversationDatabase {
  /// Opens the database on [executor].
  ConversationDatabase(super.executor);

  /// Opens the durable database at [file], off the UI isolate.
  ///
  /// A background isolate because ADR-003's adopted control is drift's
  /// generated queries on `NativeDatabase.createInBackground`: writes are
  /// microseconds, but the UI thread should not be the one finding out when
  /// they are not.
  ConversationDatabase.atFile(File file)
    : super(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (OpeningDetails details) async {
      // Crash consistency over raw speed, per the ADR's conservative control.
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = FULL');
    },
  );
}

/// The durable [ConversationStorageService], on SQLite through drift.
final class DriftConversationStorageService
    implements ConversationStorageService {
  /// Creates the service over an already-open database.
  DriftConversationStorageService({
    required this._database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ConversationDatabase _database;
  final DateTime Function() _clock;

  static const String _userRole = 'user';
  static const String _assistantRole = 'assistant';

  @override
  Future<List<Turn>> loadTurns(ConversationId conversationId) async {
    final List<TurnRow> rows =
        await (_database.select(_database.turnRows)
              ..where(
                ($TurnRowsTable t) =>
                    t.conversationId.equals(conversationId.value),
              )
              ..orderBy(<OrderClauseGenerator<$TurnRowsTable>>[
                ($TurnRowsTable t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return List<Turn>.unmodifiable(rows.map(_turnFromRow));
  }

  @override
  Future<void> saveUserTurn(ConversationId conversationId, Turn turn) {
    return _insert(conversationId, turn);
  }

  @override
  Future<void> saveTerminalAssistantTurn(Turn turn, Generation generation) {
    return _insert(generation.request.conversationId, turn);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    // The list is derived from the turns: title is the first user row, and
    // recency is the newest row's insertion order — monotonic even when two
    // turns land inside the same millisecond.
    final List<QueryRow> rows = await _database
        .customSelect(
          'SELECT conversation_id, '
          '  (SELECT content FROM turn_rows AS titles '
          '   WHERE titles.conversation_id = turns.conversation_id '
          "   AND titles.role = 'user' "
          '   ORDER BY titles.id LIMIT 1) AS title, '
          '  MAX(saved_at_ms) AS updated_at_ms '
          'FROM turn_rows AS turns '
          'GROUP BY conversation_id '
          'ORDER BY MAX(id) DESC',
          readsFrom: <TableInfo<Table, Object?>>{_database.turnRows},
        )
        .get();
    return List<ConversationSummary>.unmodifiable(
      rows.map(
        (QueryRow row) => ConversationSummary(
          id: ConversationId(row.read<String>('conversation_id')),
          title: row.readNullable<String>('title') ?? '',
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('updated_at_ms'),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> deleteConversation(ConversationId conversationId) async {
    await (_database.delete(_database.turnRows)..where(
          ($TurnRowsTable t) => t.conversationId.equals(conversationId.value),
        ))
        .go();
  }

  /// Closes the database this service owns.
  Future<void> dispose() => _database.close();

  Future<void> _insert(ConversationId conversationId, Turn turn) async {
    await _database
        .into(_database.turnRows)
        .insert(
          TurnRowsCompanion.insert(
            conversationId: conversationId.value,
            role: turn.role == TurnRole.user ? _userRole : _assistantRole,
            status: turn.status.name,
            content: turn.text,
            savedAtMs: _clock().millisecondsSinceEpoch,
          ),
        );
  }

  Turn _turnFromRow(TurnRow row) {
    return Turn(
      role: row.role == _userRole ? TurnRole.user : TurnRole.assistant,
      text: row.content,
      status: TurnStatus.values.asNameMap()[row.status] ?? TurnStatus.failed,
    );
  }
}
