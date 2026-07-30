import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/features/conversation/token_batcher.dart';

import '../../support/controlled_inference_service.dart';

/// Hands scheduled flushes to the test instead of a clock.
final class _HandScheduler implements BatchScheduler {
  final List<void Function()> scheduled = <void Function()>[];

  @override
  CancelBatch schedule(Duration delay, void Function() callback) {
    scheduled.add(callback);
    return const _KeptBatch();
  }

  /// Runs the one scheduled flush, as the frame would.
  void runFrame() {
    final void Function() flush = scheduled.removeAt(0);
    flush();
  }
}

final class _KeptBatch implements CancelBatch {
  const _KeptBatch();

  @override
  void cancel() {}
}

void main() {
  const Generation generation = Generation(
    id: GenerationId('generation-1'),
    request: GenerationRequest(
      conversationId: ConversationId('freshly-minted'),
      prompt: 'Say something long.',
    ),
  );

  Future<(ConversationViewModel, ControlledInferenceService, _HandScheduler)>
  startedViewModel() async {
    final ControlledInferenceService inference = ControlledInferenceService();
    final _HandScheduler scheduler = _HandScheduler();
    final ConversationViewModel vm = ConversationViewModel(
      repository: ConversationRepository(
        storageService: InMemoryConversationStorageService(),
        inferenceService: inference,
      ),
      idFactory: () => const ConversationId('freshly-minted'),
      startFresh: true,
      batchScheduler: scheduler,
    );
    await vm.submit('Say something long.');
    await inference.requestReceived;
    inference.emit(GenerationStarted(generation));
    await Future<void>.delayed(Duration.zero);
    return (vm, inference, scheduler);
  }

  test('deltas inside one frame reach the view as one update', () async {
    final (
      ConversationViewModel vm,
      ControlledInferenceService inference,
      _HandScheduler scheduler,
    ) = await startedViewModel();
    addTearDown(vm.dispose);
    int activeTurnUpdates = 0;
    vm.activeTurnListenable.addListener(() => activeTurnUpdates += 1);

    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'A',
      ),
    );
    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'B',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      vm.activeTurnListenable.value?.text,
      isEmpty,
      reason: 'A delta reached the view before its frame.',
    );
    expect(activeTurnUpdates, 0);

    scheduler.runFrame();
    expect(vm.activeTurnListenable.value?.text, 'AB');
    expect(
      activeTurnUpdates,
      1,
      reason: 'One frame of deltas must be one view update.',
    );
  });

  test('a terminal flushes what its frame still owes', () async {
    final (
      ConversationViewModel vm,
      ControlledInferenceService inference,
      _HandScheduler _,
    ) = await startedViewModel();
    addTearDown(vm.dispose);

    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'The whole answer.',
      ),
    );
    // The completion arrives before the frame does.
    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    await Future<void>.delayed(Duration.zero);

    expect(
      vm.completedTurnsListenable.value.last.text,
      'The whole answer.',
      reason: 'The terminal raced its own last tokens.',
    );
    expect(vm.completedTurnsListenable.value.last.status, TurnStatus.completed);
  });
}
