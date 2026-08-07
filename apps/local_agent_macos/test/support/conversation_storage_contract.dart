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

  test('voice refinement provenance round-trips with its user turn', () async {
    final TranscriptRefinement refinement = TranscriptRefinement(
      rawTranscript: '我用 flutter',
      proposedTranscript: '我用 Flutter',
      selectedTranscript: '我用 Flutter',
      status: TranscriptRefinementStatus.applied,
      edits: const <TranscriptEdit>[
        TranscriptEdit(
          rawStart: 3,
          rawEnd: 10,
          replacement: 'Flutter',
          kind: TranscriptEditKind.vocabulary,
        ),
      ],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: 'deterministic',
      refinerVersion: '1',
      elapsed: const Duration(milliseconds: 2),
    );
    await store.saveUserTurn(conversation, Turn.voice(voiceInput: refinement));

    final Turn restored = (await store.loadTurns(conversation)).single;
    expect(restored.text, '我用 Flutter');
    expect(restored.voiceInput?.rawTranscript, '我用 flutter');
    expect(restored.voiceInput?.proposedTranscript, '我用 Flutter');
    expect(
      restored.voiceInput?.edits.single.kind,
      TranscriptEditKind.vocabulary,
    );
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

  // Run records exist for the moment the process does not survive to write a
  // terminal turn. Until now the answer lived only in memory until it
  // finished, so a crash or a force-quit lost every word of it and left no
  // trace that a generation had ever run.

  RunRecord runFor(ConversationId id, [int n = 1]) => RunRecord(
    id: GenerationId('generation-$n'),
    conversationId: id,
    modelId: 'gemma-4-E2B-it',
    startedAt: DateTime.fromMillisecondsSinceEpoch(1000 * n),
  );

  test('a run that begins and ends is not left unfinished', () async {
    final RunRecord run = runFor(conversation);
    await store.beginRun(run);
    await store.checkpointRun(run.id, 'half an answer');
    await store.endRun(run.id, TurnStatus.completed);

    expect(await store.loadUnfinishedRuns(), isEmpty);
  });

  test('a run that never ended comes back with its last checkpoint', () async {
    final RunRecord run = runFor(conversation);
    await store.beginRun(run);
    await store.checkpointRun(run.id, 'the answer so');
    await store.checkpointRun(run.id, 'the answer so far');

    final List<RunRecord> unfinished = await store.loadUnfinishedRuns();

    expect(unfinished.single.id, run.id);
    expect(unfinished.single.conversationId, conversation);
    expect(unfinished.single.modelId, 'gemma-4-E2B-it');
    expect(unfinished.single.startedAt, run.startedAt);
    expect(unfinished.single.endedAt, isNull);
    expect(unfinished.single.outcome, isNull);
    // Checkpoints overwrite. Appending would double every word, because
    // what is checkpointed is the whole answer so far, not the last delta.
    expect(unfinished.single.partialText, 'the answer so far');
  });

  test('a run that began and never streamed is still unfinished', () async {
    // Dying between the first token request and the first delta is the
    // fastest way to crash, and the run must still be visible afterwards.
    final RunRecord run = runFor(conversation);
    await store.beginRun(run);

    expect((await store.loadUnfinishedRuns()).single.partialText, isEmpty);
  });

  test('unfinished runs name the conversation they belong to', () async {
    await store.beginRun(runFor(conversation, 1));
    await store.beginRun(runFor(other, 2));

    final List<RunRecord> unfinished = await store.loadUnfinishedRuns();

    expect(
      unfinished.map((RunRecord run) => run.conversationId).toSet(),
      <ConversationId>{conversation, other},
    );
  });

  test('an ended run remembers how it ended', () async {
    final RunRecord run = runFor(conversation);
    await store.beginRun(run);
    await store.endRun(run.id, TurnStatus.failed);
    // Ending twice is what a terminal event arriving after a recovery pass
    // looks like, and must not resurrect the run.
    await store.endRun(run.id, TurnStatus.completed);

    expect(await store.loadUnfinishedRuns(), isEmpty);
  });

  test('checkpointing a run that was never begun is not an error', () async {
    // The repository writes checkpoints on a timer; one can land after the
    // run has been cleaned up, and a store that threw here would take the
    // whole generation down with it.
    await store.checkpointRun(const GenerationId('never-begun'), 'text');
    await store.endRun(const GenerationId('never-begun'), TurnStatus.completed);

    expect(await store.loadUnfinishedRuns(), isEmpty);
  });

  test('a reused generation id does not overwrite the run before it', () async {
    // Generation ids are only unique within one inference service, and a new
    // one is built every time the user changes model -- its counter restarts,
    // so `litert-generation-1` comes round again. Keying runs by that id made
    // the second one land on top of the first: the earlier run's conversation
    // and model were rewritten, and because the row it landed on had already
    // ended, every later checkpoint and the close were filtered out by the
    // `not yet ended` scope. Run recording died silently at the first model
    // change.
    final RunRecord first = runFor(conversation);
    await store.beginRun(first);
    await store.checkpointRun(first.id, 'the first answer');
    await store.endRun(first.id, TurnStatus.completed);

    final RunRecord reused = RunRecord(
      id: first.id,
      conversationId: other,
      modelId: 'gemma-4-E4B-it',
      startedAt: DateTime.fromMillisecondsSinceEpoch(9999),
    );
    await store.beginRun(reused);
    await store.checkpointRun(reused.id, 'the second answer');

    final List<RunRecord> unfinished = await store.loadUnfinishedRuns();
    expect(unfinished.single.conversationId, other);
    expect(unfinished.single.partialText, 'the second answer');
    expect(unfinished.single.startedAt, reused.startedAt);

    // And closing the new one leaves the old one closed rather than reopening
    // or rewriting it.
    await store.endRun(reused.id, TurnStatus.completed);
    expect(await store.loadUnfinishedRuns(), isEmpty);
  });

  test('deleting a conversation forgets its unfinished runs', () async {
    await store.beginRun(runFor(conversation, 1));
    await store.beginRun(runFor(other, 2));

    await store.deleteConversation(conversation);

    expect((await store.loadUnfinishedRuns()).single.conversationId, other);
  });

  group('taking a conversation back to its last question', () {
    setUp(() async {
      await store.saveUserTurn(conversation, userTurn('first question'));
      await store.saveTerminalAssistantTurn(
        assistantTurn('first answer'),
        generationFor(conversation),
      );
      await store.saveUserTurn(conversation, userTurn('second question'));
      await store.saveTerminalAssistantTurn(
        assistantTurn('second answer'),
        generationFor(conversation, 2),
      );
    });

    test('the question and its answer both go', () async {
      await store.dropFromLastQuestion(conversation);

      expect(
        (await store.loadTurns(conversation)).map((Turn t) => t.text).toList(),
        <String>['first question', 'first answer'],
      );
    });

    test('an answer the view never showed goes with them', () async {
      // A cancelled answer with nothing in it is stored and deliberately kept
      // off the screen. A retry that counted the turns it could see would cut
      // above this row and leave it behind, to surface at the next launch
      // under an answer to a question it never belonged to.
      await store.saveUserTurn(conversation, userTurn('third question'));
      await store.saveTerminalAssistantTurn(
        assistantTurn('', TurnStatus.cancelled),
        generationFor(conversation, 3),
      );

      await store.dropFromLastQuestion(conversation);

      expect(
        (await store.loadTurns(conversation)).map((Turn t) => t.text).toList(),
        <String>[
          'first question',
          'first answer',
          'second question',
          'second answer',
        ],
      );
    });

    test('another conversation is untouched', () async {
      await store.saveUserTurn(other, userTurn('elsewhere'));

      await store.dropFromLastQuestion(conversation);

      expect(
        (await store.loadTurns(other)).single.text,
        'elsewhere',
        reason: 'a retry in one conversation reached into another',
      );
    });

    test('a conversation with nothing said in it is left alone', () async {
      await store.dropFromLastQuestion(other);

      expect(await store.loadTurns(other), isEmpty);
      expect(await store.loadTurns(conversation), hasLength(4));
    });
  });

  group('finding a conversation again', () {
    setUp(() async {
      await store.saveUserTurn(conversation, userTurn('明天台中天氣如何'));
      await store.saveTerminalAssistantTurn(
        assistantTurn('明天多雲，傍晚有陣雨。'),
        generationFor(conversation),
      );
      await store.saveUserTurn(other, userTurn('how do I run the tests'));
      await store.saveTerminalAssistantTurn(
        assistantTurn('Use dart run tool/verify.dart.'),
        generationFor(other, 2),
      );
    });

    test('a word from the question finds it', () async {
      expect(
        (await store.searchConversations(
          '台中',
        )).map((ConversationSummary c) => c.id),
        <ConversationId>[conversation],
      );
    });

    test('a word only the answer contains finds it too', () async {
      // The title is the first question, so searching titles alone would
      // lose every conversation the user remembers by what it told them.
      expect(
        (await store.searchConversations(
          '陣雨',
        )).map((ConversationSummary c) => c.id),
        <ConversationId>[conversation],
      );
    });

    test('an accented word matches itself', () async {
      // SQLite folds case for ASCII only and has no ICU here, so the stores
      // agree on exact matching beyond it rather than one of them quietly
      // being cleverer than the other.
      await store.saveUserTurn(conversation, userTurn('CAFÉ crème'));

      expect(await store.searchConversations('CAFÉ'), hasLength(1));
      expect(await store.searchConversations('café'), isEmpty);
    });

    test('Latin matches regardless of case', () async {
      expect(
        (await store.searchConversations(
          'VERIFY',
        )).map((ConversationSummary c) => c.id),
        <ConversationId>[other],
      );
    });

    test('a substring matches, because Chinese has no word breaks', () async {
      // Whole-word search is why full-text indexes are the wrong tool here:
      // 「台中天氣」 has no spaces to tokenize on.
      expect(await store.searchConversations('中天'), hasLength(1));
    });

    test('a blank query is not a search', () async {
      expect(
        (await store.searchConversations('   ')).length,
        (await store.listConversations()).length,
      );
    });

    test('nothing matching is an empty list, not an error', () async {
      expect(await store.searchConversations('無關的字'), isEmpty);
    });

    test('a conversation is listed once however often it matches', () async {
      expect(await store.searchConversations('明天'), hasLength(1));
    });
  });

  group('what the user decides about a conversation', () {
    setUp(() async {
      await store.saveUserTurn(conversation, userTurn('第一句話'));
      await store.saveUserTurn(other, userTurn('另一則'));
    });

    test('a renamed conversation keeps its new name', () async {
      await store.renameConversation(conversation, '週末計畫');

      expect(
        (await store.listConversations())
            .firstWhere((ConversationSummary c) => c.id == conversation)
            .title,
        '週末計畫',
      );
    });

    test('clearing the name goes back to the first thing said', () async {
      // The derived title is not lost when one is set over it, so undoing a
      // rename needs no second copy of what the user originally said.
      await store.renameConversation(conversation, '週末計畫');
      await store.renameConversation(conversation, '   ');

      expect(
        (await store.listConversations())
            .firstWhere((ConversationSummary c) => c.id == conversation)
            .title,
        '第一句話',
      );
    });

    test('a pinned conversation comes first however old it is', () async {
      // `other` was spoken in most recently, so it heads the list until the
      // older one is pinned.
      expect((await store.listConversations()).first.id, other);

      await store.setConversationPinned(conversation, pinned: true);

      final List<ConversationSummary> listed = await store.listConversations();
      expect(listed.first.id, conversation);
      expect(listed.first.isPinned, isTrue);
      expect(listed.last.isPinned, isFalse);
    });

    test('unpinning returns it to where recency puts it', () async {
      await store.setConversationPinned(conversation, pinned: true);
      await store.setConversationPinned(conversation, pinned: false);

      expect((await store.listConversations()).first.id, other);
    });

    test('the newest pin leads among the pinned', () async {
      // Pinned in the order that contradicts recency, and in the same
      // millisecond. Pinning the more recent one second would agree with
      // recency and the assertion could not fail either way.
      await store.setConversationPinned(other, pinned: true);
      await store.setConversationPinned(conversation, pinned: true);

      expect((await store.listConversations()).first.id, conversation);
    });

    test('the name the user gave is searchable', () async {
      // The list shows that name. Typing it and getting nothing back reads
      // as a broken search.
      await store.renameConversation(conversation, '週末計畫');

      expect(
        (await store.searchConversations(
          '週末',
        )).map((ConversationSummary c) => c.id),
        <ConversationId>[conversation],
      );
    });

    test('emptying a conversation takes it off the list', () async {
      await store.dropFromLastQuestion(conversation);

      expect(
        (await store.listConversations()).map((ConversationSummary c) => c.id),
        isNot(contains(conversation)),
      );
    });

    test('emptying a conversation forgets what was decided about it', () async {
      await store.renameConversation(conversation, '週末計畫');
      await store.setConversationPinned(conversation, pinned: true);
      await store.dropFromLastQuestion(conversation);
      await store.saveUserTurn(conversation, userTurn('第一句話'));

      final ConversationSummary reborn = (await store.listConversations())
          .firstWhere((ConversationSummary c) => c.id == conversation);
      expect(reborn.title, '第一句話');
      expect(reborn.isPinned, isFalse);
    });

    test('searching keeps the name and the pin', () async {
      await store.renameConversation(conversation, '週末計畫');
      await store.setConversationPinned(conversation, pinned: true);

      final List<ConversationSummary> found = await store.searchConversations(
        '第一句',
      );
      expect(found.single.title, '週末計畫');
      expect(found.single.isPinned, isTrue);
    });

    test(
      'forgetting a conversation forgets what was decided about it',
      () async {
        await store.renameConversation(conversation, '週末計畫');
        await store.setConversationPinned(conversation, pinned: true);

        await store.deleteConversation(conversation);
        await store.saveUserTurn(conversation, userTurn('第一句話'));

        final ConversationSummary reborn = (await store.listConversations())
            .firstWhere((ConversationSummary c) => c.id == conversation);
        expect(reborn.title, '第一句話');
        expect(reborn.isPinned, isFalse);
      },
    );
  });
}
