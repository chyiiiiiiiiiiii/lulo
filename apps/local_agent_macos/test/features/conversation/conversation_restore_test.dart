import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';

import '../../support/controlled_inference_service.dart';

void main() {
  const ConversationId yesterday = ConversationId('conversation-yesterday');
  const ConversationId older = ConversationId('conversation-older');

  Turn user(String text) =>
      Turn(role: TurnRole.user, text: text, status: TurnStatus.completed);
  Turn assistant(String text) =>
      Turn(role: TurnRole.assistant, text: text, status: TurnStatus.completed);

  Future<InMemoryConversationStorageService> storeWithHistory() async {
    final InMemoryConversationStorageService store =
        InMemoryConversationStorageService();
    await store.saveUserTurn(older, user('an older thread'));
    await store.saveUserTurn(yesterday, user('what we talked about'));
    await store.saveTerminalAssistantTurn(
      assistant('and what I answered'),
      const Generation(
        id: GenerationId('generation-1'),
        request: GenerationRequest(
          conversationId: yesterday,
          prompt: 'what we talked about',
        ),
      ),
    );
    return store;
  }

  ConversationViewModel viewModel(
    InMemoryConversationStorageService store, {
    ConversationId? conversationId,
    bool startFresh = false,
    InferenceService? inferenceService,
  }) {
    return ConversationViewModel(
      repository: ConversationRepository(
        storageService: store,
        inferenceService: inferenceService ?? ControlledInferenceService(),
      ),
      idFactory: () => const ConversationId('freshly-minted'),
      conversationId: conversationId,
      startFresh: startFresh,
    );
  }

  test('a view model with no conversation resumes the most recent', () async {
    // Lulo is resident: closing it is putting it away, not ending anything.
    // Coming back to yesterday's conversation gone would make every restart
    // an amnesia.
    final ConversationViewModel vm = viewModel(await storeWithHistory());
    addTearDown(vm.dispose);

    await vm.restored;

    expect(vm.completedTurnsListenable.value.map((Turn t) => t.text), <String>[
      'what we talked about',
      'and what I answered',
    ]);
  });

  test('a view model given a conversation restores that one', () async {
    final ConversationViewModel vm = viewModel(
      await storeWithHistory(),
      conversationId: older,
    );
    addTearDown(vm.dispose);

    await vm.restored;

    expect(vm.completedTurnsListenable.value.single.text, 'an older thread');
  });

  test('an empty store starts a fresh conversation', () async {
    final ConversationViewModel vm = viewModel(
      InMemoryConversationStorageService(),
    );
    addTearDown(vm.dispose);

    await vm.restored;

    expect(vm.completedTurnsListenable.value, isEmpty);
  });

  test('a fresh view model leaves the stored conversations alone', () async {
    // "New conversation" means exactly that: yesterday stays in the store,
    // and the first message begins a newly minted conversation.
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationViewModel vm = viewModel(
      await storeWithHistory(),
      startFresh: true,
      inferenceService: inference,
    );
    addTearDown(vm.dispose);

    await vm.restored;
    await vm.submit('a clean slate');
    final GenerationRequest request = await inference.requestReceived;

    expect(vm.completedTurnsListenable.value.single.text, 'a clean slate');
    expect(request.conversationId, const ConversationId('freshly-minted'));
  });

  test(
    'a message sent before restore finishes lands after the history',
    () async {
      // Restore is asynchronous and the composer is live immediately. The
      // race must resolve as a reader expects: history first, then the new
      // message — never interleaved, never lost.
      final InMemoryConversationStorageService store = await storeWithHistory();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationViewModel vm = ConversationViewModel(
        repository: ConversationRepository(
          storageService: store,
          inferenceService: inference,
        ),
        idFactory: () => const ConversationId('freshly-minted'),
      );
      addTearDown(vm.dispose);

      await vm.submit('a new question');
      await vm.restored;
      final GenerationRequest sent = await inference.requestReceived;

      expect(
        vm.completedTurnsListenable.value.map((Turn t) => t.text),
        <String>[
          'what we talked about',
          'and what I answered',
          'a new question',
        ],
      );
      // And it continues the resumed conversation rather than minting a new one.
      expect(sent.conversationId, yesterday);
    },
  );
}
