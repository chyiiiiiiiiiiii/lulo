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

  test('talking during the speak round trip still silences it', () async {
    // SpeakingStarted takes a whole pigeon round trip to come back; the
    // user can start talking inside that window, and the answer must still
    // give way.
    voice.holdSpeakingStarted = true;
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    await answerCompletely('Once upon a time, at great length.');
    expect(voice.spoken, hasLength(1));

    voice.hear(const PartialTranscript('actually'));
    await pump();

    expect(
      voice.calls,
      contains('stopSpeaking'),
      reason:
          'A partial inside the SpeakingStarted round trip left the agent '
          'talking over the user.',
    );
  });

  test('being disposed closes the microphone', () async {
    // The view that owns the controller is torn down on every conversation
    // switch; a dispose that only drops the subscription leaves the
    // microphone open with nobody listening.
    final FakeVoiceService ownVoice = FakeVoiceService();
    final VoiceConversationController owned = VoiceConversationController(
      voice: ownVoice,
      conversation: vm,
    );
    await owned.enable();

    owned.dispose();
    await pump();

    expect(ownVoice.calls, contains('stopListening'));
    expect(ownVoice.calls, contains('stopSpeaking'));
    await ownVoice.dispose();
  });

  test('a failure turns voice mode off, visibly', () async {
    await controller.enable();
    expect(controller.enabled, isTrue);

    voice.hear(const VoiceFailed('the microphone went away'));
    await pump();

    expect(
      controller.enabled,
      isFalse,
      reason: 'A dead pipeline left the button lit as listening.',
    );
    expect(controller.failure, 'the microphone went away');
  });

  test('a replacement question is not swallowed by the interruption', () async {
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    final Generation generation = await generationStarted();

    // The user talks over the streaming answer and asks something new
    // before the cancellation has fully wound down.
    voice.hear(const PartialTranscript('actually'));
    voice.hear(const FinalTranscript('actually, what time is it?'));
    for (int i = 0; i < 8; i++) {
      await pump();
    }

    expect(inference.cancellations, contains(generation.id));
    expect(
      inference.requests.map((GenerationRequest r) => r.prompt),
      contains('actually, what time is it?'),
      reason: 'The question that replaced the answer was dropped.',
    );
  });

  test('enabling voice mid-restore does not recite the history', () async {
    final InMemoryConversationStorageService store =
        InMemoryConversationStorageService();
    await store.saveUserTurn(
      const ConversationId('yesterday'),
      const Turn(
        role: TurnRole.user,
        text: 'What did we say yesterday?',
        status: TurnStatus.completed,
      ),
    );
    await store.saveTerminalAssistantTurn(
      const Turn(
        role: TurnRole.assistant,
        text: 'A great many things.',
        status: TurnStatus.completed,
      ),
      const Generation(
        id: GenerationId('generation-0'),
        request: GenerationRequest(
          conversationId: ConversationId('yesterday'),
          prompt: 'What did we say yesterday?',
        ),
      ),
    );
    final ConversationViewModel restoring = ConversationViewModel(
      repository: ConversationRepository(
        storageService: store,
        inferenceService: ControlledInferenceService(),
      ),
      idFactory: () => const ConversationId('freshly-minted'),
      batchScheduler: MicrotaskBatchScheduler(),
    );
    addTearDown(restoring.dispose);
    final FakeVoiceService earlyVoice = FakeVoiceService();
    final VoiceConversationController early = VoiceConversationController(
      voice: earlyVoice,
      conversation: restoring,
    );
    addTearDown(early.dispose);

    // Enabled before the restore has landed.
    await early.enable();
    await restoring.restored;
    await pump();

    expect(
      earlyVoice.spoken,
      isEmpty,
      reason: 'Voice mode recited yesterday aloud.',
    );
    await earlyVoice.dispose();
  });

  test('nothing heard while disabled goes anywhere', () async {
    voice.hear(const FinalTranscript('to someone else entirely'));
    await pump();

    expect(inference.requests, isEmpty);
  });
}
