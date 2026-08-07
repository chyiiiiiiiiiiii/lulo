import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';
import 'package:local_agent_macos/features/settings/agent_profile_settings.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

/// The interface speaks whatever the Mac speaks.
///
/// Before this the conversation was in Chinese and the settings sheet was in
/// English, which is not a language — it is two halves of an app written by
/// whoever happened to be typing. The choice belongs to the system, not to
/// the source file.
void main() {
  Future<void> pumpIn(WidgetTester tester, Locale? locale) async {
    final InMemoryAgentProfileStore store = InMemoryAgentProfileStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: ListView(
            children: <Widget>[AgentProfileSettings(store: store)],
          ),
        ),
      ),
    );
  }

  testWidgets('a Mac set to Chinese gets a Chinese interface', (
    WidgetTester tester,
  ) async {
    await pumpIn(tester, const Locale('zh'));

    expect(find.text('它是誰'), findsOneWidget);
    expect(find.text('Who it is'), findsNothing);
  });

  testWidgets('a Mac set to Traditional Chinese gets the same', (
    WidgetTester tester,
  ) async {
    // What macOS actually reports for a Taiwanese user is zh-Hant-TW, not a
    // bare zh, and a supported-locale list that only matched the bare code
    // would leave this user in English on their own machine.
    await pumpIn(
      tester,
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    );

    expect(find.text('它是誰'), findsOneWidget);
  });

  testWidgets('a Mac set to English gets an English interface', (
    WidgetTester tester,
  ) async {
    await pumpIn(tester, const Locale('en'));

    expect(find.text('Who it is'), findsOneWidget);
    expect(find.text('它是誰'), findsNothing);
  });

  testWidgets('a language nobody wrote falls back rather than breaking', (
    WidgetTester tester,
  ) async {
    await pumpIn(tester, const Locale('fi'));

    expect(find.text('Who it is'), findsOneWidget);
  });

  test('both languages are offered, Chinese by script', () {
    // zh-Hant has to be in the list, not just zh. The resolved locale is what
    // picks the CJK font, and a bare zh renders Simplified punctuation: a
    // centred 「，」 with a gap after it rather than one at the baseline.
    expect(
      AppLocalizations.supportedLocales,
      containsAll(<Locale>[
        const Locale('en'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]),
    );
  });
}
