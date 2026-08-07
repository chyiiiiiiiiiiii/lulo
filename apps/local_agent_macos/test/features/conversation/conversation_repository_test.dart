import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/recording_conversation_storage_service.dart';

void main() {
  const ConversationId conversationId = ConversationId('daily-briefing');
  const GenerationRequest request = GenerationRequest(
    conversationId: conversationId,
    prompt: 'Summarize my local notes.',
  );
  const Turn userTurn = Turn(
    role: TurnRole.user,
    text: 'Summarize my local notes.',
    status: TurnStatus.completed,
  );
  const Generation generation = Generation(
    id: GenerationId('generation-1'),
    request: request,
  );

  test(
    'does not expose a delta while the user-turn write is still pending',
    () async {
      // Mutation caught: removing the await before inference subscription lets
      // an immediate model delta reach the presentation layer before storage.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService()
            ..userSaveGate = Completer<void>();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final List<GenerationEvent> visibleEvents = <GenerationEvent>[];

      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent event) {
            visibleEvents.add(event);
            if (event is GenerationDelta) {
              storage.lifecycle.add('delta-visible');
            }
          });

      await Future<void>.delayed(Duration.zero);
      expect(inference.requests, isEmpty);
      expect(visibleEvents, isEmpty);

      storage.userSaveGate!.complete();
      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Your notes are ready.',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(storage.userTurns, <Turn>[userTurn]);
      expect(visibleEvents.whereType<GenerationDelta>(), hasLength(1));
      // The user turn is stored before anything about the answer exists,
      // which is what this test is for. The run opening and its first
      // checkpoint sit between because a delta is handed to the stream
      // before its write is awaited, and delivery to a listener is a later
      // microtask than a store that records synchronously.
      expect(storage.lifecycle, <String>[
        'user-saved',
        'run-begun',
        'run-checkpointed',
        'delta-visible',
      ]);

      await subscription.cancel();
      await inference.dispose();
    },
  );

  test(
    'suppresses a second cancellation for the same active generation',
    () async {
      // Mutation caught: resetting cancellation state after the first stop lets
      // a double-click call the inference service twice.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      await Future<void>.delayed(Duration.zero);

      await Future.wait<void>(<Future<void>>[
        repository.stop(const GenerationId('generation-1')),
        repository.stop(const GenerationId('generation-1')),
      ]);

      expect(inference.cancellations, <GenerationId>[
        const GenerationId('generation-1'),
      ]);
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Late text must be ignored.',
        ),
      );
      inference.emit(const GenerationCompleted(GenerationId('generation-1')));
      await Future<void>.delayed(Duration.zero);

      expect(storage.assistantTurns, hasLength(1));
      expect(storage.assistantTurns.single.turn.status, TurnStatus.cancelled);
      expect(storage.assistantTurns.single.turn.text, isEmpty);

      await subscription.cancel();
      await inference.dispose();
    },
  );

  test('emits one cancellation terminal when its persistence fails', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService()
          ..terminalSaveError = StateError('disk write failed');
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final List<GenerationEvent> visibleEvents = <GenerationEvent>[];
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen(visibleEvents.add);

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      repository.stop(const GenerationId('generation-1')),
      throwsA(isA<StateError>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(visibleEvents.whereType<GenerationCancelled>(), hasLength(1));

    await subscription.cancel();
    await inference.dispose();
  });

  test('requests native cancellation before awaiting source cleanup', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final CancellationRaceInferenceService inference =
        CancellationRaceInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final Completer<void> startedVisible = Completer<void>();
    final Completer<void> streamDone = Completer<void>();
    final List<GenerationEvent> visibleEvents = <GenerationEvent>[];
    repository.startGeneration(userTurn: userTurn, request: request).listen((
      GenerationEvent event,
    ) {
      visibleEvents.add(event);
      if (event is GenerationStarted && !startedVisible.isCompleted) {
        startedVisible.complete();
      }
    }, onDone: streamDone.complete);

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await startedVisible.future;

    final Future<void> stop = repository.stop(generation.id);
    try {
      expect(inference.cancelRequested.isCompleted, isTrue);
    } finally {
      inference.cancelAcknowledged.complete();
      inference.allowSourceCleanup.complete();
      await stop;
    }
    await streamDone.future;

    expect(visibleEvents.whereType<GenerationCancelled>(), hasLength(1));
    await inference.dispose();
  });

  test(
    'cancel acknowledgement wins races with every native terminal',
    () async {
      final List<GenerationEvent> nativeTerminals = <GenerationEvent>[
        const GenerationCompleted(GenerationId('generation-1')),
        const GenerationCancelled(GenerationId('generation-1')),
        const GenerationFailed(
          generationId: GenerationId('generation-1'),
          failure: ConversationFailure('Native inference failed.'),
        ),
      ];

      for (final GenerationEvent nativeTerminal in nativeTerminals) {
        final RecordingConversationStorageService storage =
            RecordingConversationStorageService();
        final CancellationRaceInferenceService inference =
            CancellationRaceInferenceService();
        final ConversationRepository repository = ConversationRepository(
          storageService: storage,
          inferenceService: inference,
        );
        final Completer<void> startedVisible = Completer<void>();
        final Completer<void> streamDone = Completer<void>();
        final List<GenerationEvent> visibleEvents = <GenerationEvent>[];
        repository.startGeneration(userTurn: userTurn, request: request).listen(
          (GenerationEvent event) {
            visibleEvents.add(event);
            if (event is GenerationStarted && !startedVisible.isCompleted) {
              startedVisible.complete();
            }
          },
          onDone: streamDone.complete,
        );

        await inference.requestReceived;
        inference.emit(GenerationStarted(generation));
        await startedVisible.future;

        final Future<void> stop = repository.stop(generation.id);
        expect(inference.cancelRequested.isCompleted, isTrue);
        inference.emit(nativeTerminal);
        inference.cancelAcknowledged.complete();
        inference.emit(
          const GenerationDelta(
            generationId: GenerationId('generation-1'),
            delta: 'post-terminal text',
          ),
        );
        inference.allowSourceCleanup.complete();

        await stop;
        await streamDone.future;

        final List<GenerationEvent> visibleTerminals = visibleEvents
            .where(_isTerminalGenerationEvent)
            .toList();
        expect(visibleTerminals, hasLength(1));
        expect(visibleTerminals.single, isA<GenerationCancelled>());
        expect(visibleEvents.whereType<GenerationDelta>(), isEmpty);
        expect(storage.assistantTurns, hasLength(1));
        expect(storage.assistantTurns.single.turn.status, TurnStatus.cancelled);
        expect(inference.sourceCleanupRequested.isCompleted, isTrue);

        await repository
            .startGeneration(userTurn: userTurn, request: request)
            .drain<void>();
        expect(inference.requestCount, 2);
        await inference.dispose();
      }
    },
  );

  test(
    'releases the active operation when its listener is cancelled',
    () async {
      // Mutation caught: cancelling only the upstream subscription leaves the
      // repository permanently busy and rejects the next user request.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> firstSubscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      await Future<void>.delayed(Duration.zero);
      await firstSubscription.cancel();

      final StreamSubscription<GenerationEvent> secondSubscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});
      await Future<void>.delayed(Duration.zero);

      expect(inference.requests, hasLength(2));

      await secondSubscription.cancel();
      await inference.dispose();
    },
  );

  test(
    'releases the active operation when cancellation persistence fails',
    () async {
      // Mutation caught: allowing a terminal storage exception to bypass finish
      // leaves the repository permanently busy after a failed stop request.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService()
            ..terminalSaveError = StateError('disk write failed');
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> firstSubscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        repository.stop(const GenerationId('generation-1')),
        throwsA(isA<StateError>()),
      );

      final StreamSubscription<GenerationEvent> secondSubscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {}, onError: (Object _) {});
      await Future<void>.delayed(Duration.zero);

      expect(inference.requests, hasLength(2));

      await firstSubscription.cancel();
      await secondSubscription.cancel();
      await inference.dispose();
    },
  );

  test('releases a cancelled listener when its terminal write fails', () async {
    // Mutation caught: letting a listener-cancellation write error skip finish
    // keeps the repository busy even though its only listener has gone away.
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService()
          ..terminalSaveError = StateError('disk write failed');
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final StreamSubscription<GenerationEvent> firstSubscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);

    await expectLater(firstSubscription.cancel(), throwsA(isA<StateError>()));

    final StreamSubscription<GenerationEvent> secondSubscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {}, onError: (Object _) {});
    await Future<void>.delayed(Duration.zero);

    expect(inference.requests, hasLength(2));

    await secondSubscription.cancel();
    await inference.dispose();
  });

  test(
    'persists a failed assistant turn when inference ends after start',
    () async {
      // Mutation caught: treating source completion as cleanup only drops a
      // started generation's accumulated text and terminal failed lifecycle.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Partial summary.',
        ),
      );
      await inference.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(storage.assistantTurns, hasLength(1));
      expect(storage.assistantTurns.single.generation, generation);
      expect(storage.assistantTurns.single.turn.text, 'Partial summary.');
      expect(storage.assistantTurns.single.turn.status, TurnStatus.failed);

      await subscription.cancel();
    },
  );

  test('ignores a terminal event received before a matching start', () async {
    // Mutation caught: accepting a pre-start completion marks an unknown
    // operation terminal and prevents its later valid response from saving.
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    inference.emit(GenerationStarted(generation));
    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'Valid response.',
      ),
    );
    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    await Future<void>.delayed(Duration.zero);

    expect(storage.assistantTurns, hasLength(1));
    expect(storage.assistantTurns.single.turn.text, 'Valid response.');
    expect(storage.assistantTurns.single.turn.status, TurnStatus.completed);

    await subscription.cancel();
    await inference.dispose();
  });

  test('ignores a terminal event for a different started generation', () async {
    // Mutation caught: accepting a mismatched terminal event ends the active
    // request before its own completion can persist the assistant response.
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    inference.emit(
      const GenerationCancelled(GenerationId('another-generation')),
    );
    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'Still active.',
      ),
    );
    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    await Future<void>.delayed(Duration.zero);

    expect(storage.assistantTurns, hasLength(1));
    expect(storage.assistantTurns.single.turn.text, 'Still active.');
    expect(storage.assistantTurns.single.turn.status, TurnStatus.completed);

    await subscription.cancel();
    await inference.dispose();
  });

  test(
    'persists a failed event terminal turn independently of stream errors',
    () async {
      // Mutation caught: treating GenerationFailed like a non-terminal progress
      // event loses its failure lifecycle unless the Dart stream also errors.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final List<GenerationEvent> visibleEvents = <GenerationEvent>[];
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen(visibleEvents.add);

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Partial failure response.',
        ),
      );
      inference.emit(
        const GenerationFailed(
          generationId: GenerationId('generation-1'),
          failure: ConversationFailure('Local inference failed.'),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(storage.assistantTurns, hasLength(1));
      expect(
        storage.assistantTurns.single.turn.text,
        'Partial failure response.',
      );
      expect(storage.assistantTurns.single.turn.status, TurnStatus.failed);
      expect(visibleEvents.whereType<GenerationFailed>(), hasLength(1));

      await subscription.cancel();
      await inference.dispose();
    },
  );

  test(
    'persists one completed assistant turn and ignores a late terminal event',
    () async {
      // Mutation caught: clearing terminal state after persistence allows a late
      // completion event to create a duplicate stored assistant response.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final List<GenerationEvent> visibleEvents = <GenerationEvent>[];
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen(visibleEvents.add);

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Local summary.',
        ),
      );
      inference.emit(const GenerationCompleted(GenerationId('generation-1')));
      inference.emit(const GenerationCompleted(GenerationId('generation-1')));
      await Future<void>.delayed(Duration.zero);

      expect(storage.assistantTurns, hasLength(1));
      final Turn savedTurn = storage.assistantTurns.single.turn;
      expect(savedTurn.role, TurnRole.assistant);
      expect(savedTurn.text, 'Local summary.');
      expect(savedTurn.status, TurnStatus.completed);
      expect(visibleEvents.whereType<GenerationCompleted>(), hasLength(1));

      await subscription.cancel();
      await inference.dispose();
    },
  );

  test(
    'ignores a delta for a different generation after generation starts',
    () async {
      // Mutation caught: accepting any delta after start mixes text from another
      // operation into the persisted assistant turn.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('another-generation'),
          delta: 'Do not store this.',
        ),
      );
      inference.emit(const GenerationCompleted(GenerationId('generation-1')));
      await Future<void>.delayed(Duration.zero);

      expect(storage.assistantTurns.single.turn.text, isEmpty);

      await subscription.cancel();
      await inference.dispose();
    },
  );

  test(
    'persists a failed assistant turn when inference raises an error',
    () async {
      // Mutation caught: closing an errored inference stream without persisting
      // its started generation loses the terminal lifecycle state and text.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final Completer<Object> visibleError = Completer<Object>();
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen(
            (GenerationEvent _) {},
            onError: (Object error, StackTrace _) =>
                visibleError.complete(error),
          );

      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Partial local summary.',
        ),
      );
      inference.emitError(StateError('model exited'), StackTrace.empty);

      expect(await visibleError.future, isA<StateError>());
      expect(storage.assistantTurns, hasLength(1));
      expect(storage.assistantTurns.single.turn.text, 'Partial local summary.');
      expect(storage.assistantTurns.single.turn.status, TurnStatus.failed);

      await subscription.cancel();
      await inference.dispose();
    },
  );

  test(
    'a forgotten conversation is not written back by its own cancellation',
    () async {
      // Deleting removes the rows; a conversation *is* whatever rows share
      // its id, so the cancellation's terminal write would re-create it as a
      // ghost with a blank title.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});
      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      await Future<void>.delayed(Duration.zero);

      await repository.deleteConversation(conversationId);
      await subscription.cancel();

      expect(
        storage.assistantTurns,
        isEmpty,
        reason:
            'The cancellation of a forgotten conversation wrote it back '
            'into the store.',
      );
      await inference.dispose();
    },
  );

  test(
    'asking the last question again releases the runtime session too',
    () async {
      // The store is only half of what remembers the answer being replaced.
      // The runtime keeps a live conversation per session id, and its KV
      // cache still holds the question and the answer the user just rejected
      // — so the retry would be conditioned on the very thing it is meant to
      // replace, and the model would see the question asked twice. Releasing
      // makes the next generation re-seed from the truncated history.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );

      await repository.dropFromLastQuestion(conversationId);

      expect(storage.droppedFromLastQuestion, <ConversationId>[conversationId]);
      expect(inference.releasedSessions, <ConversationId>[conversationId]);
      await inference.dispose();
    },
  );

  test(
    'forgetting a conversation releases the runtime session it held',
    () async {
      // Deleting only ever removed rows. The runtime keeps one live LiteRT-LM
      // conversation per session id, each holding its own KV cache, and nothing
      // on this path ever told it to let go: the user says forget this, and the
      // memory it costs outlives the thing they forgot.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );

      await repository.deleteConversation(conversationId);

      expect(inference.releasedSessions, <ConversationId>[conversationId]);
      await inference.dispose();
    },
  );

  test(
    'a conversation deleted mid-answer still releases its runtime session',
    () async {
      // The costliest case to leak: the session is not merely allocated, it is
      // the one currently holding a live generation and its grown KV cache.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final ControlledInferenceService inference = ControlledInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> subscription = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});
      await inference.requestReceived;
      inference.emit(GenerationStarted(generation));
      await Future<void>.delayed(Duration.zero);

      await repository.deleteConversation(conversationId);
      await subscription.cancel();

      expect(inference.releasedSessions, <ConversationId>[conversationId]);
      await inference.dispose();
    },
  );

  test(
    'a message sent while the last answer is still cancelling waits its turn',
    () async {
      // Switching conversations disposes the old ViewModel, whose
      // cancellation has a native round trip to make. The next message must
      // wait for that teardown, not be refused for arriving during it.
      final RecordingConversationStorageService storage =
          RecordingConversationStorageService();
      final _HeldCancelInferenceService inference =
          _HeldCancelInferenceService();
      final ConversationRepository repository = ConversationRepository(
        storageService: storage,
        inferenceService: inference,
      );
      final StreamSubscription<GenerationEvent> first = repository
          .startGeneration(userTurn: userTurn, request: request)
          .listen((GenerationEvent _) {});
      await inference.requestReceived.future;
      inference.emit(GenerationStarted(generation));
      await Future<void>.delayed(Duration.zero);

      // The old conversation starts cancelling and its native cancel hangs
      // in flight...
      final Future<void> cancelling = first.cancel();
      // ...while the user is already talking in the new conversation.
      const GenerationRequest nextRequest = GenerationRequest(
        conversationId: ConversationId('the-new-conversation'),
        prompt: 'A fresh question.',
      );
      final List<Object> visibleErrors = <Object>[];
      final StreamSubscription<GenerationEvent> second = repository
          .startGeneration(
            userTurn: const Turn(
              role: TurnRole.user,
              text: 'A fresh question.',
              status: TurnStatus.completed,
            ),
            request: nextRequest,
          )
          .listen(
            (GenerationEvent _) {},
            onError: (Object error, StackTrace _) => visibleErrors.add(error),
          );
      await Future<void>.delayed(Duration.zero);
      expect(
        visibleErrors,
        isEmpty,
        reason: 'The next message was refused instead of queued.',
      );

      inference.releaseCancel();
      await cancelling;
      await inference.secondRequestReceived.future;

      expect(inference.requests, hasLength(2));
      expect(
        inference.requests.last.conversationId,
        nextRequest.conversationId,
      );
      expect(visibleErrors, isEmpty);
      await second.cancel();
    },
  );

  // Run records. The turn is written once, at the end; these are what is on
  // disk while the answer is still being written.

  test('a generation opens a run naming its model and conversation', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService()
      ..modelId = 'gemma-4-E2B-it';
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
      clock: () => DateTime.fromMillisecondsSinceEpoch(5000),
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);

    expect(storage.begunRuns.single.id, generation.id);
    expect(storage.begunRuns.single.conversationId, conversationId);
    expect(storage.begunRuns.single.modelId, 'gemma-4-E2B-it');
    expect(
      storage.begunRuns.single.startedAt,
      DateTime.fromMillisecondsSinceEpoch(5000),
    );
    // The run must be open before any answer text exists, or a crash during
    // the first token leaves nothing at all.
    expect(storage.lifecycle, contains('run-begun'));
    expect(
      storage.lifecycle.indexOf('run-begun'),
      lessThan(storage.lifecycle.length),
    );

    await subscription.cancel();
  });

  test('checkpoints carry the whole answer so far, not the delta', () async {
    // Appending instead of overwriting is the mistake this shape invites,
    // and it would double every word on recovery.
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService();
    DateTime now = DateTime.fromMillisecondsSinceEpoch(0);
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
      clock: () => now,
      checkpointInterval: const Duration(milliseconds: 500),
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);

    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'Hello',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    now = DateTime.fromMillisecondsSinceEpoch(600);
    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: ' there',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(storage.checkpoints, <String>['Hello', 'Hello there']);

    await subscription.cancel();
  });

  test('deltas inside the interval do not each cost a write', () async {
    // A token-per-write store would put thousands of UPDATEs on the path
    // that is already streaming; the interval is what keeps it to dozens.
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService();
    DateTime now = DateTime.fromMillisecondsSinceEpoch(0);
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
      clock: () => now,
      checkpointInterval: const Duration(milliseconds: 500),
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);

    for (int index = 0; index < 20; index += 1) {
      now = DateTime.fromMillisecondsSinceEpoch(index * 10);
      inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'x',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    // The first delta always checkpoints, so a crash on the first token still
    // leaves a word behind. The remaining nineteen land inside one interval.
    expect(storage.checkpoints, hasLength(1));

    await subscription.cancel();
  });

  test('a completed generation closes its run', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);
    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    await Future<void>.delayed(Duration.zero);

    expect(storage.endedRuns, <TurnStatus>[TurnStatus.completed]);
    // The turn is the durable record once it exists; the run must not be
    // left open behind it.
    expect(storage.lifecycle, contains('assistant-saved'));
    expect(storage.lifecycle, contains('run-ended'));

    await subscription.cancel();
  });

  test('a cancelled generation closes its run as cancelled', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);
    inference.emit(const GenerationCancelled(GenerationId('generation-1')));
    await Future<void>.delayed(Duration.zero);

    expect(storage.endedRuns, <TurnStatus>[TurnStatus.cancelled]);

    await subscription.cancel();
  });

  test('a forgotten conversation writes no run at all', () async {
    // Deleting a conversation mid-answer must not leave a run pointing at
    // rows that no longer exist -- the same ghost the terminal turn avoids.
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ControlledInferenceService inference = ControlledInferenceService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final StreamSubscription<GenerationEvent> subscription = repository
        .startGeneration(userTurn: userTurn, request: request)
        .listen((GenerationEvent _) {});

    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);
    await repository.deleteConversation(conversationId);

    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'orphaned',
      ),
    );
    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    await Future<void>.delayed(Duration.zero);

    expect(storage.checkpoints, isEmpty);
    expect(storage.endedRuns, isEmpty);

    await subscription.cancel();
  });

  // Recovery. Everything above only writes; this is what makes the writing
  // worth anything.

  test('an interrupted run comes back as a turn saying so', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService()
          ..unfinishedRuns = <RunRecord>[
            RunRecord(
              id: const GenerationId('died-mid-answer'),
              conversationId: conversationId,
              modelId: 'gemma-4-E2B-it',
              startedAt: DateTime.fromMillisecondsSinceEpoch(1),
              partialText: 'It was going to say',
            ),
          ];
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: ControlledInferenceService(),
    );

    await repository.recoverInterruptedRuns();

    expect(storage.assistantTurns.single.turn.text, 'It was going to say');
    expect(
      storage.assistantTurns.single.turn.status,
      TurnStatus.interrupted,
      reason:
          'Nothing failed and nobody stopped it; the process went away, and '
          'the turn must not claim otherwise.',
    );
    expect(
      storage.assistantTurns.single.generation.request.conversationId,
      conversationId,
    );
    // Closed behind the turn, or the next launch recovers it a second time
    // and the conversation grows a duplicate every time the app opens.
    expect(storage.endedRuns, <TurnStatus>[TurnStatus.interrupted]);
  });

  test('a run interrupted before its first word leaves no turn', () async {
    // An empty turn is worse than none: it renders as a blank bubble the
    // user cannot account for.
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService()
          ..unfinishedRuns = <RunRecord>[
            RunRecord(
              id: const GenerationId('died-immediately'),
              conversationId: conversationId,
              modelId: 'gemma-4-E2B-it',
              startedAt: DateTime.fromMillisecondsSinceEpoch(1),
            ),
          ];
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: ControlledInferenceService(),
    );

    await repository.recoverInterruptedRuns();

    expect(storage.assistantTurns, isEmpty);
    // The run is still closed, so it is not reconsidered on every launch.
    expect(storage.endedRuns, <TurnStatus>[TurnStatus.interrupted]);
  });

  test('a clean start recovers nothing', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService();
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: ControlledInferenceService(),
    );

    await repository.recoverInterruptedRuns();

    expect(storage.assistantTurns, isEmpty);
    expect(storage.endedRuns, isEmpty);
  });

  test('every interrupted run is recovered, not just the first', () async {
    final RecordingConversationStorageService storage =
        RecordingConversationStorageService()
          ..unfinishedRuns = <RunRecord>[
            RunRecord(
              id: const GenerationId('one'),
              conversationId: conversationId,
              modelId: 'gemma-4-E2B-it',
              startedAt: DateTime.fromMillisecondsSinceEpoch(1),
              partialText: 'first',
            ),
            RunRecord(
              id: const GenerationId('two'),
              conversationId: const ConversationId('another'),
              modelId: 'gemma-4-E2B-it',
              startedAt: DateTime.fromMillisecondsSinceEpoch(2),
              partialText: 'second',
            ),
          ];
    final ConversationRepository repository = ConversationRepository(
      storageService: storage,
      inferenceService: ControlledInferenceService(),
    );

    await repository.recoverInterruptedRuns();

    expect(
      storage.assistantTurns.map((SavedAssistantTurn saved) => saved.turn.text),
      <String>['first', 'second'],
    );
    expect(
      storage.assistantTurns
          .map(
            (SavedAssistantTurn saved) =>
                saved.generation.request.conversationId,
          )
          .toList(),
      <ConversationId>[conversationId, const ConversationId('another')],
    );
  });
}

/// Records requests and holds native cancellation open until released.
final class _HeldCancelInferenceService implements InferenceService {
  @override
  String get modelId => 'test-model';

  final StreamController<GenerationEvent> _events =
      StreamController<GenerationEvent>.broadcast();
  final List<GenerationRequest> requests = <GenerationRequest>[];
  final Completer<GenerationRequest> requestReceived =
      Completer<GenerationRequest>();
  final Completer<GenerationRequest> secondRequestReceived =
      Completer<GenerationRequest>();
  final Completer<void> _cancelGate = Completer<void>();

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    requests.add(request);
    if (!requestReceived.isCompleted) {
      requestReceived.complete(request);
    } else if (!secondRequestReceived.isCompleted) {
      secondRequestReceived.complete(request);
    }
    return _events.stream;
  }

  @override
  Future<void> cancel(GenerationId generationId) => _cancelGate.future;

  @override
  Future<void> releaseSession(ConversationId conversationId) async {}

  void emit(GenerationEvent event) => _events.add(event);

  void releaseCancel() {
    if (!_cancelGate.isCompleted) {
      _cancelGate.complete();
    }
  }
}

bool _isTerminalGenerationEvent(GenerationEvent event) {
  return event is GenerationCompleted ||
      event is GenerationCancelled ||
      event is GenerationFailed;
}

final class CancellationRaceInferenceService implements InferenceService {
  @override
  String get modelId => 'test-model';

  CancellationRaceInferenceService() {
    _events = StreamController<GenerationEvent>(
      sync: true,
      onCancel: () async {
        sourceCleanupRequested.complete();
        await allowSourceCleanup.future;
      },
    );
  }

  late final StreamController<GenerationEvent> _events;
  final Completer<GenerationRequest> _requestReceived =
      Completer<GenerationRequest>();
  final Completer<void> cancelRequested = Completer<void>();
  final Completer<void> cancelAcknowledged = Completer<void>();
  final Completer<void> sourceCleanupRequested = Completer<void>();
  final Completer<void> allowSourceCleanup = Completer<void>();
  int requestCount = 0;

  Future<GenerationRequest> get requestReceived => _requestReceived.future;

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    requestCount += 1;
    if (requestCount == 1) {
      _requestReceived.complete(request);
      return _events.stream;
    }
    return const Stream<GenerationEvent>.empty();
  }

  @override
  Future<void> cancel(GenerationId generationId) async {
    cancelRequested.complete();
    await cancelAcknowledged.future;
  }

  @override
  Future<void> releaseSession(ConversationId conversationId) async {}

  void emit(GenerationEvent event) {
    _events.add(event);
  }

  Future<void> dispose() => _events.close();
}
