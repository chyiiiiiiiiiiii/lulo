import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/bootstrap.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';
import 'package:local_agent_macos/features/conversation/conversation_storage_service.dart';
import 'package:local_agent_macos/features/transcript_refiner/deadline_transcript_refiner.dart';
import 'package:local_agent_macos/features/transcript_refiner/loopback_transcript_proposal_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local bootstrap keeps the app local-only at 120 frames per second', () {
    final BootstrapConfig config = createBootstrapConfig();

    expect(config.localOnly, isTrue);
    expect(config.targetFrameRate, 120);
  });

  test('bootstrap rejects an unsupported inference runtime', () {
    expect(
      () => createAppComposition(inferenceRuntime: 'remote'),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError error) => error.message,
          'message',
          contains('remote'),
        ),
      ),
    );
  });

  test('bootstrap accepts an explicit LiteRT runtime and model path', () async {
    final composition = createAppComposition(
      inferenceRuntime: 'litert',
      localModelPath: '/models/gemma-4-E4B-it.litertlm',
    );

    await composition.dispose();
  });

  test('every runtime gives the app its desktop presence', () async {
    // The desktop form is how the agent is reached, not a property of which
    // runtime answers it. A composition without a presentation host renders
    // the conversation straight into the window, which at rest is orb-sized.
    for (final String runtime in <String>['fake', 'litert']) {
      final AppComposition composition = createAppComposition(
        inferenceRuntime: runtime,
        localModelPath: '/models/gemma-4-E4B-it.litertlm',
      );

      expect(
        composition.presentationHost,
        isNotNull,
        reason: 'The $runtime runtime bootstrapped without a desktop host.',
      );

      await composition.dispose();
    }
  });

  test(
    'bootstrap gives voice a deadline-bound local transcript refiner',
    () async {
      final AppComposition composition = createAppComposition();

      expect(composition.transcriptRefiner, isA<DeadlineTranscriptRefiner>());
      expect(composition.transcriptShadow, isNull);
      expect(
        composition.protectedVocabulary(),
        containsAll(<String>['Lulo', 'Flutter', 'Gemma', 'Qwen']),
      );

      await composition.dispose();
    },
  );

  test('an explicit loopback endpoint enables transcript shadowing', () async {
    final AppComposition composition = createAppComposition(
      transcriptShadowEndpoint: 'http://127.0.0.1:46559/v1/refine',
    );

    expect(composition.transcriptShadow, isNotNull);
    expect(
      composition.transcriptShadow?.provider,
      isA<LoopbackTranscriptProposalProvider>(),
    );
    expect(composition.transcriptShadowEvidence, isNotNull);

    await composition.dispose();
  });

  test('a non-loopback transcript endpoint is rejected', () {
    expect(
      () => createAppComposition(
        transcriptShadowEndpoint: 'https://example.com/v1/refine',
      ),
      throwsArgumentError,
    );
  });

  test('an answer is given room to finish', () {
    // 512 tokens cut real answers off mid-sentence, which reads as the app
    // being broken rather than the model being concise. The budget has to fit
    // a long structured answer and still leave the context room for the
    // conversation that prompted it.
    expect(localAnswerTokenBudget, greaterThanOrEqualTo(2048));
    expect(
      localModelContextSize - localAnswerTokenBudget,
      greaterThanOrEqualTo(localAnswerTokenBudget),
      reason: 'The answer budget crowds the conversation out of the context.',
    );
  });

  test('LiteRT bootstrap rejects a missing model path', () {
    expect(
      () => createAppComposition(
        inferenceRuntime: 'litert',
        localModelPath: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'the durable developer profile lives beside Lulo application data',
    () async {
      final Directory home = await Directory.systemTemp.createTemp(
        'lulo-home-',
      );
      addTearDown(() => home.delete(recursive: true));

      final FileAgentProfileStore store = createAgentProfileStore(
        home: home.path,
        watch: false,
      );
      addTearDown(store.dispose);

      expect(
        store.file.path,
        '${home.path}/Library/Application Support/Lulo/agent_profile.json',
      );
    },
  );

  test(
    'the composition settles an interrupted run before the app runs',
    () async {
      // The recovery is one delegation deep, which is exactly the kind of wire
      // that can be cut without any test noticing: everything below it would
      // still pass while nothing on disk was ever recovered.
      final _InterruptedRunStorage storage = _InterruptedRunStorage();
      final AppComposition composition = createAppComposition(
        conversationStorage: OwnedConversationStorage(
          service: storage,
          release: () async {},
        ),
      );

      await composition.recoverInterruptedRuns();

      expect(storage.recoveredText, 'what it had managed to say');
      await composition.dispose();
    },
  );
}

/// A store holding one run the last process never finished.
final class _InterruptedRunStorage implements ConversationStorageService {
  String? recoveredText;

  @override
  Future<List<RunRecord>> loadUnfinishedRuns() async => <RunRecord>[
    RunRecord(
      id: const GenerationId('died'),
      conversationId: const ConversationId('yesterday'),
      modelId: 'gemma-4-E2B-it',
      startedAt: DateTime.fromMillisecondsSinceEpoch(1),
      partialText: 'what it had managed to say',
    ),
  ];

  @override
  Future<void> saveTerminalAssistantTurn(
    Turn turn,
    Generation generation,
  ) async {
    recoveredText = turn.text;
  }

  @override
  Future<void> endRun(GenerationId generationId, TurnStatus outcome) async {}

  @override
  Future<void> beginRun(RunRecord run) async {}

  @override
  Future<void> checkpointRun(
    GenerationId generationId,
    String partialText,
  ) async {}

  @override
  Future<List<Turn>> loadTurns(ConversationId conversationId) async =>
      const <Turn>[];

  @override
  Future<void> saveUserTurn(ConversationId conversationId, Turn turn) async {}

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      const <ConversationSummary>[];

  @override
  Future<void> deleteConversation(ConversationId conversationId) async {}
}
