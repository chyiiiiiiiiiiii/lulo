import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/microtask_batch_scheduler.dart';
import '../../support/recording_conversation_storage_service.dart';

void main() {
  testWidgets('a token delta rebuilds only the active streaming turn', (
    tester,
  ) async {
    final storage = RecordingConversationStorageService();
    final inference = ControlledInferenceService();
    final repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final viewModel = ConversationViewModel(
      batchScheduler: MicrotaskBatchScheduler(),
      repository: repository,
      idFactory: () => const ConversationId('conversation-1'),
    );
    final ConversationBuildObserver observer = ConversationBuildObserver();
    int broadNotifications = 0;
    viewModel.addListener(() => broadNotifications += 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ConversationView(
            viewModelFactory: () => viewModel,
            buildObserver: observer,
          ),
        ),
      ),
    );
    await tester.pump();
    await viewModel.submit('Hello');
    await inference.requestReceived;
    inference.emit(
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
    await tester.pump();
    observer.reset();
    broadNotifications = 0;

    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'A',
      ),
    );
    await tester.pump();

    expect(observer.activeStreamingTurnBuilds, 1);
    expect(observer.completedTurnsBuilds, 0);
    expect(observer.composerBuilds, 0);
    expect(observer.conversationListBuilds, 0);
    expect(observer.chromeBuilds, 0);
    expect(observer.modelStatusBuilds, 0);
    expect(observer.agentPresenceOrbPaints, 1);
    expect(observer.agentPresenceSemanticBuilds, 1);
    expect(broadNotifications, 0);
    expect(find.text('A'), findsOneWidget);

    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('state and amplitude updates repaint only the presence orb', (
    WidgetTester tester,
  ) async {
    final ConversationBuildObserver observer = ConversationBuildObserver();
    final _ViewHarness harness = _ViewHarness();
    await tester.pumpWidget(
      harness.app(observer: observer, disableAnimations: true),
    );
    await tester.pump();
    final AgentPresenceController controller =
        observer.agentPresenceController!;
    observer.reset();

    controller.dispatch(
      AgentPresenceEvent.listeningStarted,
      const Duration(milliseconds: 1),
    );
    await tester.pump();

    expect(observer.agentPresenceOrbPaints, 1);
    expect(observer.agentPresenceSemanticBuilds, 1);
    _expectConversationCountersAreZero(observer);

    observer.reset();
    controller.acceptAudioRms(0, const Duration(milliseconds: 16));
    controller.acceptAudioRms(0.42, const Duration(milliseconds: 71));
    await tester.pump();

    expect(observer.agentPresenceOrbPaints, 1);
    expect(observer.agentPresenceSemanticBuilds, 0);
    _expectConversationCountersAreZero(observer);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      () => controller.semanticStateListenable.addListener(() {}),
      throwsFlutterError,
    );
  });

  testWidgets(
    'conversation projection publishes only direct lifecycle states',
    (WidgetTester tester) async {
      final ConversationBuildObserver observer = ConversationBuildObserver();
      final _ViewHarness harness = _ViewHarness();
      await tester.pumpWidget(
        harness.app(observer: observer, disableAnimations: true),
      );
      final AgentPresenceController controller =
          observer.agentPresenceController!;
      final List<AgentPresenceState> publishedStates = <AgentPresenceState>[];
      controller.semanticStateListenable.addListener(() {
        publishedStates.add(controller.semanticStateListenable.value);
      });

      expect(find.bySemanticsLabel('Agent ready'), findsOneWidget);
      await harness.start();
      await tester.pump();
      expect(find.bySemanticsLabel('Thinking'), findsOneWidget);
      expect(publishedStates, <AgentPresenceState>[
        AgentPresenceState.thinking,
      ]);

      publishedStates.clear();
      harness.inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'A',
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Speaking'), findsOneWidget);
      expect(publishedStates, <AgentPresenceState>[
        AgentPresenceState.speaking,
      ]);

      observer.reset();
      publishedStates.clear();
      harness.inference.emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: 'B',
        ),
      );
      await tester.pump();

      expect(observer.agentPresenceSemanticBuilds, 0);
      expect(observer.agentPresenceOrbPaints, 0);
      expect(observer.activeStreamingTurnBuilds, 1);
      expect(observer.completedTurnsBuilds, 0);
      expect(observer.composerBuilds, 0);
      expect(observer.conversationListBuilds, 0);
      expect(observer.chromeBuilds, 0);
      expect(observer.modelStatusBuilds, 0);
      expect(publishedStates, isEmpty);
      expect(find.bySemanticsLabel('Speaking'), findsOneWidget);

      publishedStates.clear();
      harness.inference.emit(
        const GenerationCompleted(GenerationId('generation-1')),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Agent ready'), findsOneWidget);
      expect(publishedStates, <AgentPresenceState>[AgentPresenceState.idle]);
      expect(publishedStates, isNot(contains(AgentPresenceState.listening)));
      expect(publishedStates, isNot(contains(AgentPresenceState.working)));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('empty response returns from thinking directly to idle', (
    WidgetTester tester,
  ) async {
    final ConversationBuildObserver observer = ConversationBuildObserver();
    final _ViewHarness harness = _ViewHarness();
    await tester.pumpWidget(
      harness.app(observer: observer, disableAnimations: true),
    );
    final AgentPresenceController controller =
        observer.agentPresenceController!;
    final List<AgentPresenceState> publishedStates = <AgentPresenceState>[];
    controller.semanticStateListenable.addListener(() {
      publishedStates.add(controller.semanticStateListenable.value);
    });

    await harness.start();
    await tester.pump();
    harness.inference.emit(
      const GenerationCompleted(GenerationId('generation-1')),
    );
    await tester.pumpAndSettle();

    expect(publishedStates, <AgentPresenceState>[
      AgentPresenceState.thinking,
      AgentPresenceState.idle,
    ]);
    expect(publishedStates, isNot(contains(AgentPresenceState.listening)));
    expect(publishedStates, isNot(contains(AgentPresenceState.speaking)));
    expect(publishedStates, isNot(contains(AgentPresenceState.working)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('last failed assistant turn maps to attention needed', (
    WidgetTester tester,
  ) async {
    final ConversationBuildObserver observer = ConversationBuildObserver();
    final _ViewHarness harness = _ViewHarness();
    await tester.pumpWidget(harness.app(observer: observer));
    await harness.start();
    harness.inference.emit(
      const GenerationFailed(
        generationId: GenerationId('generation-1'),
        failure: ConversationFailure('runtime failed'),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Attention needed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long streaming output stays inside the bounded scroll surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _ViewHarness harness = _ViewHarness();
    await tester.pumpWidget(harness.app());
    await harness.start();

    harness.inference.emit(
      GenerationDelta(
        generationId: const GenerationId('generation-1'),
        delta: List<String>.generate(
          120,
          (int index) => 'Streaming line $index',
        ).join('\n'),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.ancestor(
        of: find.byKey(const Key('active-streaming-markdown')),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long streaming output fits a desktop window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _ViewHarness harness = _ViewHarness();
    await tester.pumpWidget(harness.app());
    await harness.start();

    harness.inference.emit(
      GenerationDelta(
        generationId: const GenerationId('generation-1'),
        delta: List<String>.filled(160, 'A local response line').join('\n'),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('conversation-scroll-surface')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _ViewHarness {
  final RecordingConversationStorageService storage =
      RecordingConversationStorageService();
  final ControlledInferenceService inference = ControlledInferenceService();
  late final ConversationRepository repository = ConversationRepository(
    storageService: storage,
    inferenceService: inference,
  );
  late final ConversationViewModel viewModel = ConversationViewModel(
    batchScheduler: MicrotaskBatchScheduler(),
    repository: repository,
    idFactory: () => const ConversationId('conversation-1'),
  );

  Widget app({
    ConversationBuildObserver? observer,
    bool disableAnimations = false,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ConversationView(
        viewModelFactory: () => viewModel,
        buildObserver: observer,
      ),
    ),
  );

  Future<void> start() async {
    await viewModel.submit('Hello');
    await inference.requestReceived;
    inference.emit(
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
  }
}

void _expectConversationCountersAreZero(ConversationBuildObserver observer) {
  expect(observer.chromeBuilds, 0);
  expect(observer.conversationListBuilds, 0);
  expect(observer.completedTurnsBuilds, 0);
  expect(observer.activeStreamingTurnBuilds, 0);
  expect(observer.composerBuilds, 0);
  expect(observer.modelStatusBuilds, 0);
}
