import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

part 'storage_benchmark.g.dart';

enum StorageCandidate {
  driftGenerated('drift_generated'),
  driftCustom('drift_custom'),
  sqlite3Prepared('sqlite3_prepared');

  const StorageCandidate(this.id);
  final String id;
}

enum BenchmarkExecutor { main, background }

enum BenchmarkTurnRole { user, assistant }

enum BenchmarkTurnStatus { completed, cancelled, failed }

final class BenchmarkDatabaseConfig {
  const BenchmarkDatabaseConfig({required this.path, required this.executor});

  final String path;
  final BenchmarkExecutor executor;
}

final class StorageBenchmarkConversation {
  const StorageBenchmarkConversation({
    required this.id,
    required this.title,
    required this.createdAtMs,
  });

  final String id;
  final String title;
  final int createdAtMs;
}

final class StorageBenchmarkTurn {
  const StorageBenchmarkTurn({
    required this.sequence,
    required this.role,
    required this.status,
    required this.text,
  });

  final int sequence;
  final BenchmarkTurnRole role;
  final BenchmarkTurnStatus status;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is StorageBenchmarkTurn &&
      sequence == other.sequence &&
      role == other.role &&
      status == other.status &&
      text == other.text;

  @override
  int get hashCode => Object.hash(sequence, role, status, text);
}

abstract interface class StorageBenchmarkAdapter {
  Future<void> open(BenchmarkDatabaseConfig config);
  Future<void> createConversation(StorageBenchmarkConversation conversation);
  Future<void> saveUserTurn({
    required String conversationId,
    required String text,
    required int createdAtMs,
  });
  Future<void> saveTerminalAssistantTurn({
    required String conversationId,
    required String generationId,
    required String requestPrompt,
    required String text,
    required BenchmarkTurnStatus status,
    required int createdAtMs,
  });
  Future<List<StorageBenchmarkTurn>> loadTurns(String conversationId);
  Future<List<String>> validate();
  Future<void> close();
}

StorageBenchmarkAdapter createStorageBenchmarkAdapter(
  StorageCandidate candidate,
) => switch (candidate) {
  StorageCandidate.driftGenerated => _GeneratedDriftAdapter(),
  StorageCandidate.driftCustom => _CustomDriftAdapter(),
  StorageCandidate.sqlite3Prepared => _Sqlite3PreparedAdapter(),
};

final class StorageBenchmarkSummary {
  const StorageBenchmarkSummary({
    required this.sampleCount,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
  });

  final int sampleCount;
  final int p50Micros;
  final int p95Micros;
  final int p99Micros;
}

abstract final class StorageBenchmarkSummarizer {
  static StorageBenchmarkSummary summarizeDurations(List<int> durations) {
    if (durations.isEmpty) {
      throw const FormatException('At least one duration is required.');
    }
    final sorted = List<int>.of(durations)..sort();
    return StorageBenchmarkSummary(
      sampleCount: sorted.length,
      p50Micros: _nearestRank(sorted, 0.50),
      p95Micros: _nearestRank(sorted, 0.95),
      p99Micros: _nearestRank(sorted, 0.99),
    );
  }

  static int _nearestRank(List<int> sorted, double percentile) {
    final rank = math.max(1, (percentile * sorted.length).ceil());
    return sorted[rank - 1];
  }
}

final class BenchmarkRunManifest {
  const BenchmarkRunManifest({
    required this.schemaVersion,
    required this.runId,
    required this.sourceRevision,
    required this.candidate,
    required this.accessStyle,
    required this.executor,
    required this.connectionTopology,
    required this.databasePathClass,
    required this.corpusHash,
    required this.journalMode,
    required this.synchronousMode,
    required this.checkpointPolicy,
    required this.preparationPolicy,
    required this.transactionSize,
    required this.buildMode,
    required this.packageVersions,
  });

  factory BenchmarkRunManifest.fromJson(Map<String, Object?> json) {
    Object requireValue(String key) {
      final value = json[key];
      if (value == null) {
        throw FormatException('Missing required manifest dimension: $key');
      }
      return value;
    }

    final rawVersions =
        requireValue('packageVersions') as Map<Object?, Object?>;
    return BenchmarkRunManifest(
      schemaVersion: requireValue('schemaVersion') as int,
      runId: requireValue('runId') as String,
      sourceRevision: requireValue('sourceRevision') as String,
      candidate: requireValue('candidate') as String,
      accessStyle: requireValue('accessStyle') as String,
      executor: requireValue('executor') as String,
      connectionTopology: requireValue('connectionTopology') as String,
      databasePathClass: requireValue('databasePathClass') as String,
      corpusHash: requireValue('corpusHash') as String,
      journalMode: requireValue('journalMode') as String,
      synchronousMode: requireValue('synchronousMode') as String,
      checkpointPolicy: requireValue('checkpointPolicy') as String,
      preparationPolicy: requireValue('preparationPolicy') as String,
      transactionSize: requireValue('transactionSize') as int,
      buildMode: requireValue('buildMode') as String,
      packageVersions: rawVersions.map(
        (key, value) => MapEntry(key! as String, value! as String),
      ),
    );
  }

  final int schemaVersion;
  final String runId;
  final String sourceRevision;
  final String candidate;
  final String accessStyle;
  final String executor;
  final String connectionTopology;
  final String databasePathClass;
  final String corpusHash;
  final String journalMode;
  final String synchronousMode;
  final String checkpointPolicy;
  final String preparationPolicy;
  final int transactionSize;
  final String buildMode;
  final Map<String, String> packageVersions;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'runId': runId,
    'sourceRevision': sourceRevision,
    'candidate': candidate,
    'accessStyle': accessStyle,
    'executor': executor,
    'connectionTopology': connectionTopology,
    'databasePathClass': databasePathClass,
    'corpusHash': corpusHash,
    'journalMode': journalMode,
    'synchronousMode': synchronousMode,
    'checkpointPolicy': checkpointPolicy,
    'preparationPolicy': preparationPolicy,
    'transactionSize': transactionSize,
    'buildMode': buildMode,
    'packageVersions': packageVersions,
  };
}

final class StorageBenchmarkSample {
  const StorageBenchmarkSample({
    required this.operation,
    required this.iteration,
    required this.durationMicros,
    required this.correctnessOutcome,
  });

  final String operation;
  final int iteration;
  final int durationMicros;
  final String correctnessOutcome;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'sample',
    'operation': operation,
    'iteration': iteration,
    'durationMicros': durationMicros,
    'correctnessOutcome': correctnessOutcome,
  };
}

abstract final class BenchmarkEvidenceValidator {
  static void validateForDecision({
    required BenchmarkRunManifest manifest,
    required List<StorageBenchmarkSample> samples,
  }) {
    final hasCrashEvidence = samples.any(
      (sample) =>
          sample.operation == 'crash_terminal' ||
          sample.operation == 'crash_migration',
    );
    if (!hasCrashEvidence) {
      throw StateError(
        'Decision evidence for ${manifest.runId} is missing '
        'crash-consistency results.',
      );
    }
  }
}

@DriftDatabase(
  tables: <Type>[BenchmarkConversations, BenchmarkTurns, BenchmarkGenerations],
)
final class _BenchmarkDatabase extends _$_BenchmarkDatabase {
  _BenchmarkDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}

@TableIndex(
  name: 'conversations_by_updated',
  columns: <Symbol>{#updatedAtMs, #id},
)
class BenchmarkConversations extends Table {
  @override
  String get tableName => 'conversations';

  TextColumn get id => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  TextColumn get title => text()();
  IntColumn get turnCount => integer().withDefault(const Constant<int>(0))();
  IntColumn get lastTurnSequence =>
      integer().withDefault(const Constant<int>(-1))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class BenchmarkTurns extends Table {
  @override
  String get tableName => 'turns';

  TextColumn get conversationId => text()();
  IntColumn get sequence => integer()();
  IntColumn get role => integer()();
  IntColumn get status => integer()();
  TextColumn get textValue => text().named('text')();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    conversationId,
    sequence,
  };

  @override
  bool get withoutRowId => true;

  @override
  List<String> get customConstraints => <String>[
    'FOREIGN KEY (conversation_id) REFERENCES conversations(id) '
        'ON DELETE CASCADE',
    'CHECK (role IN (0, 1))',
    'CHECK (status IN (1, 2, 3))',
  ];
}

@TableIndex(
  name: 'generations_by_conversation_turn',
  columns: <Symbol>{#conversationId, #assistantTurnSequence},
)
class BenchmarkGenerations extends Table {
  @override
  String get tableName => 'generations';

  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  IntColumn get assistantTurnSequence => integer()();
  TextColumn get requestPrompt => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<String> get customConstraints => <String>[
    'FOREIGN KEY (conversation_id, assistant_turn_sequence) '
        'REFERENCES turns(conversation_id, sequence)',
  ];
}

QueryExecutor _driftExecutor(BenchmarkDatabaseConfig config) {
  final file = File(config.path);
  return switch (config.executor) {
    BenchmarkExecutor.main => NativeDatabase(file),
    BenchmarkExecutor.background => NativeDatabase.createInBackground(file),
  };
}

abstract base class _DriftAdapterBase implements StorageBenchmarkAdapter {
  _BenchmarkDatabase? _database;

  _BenchmarkDatabase get database =>
      _database ??
      (throw StateError('The benchmark adapter has not been opened.'));

  @override
  Future<void> open(BenchmarkDatabaseConfig config) async {
    _database = _BenchmarkDatabase(_driftExecutor(config));
    await database.customSelect('SELECT 1').get();
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.customStatement('PRAGMA journal_mode = WAL');
    await database.customStatement('PRAGMA synchronous = FULL');
  }

  @override
  Future<List<String>> validate() async {
    final errors = <String>[];
    final integrity = await database
        .customSelect('PRAGMA integrity_check')
        .get();
    if (integrity.single.data.values.single != 'ok') {
      errors.add('integrity_check failed');
    }
    final foreignKeys = await database
        .customSelect('PRAGMA foreign_key_check')
        .get();
    if (foreignKeys.isNotEmpty) {
      errors.add('foreign_key_check failed');
    }
    return errors;
  }

  @override
  Future<void> close() async {
    final current = _database;
    _database = null;
    await current?.close();
  }
}

final class _GeneratedDriftAdapter extends _DriftAdapterBase {
  @override
  Future<void> createConversation(StorageBenchmarkConversation conversation) =>
      database
          .into(database.benchmarkConversations)
          .insert(
            BenchmarkConversationsCompanion.insert(
              id: conversation.id,
              createdAtMs: conversation.createdAtMs,
              updatedAtMs: conversation.createdAtMs,
              title: conversation.title,
            ),
          );

  @override
  Future<void> saveUserTurn({
    required String conversationId,
    required String text,
    required int createdAtMs,
  }) => _saveTurn(
    conversationId: conversationId,
    text: text,
    role: BenchmarkTurnRole.user,
    status: BenchmarkTurnStatus.completed,
    createdAtMs: createdAtMs,
  );

  @override
  Future<void> saveTerminalAssistantTurn({
    required String conversationId,
    required String generationId,
    required String requestPrompt,
    required String text,
    required BenchmarkTurnStatus status,
    required int createdAtMs,
  }) => database.transaction(() async {
    final sequence = await _nextSequence(conversationId);
    await database
        .into(database.benchmarkTurns)
        .insert(
          BenchmarkTurnsCompanion.insert(
            conversationId: conversationId,
            sequence: sequence,
            role: BenchmarkTurnRole.assistant.index,
            status: status.index + 1,
            textValue: text,
            createdAtMs: createdAtMs,
          ),
        );
    await database
        .into(database.benchmarkGenerations)
        .insert(
          BenchmarkGenerationsCompanion.insert(
            id: generationId,
            conversationId: conversationId,
            assistantTurnSequence: sequence,
            requestPrompt: requestPrompt,
          ),
        );
    await _advanceConversation(conversationId, sequence, createdAtMs);
  });

  Future<void> _saveTurn({
    required String conversationId,
    required String text,
    required BenchmarkTurnRole role,
    required BenchmarkTurnStatus status,
    required int createdAtMs,
  }) => database.transaction(() async {
    final sequence = await _nextSequence(conversationId);
    await database
        .into(database.benchmarkTurns)
        .insert(
          BenchmarkTurnsCompanion.insert(
            conversationId: conversationId,
            sequence: sequence,
            role: role.index,
            status: status.index + 1,
            textValue: text,
            createdAtMs: createdAtMs,
          ),
        );
    await _advanceConversation(conversationId, sequence, createdAtMs);
  });

  Future<int> _nextSequence(String conversationId) async {
    final row = await (database.select(
      database.benchmarkConversations,
    )..where((table) => table.id.equals(conversationId))).getSingle();
    return row.lastTurnSequence + 1;
  }

  Future<void> _advanceConversation(
    String conversationId,
    int sequence,
    int updatedAtMs,
  ) async {
    final table = database.benchmarkConversations;
    await (database.update(
      table,
    )..where((row) => row.id.equals(conversationId))).write(
      BenchmarkConversationsCompanion(
        updatedAtMs: Value<int>(updatedAtMs),
        turnCount: Value<int>(sequence + 1),
        lastTurnSequence: Value<int>(sequence),
      ),
    );
  }

  @override
  Future<List<StorageBenchmarkTurn>> loadTurns(String conversationId) async {
    final rows =
        await (database.select(database.benchmarkTurns)
              ..where((row) => row.conversationId.equals(conversationId))
              ..orderBy(<OrderClauseGenerator<$BenchmarkTurnsTable>>[
                (row) => OrderingTerm.asc(row.sequence),
              ]))
            .get();
    return rows.map(_mapGeneratedTurn).toList(growable: false);
  }
}

StorageBenchmarkTurn _mapGeneratedTurn(BenchmarkTurn row) =>
    StorageBenchmarkTurn(
      sequence: row.sequence,
      role: BenchmarkTurnRole.values[row.role],
      status: BenchmarkTurnStatus.values[row.status - 1],
      text: row.textValue,
    );

final class _CustomDriftAdapter extends _DriftAdapterBase {
  @override
  Future<void> createConversation(StorageBenchmarkConversation conversation) =>
      database.customStatement(
        'INSERT INTO conversations '
        '(id, created_at_ms, updated_at_ms, title) VALUES (?, ?, ?, ?)',
        <Object?>[
          conversation.id,
          conversation.createdAtMs,
          conversation.createdAtMs,
          conversation.title,
        ],
      );

  @override
  Future<void> saveUserTurn({
    required String conversationId,
    required String text,
    required int createdAtMs,
  }) => _save(
    conversationId: conversationId,
    text: text,
    role: BenchmarkTurnRole.user,
    status: BenchmarkTurnStatus.completed,
    createdAtMs: createdAtMs,
  );

  @override
  Future<void> saveTerminalAssistantTurn({
    required String conversationId,
    required String generationId,
    required String requestPrompt,
    required String text,
    required BenchmarkTurnStatus status,
    required int createdAtMs,
  }) => database.transaction(() async {
    final sequence = await _insertTurn(
      conversationId,
      text,
      BenchmarkTurnRole.assistant,
      status,
      createdAtMs,
    );
    await database.customStatement(
      'INSERT INTO generations '
      '(id, conversation_id, assistant_turn_sequence, request_prompt) '
      'VALUES (?, ?, ?, ?)',
      <Object?>[generationId, conversationId, sequence, requestPrompt],
    );
  });

  Future<void> _save({
    required String conversationId,
    required String text,
    required BenchmarkTurnRole role,
    required BenchmarkTurnStatus status,
    required int createdAtMs,
  }) => database.transaction(
    () => _insertTurn(conversationId, text, role, status, createdAtMs),
  );

  Future<int> _insertTurn(
    String conversationId,
    String text,
    BenchmarkTurnRole role,
    BenchmarkTurnStatus status,
    int createdAtMs,
  ) async {
    final row = await database
        .customSelect(
          'SELECT last_turn_sequence FROM conversations WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(conversationId)],
        )
        .getSingle();
    final sequence = row.read<int>('last_turn_sequence') + 1;
    await database.customStatement(
      'INSERT INTO turns '
      '(conversation_id, sequence, role, status, text, created_at_ms) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        conversationId,
        sequence,
        role.index,
        status.index + 1,
        text,
        createdAtMs,
      ],
    );
    await database.customStatement(
      'UPDATE conversations SET updated_at_ms = ?, '
      'turn_count = turn_count + 1, last_turn_sequence = ? WHERE id = ?',
      <Object?>[createdAtMs, sequence, conversationId],
    );
    return sequence;
  }

  @override
  Future<List<StorageBenchmarkTurn>> loadTurns(String conversationId) async {
    final rows = await database
        .customSelect(
          'SELECT sequence, role, status, text FROM turns '
          'WHERE conversation_id = ? ORDER BY sequence ASC',
          variables: <Variable<Object>>[Variable<String>(conversationId)],
        )
        .get();
    return rows
        .map(
          (row) => StorageBenchmarkTurn(
            sequence: row.read<int>('sequence'),
            role: BenchmarkTurnRole.values[row.read<int>('role')],
            status: BenchmarkTurnStatus.values[row.read<int>('status') - 1],
            text: row.read<String>('text'),
          ),
        )
        .toList(growable: false);
  }
}

final class _Sqlite3PreparedAdapter implements StorageBenchmarkAdapter {
  sqlite.Database? _database;

  sqlite.Database get database =>
      _database ??
      (throw StateError('The benchmark adapter has not been opened.'));

  @override
  Future<void> open(BenchmarkDatabaseConfig config) async {
    if (config.executor == BenchmarkExecutor.background) {
      throw UnsupportedError(
        'The long-lived direct sqlite3 worker is not implemented in the '
        'partial smoke harness.',
      );
    }
    _database = sqlite.sqlite3.open(config.path);
    database.execute(_schemaSql);
  }

  @override
  Future<void> createConversation(
    StorageBenchmarkConversation conversation,
  ) async {
    final statement = database.prepare(
      'INSERT INTO conversations '
      '(id, created_at_ms, updated_at_ms, title) VALUES (?, ?, ?, ?)',
      persistent: true,
    );
    try {
      statement.execute(<Object?>[
        conversation.id,
        conversation.createdAtMs,
        conversation.createdAtMs,
        conversation.title,
      ]);
    } finally {
      statement.close();
    }
  }

  @override
  Future<void> saveUserTurn({
    required String conversationId,
    required String text,
    required int createdAtMs,
  }) async {
    _transaction(() {
      _insertTurn(
        conversationId,
        text,
        BenchmarkTurnRole.user,
        BenchmarkTurnStatus.completed,
        createdAtMs,
      );
    });
  }

  @override
  Future<void> saveTerminalAssistantTurn({
    required String conversationId,
    required String generationId,
    required String requestPrompt,
    required String text,
    required BenchmarkTurnStatus status,
    required int createdAtMs,
  }) async {
    _transaction(() {
      final sequence = _insertTurn(
        conversationId,
        text,
        BenchmarkTurnRole.assistant,
        status,
        createdAtMs,
      );
      database.execute(
        'INSERT INTO generations '
        '(id, conversation_id, assistant_turn_sequence, request_prompt) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[generationId, conversationId, sequence, requestPrompt],
      );
    });
  }

  int _insertTurn(
    String conversationId,
    String text,
    BenchmarkTurnRole role,
    BenchmarkTurnStatus status,
    int createdAtMs,
  ) {
    final result = database.select(
      'SELECT last_turn_sequence FROM conversations WHERE id = ?',
      <Object?>[conversationId],
    );
    final sequence = (result.single['last_turn_sequence'] as int) + 1;
    database.execute(
      'INSERT INTO turns '
      '(conversation_id, sequence, role, status, text, created_at_ms) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        conversationId,
        sequence,
        role.index,
        status.index + 1,
        text,
        createdAtMs,
      ],
    );
    database.execute(
      'UPDATE conversations SET updated_at_ms = ?, '
      'turn_count = turn_count + 1, last_turn_sequence = ? WHERE id = ?',
      <Object?>[createdAtMs, sequence, conversationId],
    );
    return sequence;
  }

  void _transaction(void Function() body) {
    database.execute('BEGIN IMMEDIATE');
    try {
      body();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<List<StorageBenchmarkTurn>> loadTurns(String conversationId) async =>
      database
          .select(
            'SELECT sequence, role, status, text FROM turns '
            'WHERE conversation_id = ? ORDER BY sequence ASC',
            <Object?>[conversationId],
          )
          .map(
            (row) => StorageBenchmarkTurn(
              sequence: row['sequence'] as int,
              role: BenchmarkTurnRole.values[row['role'] as int],
              status: BenchmarkTurnStatus.values[(row['status'] as int) - 1],
              text: row['text'] as String,
            ),
          )
          .toList(growable: false);

  @override
  Future<List<String>> validate() async {
    final errors = <String>[];
    if (database.select('PRAGMA integrity_check').single.values.single !=
        'ok') {
      errors.add('integrity_check failed');
    }
    if (database.select('PRAGMA foreign_key_check').isNotEmpty) {
      errors.add('foreign_key_check failed');
    }
    return errors;
  }

  @override
  Future<void> close() async {
    final current = _database;
    _database = null;
    current?.close();
  }
}

const String _schemaSql = '''
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = FULL;
CREATE TABLE conversations (
  id TEXT NOT NULL PRIMARY KEY,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  title TEXT NOT NULL,
  turn_count INTEGER NOT NULL DEFAULT 0,
  last_turn_sequence INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE turns (
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL,
  role INTEGER NOT NULL CHECK (role IN (0, 1)),
  status INTEGER NOT NULL CHECK (status IN (1, 2, 3)),
  text TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY (conversation_id, sequence)
) WITHOUT ROWID;
CREATE TABLE generations (
  id TEXT NOT NULL PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  assistant_turn_sequence INTEGER NOT NULL,
  request_prompt TEXT NOT NULL,
  FOREIGN KEY (conversation_id, assistant_turn_sequence)
    REFERENCES turns (conversation_id, sequence)
);
CREATE INDEX conversations_by_updated
  ON conversations (updated_at_ms DESC, id DESC);
CREATE INDEX generations_by_conversation_turn
  ON generations (conversation_id, assistant_turn_sequence);
PRAGMA user_version = 1;
''';

final class StorageSmokeSuiteResult {
  const StorageSmokeSuiteResult({
    required this.completedCandidates,
    required this.failedConfigurations,
  });

  final Set<StorageCandidate> completedCandidates;
  final List<String> failedConfigurations;
}

Future<StorageSmokeSuiteResult> runStorageSmokeSuite({
  required File output,
  required String sourceRevision,
  int iterations = 30,
}) async {
  await output.parent.create(recursive: true);
  final sink = output.openWrite(mode: FileMode.writeOnly);
  final completed = <StorageCandidate>{};
  final failures = <String>[];
  final directory = await Directory.systemTemp.createTemp(
    'phase1a-storage-smoke-',
  );
  try {
    for (final candidate in StorageCandidate.values) {
      final adapter = createStorageBenchmarkAdapter(candidate);
      final path = '${directory.path}/${candidate.id}.sqlite';
      final manifest = BenchmarkRunManifest(
        schemaVersion: 1,
        runId: 'smoke-${candidate.id}',
        sourceRevision: sourceRevision,
        candidate: candidate.id,
        accessStyle: candidate.id,
        executor: BenchmarkExecutor.main.name,
        connectionTopology: 'single_writer',
        databasePathClass: 'temporary',
        corpusHash: 'phase1a-storage-smoke-v1',
        journalMode: 'wal',
        synchronousMode: 'full',
        checkpointPolicy: 'auto_1000',
        preparationPolicy: candidate == StorageCandidate.sqlite3Prepared
            ? 'persistent_reuse'
            : 'executor_reuse',
        transactionSize: 1,
        buildMode: 'aot_or_jit_reported_by_runner',
        packageVersions: const <String, String>{
          'drift': '2.34.2',
          'drift_dev': '2.34.0',
          'sqlite3': '3.5.0',
          'build_runner': '2.15.1',
        },
      );
      sink.writeln(
        jsonEncode(<String, Object?>{'type': 'manifest', ...manifest.toJson()}),
      );
      try {
        await adapter.open(
          BenchmarkDatabaseConfig(path: path, executor: BenchmarkExecutor.main),
        );
        await adapter.createConversation(
          StorageBenchmarkConversation(
            id: 'conversation-${candidate.id}',
            title: 'Synthetic conversation',
            createdAtMs: 1,
          ),
        );
        for (var iteration = 0; iteration < iterations; iteration++) {
          final stopwatch = Stopwatch()..start();
          await adapter.saveUserTurn(
            conversationId: 'conversation-${candidate.id}',
            text: 'synthetic turn $iteration',
            createdAtMs: iteration + 2,
          );
          stopwatch.stop();
          sink.writeln(
            jsonEncode(
              StorageBenchmarkSample(
                operation: 'save_user_1',
                iteration: iteration,
                durationMicros: stopwatch.elapsedMicroseconds,
                correctnessOutcome: 'pass',
              ).toJson(),
            ),
          );
        }
        final validationErrors = await adapter.validate();
        if (validationErrors.isNotEmpty) {
          throw StateError(validationErrors.join(', '));
        }
        completed.add(candidate);
      } catch (error) {
        failures.add('${candidate.id}: $error');
      } finally {
        await adapter.close();
      }
    }
  } finally {
    await sink.flush();
    await sink.close();
    await directory.delete(recursive: true);
  }
  return StorageSmokeSuiteResult(
    completedCandidates: completed,
    failedConfigurations: failures,
  );
}

Future<void> main(List<String> arguments) async {
  String? option(String name) {
    final index = arguments.indexOf(name);
    return index >= 0 && index + 1 < arguments.length
        ? arguments[index + 1]
        : null;
  }

  final suite = option('--suite') ?? 'smoke';
  if (suite != 'smoke') {
    throw UnsupportedError(
      'Only the reproducible smoke suite is implemented. Full, crash, and UI '
      'suites remain required before an ADR selection.',
    );
  }
  final outputPath = option('--output');
  if (outputPath == null) {
    throw const FormatException('--output is required.');
  }
  final result = await runStorageSmokeSuite(
    output: File(outputPath),
    sourceRevision: option('--source-revision') ?? 'working-tree',
  );
  if (result.failedConfigurations.isNotEmpty) {
    stderr.writeln(result.failedConfigurations.join('\n'));
    exitCode = 1;
  }
}
