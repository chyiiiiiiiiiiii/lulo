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
      await tester.pumpAndSettle();

      expect(find.text('Start a conversation'), findsOneWidget);
      expect(find.byKey(const Key('agent-presence-fallback')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('conversation-composer-field')),
        'Explain local AI',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('conversation-submit-button')));

      await tester.pump(const Duration(milliseconds: 90));
      expect(find.textContaining('Local inference'), findsOneWidget);
      expect(find.byKey(const Key('conversation-stop-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('conversation-stop-button')));
      await tester.pump();

      expect(find.text('Response stopped'), findsOneWidget);
      expect(find.textContaining('Local inference'), findsOneWidget);
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

      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text(
          'Local inference is streaming through the real app pipeline. '
          'This preview is deterministic and runs without a network '
          'connection.',
        ),
        findsOneWidget,
      );
      expect(find.text('Response stopped'), findsOneWidget);
      expect(find.byKey(const Key('terminal-markdown')), findsNWidgets(2));
      expect(
        find.byKey(const Key('conversation-submit-button')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Future<ui.FragmentProgram> _failShaderLoad() async {
  throw UnsupportedError('Runtime shader rendering is outside this test.');
}
