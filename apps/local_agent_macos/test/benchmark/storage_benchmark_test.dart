import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

    test('smoke suite emits raw samples for every candidate', () async {
      final directory = await Directory.systemTemp.createTemp(
        'storage-benchmark-suite-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final output = File('${directory.path}/smoke.ndjson');

      final result = await runStorageSmokeSuite(
        output: output,
        sourceRevision: 'test-revision',
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
  transactionSize: 1,
  buildMode: 'release',
  packageVersions: <String, String>{'sqlite3': '3.5.0'},
);
