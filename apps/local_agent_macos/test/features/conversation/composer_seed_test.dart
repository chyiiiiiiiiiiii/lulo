import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_composer.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  Widget composer(Stream<String> seed, List<String> sent) => MaterialApp(
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
    final StreamController<String> seed = StreamController<String>.broadcast();
    addTearDown(seed.close);
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed.stream, sent));
    await tester.pump();

    seed.add('這段話請幫我改客氣一點的原文');
    await tester.pump();

    expect(find.text('這段話請幫我改客氣一點的原文'), findsOneWidget);
  });

  testWidgets('it is not sent on the user\'s behalf', (
    WidgetTester tester,
  ) async {
    // A selection is not a question. Submitting it would ask the agent to
    // respond to a paragraph with no instruction attached, and the user
    // still has to say what they wanted.
    final StreamController<String> seed = StreamController<String>.broadcast();
    addTearDown(seed.close);
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed.stream, sent));
    await tester.pump();

    seed.add('a paragraph');
    await tester.pump();

    expect(sent, isEmpty);
  });

  testWidgets('it does not discard what was already being typed', (
    WidgetTester tester,
  ) async {
    final StreamController<String> seed = StreamController<String>.broadcast();
    addTearDown(seed.close);
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed.stream, sent));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '幫我改成');
    seed.add('原文在這裡');
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

  testWidgets('the same selection sent twice arrives twice', (
    WidgetTester tester,
  ) async {
    // A `ValueNotifier` suppresses a write equal to what it holds, so
    // invoking the service on the same paragraph a second time did nothing
    // — silently, with the field left empty.
    final StreamController<String> seed = StreamController<String>.broadcast();
    addTearDown(seed.close);
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed.stream, sent));
    await tester.pump();

    seed.add('the same paragraph');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    seed.add('the same paragraph');
    await tester.pump();

    expect(find.text('the same paragraph'), findsOneWidget);
  });

  testWidgets('a new conversation does not inherit an old selection', (
    WidgetTester tester,
  ) async {
    // The composer is remounted under a fresh key whenever a conversation is
    // opened, started, or deleted. A held value was re-applied every time,
    // so last week's selection reappeared in an empty new conversation.
    final StreamController<String> seed = StreamController<String>.broadcast();
    addTearDown(seed.close);
    final List<String> sent = <String>[];
    await tester.pumpWidget(composer(seed.stream, sent));
    await tester.pump();

    seed.add('an old selection');
    await tester.pump();
    expect(find.text('an old selection'), findsOneWidget);

    // Remount, the way opening another conversation does.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(composer(seed.stream, sent));
    await tester.pump();

    expect(find.text('an old selection'), findsNothing);
  });
}
