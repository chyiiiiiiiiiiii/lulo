import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_search_tool.dart';

Future<void> _speakIn(
  InMemoryConversationStorageService storage,
  String id,
  String text,
) async {
  await storage.saveUserTurn(
    ConversationId(id),
    Turn(role: TurnRole.user, text: text, status: TurnStatus.completed),
  );
}

void main() {
  test('declares itself with a query the model must supply', () {
    final tool = ConversationSearchTool(searchConversations: (_) async => []);
    expect(tool.name, 'search_conversations');
    expect(tool.parameters.keys, contains('query'));
  });

  test('answers with the matching conversations, newest first', () async {
    final storage = InMemoryConversationStorageService();
    addTearDown(storage.dispose);
    await _speakIn(storage, 'c1', '幫我看看 Flutter 的測試怎麼寫');
    await _speakIn(storage, 'c2', '今天晚餐吃什麼');
    final tool = ConversationSearchTool(
      searchConversations: storage.searchConversations,
    );

    final result =
        await tool.call(<String, Object?>{'query': 'Flutter'})
            as Map<String, Object?>;

    final found = result['matches']! as List<Object?>;
    expect(found, hasLength(1));
    final match = found.single! as Map<String, Object?>;
    expect(match['title'], contains('Flutter'));
    expect(match['when'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('a query the history says nothing about is an honest empty', () async {
    final storage = InMemoryConversationStorageService();
    addTearDown(storage.dispose);
    await _speakIn(storage, 'c1', '幫我看看 Flutter 的測試怎麼寫');
    final tool = ConversationSearchTool(
      searchConversations: storage.searchConversations,
    );

    final result =
        await tool.call(<String, Object?>{'query': '量子力學'})
            as Map<String, Object?>;

    expect(result['matches'], isEmpty);
  });

  test('a missing query is an error the model can read, not a crash', () async {
    final tool = ConversationSearchTool(searchConversations: (_) async => []);
    final result = await tool.call(const <String, Object?>{});
    expect((result! as Map<String, Object?>)['error'], isNotEmpty);
  });

  test('caps what one answer carries', () async {
    final storage = InMemoryConversationStorageService();
    addTearDown(storage.dispose);
    for (int i = 0; i < 12; i += 1) {
      await _speakIn(storage, 'c$i', '關於天氣的第 $i 次對話');
    }
    final tool = ConversationSearchTool(
      searchConversations: storage.searchConversations,
    );

    final result =
        await tool.call(<String, Object?>{'query': '天氣'})
            as Map<String, Object?>;

    expect((result['matches']! as List<Object?>).length, 5);
    expect(result['totalMatches'], 12);
  });
}
