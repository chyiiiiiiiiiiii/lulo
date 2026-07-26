import 'dart:io';

import 'package:test/test.dart';

import '../../tool/benchmark/storage_benchmark.dart';

void main() {
  group('StorageBenchmarkSummarizer', () {
    test('uses nearest-rank p50 p95 and p99', () {
      final summary = StorageBenchmarkSummarizer.summarizeDurations(
        List<int>.generate(100, (index) => index + 1),
      );

      expect(summary.sampleCount, 100);
      expect(summary.p50Micros, 50);
      expect(summary.p95Micros, 95);
      expect(summary.p99Micros, 99);
    });

    test('rejects a manifest with a missing required dimension', () {
      final manifest = validManifest().toJson()..remove('executor');

      expect(
        () => BenchmarkRunManifest.fromJson(manifest),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('executor'),
          ),
        ),
      );
    });

    test('rejects a decision run without crash-consistency evidence', () {
      expect(
        () => BenchmarkEvidenceValidator.validateForDecision(
          manifest: validManifest(),
          samples: const <StorageBenchmarkSample>[
            StorageBenchmarkSample(
              operation: 'save_terminal_1',
              iteration: 0,
              durationMicros: 42,
              correctnessOutcome: 'pass',
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('crash-consistency'),
          ),
        ),
      );
    });

    test('requires passing terminal and migration crash evidence', () {
      const terminalOnly = <StorageBenchmarkSample>[
        StorageBenchmarkSample(
          operation: 'crash_terminal',
          iteration: 0,
          durationMicros: 1,
          correctnessOutcome: 'pass',
        ),
      ];
      const oneFailed = <StorageBenchmarkSample>[
        ...terminalOnly,
        StorageBenchmarkSample(
          operation: 'crash_migration',
          iteration: 0,
          durationMicros: 1,
          correctnessOutcome: 'fail',
        ),
      ];

      expect(
        () => BenchmarkEvidenceValidator.validateForDecision(
          manifest: validManifest(),
          samples: terminalOnly,
        ),
        throwsStateError,
      );
      expect(
        () => BenchmarkEvidenceValidator.validateForDecision(
          manifest: validManifest(),
          samples: oneFailed,
        ),
        throwsStateError,
      );
      expect(
        () => BenchmarkEvidenceValidator.validateForDecision(
          manifest: validManifest(),
          samples: const <StorageBenchmarkSample>[
            ...terminalOnly,
            StorageBenchmarkSample(
              operation: 'crash_migration',
              iteration: 0,
              durationMicros: 1,
              correctnessOutcome: 'pass',
            ),
          ],
        ),
        returnsNormally,
      );
    });

    test('rejects placeholder provenance and build dimensions', () {
      for (final invalid in <Map<String, Object?>>[
        validManifest().toJson()..['sourceRevision'] = 'working-tree',
        validManifest().toJson()..['contentFingerprint'] = '',
        validManifest().toJson()..['buildMode'] = 'aot_or_jit',
        validManifest().toJson()..remove('transactionMode'),
      ]) {
        expect(
          () => BenchmarkRunManifest.fromJson(invalid),
          throwsFormatException,
        );
      }
    });
  });

  group('storage adapter smoke path', () {
    for (final candidate in StorageCandidate.values) {
      test('${candidate.id} round-trips the identical terminal unit', () async {
        final directory = await Directory.systemTemp.createTemp(
          'storage-benchmark-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final adapter = createStorageBenchmarkAdapter(candidate);
        addTearDown(adapter.close);

        await adapter.open(
          BenchmarkDatabaseConfig(
            path: '${directory.path}/database.sqlite',
            executor: BenchmarkExecutor.main,
          ),
        );
        await adapter.createConversation(
          const StorageBenchmarkConversation(
            id: 'conversation-1',
            title: 'Synthetic title',
            createdAtMs: 1,
          ),
        );
        await adapter.saveUserTurn(
          conversationId: 'conversation-1',
          text: 'synthetic user text',
          createdAtMs: 2,
        );
        await adapter.saveTerminalAssistantTurn(
          conversationId: 'conversation-1',
          generationId: 'generation-1',
          requestPrompt: 'synthetic prompt',
          text: 'synthetic assistant text',
          status: BenchmarkTurnStatus.completed,
          createdAtMs: 3,
        );

        final turns = await adapter.loadTurns('conversation-1');
        expect(turns, const <StorageBenchmarkTurn>[
          StorageBenchmarkTurn(
            sequence: 0,
            role: BenchmarkTurnRole.user,
            status: BenchmarkTurnStatus.completed,
            text: 'synthetic user text',
          ),
          StorageBenchmarkTurn(
            sequence: 1,
            role: BenchmarkTurnRole.assistant,
            status: BenchmarkTurnStatus.completed,
            text: 'synthetic assistant text',
          ),
        ]);
        expect(await adapter.validate(), isEmpty);
      });
    }

    test('all candidates expose equivalent SQLite schema metadata', () async {
      final directory = await Directory.systemTemp.createTemp(
        'storage-schema-equivalence-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final snapshots = <StorageCandidate, BenchmarkSchemaSnapshot>{};

      for (final candidate in StorageCandidate.values) {
        final path = '${directory.path}/${candidate.id}.sqlite';
        final adapter = createStorageBenchmarkAdapter(candidate);
        await adapter.open(
          BenchmarkDatabaseConfig(path: path, executor: BenchmarkExecutor.main),
        );
        await adapter.close();
        snapshots[candidate] = readBenchmarkSchemaSnapshot(path);
      }

      expect(
        snapshots.values.toSet(),
        hasLength(1),
        reason: snapshots.toString(),
      );
      expect(
        snapshots.values.first.indexes['conversations_by_updated'],
        const <String>['updated_at_ms DESC', 'id DESC'],
      );
    });

    test('direct adapter reuses statements until adapter close', () async {
      final directory = await Directory.systemTemp.createTemp(
        'storage-persistent-statements-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final adapter =
          createStorageBenchmarkAdapter(StorageCandidate.sqlite3Prepared)
              as PersistentPreparedStatementDiagnostics;
      final storage = adapter as StorageBenchmarkAdapter;

      await storage.open(
        BenchmarkDatabaseConfig(
          path: '${directory.path}/database.sqlite',
          executor: BenchmarkExecutor.main,
        ),
      );
      final preparedAfterOpen = adapter.totalPreparedStatements;
      expect(preparedAfterOpen, greaterThanOrEqualTo(6));
      expect(adapter.activePreparedStatements, preparedAfterOpen);
      await storage.createConversation(
        const StorageBenchmarkConversation(
          id: 'conversation-1',
          title: 'Synthetic',
          createdAtMs: 1,
        ),
      );
      await storage.saveUserTurn(
        conversationId: 'conversation-1',
        text: 'one',
        createdAtMs: 2,
      );
      await storage.saveUserTurn(
        conversationId: 'conversation-1',
        text: 'two',
        createdAtMs: 3,
      );

      expect(adapter.totalPreparedStatements, preparedAfterOpen);
      expect(adapter.activePreparedStatements, preparedAfterOpen);
      await storage.close();
      expect(adapter.activePreparedStatements, 0);
    });

    test('smoke suite emits raw samples for every candidate', () async {
      final directory = await Directory.systemTemp.createTemp(
        'storage-benchmark-suite-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final output = File('${directory.path}/smoke.ndjson');

      final result = await runStorageSmokeSuite(
        output: output,
        sourceRevision: 'test-revision',
        contentFingerprint: 'sha256:test-content',
        buildMode: 'aot',
        iterations: 2,
      );

      expect(result.completedCandidates, StorageCandidate.values.toSet());
      expect(result.failedConfigurations, isEmpty);
      expect(await output.readAsLines(), hasLength(greaterThan(6)));
    });
  });
}

BenchmarkRunManifest validManifest() => const BenchmarkRunManifest(
  schemaVersion: 1,
  runId: 'test-run',
  sourceRevision: 'test-revision',
  contentFingerprint: 'sha256:test-content',
  candidate: 'sqlite3_prepared',
  accessStyle: 'prepared',
  executor: 'background',
  connectionTopology: 'single_writer',
  databasePathClass: 'temporary',
  corpusHash: 'fixture-hash',
  journalMode: 'wal',
  synchronousMode: 'full',
  checkpointPolicy: 'auto_1000',
  preparationPolicy: 'persistent_reuse',
  transactionMode: 'begin_immediate',
  transactionSize: 1,
  buildMode: 'release',
  packageVersions: <String, String>{'sqlite3': '3.5.0'},
);
