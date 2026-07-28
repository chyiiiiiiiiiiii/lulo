import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';
import 'package:local_agent_macos/features/presence/desktop_orb_surface.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

void main() {
  testWidgets('collapsing to the orb keeps the answer being generated', (
    WidgetTester tester,
  ) async {
    final _FakePresentationHost host = _FakePresentationHost();
    final _HoldingInferenceService inference = _HoldingInferenceService();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: inference,
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: _failShaderLoad,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('conversation-composer-field')),
      'Explain local inference',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-submit-button')));
    await tester.pump();
    expect(inference.activeRequests, 1);
    expect(inference.cancelledGenerations, isEmpty);

    // Collapsing must not tear the conversation down: its ViewModel owns the
    // generation, so unmounting it would cancel the answer in flight.
    host.presentation.value = DesktopPresentation.orb;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      inference.cancelledGenerations,
      isEmpty,
      reason: 'Collapsing to the orb cancelled the running generation.',
    );
    expect(
      find.byKey(const Key('conversation-composer-field')),
      findsNothing,
      reason: 'The conversation must not be visible while collapsed.',
    );

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pump();
    expect(
      find.byKey(const Key('conversation-composer-field')),
      findsOneWidget,
      reason: 'Expanding must show the same conversation again.',
    );
    expect(inference.activeRequests, 1);
  });

  testWidgets('the collapsed orb shows the agent speaking, not resting', (
    WidgetTester tester,
  ) async {
    final _FakePresentationHost host = _FakePresentationHost();
    final _HoldingInferenceService inference = _HoldingInferenceService();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: inference,
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: _failShaderLoad,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('conversation-composer-field')),
      'Explain local inference',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-submit-button')));
    await tester.pump();
    inference.emitDelta('Local inference ');
    await tester.pump();

    host.presentation.value = DesktopPresentation.orb;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The orb must be the same agent, so while the answer is being spoken the
    // resting presence says so rather than reporting itself as ready.
    final Finder orb = find.descendant(
      of: find.byType(DesktopOrbSurface),
      matching: find.bySemanticsLabel('Speaking'),
    );
    expect(
      orb,
      findsOneWidget,
      reason: 'The collapsed orb did not follow the conversation state.',
    );
  });

  testWidgets('an app that starts as an orb still follows the agent', (
    WidgetTester tester,
  ) async {
    final _FakePresentationHost host = _FakePresentationHost();
    final _HoldingInferenceService inference = _HoldingInferenceService();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: inference,
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    // The real app launches resting on the desktop, so the conversation is
    // first built inside the collapsed wrapper. Starting expanded hides any
    // ordering fault in how the presence is handed over.
    expect(host.presentation.value, DesktopPresentation.orb);
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: _failShaderLoad,
      ),
    );
    await tester.pump();

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('conversation-composer-field')),
      'Explain local inference',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-submit-button')));
    await tester.pump();
    inference.emitDelta('Local inference ');
    await tester.pump();

    host.presentation.value = DesktopPresentation.orb;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(
        of: find.byType(DesktopOrbSurface),
        matching: find.bySemanticsLabel('Speaking'),
      ),
      findsOneWidget,
      reason:
          'An orb-first launch left the desktop presence on its own idle '
          'controller, so it rested while the agent was speaking.',
    );
  });

  testWidgets('changing form never rebuilds the presence orb', (
    WidgetTester tester,
  ) async {
    final _FakePresentationHost host = _FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: _HoldingInferenceService(),
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    // Each mounted orb loads the shader program once, so the number of loads
    // counts how many orbs the app has built. The agent is one presence: it
    // should be built once and moved between the two forms, not torn down and
    // recreated on every collapse.
    int shaderLoads = 0;
    Future<Never> countShaderLoad() async {
      shaderLoads += 1;
      throw UnsupportedError('Runtime shader rendering is outside this test.');
    }

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: countShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(shaderLoads, 1, reason: 'The app built more than one presence.');

    for (int cycle = 0; cycle < 2; cycle += 1) {
      host.presentation.value = DesktopPresentation.orb;
      await tester.pump();
      await tester.pump();
      host.presentation.value = DesktopPresentation.expanded;
      await tester.pump();
      await tester.pump();
    }

    expect(
      shaderLoads,
      1,
      reason:
          'Changing form rebuilt the orb, which restarts its clock and '
          'reloads its shader every time the window collapses.',
    );
  });
}

final class _FakePresentationHost implements DesktopPresentationHost {
  @override
  final ValueNotifier<DesktopPresentation> presentation =
      ValueNotifier<DesktopPresentation>(DesktopPresentation.orb);

  @override
  Future<void> setPresentation(DesktopPresentation mode) async {
    presentation.value = mode;
  }

  final List<Offset> moves = <Offset>[];

  @override
  Future<void> moveWindowBy(Offset delta) async {
    moves.add(delta);
  }

  /// A canvas holding a centred conversation and an orb in the lower corner.
  DesktopTransitionGeometry geometry = const DesktopTransitionGeometry(
    size: Size(1268, 828),
    conversation: Rect.fromLTWH(0, 0, 720, 560),
    orb: Rect.fromLTWH(1100, 660, 148, 148),
  );

  /// Targets passed to [beginPresentationTransition], in order.
  final List<DesktopPresentation> begunTransitions = <DesktopPresentation>[];

  /// Modes passed to [endPresentationTransition], in order.
  final List<DesktopPresentation> endedTransitions = <DesktopPresentation>[];

  @override
  Future<DesktopTransitionGeometry> beginPresentationTransition(
    DesktopPresentation target,
  ) async {
    begunTransitions.add(target);
    return geometry;
  }

  @override
  Future<void> endPresentationTransition(DesktopPresentation mode) async {
    endedTransitions.add(mode);
    presentation.value = mode;
  }
}

/// Streams a started event and then holds, so a generation stays in flight.
final class _HoldingInferenceService implements InferenceService {
  int activeRequests = 0;
  final List<GenerationId> cancelledGenerations = <GenerationId>[];
  final List<StreamController<GenerationEvent>> _controllers =
      <StreamController<GenerationEvent>>[];

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    activeRequests += 1;
    final StreamController<GenerationEvent> controller =
        StreamController<GenerationEvent>();
    _controllers.add(controller);
    final GenerationId id = GenerationId('generation-$activeRequests');
    controller.add(GenerationStarted(Generation(id: id, request: request)));
    return controller.stream;
  }

  void emitDelta(String delta) {
    _controllers.last.add(
      GenerationDelta(
        generationId: GenerationId('generation-$activeRequests'),
        delta: delta,
      ),
    );
  }

  @override
  Future<void> cancel(GenerationId generationId) async {
    cancelledGenerations.add(generationId);
  }
}

Future<Never> _failShaderLoad() async {
  throw UnsupportedError('Runtime shader rendering is outside this test.');
}
