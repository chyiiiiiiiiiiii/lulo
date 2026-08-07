import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/microtask_batch_scheduler.dart';
import '../../support/recording_conversation_storage_service.dart';

/// Asking again, and asking something else.
///
/// A model running on this machine gets an answer wrong often enough that
/// reading it was never going to be the only thing anyone wanted to do with
/// one. Both paths replace what is on screen, so both have to take it out of
/// the store as well — an answer the user rejected coming back at the next
/// launch is a conversation they never had.
void main() {
  const ConversationId conversation = ConversationId('conversation-1');

  /// Lets every queued repository step run. Generations are started behind
  /// the one before them, so a retry's request is not in flight the moment
  /// the call returns.
  Future<void> settle() async {
    for (int i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Generation generation(String id, String prompt) => Generation(
    id: GenerationId(id),
    request: GenerationRequest(conversationId: conversation, prompt: prompt),
  );

  /// Runs one generation to completion, from a question already submitted.
  Future<void> answer(_Harness harness, String id, String prompt, String text) {
    harness.inference.emit(GenerationStarted(generation(id, prompt)));
    harness.inference.emit(
      GenerationDelta(generationId: GenerationId(id), delta: text),
    );
    harness.inference.emit(GenerationCompleted(GenerationId(id)));
    return settle();
  }

  /// Puts one finished exchange on the screen and in the store.
  Future<ConversationViewModel> exchange(_Harness harness) async {
    final ConversationViewModel viewModel = harness.createViewModel();
    await viewModel.submit('明天天氣如何');
    await harness.inference.requestReceived;
    await answer(harness, 'generation-1', '明天天氣如何', '會下雨');
    return viewModel;
  }

  test('asking again replaces the answer rather than adding one', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = await exchange(harness);
    expect(viewModel.projection.completedTurns, hasLength(2));

    await viewModel.regenerateLastAnswer();
    await settle();

    // The question is back, alone, waiting for its second answer.
    expect(
      viewModel.projection.completedTurns.map((Turn t) => t.text).toList(),
      <String>['明天天氣如何'],
    );
    // And the same question was put to the model, not a new one.
    expect(harness.inference.requests.last.prompt, '明天天氣如何');
    // The history it is given no longer contains the answer being replaced.
    expect(harness.inference.requests.last.history, isEmpty);

    viewModel.dispose();
    await harness.dispose();
  });

  test('asking again takes the old exchange out of the store', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = await exchange(harness);

    await viewModel.regenerateLastAnswer();
    await settle();

    expect(harness.storage.droppedFromLastQuestion, <ConversationId>[
      conversation,
    ]);
    expect(
      harness.inference.releasedSessions,
      <ConversationId>[conversation],
      reason:
          'the runtime still held the rejected answer in its own KV cache, '
          'so the retry would have been conditioned on it',
    );

    viewModel.dispose();
    await harness.dispose();
  });

  test('a rewritten question replaces the one that was asked', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = await exchange(harness);

    await viewModel.reviseLastQuestion('  後天天氣如何  ');
    await settle();

    expect(
      viewModel.projection.completedTurns.map((Turn t) => t.text).toList(),
      <String>['後天天氣如何'],
    );
    expect(harness.inference.requests.last.prompt, '後天天氣如何');
    expect(harness.storage.droppedFromLastQuestion, <ConversationId>[
      conversation,
    ]);

    viewModel.dispose();
    await harness.dispose();
  });

  test('there is nothing to ask again before anything was said', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();

    await viewModel.regenerateLastAnswer();
    await viewModel.reviseLastQuestion('anything');
    await settle();

    expect(harness.inference.requests, isEmpty);
    expect(harness.storage.droppedFromLastQuestion, isEmpty);

    viewModel.dispose();
    await harness.dispose();
  });

  test('a blank rewrite leaves the conversation as it was', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = await exchange(harness);

    await viewModel.reviseLastQuestion('   ');
    await settle();

    expect(viewModel.projection.completedTurns, hasLength(2));
    expect(
      harness.storage.droppedFromLastQuestion,
      isEmpty,
      reason: 'an empty rewrite deleted the exchange and asked nothing',
    );

    viewModel.dispose();
    await harness.dispose();
  });

  test('an answer being written cannot be asked for again', () async {
    final _Harness harness = _Harness();
    final ConversationViewModel viewModel = harness.createViewModel();
    await viewModel.submit('明天天氣如何');
    await harness.inference.requestReceived;
    harness.inference.emit(
      GenerationStarted(generation('generation-1', '明天天氣如何')),
    );
    await Future<void>.delayed(Duration.zero);

    await viewModel.regenerateLastAnswer();
    await settle();

    expect(harness.inference.requests, hasLength(1));
    expect(
      harness.storage.droppedFromLastQuestion,
      isEmpty,
      reason: 'the exchange was cut out from under a generation still running',
    );

    viewModel.dispose();
    await harness.dispose();
  });
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
