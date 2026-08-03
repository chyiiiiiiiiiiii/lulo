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

  test('deleting a conversation forgets its unfinished runs', () async {
    await store.beginRun(runFor(conversation, 1));
    await store.beginRun(runFor(other, 2));

    await store.deleteConversation(conversation);

    expect((await store.loadUnfinishedRuns()).single.conversationId, other);
  });
}
