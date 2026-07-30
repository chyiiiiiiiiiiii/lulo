import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';

/// The behaviour every conversation store must have, whatever it is made of.
///
/// The in-memory store and the SQLite store run this same suite, so a test
/// that passes against one and fails against the other is a bug in a store
/// rather than a difference of opinion about the contract.
void runConversationStorageContract({
  required Future<ConversationStorageService> Function() createStore,
  Future<void> Function(ConversationStorageService store)? disposeStore,
}) {
  late ConversationStorageService store;

  setUp(() async {
    store = await createStore();
  });

  tearDown(() async {
    await disposeStore?.call(store);
  });

  const ConversationId conversation = ConversationId('conversation-1');
  const ConversationId other = ConversationId('conversation-2');

  Turn userTurn(String text) =>
      Turn(role: TurnRole.user, text: text, status: TurnStatus.completed);

  Turn assistantTurn(String text, [TurnStatus status = TurnStatus.completed]) =>
      Turn(role: TurnRole.assistant, text: text, status: status);

  Generation generationFor(ConversationId id, [int n = 1]) => Generation(
    id: GenerationId('generation-$n'),
    request: GenerationRequest(conversationId: id, prompt: 'prompt-$n'),
  );

  test('an empty store has no history and no conversations', () async {
    expect(await store.loadTurns(conversation), isEmpty);
    expect(await store.listConversations(), isEmpty);
  });

  test('turns come back in the order they were said', () async {
    await store.saveUserTurn(conversation, userTurn('first question'));
    await store.saveTerminalAssistantTurn(
      assistantTurn('first answer'),
      generationFor(conversation),
    );
    await store.saveUserTurn(conversation, userTurn('second question'));
    await store.saveTerminalAssistantTurn(
      assistantTurn('second answer', TurnStatus.cancelled),
      generationFor(conversation, 2),
    );

    final List<Turn> turns = await store.loadTurns(conversation);
    expect(turns.map((Turn t) => t.text).toList(), <String>[
      'first question',
      'first answer',
      'second question',
      'second answer',
    ]);
    expect(turns[0].role, TurnRole.user);
    expect(turns[1].role, TurnRole.assistant);
    expect(turns[3].status, TurnStatus.cancelled);
  });

  test('conversations do not leak into each other', () async {
    await store.saveUserTurn(conversation, userTurn('mine'));
    await store.saveUserTurn(other, userTurn('theirs'));

    expect((await store.loadTurns(conversation)).single.text, 'mine');
    expect((await store.loadTurns(other)).single.text, 'theirs');
  });

  test('the list names a conversation after its first user turn', () async {
    await store.saveUserTurn(conversation, userTurn('How do springs work?'));
    await store.saveTerminalAssistantTurn(
      assistantTurn('Like this.'),
      generationFor(conversation),
    );
    await store.saveUserTurn(conversation, userTurn('And dampers?'));

    final List<ConversationSummary> summaries = await store.listConversations();
    expect(summaries.single.id, conversation);
    expect(summaries.single.title, 'How do springs work?');
  });

  test('the most recently spoken-in conversation comes first', () async {
    await store.saveUserTurn(conversation, userTurn('older'));
    await store.saveUserTurn(other, userTurn('newer'));

    List<ConversationSummary> summaries = await store.listConversations();
    expect(
      summaries.map((ConversationSummary s) => s.id).toList(),
      <ConversationId>[other, conversation],
    );

    // Speaking in the older one again brings it back to the top.
    await store.saveUserTurn(conversation, userTurn('current again'));
    summaries = await store.listConversations();
    expect(summaries.first.id, conversation);
  });

  test('deleting a conversation forgets its turns and its listing', () async {
    await store.saveUserTurn(conversation, userTurn('to be forgotten'));
    await store.saveUserTurn(other, userTurn('to be kept'));

    await store.deleteConversation(conversation);

    expect(await store.loadTurns(conversation), isEmpty);
    expect((await store.listConversations()).single.id, other);
  });

  test('deleting a conversation that never existed is not an error', () async {
    await store.deleteConversation(const ConversationId('never-existed'));
    expect(await store.listConversations(), isEmpty);
  });
}
