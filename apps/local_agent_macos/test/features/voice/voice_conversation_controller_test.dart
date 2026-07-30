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
      GenerationDelta(generationId: generation.id, delta: '台北是台灣的首都,也是'),
    );
    await pump();
    expect(voice.spoken, <String>[
      '台北是台灣的首都,',
    ], reason: 'A finished clause is enough to start the voice.');

    inference.emit(
      GenerationDelta(generationId: generation.id, delta: '最大的城市。'),
    );
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();
    expect(voice.spoken, <String>['台北是台灣的首都,', '也是最大的城市。']);
  });

  test('a clause too short to sound like speech waits for more', () async {
    // "好的," alone reads as a stutter; the clause hand-off only fires once
    // there is something substantive to say.
    await controller.enable();
    voice.hear(const FinalTranscript('可以嗎?'));
    await pump();
    final Generation generation = await generationStarted();

    inference.emit(GenerationDelta(generationId: generation.id, delta: '好的,我'));
    await pump();
    expect(voice.spoken, isEmpty);

    inference.emit(GenerationDelta(generationId: generation.id, delta: '會幫你。'));
    await pump();
    expect(voice.spoken, <String>['好的,我會幫你。']);
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
        delta: '你可以逛夜市,參觀故宮,搭捷運,爬象山,喝珍珠奶茶,吃小籠包,體驗這座城市的多元文化',
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
        delta: '是一套跨平台的開發框架,用一份程式碼同時建構多個平台的應用。',
      ),
    );
    await pump();
    await pump();
    inference.emit(GenerationCompleted(generation.id));
    await pump();
    await pump();

    expect(voice.spoken, hasLength(2));
    expect(voice.spoken[1], 'Flutter。是一套跨平台的開發框架,用一份程式碼同時建構多個平台的應用。');
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
