import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_content_column.dart';
import 'package:local_agent_macos/features/presence/desktop_orb_surface.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/fake_presentation_host.dart';

void main() {
  testWidgets('collapsing to the orb keeps the answer being generated', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
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
        presenceShaderLoader: failShaderLoad,
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
    // Both forms live in one window that never changes size, so the
    // conversation is hidden by being fully transparent rather than by being
    // taken out of the tree — it stays laid out so the presence has a place
    // to land when it comes back.
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('conversation-visibility')))
          .opacity,
      0,
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
    final FakePresentationHost host = FakePresentationHost();
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
        presenceShaderLoader: failShaderLoad,
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
    final FakePresentationHost host = FakePresentationHost();
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
        presenceShaderLoader: failShaderLoad,
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

  testWidgets('a form change is drawn before the window settles into it', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
    addTearDown(() => unawaited(host.dispose()));
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: _HoldingInferenceService(),
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();

    // The hotkey asks for the orb rather than moving the window itself.
    host.requestPresentation(DesktopPresentation.orb);
    await tester.pump();
    await tester.pump();

    expect(
      host.begunTransitions,
      <DesktopPresentation>[DesktopPresentation.orb],
      reason: 'The window was never grown to cover both forms.',
    );
    expect(
      host.endedTransitions,
      isEmpty,
      reason: 'The window settled before the presence had moved.',
    );

    // Not pumpAndSettle: the travelling presence animates continuously, so
    // there is no quiet frame to settle on.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump();

    expect(
      host.endedTransitions,
      <DesktopPresentation>[DesktopPresentation.orb],
      reason: 'The window never settled once the presence had arrived.',
    );
    expect(host.presentation.value, DesktopPresentation.orb);
  });

  testWidgets('the conversation follows the window the user resizes', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
    addTearDown(() => unawaited(host.dispose()));
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: _HoldingInferenceService(),
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();

    // The user grows the window — a drag of its edge, the zoom button, or
    // full screen; the layout must not keep drawing at the size it was.
    host.changeGeometry(
      const DesktopTransitionGeometry(
        size: Size(1000, 700),
        conversation: Rect.fromLTWH(0, 0, 1000, 700),
        orb: Rect.fromLTWH(832, 532, 168, 168),
      ),
    );
    await tester.pump();

    expect(
      tester.getRect(find.byKey(const Key('conversation-visibility'))).size,
      const Size(1000, 700),
      reason:
          'The window was resized and the conversation stayed the old size.',
    );
  });

  testWidgets('the title and the composer share one leading edge', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
    addTearDown(() => unawaited(host.dispose()));
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: _HoldingInferenceService(),
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();

    // The title, the messages and the composer share one content column, so
    // the title's leading edge is the composer's leading edge — at this size
    // and at every other.
    double titleLeads() => tester.getTopLeft(find.text('Lulo')).dx;
    double composerLeads() => tester
        .getTopLeft(find.byKey(const Key('conversation-composer-field')))
        .dx;
    expect(titleLeads(), composerLeads());

    // Wider than the column: both centre together rather than the composer
    // walking away from a title pinned to the window's edge.
    host.changeGeometry(
      const DesktopTransitionGeometry(
        size: Size(1512, 949),
        conversation: Rect.fromLTWH(0, 0, 1512, 949),
        orb: Rect.fromLTWH(1344, 781, 168, 168),
        fullScreen: true,
      ),
    );
    await tester.pump();

    expect(
      titleLeads(),
      composerLeads(),
      reason: 'The window grew and the title left the composer\'s edge.',
    );
    expect(
      titleLeads(),
      greaterThan(conversationContentMargin),
      reason: 'A window wider than the column should centre the content.',
    );
  });

  testWidgets('the conversation keeps its corners rounded as it leaves', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
    addTearDown(() => unawaited(host.dispose()));
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: _HoldingInferenceService(),
      presentationHost: host,
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();

    final Rect slot = tester.getRect(
      find.byKey(const Key('conversation-visibility')),
    );
    expect(
      tester.getRect(find.byKey(const Key('conversation-corners'))),
      slot,
      reason: 'The conversation is not rounded at the size it is drawn at.',
    );

    // Leaving shrinks the conversation. Rounding it from outside that shrink
    // leaves the corners cut at the size it no longer is, so the conversation
    // pulls away from its own rounding and four square corners appear for as
    // long as the change of form lasts.
    host.presentation.value = DesktopPresentation.orb;
    await tester.pump();
    await tester.pump();

    final Rect rounded = tester.getRect(
      find.byKey(const Key('conversation-corners')),
    );
    expect(
      rounded.width,
      lessThan(slot.width),
      reason: 'The rounding stayed at full size while the conversation shrank.',
    );
    expect(
      tester.getRect(find.byType(ConversationView)).size,
      rounded.size,
      reason: 'The rounding and the conversation are drawn at different sizes.',
    );
  });

  testWidgets('a choice made in settings reaches the window itself', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
    addTearDown(() => unawaited(host.dispose()));
    final List<String> loaded = <String>[];
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: _HoldingInferenceService(),
      presentationHost: host,
      changeModel: (String modelPath) async => loaded.add(modelPath),
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();

    // Settings that only record a preference are decoration. Every switch
    // here changes how the window behaves, so the window has to hear about it.
    expect(host.windowBehaviours.last, (true, true));

    host.requestSettings();
    await tester.pump();
    expect(find.byKey(const Key('settings-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('setting-keep-orb-on-top')));
    await tester.pump();
    await tester.pump();

    expect(
      host.windowBehaviours.last,
      (false, true),
      reason: 'Turning the orb off the top never reached the window.',
    );
    expect(
      (await composition.settingsStore.load()).keepOrbOnTop,
      isFalse,
      reason: 'The choice would not have survived a restart.',
    );

    // A model is chosen in settings rather than fixed when the app is built,
    // so choosing one has to be written down or it is gone on the next run.
    host.chosenModelFile = '/models/gemma-4-E4B-it.litertlm';
    await tester.tap(find.byKey(const Key('setting-choose-model')));
    await tester.pump();
    await tester.pump();
    expect(
      (await composition.settingsStore.load()).modelPath,
      '/models/gemma-4-E4B-it.litertlm',
    );
    // And it is thinking with it now. Writing the choice down and carrying on
    // with the old model until the next launch is the same decoration as a
    // switch that changes nothing.
    expect(loaded, <String>[
      '/models/gemma-4-E4B-it.litertlm',
    ], reason: 'The chosen model never reached the runtime.');

    // Every other switch on the sheet must not pay for a model load, which
    // costs seconds and gigabytes.
    await tester.tap(find.byKey(const Key('setting-follow-across-spaces')));
    await tester.pump();
    await tester.pump();
    expect(loaded, hasLength(1));

    await tester.tap(find.byKey(const Key('settings-close-button')));
    await tester.pump();
    expect(find.byKey(const Key('settings-sheet')), findsNothing);
  });

  testWidgets('changing form never rebuilds the presence orb', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost();
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
