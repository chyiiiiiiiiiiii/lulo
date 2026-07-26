import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';

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
      expect(storage.lifecycle, <String>['user-saved', 'delta-visible']);

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
}
