import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/conversation_composer.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  Widget composer({
    required ValueNotifier<bool> canSubmit,
    required Future<void> Function() onStop,
    ValueChanged<String>? onLook,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ConversationComposer(
        canSubmit: canSubmit,
        onSubmit: (String _) {},
        onStop: onStop,
        onLook: onLook,
      ),
    ),
  );

  testWidgets('the look button sends the field, empty included', (
    WidgetTester tester,
  ) async {
    // A look with an empty field is still a question — "what am I looking
    // at" — so the button works without words, unlike send.
    final ValueNotifier<bool> canSubmit = ValueNotifier<bool>(true);
    addTearDown(canSubmit.dispose);
    final List<String> looks = <String>[];
    await tester.pumpWidget(
      composer(canSubmit: canSubmit, onStop: () async {}, onLook: looks.add),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-look-button')));
    expect(looks, <String>['']);

    await tester.enterText(
      find.byKey(const Key('conversation-composer-field')),
      '這是什麼錯誤？',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-look-button')));
    expect(looks, <String>['', '這是什麼錯誤？']);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('conversation-composer-field')),
          )
          .controller!
          .text,
      isEmpty,
      reason: 'The look consumed the field the way send does.',
    );
  });

  testWidgets('no screen behind the surface means no look button', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<bool> canSubmit = ValueNotifier<bool>(true);
    addTearDown(canSubmit.dispose);
    await tester.pumpWidget(
      composer(canSubmit: canSubmit, onStop: () async {}),
    );
    await tester.pump();
    expect(find.byKey(const Key('conversation-look-button')), findsNothing);
  });

  testWidgets('escape stops the answer being generated', (
    WidgetTester tester,
  ) async {
    // The stop button is a mouse target; a keyboard user watching a wrong
    // answer stream needs a key that says enough.
    final ValueNotifier<bool> canSubmit = ValueNotifier<bool>(false);
    addTearDown(canSubmit.dispose);
    int stops = 0;
    await tester.pumpWidget(
      composer(canSubmit: canSubmit, onStop: () async => stops += 1),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(stops, 1, reason: 'Escape did not stop the streaming answer.');
  });

  testWidgets('escape while idle belongs to whoever is above', (
    WidgetTester tester,
  ) async {
    // With nothing streaming there is nothing to stop, and the sheets over
    // the conversation close on Escape — the composer must not swallow it.
    final ValueNotifier<bool> canSubmit = ValueNotifier<bool>(true);
    addTearDown(canSubmit.dispose);
    int stops = 0;
    await tester.pumpWidget(
      composer(canSubmit: canSubmit, onStop: () async => stops += 1),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(stops, 0);
  });
}
