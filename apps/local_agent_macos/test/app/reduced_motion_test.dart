import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

void main() {
  testWidgets('reduced motion changes form without the flight', (
    WidgetTester tester,
  ) async {
    // The travelling presence is ornament. A user who asked the system for
    // less motion gets the change of form itself, immediately, rather than
    // a spring they cannot opt out of.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    final FakePresentationHost host = FakePresentationHost();
    addTearDown(() => unawaited(host.dispose()));
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
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

    host.requestPresentation(DesktopPresentation.orb);
    await tester.pump();
    await tester.pump();

    expect(
      host.endedTransitions,
      <DesktopPresentation>[DesktopPresentation.orb],
      reason:
          'With animations disabled the window must settle at once, not '
          'after a spring has wobbled its way over.',
    );
  });
}
