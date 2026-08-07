import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/bootstrap.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'fake runtime stops partial output then completes a second response',
    (WidgetTester tester) async {
      final composition = createAppComposition(inferenceRuntime: 'fake');
      await tester.pumpWidget(
        LocalAgentApp(
          composition: composition,
          presenceShaderLoader: _failShaderLoad,
        ),
      );
      await tester.pump();

      // The app rests on the desktop as an orb, so the conversation is not on
      // screen until it is summoned. Driving the real host also resizes the
      // real window, which is what gives the conversation room to lay out.
      await composition.presentationHost!.setPresentation(
        DesktopPresentation.expanded,
      );
      // Not pumpAndSettle: the presence animates continuously on the display's
      // cadence, so there is never a frame with nothing scheduled to settle on.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // By key rather than by text: the interface follows the system's
      // language now, and this runs on whichever Mac happens to be running
      // it. A string assertion here would pass in one country and fail in
      // the next.
      expect(find.byKey(const Key('conversation-empty')), findsOneWidget);
      expect(find.byKey(const Key('agent-presence-fallback')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('conversation-composer-field')),
        'Explain local AI',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('conversation-submit-button')));

      // Waited on the first words rather than on the button, because what is
      // being tested is stopping output that has already partly arrived. The
      // button is there from the moment the request is accepted, which is
      // before there is anything to have stopped.
      await _pumpUntil(tester, find.textContaining('Local inference'));
      expect(find.textContaining('Local inference'), findsOneWidget);
      expect(find.byKey(const Key('conversation-stop-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('conversation-stop-button')));
      await tester.pump();

      expect(find.byKey(const Key('turn-status')), findsOneWidget);
      expect(find.textContaining('Local inference'), findsOneWidget);
      // The composer's button follows canSubmit a frame or two behind the
      // cancellation; waited on rather than assumed, like everything else
      // in this slice.
      await _pumpUntil(
        tester,
        find.byKey(const Key('conversation-submit-button')),
      );
      expect(
        find.byKey(const Key('conversation-submit-button')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('conversation-composer-field')),
        'Finish a second response',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('conversation-submit-button')));

      await _pumpUntil(
        tester,
        find.text(
          'Local inference is streaming through the real app pipeline. '
          'This preview is deterministic and runs without a network '
          'connection.',
        ),
      );

      expect(
        find.text(
          'Local inference is streaming through the real app pipeline. '
          'This preview is deterministic and runs without a network '
          'connection.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('turn-status')), findsOneWidget);
      // The streaming bubble renders the same Markdown as a completed one
      // now, so two markdown bubbles exist while the second response is
      // still arriving — completion is the composer offering submission
      // again, not a bubble count.
      await _pumpUntil(
        tester,
        find.byKey(const Key('conversation-submit-button')),
      );
      expect(find.byKey(const Key('terminal-markdown')), findsNWidgets(2));
      expect(
        find.byKey(const Key('conversation-submit-button')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

/// Pumps until [finder] matches, or gives up.
///
/// The runtime streams on its own clock, so a fixed pump is a guess about how
/// fast the machine is that day. Waiting for the thing itself is not.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int count = 1,
}) async {
  const Duration step = Duration(milliseconds: 50);
  for (int attempt = 0; attempt < 80; attempt += 1) {
    if (finder.evaluate().length >= count) {
      return;
    }
    await tester.pump(step);
  }
}

Future<ui.FragmentProgram> _failShaderLoad() async {
  throw UnsupportedError('Runtime shader rendering is outside this test.');
}
