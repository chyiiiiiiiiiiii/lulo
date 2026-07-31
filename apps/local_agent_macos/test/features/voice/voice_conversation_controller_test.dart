import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';
import 'package:local_agent_macos/features/conversation/token_batcher.dart';
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
    // The shared controller's clock steps 600ms per reading, so events
    // that land in the same microtask still sit past the post-final
    // cooldown, the way real interruptions do. The cooldown itself is
    // tested with a pinned clock of its own.
    DateTime testClock = DateTime(2026);
    controller = VoiceConversationController(
      voice: voice,
      conversation: vm,
      now: () {
        testClock = testClock.add(const Duration(milliseconds: 600));
        return testClock;
      },
    );
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

  test('a breath right after the final does not cancel the answer', () async {
    // The fast endpointer submits 0.8s after the last sound, which puts
    // live microphone time right where the user's trailing breath lands.
    // A partial inside the post-final cooldown must not cancel the answer
    // the user just asked for; one after it is a real interruption.
    DateTime now = DateTime(2026, 7, 31, 1);
    final VoiceConversationController timed = VoiceConversationController(
      voice: voice,
      conversation: vm,
      now: () => now,
    );
    addTearDown(timed.dispose);
    await timed.enable();
    voice.hear(const FinalTranscript('介紹台北。'));
    await pump();
    final Generation generation = await generationStarted();

    now = now.add(const Duration(milliseconds: 200));
    voice.hear(const PartialTranscript('嗯'));
    await pump();
    expect(
      inference.cancellations,
      isEmpty,
      reason: 'A breath inside the cooldown is not an interruption.',
    );

    now = now.add(const Duration(milliseconds: 400));
    voice.hear(const PartialTranscript('等等'));
    await pump();
    expect(
      inference.cancellations,
      contains(generation.id),
      reason: 'Past the cooldown, talking over the answer still cancels.',
    );
  });

  test('a correction spoken wholly inside the cooldown still lands', () async {
    // Every volatile of "不對" fits in the 500ms window, so none of them
    // yields — but its final must still interrupt the answer instead of
    // letting it play out and then answering "不對" as a fresh question.
    DateTime now = DateTime(2026, 7, 31, 2);
    final VoiceConversationController timed = VoiceConversationController(
      voice: voice,
      conversation: vm,
      now: () => now,
    );
    addTearDown(timed.dispose);
    await timed.enable();
    voice.hear(const FinalTranscript('介紹台北。'));
    await pump();
    final Generation generation = await generationStarted();

    now = now.add(const Duration(milliseconds: 300));
    voice.hear(const PartialTranscript('不對'));
    await pump();
    expect(inference.cancellations, isEmpty);

    now = now.add(const Duration(milliseconds: 100));
    voice.hear(const FinalTranscript('不對'));
    await pump();
    expect(
      inference.cancellations,
      contains(generation.id),
      reason: 'The correction must interrupt at its final at the latest.',
    );
  });

  test('a short word while the agent speaks is not an interruption', () async {
    // "OK" and "嗯嗯" are how people show they are still listening. Taking
    // them as a request to stop ended a minute of speech that was 571
    // characters in, and the user got silence for saying the one thing that
    // means "carry on". While nothing is being said, one character is still
    // enough — there is nothing to take away.
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    final Generation generation = await generationStarted();
    // Still streaming, and far enough in that the voice has started: this is
    // the state a real acknowledgement lands in.
    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: 'Once upon a time, at very great length indeed. ',
      ),
    );
    await pump();
    await pump();
    expect(voice.spoken, isNotEmpty);

    voice.hear(const PartialTranscript('OK'));
    await pump();
    voice.hear(const FinalTranscript('OK。'));
    await pump();

    expect(
      inference.cancellations,
      isNot(contains(generation.id)),
      reason: 'Acknowledging is not interrupting.',
    );
    expect(voice.calls, isNot(contains('stopSpeaking')));
  });

  test('enough words while the agent speaks is an interruption', () async {
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    final Generation generation = await generationStarted();
    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: 'Once upon a time, at very great length indeed. ',
      ),
    );
    await pump();
    await pump();
    expect(voice.spoken, isNotEmpty);

    voice.hear(const PartialTranscript('你可以解釋'));
    await pump();

    expect(
      inference.cancellations,
      contains(generation.id),
      reason: 'Past the threshold the user still has the floor on demand.',
    );
  });

  test('an interruption that asks nothing resumes the answer', () async {
    // 53 interruptions in one real session stopped the speech; 5 of them
    // replaced the question. The other 48 left the answer written on screen
    // and permanently unsaid, because the dispatch counter records what was
    // handed to the voice rather than what was heard. Saying "嗯" should not
    // cost the rest of the answer.
    // Its own scheduler: the shared controller runs the resume on a real
    // two-second timer, which no amount of pumping will reach.
    DateTime resumeClock = DateTime(2026, 8);
    final VoiceConversationController resuming = VoiceConversationController(
      voice: voice,
      conversation: vm,
      utteranceScheduler: MicrotaskBatchScheduler(),
      // Same 600ms step as the shared controller, so events in one microtask
      // still land past the post-final cooldown.
      now: () {
        resumeClock = resumeClock.add(const Duration(milliseconds: 600));
        return resumeClock;
      },
    );
    addTearDown(resuming.dispose);
    // The shared controller stays constructed but never enabled, so every
    // event below reaches only this one.
    await resuming.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    // The answer has finished generating and is being read aloud — the state
    // most of those 53 interruptions actually landed in.
    await answerCompletely('Once upon a time, at very great length indeed.');
    final int spokenBefore = voice.spoken.length;
    expect(spokenBefore, greaterThan(0));
    expect(vm.canSubmit, isTrue);
    final String cutOff = voice.spoken.last;

    // Long enough to take the floor, but it never settles into a question.
    voice.hear(const PartialTranscript('等一下我'));
    await pump();
    expect(voice.calls, contains('stopSpeaking'));

    // Nothing was asked, so the answer picks up where it was cut off.
    await pump();
    await pump();
    await pump();
    expect(
      voice.spoken.length,
      greaterThan(spokenBefore),
      reason: 'The interrupted sentence must be said again.',
    );
    expect(voice.spoken.last, cutOff);
  });

  test('a noise that settles into nothing resumes at once', () async {
    // The two-second backstop is the wrong latency for the common case. A
    // cough or a misheard syllable produces a final with no words in it, and
    // at that instant it is already known that nothing replaced the answer —
    // so it picks up immediately rather than leaving a two-second hole.
    DateTime clock = DateTime(2026, 8);
    final VoiceConversationController resuming = VoiceConversationController(
      voice: voice,
      conversation: vm,
      // A scheduler that never fires: only the immediate path can pass this.
      utteranceScheduler: const _NeverScheduler(),
      now: () {
        clock = clock.add(const Duration(milliseconds: 600));
        return clock;
      },
    );
    addTearDown(resuming.dispose);
    await resuming.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    await answerCompletely('Once upon a time, at very great length indeed.');
    final int spokenBefore = voice.spoken.length;
    final String cutOff = voice.spoken.last;

    voice.hear(const PartialTranscript('等一下我'));
    await pump();
    expect(voice.calls, contains('stopSpeaking'));

    // The utterance settles into nothing at all.
    voice.hear(const FinalTranscript('   '));
    await pump();
    await pump();

    expect(voice.spoken.length, greaterThan(spokenBefore));
    expect(voice.spoken.last, cutOff);
  });

  test('a real question beats the resume it interrupted', () async {
    // The resume must never talk over the answer to the question that
    // caused it. If what the user said becomes a question, the interrupted
    // sentence is dropped, not queued behind it.
    DateTime clock = DateTime(2026, 8);
    final VoiceConversationController resuming = VoiceConversationController(
      voice: voice,
      conversation: vm,
      // The backstop never fires, so this isolates the settle path: the
      // question itself must be what drops the interrupted sentence.
      utteranceScheduler: const _NeverScheduler(),
      now: () {
        clock = clock.add(const Duration(milliseconds: 600));
        return clock;
      },
    );
    addTearDown(resuming.dispose);
    await resuming.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    await answerCompletely('Once upon a time, at very great length indeed.');
    final int spokenBefore = voice.spoken.length;

    voice.hear(const PartialTranscript('等一下我想問'));
    await pump();
    expect(voice.calls, contains('stopSpeaking'));

    // It settles into an actual question.
    voice.hear(const FinalTranscript('等一下我想問別的'));
    await pump();
    await pump();
    await pump();

    expect(
      inference.requests.map((GenerationRequest r) => r.prompt),
      contains('等一下我想問別的'),
    );
    expect(
      voice.spoken.length,
      spokenBefore,
      reason: 'The abandoned sentence must not be read over the new answer.',
    );
  });

  test('a resume that already started is silenced by the question', () async {
    // The race the backstop makes possible: it puts the sentence back, and
    // only then does the user's utterance settle into a question. The
    // resumed sentence would otherwise be read over the answer to it.
    DateTime clock = DateTime(2026, 8);
    final VoiceConversationController resuming = VoiceConversationController(
      voice: voice,
      conversation: vm,
      // Fires at once, so the resume always wins the race with the final.
      utteranceScheduler: MicrotaskBatchScheduler(),
      now: () {
        clock = clock.add(const Duration(milliseconds: 600));
        return clock;
      },
    );
    addTearDown(resuming.dispose);
    await resuming.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    await answerCompletely('Once upon a time, at very great length indeed.');
    final int spokenBefore = voice.spoken.length;

    voice.hear(const PartialTranscript('等一下我想問'));
    await pump();
    expect(
      voice.spoken.length,
      greaterThan(spokenBefore),
      reason: 'This test is only meaningful if the resume actually ran.',
    );

    voice.hear(const FinalTranscript('等一下我想問別的'));
    await pump();
    await pump();

    expect(
      voice.calls.lastIndexOf('stopSpeaking'),
      greaterThan(voice.calls.lastIndexOf('speak')),
      reason: 'The question must silence the sentence it replaced.',
    );
  });

  test('full-width and halfwidth ideographic stops end a sentence', () async {
    // The sentence-end set had 。 but not ．(U+FF0E) or ｡(U+FF61), both of
    // which appear in Chinese text from real keyboards and in text converted
    // from Japanese sources. A sentence ending in one of them was never
    // recognised as finished, so the chunk waited for punctuation that had
    // already been there. Pipecat treats all of these as unambiguous
    // sentence ends precisely because no Latin disambiguation applies.
    await controller.enable();
    voice.hear(const FinalTranscript('說一段話'));
    await pump();
    final Generation generation = await generationStarted();
    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: '這是第一句話講得夠長足以成為一個完整的段落而且沒有任何逗號．',
      ),
    );
    await pump();
    await pump();

    expect(
      voice.spoken,
      isNotEmpty,
      reason: 'A full-width period ends a sentence.',
    );
  });

  test('resuming starts from the earliest sentence still unheard', () async {
    // Chunks are dispatched as the answer streams and queued back to back by
    // the native side, so the most recently dispatched sentence is normally
    // NOT the one being heard — the next one is already handed over while the
    // current one plays. Resuming "the last thing dispatched" therefore skips
    // whatever was actually cut off and says something the user never heard a
    // word of. Over-repeating is recoverable; skipping is not.
    DateTime clock = DateTime(2026, 8);
    final VoiceConversationController resuming = VoiceConversationController(
      voice: voice,
      conversation: vm,
      utteranceScheduler: MicrotaskBatchScheduler(),
      now: () {
        clock = clock.add(const Duration(milliseconds: 600));
        return clock;
      },
    );
    addTearDown(resuming.dispose);
    await resuming.enable();
    voice.hear(const FinalTranscript('說個長故事。'));
    await pump();
    final Generation generation = await generationStarted();

    // Two sentences dispatched, neither confirmed finished.
    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: '第一句話講得夠長足以成為完整的一個段落。',
      ),
    );
    await pump();
    await pump();
    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: '第二句話同樣講得夠長足以成為完整的一個段落，而且它的字數確實已經超過四十個字元的門檻了。',
      ),
    );
    await pump();
    await pump();
    // Generation is done; both sentences are still queued for playback.
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
    expect(voice.spoken.length, 2, reason: 'Two chunks must be in flight.');
    expect(vm.canSubmit, isTrue);
    final String firstOutstanding = voice.spoken[0];

    voice.hear(const PartialTranscript('等一下我'));
    await pump();
    voice.hear(const FinalTranscript('   '));
    await pump();
    await pump();

    expect(
      voice.spoken.last,
      startsWith(firstOutstanding),
      reason: 'Resume must not skip the sentence that was actually cut off.',
    );
  });

  test('an answer that was cancelled does not come back to life', () async {
    // The interruption cancelled the generation, so the answer is over. If
    // the user's words then never settle into a question, the empty final
    // would otherwise put one orphaned chunk of a dead answer back — the
    // agent speaks half a sentence of something it already abandoned. The
    // backstop never fires here, so this is the immediate path alone; with a
    // real timer the cancel completes first and the same hole opens.
    DateTime clock = DateTime(2026, 8);
    final VoiceConversationController resuming = VoiceConversationController(
      voice: voice,
      conversation: vm,
      utteranceScheduler: const _NeverScheduler(),
      now: () {
        clock = clock.add(const Duration(milliseconds: 600));
        return clock;
      },
    );
    addTearDown(resuming.dispose);
    await resuming.enable();
    voice.hear(const FinalTranscript('說個長故事。'));
    await pump();
    final Generation generation = await generationStarted();
    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: '第一句話講得夠長足以成為完整的一個段落。',
      ),
    );
    await pump();
    await pump();
    final int spokenBefore = voice.spoken.length;

    // Interrupt while it is still generating: this cancels the answer.
    voice.hear(const PartialTranscript('等一下我'));
    await pump();
    await pump();
    expect(inference.cancellations, contains(generation.id));

    // The utterance dissolves into nothing, so nothing replaced the answer.
    voice.hear(const FinalTranscript('   '));
    await pump();
    await pump();
    await pump();

    expect(
      voice.spoken.length,
      spokenBefore,
      reason: 'A cancelled answer has nothing left to say.',
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

  test('being disposed while still enabling never opens the ears', () async {
    // Enable waits for the stored history; the view can be torn down while
    // it waits. The resume must notice it is running on a corpse — in
    // release builds notifyListeners on a disposed notifier is silent, and
    // the microphone would open with nobody listening.
    final FakeVoiceService ownVoice = FakeVoiceService();
    final VoiceConversationController owned = VoiceConversationController(
      voice: ownVoice,
      conversation: vm,
    );

    final Future<void> enabling = owned.enable();
    owned.dispose();
    await enabling;
    await pump();

    expect(
      ownVoice.calls,
      isNot(contains('startListening')),
      reason: 'A disposed controller opened the microphone.',
    );
    await ownVoice.dispose();
  });

  test('a failure also silences whatever was being spoken', () async {
    voice.holdSpeakingStarted = true;
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    await answerCompletely('Once upon a time, at great length.');
    expect(voice.spoken, hasLength(1));

    // The audio device changes while the answer is being read: the pipeline
    // dies, and the reading must die with it — the user cannot stop it any
    // other way once the button has gone dark.
    voice.hear(const VoiceFailed('the audio device changed'));
    await pump();

    expect(voice.calls, contains('stopSpeaking'));
    expect(controller.enabled, isFalse);
  });

  test('a failure forgets the utterance that was waiting its turn', () async {
    // The cancel is held open so the replacement question genuinely queues,
    // then the pipeline dies before the queue can drain.
    final _HeldCancelVoiceInference held = _HeldCancelVoiceInference();
    final ConversationViewModel heldVm = ConversationViewModel(
      repository: ConversationRepository(
        storageService: InMemoryConversationStorageService(),
        inferenceService: held,
      ),
      idFactory: () => const ConversationId('freshly-minted'),
      startFresh: true,
      batchScheduler: MicrotaskBatchScheduler(),
    );
    addTearDown(heldVm.dispose);
    final FakeVoiceService heldVoice = FakeVoiceService();
    final VoiceConversationController heldController =
        VoiceConversationController(voice: heldVoice, conversation: heldVm);
    addTearDown(heldController.dispose);
    await heldController.enable();

    heldVoice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    final GenerationRequest request = await held.requestReceived.future;
    held.emit(
      GenerationStarted(
        Generation(id: const GenerationId('generation-1'), request: request),
      ),
    );
    await pump();
    heldVoice.hear(const PartialTranscript('actually'));
    heldVoice.hear(const FinalTranscript('actually, forget it'));
    for (int i = 0; i < 4; i++) {
      await pump();
    }

    heldVoice.hear(const VoiceFailed('the microphone went away'));
    await pump();
    held.releaseCancel();
    for (int i = 0; i < 8; i++) {
      await pump();
    }

    expect(
      held.requests.map((GenerationRequest r) => r.prompt),
      isNot(contains('actually, forget it')),
      reason:
          'A dead pipeline fired a stale utterance once the cancel '
          'wound down.',
    );
  });

  test('what is spoken is the words, not the decoration', () async {
    // The synthesizer reads exactly what it is given: emoji become
    // "smiling face with smiling eyes", markdown becomes noise, and code
    // is unreadable aloud. Speech gets the sentences alone.
    await controller.enable();
    voice.hear(const FinalTranscript('hello'));
    await pump();
    await answerCompletely(
      'Hello! **How** can I `help` you today? 😊\n\n'
      '```dart\nprint("hi");\n```\nSee [docs](https://example.com).',
    );

    expect(voice.spoken, hasLength(1));
    final String spoken = voice.spoken.single;
    expect(spoken, contains('Hello! How can I help you today?'));
    expect(spoken, contains('See docs.'));
    expect(spoken, isNot(contains('😊')));
    expect(spoken, isNot(contains('**')));
    expect(spoken, isNot(contains('`')));
    expect(spoken, isNot(contains('print(')));
    expect(spoken, isNot(contains('https://')));
  });

  test('rules and list bullets are layout, not words', () {
    expect(
      speakableText('第一段。\n\n---\n\n### 💡 建議\n\n- 第一點\n- 第二點\n* 第三點'),
      '第一段。 建議 第一點 第二點 第三點',
    );
  });

  test('speech begins with the first finished sentence', () async {
    // Waiting for the whole answer stacks three delays end to end. A
    // sentence is speakable the moment its full stop arrives.
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me about Taipei.'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(GenerationDelta(generationId: generation.id, delta: '台北是'));
    await pump();
    expect(voice.spoken, isEmpty, reason: 'Half a sentence is not speech.');

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: '台灣的首都。它有豐富'),
    );
    await pump();
    await pump();
    expect(voice.spoken, <String>[
      '台北是台灣的首都。',
    ], reason: 'The first finished sentence must be spoken at once.');

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: '的夜市文化。'),
    );
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
    expect(voice.spoken, <String>['台北是台灣的首都。', '它有豐富的夜市文化。']);
  });

  test('a completed answer with no boundaries is still spoken once', () async {
    await controller.enable();
    voice.hear(const FinalTranscript('hi'));
    await pump();
    await answerCompletely('Sunny, all day.');

    expect(voice.spoken, <String>['Sunny, all day.']);
  });

  test('the first chunk may hand off at a comma', () async {
    // The first sentence of an answer can run long; a finished clause is
    // enough to get the voice started, and the full stop can catch up.
    await controller.enable();
    voice.hear(const FinalTranscript('介紹台北。'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: '台北是台灣的首都，也是'),
    );
    await pump();
    expect(voice.spoken, <String>[
      '台北是台灣的首都，',
    ], reason: 'A finished clause is enough to start the voice.');

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: '最大的城市。'),
    );
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
    expect(voice.spoken, <String>['台北是台灣的首都，', '也是最大的城市。']);
  });

  test('a clause too short to sound like speech waits for more', () async {
    // "好的," alone reads as a stutter; the clause hand-off only fires once
    // there is something substantive to say.
    await controller.enable();
    voice.hear(const FinalTranscript('可以嗎?'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(GenerationDelta(generationId: generation.id, delta: '好的，我'));
    await pump();
    expect(voice.spoken, isEmpty);

    inference.emit(GenerationDelta(generationId: generation.id, delta: '會幫你。'));
    await pump();
    expect(voice.spoken, <String>['好的，我會幫你。']);
    inference.emit(GenerationCompleted(generation.id));
    await pump();
  });

  test('a comma inside a number is not a clause boundary', () async {
    // "1,234" must not be read as "one" and then "two hundred thirty-four".
    await controller.enable();
    voice.hear(const FinalTranscript('How many came?'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: 'There were 1,234 people at the event',
      ),
    );
    await pump();
    expect(voice.spoken, isEmpty);

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: ' yesterday.'),
    );
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
    expect(voice.spoken, <String>[
      'There were 1,234 people at the event yesterday.',
    ]);
  });

  test('a decimal point is not a sentence end', () async {
    // "Pi is about 3.14" must not be read as "Pi is about 3." with the
    // "14" arriving in the next breath.
    await controller.enable();
    voice.hear(const FinalTranscript('What is pi?'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: 'Pi is about 3.14159 rounded down',
      ),
    );
    await pump();
    expect(voice.spoken, isEmpty);

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: ' a little.'),
    );
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
    expect(voice.spoken, <String>[
      'Pi is about 3.14159 rounded down a little.',
    ]);
  });

  test('after the first chunk, commas no longer split the speech', () async {
    // Only the opening clause is worth the extra synthesis seam; later
    // chunks keep accumulating to whole sentences so the voice stays even.
    await controller.enable();
    voice.hear(const FinalTranscript('介紹台北。'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: '台北是台灣的首都。'),
    );
    await pump();
    expect(voice.spoken, <String>['台北是台灣的首都。']);

    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: '你可以逛夜市，參觀故宮，搭捷運，爬象山，喝珍珠奶茶，吃小籠包，體驗這座城市的多元文化',
      ),
    );
    await pump();
    expect(
      voice.spoken,
      hasLength(1),
      reason: 'Later chunks wait for a sentence, however many commas pass.',
    );

    inference.emit(GenerationDelta(generationId: generation.id, delta: '。'));
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
    expect(voice.spoken, hasLength(2));
  });

  test('a voice that has stopped is settled without waiting', () async {
    // The transcriber's own endpointing waits seconds of silence before a
    // final; a partial that has stopped changing for a beat is the user
    // having finished, and the utterance is settled by hand.
    final _HandVoiceScheduler timers = _HandVoiceScheduler();
    final VoiceConversationController timed = VoiceConversationController(
      voice: voice,
      conversation: vm,
      utteranceScheduler: timers,
    );
    addTearDown(timed.dispose);
    await timed.enable();

    voice.hear(const PartialTranscript('明天天氣'));
    await pump();
    expect(timers.scheduled, hasLength(1));

    // Still talking: the newer partial replaces the pending settle.
    voice.hear(const PartialTranscript('明天天氣如何'));
    await pump();
    expect(timers.cancelled, 1);
    expect(timers.scheduled, hasLength(2));

    timers.fireLast();
    expect(voice.calls, contains('finalizeUtterance'));
  });

  test('a final on its own cancels the pending settle', () async {
    final _HandVoiceScheduler timers = _HandVoiceScheduler();
    final VoiceConversationController timed = VoiceConversationController(
      voice: voice,
      conversation: vm,
      utteranceScheduler: timers,
    );
    addTearDown(timed.dispose);
    await timed.enable();

    voice.hear(const PartialTranscript('hello'));
    await pump();
    voice.hear(const FinalTranscript('hello'));
    await pump();

    expect(timers.cancelled, 1);
    timers.fireLast();
    expect(voice.calls, isNot(contains('finalizeUtterance')));
  });

  test('listening is what the host reports, not what was asked', () async {
    // startListening does not return until the first-run asset download
    // finishes — minutes — and the indicator must not claim an open
    // microphone for that whole wait.
    final _NeverStartsVoice slow = _NeverStartsVoice();
    final VoiceConversationController waiting = VoiceConversationController(
      voice: slow,
      conversation: vm,
    );
    addTearDown(waiting.dispose);

    unawaited(waiting.enable());
    await pump();
    expect(waiting.listening, isFalse);

    slow.events_.add(const ListeningStarted());
    await pump();
    expect(waiting.listening, isTrue);

    slow.events_.add(const ListeningStopped());
    await pump();
    expect(waiting.listening, isFalse);
  });

  test('a settle that produced no final tries again', () async {
    final _HandVoiceScheduler timers = _HandVoiceScheduler();
    final VoiceConversationController timed = VoiceConversationController(
      voice: voice,
      conversation: vm,
      utteranceScheduler: timers,
    );
    addTearDown(timed.dispose);
    await timed.enable();

    voice.hear(const PartialTranscript('明天天氣'));
    await pump();
    timers.fireLast();
    expect(voice.calls, contains('finalizeUtterance'));

    // No final ever arrives; the settle must be re-armed rather than the
    // utterance hanging on screen forever.
    expect(
      timers.scheduled.length,
      2,
      reason: 'A finalize that yields nothing leaves no retry armed.',
    );
  });

  test('pressing stop silences what is already being spoken', () async {
    // Stop cancels the generation, but the sentences already handed to the
    // voice keep playing: the button stops the writing and not the talking,
    // and the only way out is switching the microphone off.
    await controller.enable();
    voice.hear(const FinalTranscript('講一個長故事。'));
    await pump();
    final Generation generation = await generationStarted();
    inference.emit(
      GenerationDelta(generationId: generation.id, delta: '很久很久以前。'),
    );
    await pump();
    expect(voice.spoken, isNotEmpty, reason: 'nothing was being spoken');

    await vm.stop();
    for (int i = 0; i < 8; i++) {
      await pump();
    }

    expect(voice.calls, contains('stopSpeaking'));
  });

  test('a barge-in silences the sentence still in the batcher', () async {
    // Cancelling flushes the token batcher; if the flushed tail completes a
    // sentence, it must not be dispatched to the voice — the interruption
    // exists to stop exactly that.
    final _HeldCancelVoiceInference held = _HeldCancelVoiceInference();
    final _HandVoiceScheduler heldBatch = _HandVoiceScheduler();
    final ConversationViewModel heldVm = ConversationViewModel(
      repository: ConversationRepository(
        storageService: InMemoryConversationStorageService(),
        inferenceService: held,
      ),
      idFactory: () => const ConversationId('freshly-minted'),
      startFresh: true,
      batchScheduler: heldBatch,
    );
    addTearDown(heldVm.dispose);
    final FakeVoiceService heldVoice = FakeVoiceService();
    final VoiceConversationController heldController =
        VoiceConversationController(voice: heldVoice, conversation: heldVm);
    addTearDown(heldController.dispose);
    await heldController.enable();

    heldVoice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    final GenerationRequest request = await held.requestReceived.future;
    final Generation generation = Generation(
      id: const GenerationId('generation-1'),
      request: request,
    );
    held.emit(GenerationStarted(generation));
    await pump();

    // A finished sentence sits in the token batcher, its frame not fired.
    held.emit(GenerationDelta(generationId: generation.id, delta: '很久很久以前。'));
    await pump();
    expect(heldVoice.spoken, isEmpty);

    // The user talks over it; the cancel hangs, then lands, and the
    // terminal flushes the batcher.
    heldVoice.hear(const PartialTranscript('等等'));
    await pump();
    held.releaseCancel();
    for (int i = 0; i < 8; i++) {
      await pump();
    }

    expect(
      heldVoice.spoken,
      isEmpty,
      reason: 'The agent got one more sentence in after the interruption.',
    );
  });

  test('the settle gives up after three tries and clears the screen', () async {
    final _HandVoiceScheduler timers = _HandVoiceScheduler();
    final VoiceConversationController timed = VoiceConversationController(
      voice: voice,
      conversation: vm,
      utteranceScheduler: timers,
    );
    addTearDown(timed.dispose);
    await timed.enable();

    voice.hear(const PartialTranscript('明天天氣'));
    await pump();
    timers.fireLast();
    timers.fireLast();
    timers.fireLast();

    expect(voice.calls.where((String c) => c == 'finalizeUtterance').length, 3);
    expect(
      timers.scheduled.length,
      3,
      reason: 'The settle re-armed past its bound.',
    );
    expect(
      timed.partialTranscript,
      isEmpty,
      reason: 'A transcript that will never settle stayed on screen.',
    );
  });

  test('streaming speech survives a barge-in during prefill', () async {
    // A cancel before the first token nulls an already-null active turn;
    // ValueNotifier suppresses null-to-null, and a dispatch flag stuck true
    // would mute the whole next answer into one end-block.
    await controller.enable();
    voice.hear(const FinalTranscript('Tell me a long story.'));
    await pump();
    await inference.requestReceived;
    // Barge in before GenerationStarted ever arrives.
    voice.hear(const PartialTranscript('等等'));
    for (int i = 0; i < 6; i++) {
      await pump();
    }

    // The replacement question begins a fresh generation.
    voice.hear(const FinalTranscript('那說個短的。'));
    for (int i = 0; i < 6; i++) {
      await pump();
    }
    final GenerationRequest second = inference.requests.last;
    expect(second.prompt, '那說個短的。');
    final Generation nextGeneration = Generation(
      id: const GenerationId('generation-2'),
      request: second,
    );
    inference.emit(GenerationStarted(nextGeneration));
    await pump();
    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-2'),
        delta: '從前有座山。',
      ),
    );

    for (int i = 0; i < 4; i++) {
      await pump();
    }

    expect(
      voice.spoken,
      contains('從前有座山。'),
      reason: 'The next answer was muted into an end-block by a stuck flag.',
    );
  });

  test('one answer speaks one language and in steadier pieces', () async {
    // Per-sentence language detection let a lone English word flip the
    // accent mid-answer, and single short sentences drifted in timbre.
    // The first sentence still goes out alone for latency; afterwards
    // sentences accumulate into steadier chunks, and every chunk of one
    // answer carries the language decided by its beginning.
    await controller.enable();
    voice.hear(const FinalTranscript('介紹一下 Flutter。'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(GenerationDelta(generationId: generation.id, delta: '好的。'));
    await pump();
    await pump();
    expect(voice.spoken, <String>['好的。']);
    expect(voice.spokenLanguages, <String?>['zh']);

    // Two short sentences follow; neither alone reaches the chunk size, so
    // they travel together — and "Flutter." alone must not flip to English.
    inference.emit(
      GenerationDelta(generationId: generation.id, delta: 'Flutter。'),
    );
    await pump();
    await pump();
    expect(voice.spoken, hasLength(1), reason: 'A short tail went out alone.');

    inference.emit(
      GenerationDelta(
        generationId: generation.id,
        delta: '是一套跨平台的開發框架，用一份程式碼同時建構多個平台的應用。',
      ),
    );
    await pump();
    await pump();
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();

    expect(voice.spoken, hasLength(2));
    expect(voice.spoken[1], 'Flutter。是一套跨平台的開發框架，用一份程式碼同時建構多個平台的應用。');
    expect(
      voice.spokenLanguages.toSet(),
      <String?>{'zh'},
      reason: 'One answer flipped language mid-thought.',
    );
  });

  test('nothing heard while disabled goes anywhere', () async {
    voice.hear(const FinalTranscript('to someone else entirely'));
    await pump();

    expect(inference.requests, isEmpty);
  });
}

/// Records requests and holds native cancellation open until released.
final class _HeldCancelVoiceInference implements InferenceService {
  final StreamController<GenerationEvent> _events =
      StreamController<GenerationEvent>.broadcast();
  final List<GenerationRequest> requests = <GenerationRequest>[];
  final Completer<GenerationRequest> requestReceived =
      Completer<GenerationRequest>();
  final Completer<void> _cancelGate = Completer<void>();

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    requests.add(request);
    if (!requestReceived.isCompleted) {
      requestReceived.complete(request);
    }
    return _events.stream;
  }

  @override
  Future<void> cancel(GenerationId generationId) => _cancelGate.future;

  void emit(GenerationEvent event) => _events.add(event);

  void releaseCancel() {
    if (!_cancelGate.isCompleted) {
      _cancelGate.complete();
    }
  }
}

/// Hands scheduled utterance settles to the test.
final class _HandVoiceScheduler implements BatchScheduler {
  final List<void Function()> scheduled = <void Function()>[];
  int cancelled = 0;

  @override
  CancelBatch schedule(Duration delay, void Function() callback) {
    scheduled.add(callback);
    return _HandCancel(this);
  }

  void fireLast() => scheduled.last();
}

final class _HandCancel implements CancelBatch {
  _HandCancel(this._owner);

  final _HandVoiceScheduler _owner;
  bool _done = false;

  @override
  void cancel() {
    if (!_done) {
      _done = true;
      _owner.cancelled += 1;
    }
  }
}

/// A voice whose startListening never returns, as on first-run downloads.
final class _NeverStartsVoice implements VoiceService {
  final StreamController<VoiceEvent> events_ =
      StreamController<VoiceEvent>.broadcast();

  @override
  Stream<VoiceEvent> get events => events_.stream;

  @override
  Future<void> startListening() => Completer<void>().future;

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> finalizeUtterance() async {}

  @override
  Future<void> speak(String text, {String? language}) async {}

  @override
  Future<void> stopSpeaking() async {}
}

/// A scheduler whose work never runs: proves a path did not rely on a timer.
final class _NeverScheduler implements BatchScheduler {
  const _NeverScheduler();

  @override
  CancelBatch schedule(Duration delay, void Function() callback) =>
      const _NeverCancel();
}

final class _NeverCancel implements CancelBatch {
  const _NeverCancel();

  @override
  void cancel() {}
}
