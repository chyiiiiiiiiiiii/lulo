import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/features/voice/voice_conversation_controller.dart';
import 'package:local_agent_macos/features/voice/voice_service.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/fake_voice_service.dart';
import '../../support/microtask_batch_scheduler.dart';

void main() {
  late FakeVoiceService voice;
  late ControlledInferenceService inference;
  late ConversationViewModel vm;
  late VoiceConversationController controller;

  setUp(() {
    voice = FakeVoiceService();
    inference = ControlledInferenceService();
    vm = ConversationViewModel(
      repository: ConversationRepository(
        storageService: InMemoryConversationStorageService(),
        inferenceService: inference,
      ),
      idFactory: () => const ConversationId('freshly-minted'),
      startFresh: true,
      batchScheduler: MicrotaskBatchScheduler(),
    );
    controller = VoiceConversationController(voice: voice, conversation: vm);
  });

  tearDown(() async {
    controller.dispose();
    vm.dispose();
    await voice.dispose();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  /// Starts the generation the way the runtime would: for the request that
  /// was actually made.
  Future<Generation> generationStarted() async {
    final GenerationRequest request = await inference.requestReceived;
    final Generation generation = Generation(
      id: const GenerationId('generation-1'),
      request: request,
    );
    inference.emit(GenerationStarted(generation));
    await pump();
    return generation;
  }

  Future<void> answerCompletely(String text) async {
    final Generation generation = await generationStarted();
    inference.emit(GenerationDelta(generationId: generation.id, delta: text));
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
  }

  test('enabling opens the ears; disabling releases them', () async {
    await controller.enable();
    expect(voice.calls, contains('startListening'));
    expect(controller.enabled, isTrue);

    await controller.disable();
    expect(voice.calls, contains('stopListening'));
    expect(controller.enabled, isFalse);
  });

  test('a finished utterance becomes the next message', () async {
    await controller.enable();

    voice.hear(const FinalTranscript('What is the weather like?'));
    await pump();

    final GenerationRequest sent = await inference.requestReceived;
    expect(sent.prompt, 'What is the weather like?');
  });

  test('a completed answer is spoken aloud', () async {
    await controller.enable();

    voice.hear(const FinalTranscript('What is the weather like?'));
    await pump();
    await answerCompletely('Sunny, all day.');

    expect(voice.spoken, <String>['Sunny, all day.']);
  });

  test('history restored before voice mode is never read aloud', () async {
    // Enabling voice over yesterday's conversation must not recite it.
    await controller.enable();
    await pump();

    expect(voice.spoken, isEmpty);
  });

  test('the user talking over the answer silences it', () async {
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    await answerCompletely('Once upon a time, at great length.');
    expect(voice.spoken, hasLength(1));

    // The synthesizer is mid-sentence when the user starts talking again.
    voice.hear(const PartialTranscript('actually'));
    await pump();

    expect(
      voice.calls,
      contains('stopSpeaking'),
      reason: 'A friend stops talking when you start.',
    );
  });

  test('the user talking over a streaming answer cancels it', () async {
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    final Generation generation = await generationStarted();

    // Still generating — nothing spoken yet — and the user interrupts.
    voice.hear(const PartialTranscript('wait'));
    await pump();

    expect(
      inference.cancellations,
      contains(generation.id),
      reason: 'Talking over a streaming answer must cancel it.',
    );
  });

  test('what is being heard is visible while it is being said', () async {
    await controller.enable();

    voice.hear(const PartialTranscript('what is'));
    await pump();
    expect(controller.partialTranscript, 'what is');

    voice.hear(const FinalTranscript('what is the weather like'));
    await pump();
    expect(
      controller.partialTranscript,
      isEmpty,
      reason: 'A settled utterance is no longer being heard.',
    );
  });

  test('nothing heard while disabled goes anywhere', () async {
    voice.hear(const FinalTranscript('to someone else entirely'));
    await pump();

    expect(inference.requests, isEmpty);
  });
}
