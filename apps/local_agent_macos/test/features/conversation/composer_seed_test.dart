import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_composer.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  Widget composer(ValueListenable<String> seed, List<String> sent) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConversationComposer(
            canSubmit: ValueNotifier<bool>(true),
            onSubmit: sent.add,
            onStop: () async {},
            seed: seed,
          ),
        ),
      );

  testWidgets('a selection sent from another app lands in the field', (
    WidgetTester tester,
  ) async {
    // Six steps became one: select in Mail, invoke the service, and the text
    // is here waiting for the user to say what they want done with it.
    final ValueNotifier<String> seed = ValueNotifier<String>('');
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed, sent));
    await tester.pump();

    seed.value = '這段話請幫我改客氣一點的原文';
    await tester.pump();

    expect(find.text('這段話請幫我改客氣一點的原文'), findsOneWidget);
  });

  testWidgets('it is not sent on the user\'s behalf', (
    WidgetTester tester,
  ) async {
    // A selection is not a question. Submitting it would ask the agent to
    // respond to a paragraph with no instruction attached, and the user
    // still has to say what they wanted.
    final ValueNotifier<String> seed = ValueNotifier<String>('');
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed, sent));
    await tester.pump();

    seed.value = 'a paragraph';
    await tester.pump();

    expect(sent, isEmpty);
  });

  testWidgets('it does not discard what was already being typed', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<String> seed = ValueNotifier<String>('');
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed, sent));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '幫我改成');
    seed.value = '原文在這裡';
    await tester.pump();

    expect(find.textContaining('幫我改成'), findsOneWidget);
    expect(find.textContaining('原文在這裡'), findsOneWidget);
  });

  testWidgets('a composer with nothing seeding it behaves as before', (
    WidgetTester tester,
  ) async {
    final List<String> sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConversationComposer(
            canSubmit: ValueNotifier<bool>(true),
            onSubmit: sent.add,
            onStop: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });
}
