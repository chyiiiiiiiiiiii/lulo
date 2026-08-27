import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/obsidian/obsidian_journal_writer.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

/// What the agent writes into somebody else's notes.
void main() {
  late InMemoryConversationStorageService store;
  late List<({String entry, String fileName, String header})> written;
  late ValueNotifier<bool> enabled;
  late DesktopVaultStatus answer;

  setUp(() {
    store = InMemoryConversationStorageService();
    written = <({String entry, String fileName, String header})>[];
    enabled = ValueNotifier<bool>(true);
    answer = DesktopVaultStatus.written;
  });

  ObsidianJournalWriter writerAt(DateTime when) => ObsidianJournalWriter(
    inner: store,
    enabled: enabled,
    heading: ValueNotifier<String>('與 Lulo 的對話'),
    clock: () => when,
    append:
        ({
          required String fileName,
          required String header,
          required String entry,
        }) async {
          written.add((fileName: fileName, header: header, entry: entry));
          return answer;
        },
  );

  Generation generationOf(String question) => Generation(
    id: const GenerationId('g1'),
    request: GenerationRequest(
      conversationId: const ConversationId('c1'),
      prompt: question,
    ),
  );

  Future<void> answerWith(
    ObsidianJournalWriter writer,
    String question,
    String answerText, {
    TurnStatus status = TurnStatus.completed,
  }) => writer.saveTerminalAssistantTurn(
    Turn(role: TurnRole.assistant, text: answerText, status: status),
    generationOf(question),
  );

  test('a finished exchange lands in the day it happened', () async {
    final ObsidianJournalWriter writer = writerAt(DateTime(2026, 8, 28, 2, 4));

    await answerWith(writer, '明天台中天氣如何', '台中明天多雲。');

    expect(written.single.fileName, '2026-08-28.md');
    expect(written.single.entry, contains('## 02:04 明天台中天氣如何'));
    expect(written.single.entry, contains('台中明天多雲。'));
    expect(written.single.header, contains('source: lulo'));
  });

  test(
    'the turn is still stored when there is no vault to mirror it to',
    () async {
      answer = DesktopVaultStatus.noVault;
      final ObsidianJournalWriter writer = writerAt(DateTime(2026, 8, 28));

      await answerWith(writer, '嗨', '嗨。');

      expect(await store.loadTurns(const ConversationId('c1')), hasLength(1));
    },
  );

  test(
    'a vault that cannot be reached does not take the turn with it',
    () async {
      final ObsidianJournalWriter writer = ObsidianJournalWriter(
        inner: store,
        enabled: enabled,
        heading: ValueNotifier<String>('與 Lulo 的對話'),
        clock: () => DateTime(2026, 8, 28),
        append:
            ({
              required String fileName,
              required String header,
              required String entry,
            }) async =>
                throw StateError('the vault is on a dead network share'),
      );

      await answerWith(writer, '嗨', '嗨。');

      expect(await store.loadTurns(const ConversationId('c1')), hasLength(1));
      expect(writer.lastWrite.value, DesktopVaultStatus.failed);
    },
  );

  test('nothing is written while the setting is off', () async {
    enabled.value = false;
    final ObsidianJournalWriter writer = writerAt(DateTime(2026, 8, 28));

    await answerWith(writer, '嗨', '嗨。');

    expect(written, isEmpty);
  });

  test('an answer that never finished is not filed as one', () async {
    final ObsidianJournalWriter writer = writerAt(DateTime(2026, 8, 28));

    await answerWith(writer, '嗨', '嗨', status: TurnStatus.cancelled);
    await answerWith(writer, '嗨', '', status: TurnStatus.failed);

    expect(written, isEmpty);
  });

  test('an empty answer is nothing to keep', () async {
    final ObsidianJournalWriter writer = writerAt(DateTime(2026, 8, 28));

    await answerWith(writer, '嗨', '   ');

    expect(written, isEmpty);
  });

  test('how the last write went is readable', () async {
    final ObsidianJournalWriter writer = writerAt(DateTime(2026, 8, 28));
    expect(writer.lastWrite.value, isNull);

    answer = DesktopVaultStatus.denied;
    await answerWith(writer, '嗨', '嗨。');

    expect(writer.lastWrite.value, DesktopVaultStatus.denied);
  });

  test('everything else goes straight through to the store', () async {
    final ObsidianJournalWriter writer = writerAt(DateTime(2026, 8, 28));

    await writer.saveUserTurn(
      const ConversationId('c1'),
      const Turn(role: TurnRole.user, text: '哈囉', status: TurnStatus.completed),
    );
    await writer.renameConversation(const ConversationId('c1'), '打招呼');

    final List<ConversationSummary> listed = await writer.listConversations();
    expect(listed.single.title, '打招呼');
    expect(written, isEmpty, reason: 'a rename is not a new exchange');
  });
}
