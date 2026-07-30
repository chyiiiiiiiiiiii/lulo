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

  /// Opens the durable database at [file], on this isolate.
  ///
  /// ADR-003 adopted `createInBackground`, but the background isolate's own
  /// native-asset resolution maps sqlite3.framework a second time into the
  /// process, and a statement created through one mapping crashes when it
  /// reaches the other — a branch to null inside sqlite3_bind_int64
  /// (upstream: simolus3/sqlite3.dart#381, our report
  /// Lulo-2026-07-30-231954.ips shows the double mapping). One isolate, one
  /// mapping; writes are microseconds per the ADR's own benchmark, and the
  /// background isolate returns when the upstream fix lands.
  ConversationDatabase.atFile(File file) : super(NativeDatabase(file));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA journal_mode = WAL');
      // NORMAL, not FULL: in WAL mode NORMAL still cannot corrupt the file —
      // a power cut costs at most the last commits — and FULL's per-commit
      // F_FULLFSYNC is a 10-50ms device-cache flush that now lands on the
      // calling isolate, right at the moment the user presses send.
      await customStatement('PRAGMA synchronous = NORMAL');
      // The conversation list derives everything from the turns; without
      // this the derivation is a full scan with a correlated subquery.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_turn_rows_conversation '
        'ON turn_rows (conversation_id, id)',
      );
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
