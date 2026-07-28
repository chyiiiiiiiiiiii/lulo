import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/inference_service.dart';
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

  @override
  Future<void> cancel(GenerationId generationId) async {
    cancelledGenerations.add(generationId);
  }
}

Future<Never> _failShaderLoad() async {
  throw UnsupportedError('Runtime shader rendering is outside this test.');
}
