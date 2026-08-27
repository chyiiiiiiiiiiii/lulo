import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

/// What the resting orb is told to offer, which is the only thing it can show.
///
/// The strip is drawn by AppKit the instant the pointer settles on the orb, so
/// anything Dart has not already pushed is not there. A strip wired up and
/// never told anything is invisible from the native side.
void main() {
  Future<(FakePresentationHost, AppComposition)> pumpApp(
    WidgetTester tester, {
    String modelPath = '/models/gemma-4-E4B-it.litertlm',
  }) async {
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      settingsStore: InMemorySettingsStore(AppSettings(modelPath: modelPath)),
    );
    addTearDown(() => unawaited(composition.dispose()));
    host.presentation.value = DesktopPresentation.orb;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return (host, composition);
  }

  testWidgets('the resting orb is told what to offer before it is hovered', (
    WidgetTester tester,
  ) async {
    final (FakePresentationHost host, _) = await pumpApp(tester);

    expect(
      host.offeredOrbActions,
      isNotEmpty,
      reason: 'the strip was wired up and never told anything',
    );
    // Every word it shows comes from here: AppKit has no localizations.
    for (final DesktopOrbAction action in host.offeredOrbActions) {
      expect(action.label, isNotEmpty);
      expect(action.symbol, isNotEmpty);
    }
    expect(
      host.offeredOrbActions.map((DesktopOrbAction a) => a.id),
      contains('look'),
    );
    expect(
      host.offeredOrbActions.map((DesktopOrbAction a) => a.id),
      isNot(contains('stop')),
      reason: 'nothing is being answered, so there is nothing to stop',
    );
  });

  testWidgets('an orb with no model to think with offers nothing', (
    WidgetTester tester,
  ) async {
    final (FakePresentationHost host, _) = await pumpApp(tester, modelPath: '');

    expect(host.offeredOrbActions, isEmpty);
  });

  testWidgets('a button under the orb reaches the conversation', (
    WidgetTester tester,
  ) async {
    final (FakePresentationHost host, AppComposition composition) =
        await pumpApp(tester);

    host.orbActions.add('look');
    await tester.pump();

    expect(composition.orbActionRequests.value?.$1, OrbActionKind.look);
    // Looking has to bring the window back: the answer is written, not
    // spoken, and an answer nobody can see is not one.
    expect(host.presentation.value, DesktopPresentation.expanded);
  });

  testWidgets('pressing the same button twice arrives twice', (
    WidgetTester tester,
  ) async {
    final (FakePresentationHost host, AppComposition composition) =
        await pumpApp(tester);
    int arrivals = 0;
    composition.orbActionRequests.addListener(() => arrivals += 1);

    host.orbActions
      ..add('stop')
      ..add('stop');
    await tester.pump();

    expect(arrivals, 2);
  });

  testWidgets('a button nobody put there is ignored', (
    WidgetTester tester,
  ) async {
    final (FakePresentationHost host, AppComposition composition) =
        await pumpApp(tester);

    host.orbActions.add('launch-the-missiles');
    await tester.pump();

    expect(composition.orbActionRequests.value, isNull);
  });
}
