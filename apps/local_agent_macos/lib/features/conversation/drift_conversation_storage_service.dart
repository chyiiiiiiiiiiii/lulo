import 'dart:convert';
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

  /// Exact recognizer output for a voice-authored user turn.
  TextColumn get rawTranscript => text().nullable()();

  /// Applied proposal, absent when raw text was selected.
  TextColumn get refinedTranscript => text().nullable()();

  /// [TranscriptRefinementStatus.name] for voice input.
  TextColumn get refinementStatus => text().nullable()();

  /// Stable refiner implementation identity.
  TextColumn get refinerId => text().nullable()();

  /// Refiner implementation or model version.
  TextColumn get refinerVersion => text().nullable()();

  /// JSON edit trail, rejection categories, and elapsed microseconds.
  TextColumn get refinementEditsJson => text().nullable()();
}

/// One generation, written while it runs rather than after it ends.
///
/// Separate from [TurnRows] on purpose. A turn is what was said and is
/// written once; a run is the act of saying it, overwritten as it streams,
/// and only some runs ever become turns. Merging them would put a row that
/// changes every half second into the table every conversation read scans.
class RunRows extends Table {
  /// Insertion order, and the row's identity.
  ///
  /// Deliberately not [generationId]. Those are only unique within one
  /// inference service, and a new one is built every time the user changes
  /// model — its counter restarts, so `litert-generation-1` comes round
  /// again. Keyed by the generation, the second run landed on top of the
  /// first: it rewrote that run's conversation and model, and because the row
  /// already carried an end time every later checkpoint and the close were
  /// filtered out by the not-yet-ended scope. Run recording died silently at
  /// the first model change.
  IntColumn get id => integer().autoIncrement()();

  /// The generation this run records.
  ///
  /// Unique only among runs that are open at the same time, which is what the
  /// checkpoint and close scopes rely on.
  TextColumn get generationId => text()();

  /// The conversation the generation belongs to.
  TextColumn get conversationId => text()();

  /// What produced the answer.
  TextColumn get modelId => text()();

  /// When generation started, in milliseconds since the epoch.
  IntColumn get startedAtMs => integer()();

  /// When it reached a terminal state; null while it is still running.
  IntColumn get endedAtMs => integer().nullable()();

  /// [TurnStatus.name]; null while it is still running.
  TextColumn get outcome => text().nullable()();

  /// The whole answer as of the last checkpoint, not the last delta.
  TextColumn get partialText =>
      text().withDefault(const Constant<String>(''))();
}

/// What the user has decided about a conversation, as opposed to what was
/// said in it.
///
/// A separate table rather than columns on the turns, because a conversation
/// has no row of its own: it is whatever turns share a `conversationId`, and
/// that is deliberate — it leaves no second copy of the truth to fall out of
/// step. This holds only the things the turns cannot derive. A conversation
/// nobody has renamed or pinned has no row here at all.
class ConversationMetaRows extends Table {
  /// The conversation these decisions belong to.
  TextColumn get conversationId => text()();

  /// The name the user gave it, or null to keep the derived one.
  TextColumn get title => text().nullable()();

  /// When it was pinned, or null if it is not.
  ///
  /// A time rather than a flag so that pinned conversations keep an order of
  /// their own — most recently pinned first — instead of falling back to a
  /// recency the user pinned them to escape.
  IntColumn get pinnedAtMs => integer().nullable()();

  /// One row per conversation, keyed by the conversation itself.
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{conversationId};
}

/// The SQLite database holding every conversation.
@DriftDatabase(tables: <Type>[TurnRows, RunRows, ConversationMetaRows])
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 2) {
        await migrator.addColumn(turnRows, turnRows.rawTranscript);
        await migrator.addColumn(turnRows, turnRows.refinedTranscript);
        await migrator.addColumn(turnRows, turnRows.refinementStatus);
        await migrator.addColumn(turnRows, turnRows.refinerId);
        await migrator.addColumn(turnRows, turnRows.refinerVersion);
        await migrator.addColumn(turnRows, turnRows.refinementEditsJson);
      }
      if (from < 3) {
        await migrator.createTable(runRows);
      }
      if (from < 4) {
        // Schema 3 keyed runs by their generation id, which repeats after a
        // model change. Nothing has ever been recovered from these rows, and
        // an open run only means the last process died mid-answer, so the
        // table is rebuilt rather than migrated row by row.
        await migrator.deleteTable(runRows.actualTableName);
        await migrator.createTable(runRows);
      }
      if (from < 5) {
        await migrator.createTable(conversationMetaRows);
      }
    },
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
  Future<List<ConversationSummary>> listConversations() =>
      _summaries(match: null);

  /// The list, optionally narrowed to conversations containing [match].
  ///
  /// One query for both because the shape is the same: the title is the user's
  /// own if they set one and the first thing they said otherwise, and the
  /// order is pinned first — newest pin leading — then recency, which is the
  /// newest row's insertion order and stays monotonic even when two turns
  /// land inside the same millisecond.
  Future<List<ConversationSummary>> _summaries({required String? match}) async {
    final List<QueryRow> rows = await _database
        .customSelect(
          'SELECT turns.conversation_id AS conversation_id, '
          '  COALESCE(NULLIF(meta.title, \'\'), ('
          '    SELECT content FROM turn_rows AS titles '
          '    WHERE titles.conversation_id = turns.conversation_id '
          "    AND titles.role = 'user' "
          '    ORDER BY titles.id LIMIT 1'
          '  )) AS title, '
          '  MAX(turns.saved_at_ms) AS updated_at_ms, '
          '  meta.pinned_at_ms AS pinned_at_ms '
          'FROM turn_rows AS turns '
          'LEFT JOIN conversation_meta_rows AS meta '
          '  ON meta.conversation_id = turns.conversation_id '
          '${match == null ? '' : 'WHERE (turns.conversation_id IN ('
                    '  SELECT conversation_id FROM turn_rows '
                    r"  WHERE content LIKE ?1 ESCAPE '\'"
                    ') OR turns.conversation_id IN ('
                    '  SELECT conversation_id FROM conversation_meta_rows '
                    r"  WHERE title LIKE ?1 ESCAPE '\'"
                    ')) '}'
          'GROUP BY turns.conversation_id '
          'ORDER BY meta.pinned_at_ms IS NULL, meta.pinned_at_ms DESC, '
          '  MAX(turns.id) DESC',
          variables: <Variable<Object>>[
            if (match != null) Variable<String>('%$match%'),
          ],
          readsFrom: <TableInfo<Table, Object?>>{
            _database.turnRows,
            _database.conversationMetaRows,
          },
        )
        .get();
    return List<ConversationSummary>.unmodifiable(rows.map(_summaryFrom));
  }

  /// One list row, however it was selected.
  ConversationSummary _summaryFrom(QueryRow row) => ConversationSummary(
    id: ConversationId(row.read<String>('conversation_id')),
    title: row.readNullable<String>('title') ?? '',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('updated_at_ms'),
    ),
    isPinned: row.readNullable<int>('pinned_at_ms') != null,
  );

  @override
  Future<List<ConversationSummary>> searchConversations(String query) {
    final String needle = query.trim();
    if (needle.isEmpty) {
      return listConversations();
    }
    // LIKE rather than a full-text index, deliberately. FTS5 tokenizes on
    // non-alphanumerics, and Chinese has no word breaks: 「台中天氣」 would be
    // one token and 「中天」 would find nothing. A substring scan over a store
    // one person talks into is cheap, and it is the only thing that answers
    // the question the user is actually asking.
    //
    // Escaped so a query containing % or _ searches for those characters
    // rather than matching everything.
    return _summaries(
      match: needle
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_'),
    );
  }

  @override
  Future<void> renameConversation(
    ConversationId conversationId,
    String title,
  ) async {
    await _database
        .into(_database.conversationMetaRows)
        .insertOnConflictUpdate(
          ConversationMetaRowsCompanion(
            conversationId: Value<String>(conversationId.value),
            title: Value<String?>(title.trim().isEmpty ? null : title.trim()),
          ),
        );
  }

  @override
  Future<void> setConversationPinned(
    ConversationId conversationId, {
    required bool pinned,
  }) async {
    int? at;
    if (pinned) {
      // Strictly above every existing pin rather than simply "now". Two pins
      // inside one millisecond are the same instant, and the order then falls
      // through to recency — which is the exact ordering a pin exists to
      // override.
      final List<QueryRow> highest = await _database
          .customSelect(
            'SELECT MAX(pinned_at_ms) AS top FROM conversation_meta_rows',
            readsFrom: <TableInfo<Table, Object?>>{
              _database.conversationMetaRows,
            },
          )
          .get();
      final int? top = highest.single.readNullable<int>('top');
      final int now = DateTime.now().millisecondsSinceEpoch;
      at = top == null || now > top ? now : top + 1;
    }
    await _database
        .into(_database.conversationMetaRows)
        .insertOnConflictUpdate(
          ConversationMetaRowsCompanion(
            conversationId: Value<String>(conversationId.value),
            pinnedAtMs: Value<int?>(at),
          ),
        );
  }

  @override
  Future<void> deleteConversation(ConversationId conversationId) async {
    await (_database.delete(_database.turnRows)..where(
          ($TurnRowsTable t) => t.conversationId.equals(conversationId.value),
        ))
        .go();
    await (_database.delete(_database.runRows)..where(
          ($RunRowsTable r) => r.conversationId.equals(conversationId.value),
        ))
        .go();
    await (_database.delete(_database.conversationMetaRows)..where(
          ($ConversationMetaRowsTable m) =>
              m.conversationId.equals(conversationId.value),
        ))
        .go();
  }

  @override
  Future<void> dropFromLastQuestion(ConversationId conversationId) async {
    // Found and cut by row id rather than by time. `saved_at_ms` repeats
    // whenever two turns land inside the same millisecond, which is exactly
    // what a question and the answer to it can do; the id is also the order
    // `loadTurns` hands the caller.
    final TurnRow? question =
        await (_database.select(_database.turnRows)
              ..where(
                ($TurnRowsTable t) =>
                    t.conversationId.equals(conversationId.value) &
                    t.role.equals(TurnRole.user.name),
              )
              ..orderBy(<OrderClauseGenerator<$TurnRowsTable>>[
                ($TurnRowsTable t) => OrderingTerm.desc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (question == null) {
      return;
    }
    await (_database.delete(_database.turnRows)..where(
          ($TurnRowsTable t) =>
              t.conversationId.equals(conversationId.value) &
              t.id.isBiggerOrEqualValue(question.id),
        ))
        .go();
    // A conversation with no turns left is off the list, so what the user
    // decided about it is unreachable — and would otherwise attach itself to
    // whatever was said in that id next.
    final int remaining =
        await (_database.select(_database.turnRows)..where(
              ($TurnRowsTable t) =>
                  t.conversationId.equals(conversationId.value),
            ))
            .get()
            .then((List<TurnRow> rows) => rows.length);
    if (remaining == 0) {
      await (_database.delete(_database.conversationMetaRows)..where(
            ($ConversationMetaRowsTable m) =>
                m.conversationId.equals(conversationId.value),
          ))
          .go();
    }
  }

  @override
  Future<void> beginRun(RunRecord run) async {
    await _database
        .into(_database.runRows)
        .insert(
          RunRowsCompanion.insert(
            generationId: run.id.value,
            conversationId: run.conversationId.value,
            modelId: run.modelId,
            startedAtMs: run.startedAt.millisecondsSinceEpoch,
            partialText: Value<String>(run.partialText),
          ),
        );
  }

  @override
  Future<void> checkpointRun(
    GenerationId generationId,
    String partialText,
  ) async {
    // Scoped to rows that have not ended, so a checkpoint arriving after the
    // terminal event cannot rewrite a closed run's answer.
    await (_database.update(_database.runRows)..where(
          ($RunRowsTable r) =>
              r.generationId.equals(generationId.value) & r.endedAtMs.isNull(),
        ))
        .write(RunRowsCompanion(partialText: Value<String>(partialText)));
  }

  @override
  Future<void> endRun(GenerationId generationId, TurnStatus outcome) async {
    await (_database.update(_database.runRows)..where(
          ($RunRowsTable r) =>
              r.generationId.equals(generationId.value) & r.endedAtMs.isNull(),
        ))
        .write(
          RunRowsCompanion(
            endedAtMs: Value<int?>(_clock().millisecondsSinceEpoch),
            outcome: Value<String?>(outcome.name),
          ),
        );
  }

  @override
  Future<List<RunRecord>> loadUnfinishedRuns() async {
    final List<RunRow> rows =
        await (_database.select(_database.runRows)
              ..where(($RunRowsTable r) => r.endedAtMs.isNull())
              ..orderBy(<OrderClauseGenerator<$RunRowsTable>>[
                ($RunRowsTable r) => OrderingTerm.asc(r.startedAtMs),
              ]))
            .get();
    return List<RunRecord>.unmodifiable(
      rows.map(
        (RunRow row) => RunRecord(
          id: GenerationId(row.generationId),
          conversationId: ConversationId(row.conversationId),
          modelId: row.modelId,
          startedAt: DateTime.fromMillisecondsSinceEpoch(row.startedAtMs),
          partialText: row.partialText,
        ),
      ),
    );
  }

  /// Closes the database this service owns.
  Future<void> dispose() => _database.close();

  Future<void> _insert(ConversationId conversationId, Turn turn) async {
    final TranscriptRefinement? voiceInput = turn.voiceInput;
    await _database
        .into(_database.turnRows)
        .insert(
          TurnRowsCompanion.insert(
            conversationId: conversationId.value,
            role: turn.role == TurnRole.user ? _userRole : _assistantRole,
            status: turn.status.name,
            content: turn.text,
            savedAtMs: _clock().millisecondsSinceEpoch,
            rawTranscript: Value<String?>(voiceInput?.rawTranscript),
            refinedTranscript: Value<String?>(
              voiceInput?.status == TranscriptRefinementStatus.applied
                  ? voiceInput?.proposedTranscript
                  : null,
            ),
            refinementStatus: Value<String?>(voiceInput?.status.name),
            refinerId: Value<String?>(voiceInput?.refinerId),
            refinerVersion: Value<String?>(voiceInput?.refinerVersion),
            refinementEditsJson: Value<String?>(
              voiceInput == null ? null : _encodeRefinementDetails(voiceInput),
            ),
          ),
        );
  }

  Turn _turnFromRow(TurnRow row) {
    final Turn plain = Turn(
      role: row.role == _userRole ? TurnRole.user : TurnRole.assistant,
      text: row.content,
      status: TurnStatus.values.asNameMap()[row.status] ?? TurnStatus.failed,
    );
    if (plain.role != TurnRole.user ||
        plain.status != TurnStatus.completed ||
        row.rawTranscript == null ||
        row.refinementStatus == null ||
        row.refinerId == null ||
        row.refinerVersion == null ||
        row.refinementEditsJson == null) {
      return plain;
    }
    try {
      final TranscriptRefinementStatus? status = TranscriptRefinementStatus
          .values
          .asNameMap()[row.refinementStatus];
      if (status == null) {
        return plain;
      }
      final Map<String, Object?> details =
          jsonDecode(row.refinementEditsJson!) as Map<String, Object?>;
      final List<Object?> rawEdits = details['edits']! as List<Object?>;
      final List<Object?> rawReasons =
          details['rejectionReasons']! as List<Object?>;
      final TranscriptRefinement refinement = TranscriptRefinement(
        rawTranscript: row.rawTranscript!,
        proposedTranscript: row.refinedTranscript,
        selectedTranscript: row.content,
        status: status,
        edits: rawEdits
            .map((Object? value) {
              final Map<String, Object?> edit = value! as Map<String, Object?>;
              return TranscriptEdit(
                rawStart: edit['rawStart']! as int,
                rawEnd: edit['rawEnd']! as int,
                replacement: edit['replacement']! as String,
                kind: TranscriptEditKind.values.asNameMap()[edit['kind']]!,
              );
            })
            .toList(growable: false),
        rejectionReasons: rawReasons
            .map(
              (Object? value) =>
                  TranscriptRejectionReason.values.asNameMap()[value]!,
            )
            .toList(growable: false),
        refinerId: row.refinerId!,
        refinerVersion: row.refinerVersion!,
        elapsed: Duration(microseconds: details['elapsedMicros']! as int),
      );
      return Turn.voice(voiceInput: refinement);
    } on Object {
      return plain;
    }
  }
}

String _encodeRefinementDetails(TranscriptRefinement refinement) =>
    jsonEncode(<String, Object?>{
      'edits': <Object?>[
        for (final TranscriptEdit edit in refinement.edits)
          <String, Object?>{
            'rawStart': edit.rawStart,
            'rawEnd': edit.rawEnd,
            'replacement': edit.replacement,
            'kind': edit.kind.name,
          },
      ],
      'rejectionReasons': <String>[
        for (final TranscriptRejectionReason reason
            in refinement.rejectionReasons)
          reason.name,
      ],
      'elapsedMicros': refinement.elapsed.inMicroseconds,
    });
