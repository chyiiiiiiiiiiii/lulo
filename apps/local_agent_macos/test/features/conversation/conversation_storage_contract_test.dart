import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
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
  });
}
