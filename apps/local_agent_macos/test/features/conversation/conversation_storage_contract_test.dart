import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/conversation/drift_conversation_storage_service.dart';

import '../../support/conversation_storage_contract.dart';

void main() {
  group('InMemoryConversationStorageService', () {
    runConversationStorageContract(
      createStore: () async => InMemoryConversationStorageService(),
    );
  });

  group('DriftConversationStorageService', () {
    runConversationStorageContract(
      // In-memory SQLite: the same engine and SQL as the file on disk, with
      // nothing left behind by a test run.
      createStore: () async => DriftConversationStorageService(
        database: ConversationDatabase(NativeDatabase.memory()),
      ),
      disposeStore: (store) =>
          (store as DriftConversationStorageService).dispose(),
    );

    test('schema 1 history survives the provenance migration', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final Directory temporaryDirectory = Directory.systemTemp.createTempSync(
        'lulo-conversation-migration-',
      );
      final NativeDatabase executor = NativeDatabase(
        File('${temporaryDirectory.path}/conversations.db'),
        setup: (database) {
          database.execute('''
            CREATE TABLE turn_rows (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              conversation_id TEXT NOT NULL,
              role TEXT NOT NULL,
              status TEXT NOT NULL,
              content TEXT NOT NULL,
              saved_at_ms INTEGER NOT NULL
            )
          ''');
          database.execute(
            'INSERT INTO turn_rows '
            '(conversation_id, role, status, content, saved_at_ms) '
            "VALUES ('legacy', 'user', 'completed', '舊對話', 1)",
          );
          database.userVersion = 1;
        },
      );
      final ConversationDatabase database = ConversationDatabase(executor);
      final DriftConversationStorageService store =
          DriftConversationStorageService(database: database);
      try {
        final List<Turn> turns = await store.loadTurns(
          const ConversationId('legacy'),
        );
        final List<String> columns = await database
            .customSelect('PRAGMA table_info(turn_rows)')
            .map((row) => row.read<String>('name'))
            .get();

        expect(turns.single.text, '舊對話');
        expect(turns.single.voiceInput, isNull);
        expect(
          columns,
          containsAll(<String>[
            'raw_transcript',
            'refined_transcript',
            'refinement_status',
            'refiner_id',
            'refiner_version',
            'refinement_edits_json',
          ]),
        );
      } finally {
        await store.dispose();
        temporaryDirectory.deleteSync(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      }
    });

    test(
      'schema 4 gains what the user decided, keeping turns and runs',
      () async {
        // Two migrations have shipped without a test of their own, and this is
        // the first one where getting it wrong loses something the user typed.
        // An install on schema 4 has real turns and possibly an open run; both
        // have to survive, and the new table has to take a write.
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final Directory temporaryDirectory = Directory.systemTemp
            .createTempSync('lulo-meta-migration-');
        final NativeDatabase executor = NativeDatabase(
          File('${temporaryDirectory.path}/conversations.db'),
          setup: (database) {
            database.execute('''
            CREATE TABLE turn_rows (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              conversation_id TEXT NOT NULL,
              role TEXT NOT NULL,
              status TEXT NOT NULL,
              content TEXT NOT NULL,
              saved_at_ms INTEGER NOT NULL,
              raw_transcript TEXT,
              refined_transcript TEXT,
              refinement_status TEXT,
              refiner_id TEXT,
              refiner_version TEXT,
              refinement_edits_json TEXT
            )
          ''');
            database.execute('''
            CREATE TABLE run_rows (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              generation_id TEXT NOT NULL,
              conversation_id TEXT NOT NULL,
              model_id TEXT NOT NULL,
              started_at_ms INTEGER NOT NULL,
              ended_at_ms INTEGER,
              outcome TEXT,
              partial_text TEXT NOT NULL DEFAULT ''
            )
          ''');
            database.execute(
              'INSERT INTO turn_rows '
              '(conversation_id, role, status, content, saved_at_ms) '
              "VALUES ('existing', 'user', 'completed', '既有對話', 1)",
            );
            database.execute(
              'INSERT INTO run_rows '
              '(generation_id, conversation_id, model_id, started_at_ms, '
              ' partial_text) '
              "VALUES ('open', 'existing', 'gemma-4-E2B-it', 2, '說到一半')",
            );
            database.userVersion = 4;
          },
        );
        final ConversationDatabase database = ConversationDatabase(executor);
        final DriftConversationStorageService store =
            DriftConversationStorageService(database: database);
        try {
          expect(
            (await store.loadTurns(
              const ConversationId('existing'),
            )).single.text,
            '既有對話',
          );
          expect(
            (await store.loadUnfinishedRuns()).single.partialText,
            '說到一半',
            reason: 'an answer the last process died in the middle of was lost',
          );

          // The new table is not merely present: it takes a write and the list
          // reads it back.
          await store.renameConversation(
            const ConversationId('existing'),
            '舊的對話',
          );
          await store.setConversationPinned(
            const ConversationId('existing'),
            pinned: true,
          );
          final ConversationSummary listed =
              (await store.listConversations()).single;
          expect(listed.title, '舊的對話');
          expect(listed.isPinned, isTrue);
        } finally {
          await database.close();
          temporaryDirectory.deleteSync(recursive: true);
        }
      },
    );

    test('schema 2 gains run records without losing its turns', () async {
      // Every existing install is on schema 2. Adding a table is the easy
      // migration to get wrong quietly: the app opens, the turns are all
      // there, and the first crash discovers that runs were never written
      // because the table the writes go to does not exist.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final Directory temporaryDirectory = Directory.systemTemp.createTempSync(
        'lulo-run-migration-',
      );
      final NativeDatabase executor = NativeDatabase(
        File('${temporaryDirectory.path}/conversations.db'),
        setup: (database) {
          database.execute('''
            CREATE TABLE turn_rows (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              conversation_id TEXT NOT NULL,
              role TEXT NOT NULL,
              status TEXT NOT NULL,
              content TEXT NOT NULL,
              saved_at_ms INTEGER NOT NULL,
              raw_transcript TEXT,
              refined_transcript TEXT,
              refinement_status TEXT,
              refiner_id TEXT,
              refiner_version TEXT,
              refinement_edits_json TEXT
            )
          ''');
          database.execute(
            'INSERT INTO turn_rows '
            '(conversation_id, role, status, content, saved_at_ms) '
            "VALUES ('existing', 'user', 'completed', '既有對話', 1)",
          );
          database.userVersion = 2;
        },
      );
      final ConversationDatabase database = ConversationDatabase(executor);
      final DriftConversationStorageService store =
          DriftConversationStorageService(database: database);
      try {
        final List<Turn> turns = await store.loadTurns(
          const ConversationId('existing'),
        );
        expect(turns.single.text, '既有對話');

        // The table is not merely present: it takes a write and gives it
        // back, which is what the crash path will need of it.
        expect(await store.loadUnfinishedRuns(), isEmpty);
        await store.beginRun(
          RunRecord(
            id: const GenerationId('after-migration'),
            conversationId: const ConversationId('existing'),
            modelId: 'gemma-4-E2B-it',
            startedAt: DateTime.fromMillisecondsSinceEpoch(2),
          ),
        );
        await store.checkpointRun(
          const GenerationId('after-migration'),
          'survived',
        );
        expect(
          (await store.loadUnfinishedRuns()).single.partialText,
          'survived',
        );
      } finally {
        await store.dispose();
        temporaryDirectory.deleteSync(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      }
    });
  });
}
