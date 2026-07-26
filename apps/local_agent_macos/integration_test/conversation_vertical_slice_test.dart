import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'fake runtime launches, streams partial output, and stops visibly',
    (WidgetTester tester) async {
      final composition = createAppComposition(inferenceRuntime: 'fake');
      await tester.pumpWidget(LocalAgentApp(composition: composition));

      expect(find.text('Start a conversation'), findsOneWidget);

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
      await tester.pumpAndSettle();

      expect(find.text('Response stopped'), findsOneWidget);
      expect(find.textContaining('Local inference'), findsOneWidget);
      expect(
        find.byKey(const Key('conversation-submit-button')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
