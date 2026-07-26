import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';

import '../../support/controlled_inference_service.dart';
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

  ConversationViewModel createViewModel() => ConversationViewModel(
    repository: ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    ),
    idFactory: () => const ConversationId('conversation-1'),
  );

  Future<void> dispose() => inference.dispose();
}
