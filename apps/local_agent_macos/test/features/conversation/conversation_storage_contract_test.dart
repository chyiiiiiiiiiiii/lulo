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
  });
}
