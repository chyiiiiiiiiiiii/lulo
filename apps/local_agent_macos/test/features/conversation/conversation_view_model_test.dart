import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/microtask_batch_scheduler.dart';
import '../../support/recording_conversation_storage_service.dart';

void main() {
  test(
    'trimmed non-empty submit delegates one user turn and request',
    () async {
      final _Harness harness = _Harness();
      final ConversationViewModel viewModel = harness.createViewModel();

      await viewModel.submit('  Hello local model  ');
      await harness.inference.requestReceived;

      expect(harness.storage.userTurns, hasLength(1));
      expect(harness.storage.userTurns.single.role, TurnRole.user);
      expect(harness.storage.userTurns.single.text, 'Hello local model');
      expect(harness.storage.userTurns.single.status, TurnStatus.completed);
      expect(harness.inference.requests, hasLength(1));
      expect(
        harness.inference.requests.single.conversationId,
        const ConversationId('conversation-1'),
      );
      expect(harness.inference.requests.single.prompt, 'Hello local model');
      expect(viewModel.projection.completedTurns, hasLength(1));
      expect(
        viewModel.projection.completedTurns.single.text,
        'Hello local model',
      );

      viewModel.dispose();
      await harness.dispose();
    },
  );

  test('blank submission is rejected without repository work', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit(' \n\t ');
    await Future<void>.delayed(Duration.zero);

    expect(harness.storage.userTurns, isEmpty);
    expect(harness.inference.requests, isEmpty);
    expect(viewModel.projection.completedTurns, isEmpty);
    expect(viewModel.canSubmit, isTrue);

    viewModel.dispose();
    await harness.dispose();
  });

  test('active submission is rejected without repository work', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit('First');
    await harness.inference.requestReceived;
    await viewModel.submit('Second');
    await Future<void>.delayed(Duration.zero);

    expect(harness.storage.userTurns, hasLength(1));
    expect(harness.inference.requests, hasLength(1));
    expect(viewModel.projection.completedTurns, hasLength(1));
    expect(viewModel.projection.completedTurns.single.text, 'First');
    expect(viewModel.canSubmit, isFalse);

    viewModel.dispose();
    await harness.dispose();
  });

  test('matching streaming events update only the active projection', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit('Hello');
    await harness.inference.requestReceived;
    harness.inference.emit(
      GenerationStarted(
        const Generation(
          id: GenerationId('generation-1'),
          request: GenerationRequest(
            conversationId: ConversationId('conversation-1'),
            prompt: 'Hello',
          ),
        ),
      ),
    );
    harness.inference.emit(
      const GenerationDelta(
        generationId: GenerationId('another-generation'),
        delta: 'Wrong',
      ),
    );
    harness.inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'Local ',
      ),
    );
    harness.inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'reply',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.projection.completedTurns, hasLength(1));
    expect(viewModel.projection.completedTurns.single.text, 'Hello');
    expect(viewModel.projection.activeTurn?.role, TurnRole.assistant);
    expect(viewModel.projection.activeTurn?.text, 'Local reply');
    expect(viewModel.projection.activeTurn?.status, TurnStatus.streaming);
    expect(viewModel.canSubmit, isFalse);

    viewModel.dispose();
    await harness.dispose();
  });

  test('completion finalizes the active turn and enables submission', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();
    await _startGeneration(harness, viewModel);

    harness.inference.emit(
      const GenerationCompleted(GenerationId('generation-1')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.projection.activeTurn, isNull);
    expect(viewModel.projection.completedTurns, hasLength(2));
    expect(viewModel.projection.completedTurns.last.role, TurnRole.assistant);
    expect(viewModel.projection.completedTurns.last.text, 'Partial');
    expect(
      viewModel.projection.completedTurns.last.status,
      TurnStatus.completed,
    );
    expect(viewModel.canSubmit, isTrue);

    await viewModel.submit('Next');
    await Future<void>.delayed(Duration.zero);
    expect(harness.inference.requests, hasLength(2));

    viewModel.dispose();
    await harness.dispose();
  });

  test('a follow-up carries what was already said, and only that', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();
    await _startGeneration(harness, viewModel);
    harness.inference.emit(
      const GenerationCompleted(GenerationId('generation-1')),
    );
    await Future<void>.delayed(Duration.zero);

    await viewModel.submit('Next');
    await Future<void>.delayed(Duration.zero);

    // The opening question had nothing behind it.
    expect(harness.inference.requests.first.history, isEmpty);

    // The follow-up carries the finished exchange, oldest first — and stops
    // there. A history ending in 'Next' would ask the model the same
    // question twice.
    final List<Turn> history = harness.inference.requests.last.history;
    expect(history, hasLength(2));
    expect(history.first.role, TurnRole.user);
    expect(history.first.text, 'Hello');
    expect(history.last.role, TurnRole.assistant);
    expect(history.last.text, 'Partial');
    expect(history.map((Turn turn) => turn.text), isNot(contains('Next')));

    viewModel.dispose();
    await harness.dispose();
  });

  test(
    'cancellation finalizes the partial turn and enables submission',
    () async {
      final _Harness harness = _Harness();
      final ConversationViewModel viewModel = harness.createViewModel();
      await _startGeneration(harness, viewModel);

      harness.inference.emit(
        const GenerationCancelled(GenerationId('generation-1')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.projection.activeTurn, isNull);
      expect(viewModel.projection.completedTurns.last.text, 'Partial');
      expect(
        viewModel.projection.completedTurns.last.status,
        TurnStatus.cancelled,
      );
      expect(viewModel.canSubmit, isTrue);

      viewModel.dispose();
      await harness.dispose();
    },
  );

  test('failure finalizes the partial turn and enables submission', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();
    await _startGeneration(harness, viewModel);

    harness.inference.emit(
      const GenerationFailed(
        generationId: GenerationId('generation-1'),
        failure: ConversationFailure('Local runtime failed.'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.projection.activeTurn, isNull);
    expect(viewModel.projection.completedTurns.last.text, 'Partial');
    expect(viewModel.projection.completedTurns.last.status, TurnStatus.failed);
    expect(viewModel.canSubmit, isTrue);

    viewModel.dispose();
    await harness.dispose();
  });

  test('stop delegates idempotently for the active generation', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();
    await _startGeneration(harness, viewModel);

    await Future.wait<void>(<Future<void>>[viewModel.stop(), viewModel.stop()]);
    await Future<void>.delayed(Duration.zero);

    expect(harness.inference.cancellations, <GenerationId>[
      const GenerationId('generation-1'),
    ]);
    expect(viewModel.projection.activeTurn, isNull);
    expect(viewModel.projection.completedTurns.last.text, 'Partial');
    expect(
      viewModel.projection.completedTurns.last.status,
      TurnStatus.cancelled,
    );

    viewModel.dispose();
    await harness.dispose();
  });

  test(
    'dispose cancels the operation and prevents post-dispose notifications',
    () async {
      final _Harness harness = _Harness();
      final ConversationViewModel viewModel = harness.createViewModel();
      await _startGeneration(harness, viewModel);
      int notifications = 0;
      viewModel.addListener(() => notifications += 1);

      viewModel.dispose();
      await Future<void>.delayed(Duration.zero);
      final int notificationsAtDispose = notifications;
      harness.inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Late',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(harness.inference.cancellations, <GenerationId>[
        const GenerationId('generation-1'),
      ]);
      expect(notifications, notificationsAtDispose);

      await harness.dispose();
    },
  );

  test('stream error finalizes the active turn as failed', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();
    await _startGeneration(harness, viewModel);

    harness.inference.emitError(
      StateError('runtime disconnected'),
      StackTrace.current,
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.projection.activeTurn, isNull);
    expect(viewModel.projection.completedTurns.last.text, 'Partial');
    expect(viewModel.projection.completedTurns.last.status, TurnStatus.failed);
    expect(viewModel.canSubmit, isTrue);

    viewModel.dispose();
    await harness.dispose();
  });

  test('stop before the first token leaves the composer alive', () async {
    // Escape lands exactly in the prefill window. Cancelling by hand skips
    // the onDone path that re-enables submission, and the composer gates on
    // the listenable — a stale false is a dead send key forever.
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit('Hello');
    await harness.inference.requestReceived;
    await viewModel.stop();
    await Future<void>.delayed(Duration.zero);

    expect(
      viewModel.canSubmitListenable.value,
      isTrue,
      reason: 'The composer stayed disabled with nothing left to enable it.',
    );

    viewModel.dispose();
    await harness.dispose();
  });

  test('stop before generation starts cancels the pending operation', () async {
    final _Harness harness = _Harness();
    final Completer<void> saveGate = Completer<void>();
    harness.storage.userSaveGate = saveGate;
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit('Hello');
    await Future<void>.delayed(Duration.zero);
    await Future.wait<void>(<Future<void>>[viewModel.stop(), viewModel.stop()]);
    saveGate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(harness.inference.requests, isEmpty);
    expect(viewModel.projection.activeTurn, isNull);
    // The cancelled answer said nothing, so it is not listed — see 'a stop
    // before the first token leaves no turn behind'. What this test is about
    // is that two overlapping stops cancel the pending operation once and
    // hand the composer back.
    expect(viewModel.projection.completedTurns, hasLength(1));
    expect(viewModel.projection.completedTurns.single.role, TurnRole.user);
    expect(viewModel.canSubmit, isTrue);

    viewModel.dispose();
    await harness.dispose();
  });

  test(
    'source error before generation starts publishes a failed assistant turn',
    () async {
      final _Harness harness = _Harness();
      final ConversationViewModel viewModel = harness.createViewModel();

      await viewModel.submit('Hello');
      await harness.inference.requestReceived;
      harness.inference.emitError(
        StateError('runtime failed before start'),
        StackTrace.current,
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.projection.activeTurn, isNull);
      expect(viewModel.projection.completedTurns, hasLength(2));
      expect(viewModel.projection.completedTurns.last.role, TurnRole.assistant);
      expect(viewModel.projection.completedTurns.last.text, isEmpty);
      expect(
        viewModel.projection.completedTurns.last.status,
        TurnStatus.failed,
      );
      expect(viewModel.canSubmit, isTrue);

      await viewModel.submit('Recovered');
      await Future<void>.delayed(Duration.zero);
      expect(harness.inference.requests, hasLength(2));

      viewModel.dispose();
      await harness.dispose();
    },
  );

  test(
    'dispose during a pending user save prevents inference and late notification',
    () async {
      final _Harness harness = _Harness();
      final Completer<void> saveGate = Completer<void>();
      harness.storage.userSaveGate = saveGate;
      final ConversationViewModel viewModel = harness.createViewModel();
      int notifications = 0;
      viewModel.addListener(() => notifications += 1);

      await viewModel.submit('Hello');
      final int notificationsBeforeDispose = notifications;
      viewModel.dispose();
      saveGate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(harness.inference.requests, isEmpty);
      expect(notifications, notificationsBeforeDispose);

      await harness.dispose();
    },
  );

  test(
    'late delta after stop cannot mutate or notify the projection',
    () async {
      final _Harness harness = _Harness();
      final ConversationViewModel viewModel = harness.createViewModel();
      await _startGeneration(harness, viewModel);
      int notifications = 0;
      viewModel.addListener(() => notifications += 1);

      await viewModel.stop();
      await Future<void>.delayed(Duration.zero);
      final int notificationsAfterStop = notifications;
      final List<Turn> turnsAfterStop = viewModel.projection.completedTurns;
      harness.inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'Late mutation',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(notifications, notificationsAfterStop);
      expect(viewModel.projection.activeTurn, isNull);
      expect(viewModel.projection.completedTurns, same(turnsAfterStop));
      expect(viewModel.projection.completedTurns.last.text, 'Partial');
      expect(
        viewModel.projection.completedTurns.last.status,
        TurnStatus.cancelled,
      );

      viewModel.dispose();
      await harness.dispose();
    },
  );

  test('a stop before the first token leaves no turn behind', () async {
    // Barging in during prefill cancels an answer that never said anything.
    // Listing it puts an empty grey "Response stopped" bubble in the
    // scrollback — a turn the user was never shown a word of, and which they
    // ended themselves. Interrupting before there is anything to interrupt
    // should leave the conversation exactly as it was.
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit('Hello');
    await harness.inference.requestReceived;
    await viewModel.stop();

    expect(viewModel.projection.activeTurn, isNull);
    expect(viewModel.projection.completedTurns, hasLength(1));
    expect(viewModel.projection.completedTurns.single.role, TurnRole.user);
    expect(viewModel.canSubmit, isTrue);

    viewModel.dispose();
    await harness.dispose();
  });

  test('a failure with nothing written still says so', () async {
    // The mirror image, and deliberately not symmetric: the user caused the
    // cancellation and needs no receipt for it, but a failure is something
    // that happened to them. Dropping it would leave a question that looks
    // answered and never was.
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit('Hello');
    await harness.inference.requestReceived;
    harness.inference.emitError(
      StateError('runtime unavailable'),
      StackTrace.empty,
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.projection.completedTurns, hasLength(2));
    expect(viewModel.projection.completedTurns.last.status, TurnStatus.failed);

    viewModel.dispose();
    await harness.dispose();
  });

  test('a stop whose cancellation fails still returns the composer', () async {
    // Stopping before the generation started cancels the subscription by
    // hand, and that is the only thing that re-enables submission on this
    // path. A throw from the boundary used to skip it, leaving the send key
    // dead with nothing left to flip it — and stop() memoised the failed
    // future, so asking again returned the same failure without retrying.
    final _Harness harness = _Harness();
    harness.inference.listenerCancellationFailure = StateError(
      'the host could not answer for this generation',
    );
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.submit('Hello');
    await harness.inference.requestReceived;
    expect(viewModel.canSubmit, isFalse);

    await expectLater(viewModel.stop(), completes);

    expect(viewModel.canSubmit, isTrue);
    expect(viewModel.projection.completedTurns.single.role, TurnRole.user);

    harness.inference.listenerCancellationFailure = null;
    await viewModel.submit('And again');
    await Future<void>.delayed(Duration.zero);
    expect(harness.inference.requests, hasLength(2));

    viewModel.dispose();
    await harness.dispose();
  });

  test(
    'dispose while pre-start stop is suspended prevents its continuation',
    () async {
      final _Harness harness = _Harness();
      final Completer<void> saveGate = Completer<void>();
      harness.storage.userSaveGate = saveGate;
      final ConversationViewModel viewModel = harness.createViewModel();
      int notifications = 0;
      viewModel.addListener(() => notifications += 1);

      await viewModel.submit('Hello');
      final ConversationProjection projectionBeforeStop = viewModel.projection;
      final int notificationsBeforeStop = notifications;
      final Future<void> stop = viewModel.stop();
      viewModel.dispose();
      saveGate.complete();
      await stop;
      await Future<void>.delayed(Duration.zero);

      expect(notifications, notificationsBeforeStop);
      expect(viewModel.projection, same(projectionBeforeStop));
      expect(harness.inference.requests, isEmpty);

      final ConversationViewModel recovered = harness.createViewModel();
      await recovered.submit('Recovered');
      await Future<void>.delayed(Duration.zero);
      expect(harness.inference.requests, hasLength(1));

      recovered.dispose();
      await harness.dispose();
    },
  );
}

Future<void> _startGeneration(
  _Harness harness,
  ConversationViewModel viewModel,
) async {
  await viewModel.submit('Hello');
  await harness.inference.requestReceived;
  harness.inference.emit(
    GenerationStarted(
      const Generation(
        id: GenerationId('generation-1'),
        request: GenerationRequest(
          conversationId: ConversationId('conversation-1'),
          prompt: 'Hello',
        ),
      ),
    ),
  );
  harness.inference.emit(
    const GenerationDelta(
      generationId: GenerationId('generation-1'),
      delta: 'Partial',
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

final class _Harness {
  final RecordingConversationStorageService storage =
      RecordingConversationStorageService();
  final ControlledInferenceService inference = ControlledInferenceService();
  late final ConversationRepository repository = ConversationRepository(
    storageService: storage,
    inferenceService: inference,
  );

  ConversationViewModel createViewModel() => ConversationViewModel(
    repository: repository,
    idFactory: () => const ConversationId('conversation-1'),
    batchScheduler: MicrotaskBatchScheduler(),
  );

  Future<void> dispose() => inference.dispose();
}
