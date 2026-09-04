import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';
import 'package:local_agent_macos/features/model/model_catalog.dart';
import 'package:local_agent_macos/features/model/model_download_manager.dart';
import 'package:local_agent_macos/features/model/model_file_service.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/features/settings/settings_sheet.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  final ModelDownloadManager downloads = ModelDownloadManager(
    files: ModelFileService(
      modelsDirectory: Directory('${Directory.systemTemp.path}/lulo-unused'),
      fetch: (Uri url) async => throw StateError('not in this test'),
    ),
  );
  tearDownAll(downloads.dispose);

  Widget sheet({
    required VoidCallback onClose,
    ValueChanged<AppSettings>? onChanged,
    Locale? locale,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: SettingsSheet(
      agentProfile: InMemoryAgentProfileStore(),
      settings: const AppSettings(),
      onChanged: onChanged ?? (AppSettings _) {},
      onChooseModel: () async => '',
      onClose: onClose,
      modelDownloads: downloads,
      onDownloadModel: (ModelCatalogEntry _) {},
      onUseModel: (ModelCatalogEntry _) {},
    ),
  );

  testWidgets('escape puts the settings away', (WidgetTester tester) async {
    // The sheet sits over the conversation and Esc is how a Mac user backs
    // out of anything transient. Without it the only way out is hunting for
    // the close button.
    int closed = 0;
    await tester.pumpWidget(sheet(onClose: () => closed += 1));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closed, 1, reason: 'Escape did not close the settings.');
  });

  testWidgets('the settings title sits on the content grid', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(sheet(onClose: () {}));
    await tester.pump();

    // Same grid as the conversation: the window buttons live on the line
    // above, so the title has nothing to clear and sits at the content
    // margin.
    expect(tester.getTopLeft(find.text('Settings')).dx, 24);
  });

  testWidgets('the settings say which way in hears which language', (
    WidgetTester tester,
  ) async {
    // Two of the three ways in hear English and the always-listening one
    // pins a locale for the whole session. Nothing on screen said so, which
    // left "it did not understand me" looking like a broken agent rather
    // than the wrong button.
    await tester.pumpWidget(sheet(onClose: () {}));
    await tester.pump();

    await tester.dragUntilVisible(
      find.byKey(const Key('setting-hearing-duplex')),
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setting-hearing-hold')), findsOneWidget);
    expect(find.byKey(const Key('setting-hearing-duplex')), findsOneWidget);
  });

  testWidgets('the conversation language is a choice, English by default', (
    WidgetTester tester,
  ) async {
    // The agent speaks English out of the box because that is the half
    // that is measured good: the voice renders English word-perfect back
    // through a recogniser, where Chinese needed 214 respellings before
    // ordinary words came out right. Chinese is one tap away and stays a
    // first-class language — this is which one the app opens in.
    AppSettings? changed;
    await tester.pumpWidget(
      sheet(onClose: () {}, onChanged: (AppSettings value) => changed = value),
    );
    await tester.pump();

    await tester.dragUntilVisible(
      find.byKey(const Key('setting-conversation-language')),
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-conversation-language-chinese')),
    );
    await tester.pump();

    expect(changed?.conversationLanguage, AgentLanguage.chinese);
  });

  testWidgets('the hearing notes say what is true now and where the cure is', (
    WidgetTester tester,
  ) async {
    // Two separate defects in one paragraph. The always-listening note said
    // the recogniser uses "the first of your preferred languages", which
    // stopped being true the moment the language became a setting — a
    // user-facing sentence that describes the old behaviour is worse than no
    // sentence. And the hold note named the failure it makes (product names
    // that are also ordinary words) without ever saying that the app can be
    // taught them, which is the one thing that fixes it.
    await tester.pumpWidget(sheet(onClose: () {}, locale: const Locale('en')));
    await tester.pump();

    await tester.dragUntilVisible(
      find.byKey(const Key('setting-hearing-duplex')),
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    final String duplex = tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(const Key('setting-hearing-duplex')),
                matching: find.byType(Text),
              )
              .last,
        )
        .data!;
    expect(
      duplex,
      isNot(contains('preferred languages')),
      reason: 'The note still describes the behaviour this replaced.',
    );
    expect(duplex, contains('setting'));

    final String hold = tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(const Key('setting-hearing-hold')),
                matching: find.byType(Text),
              )
              .last,
        )
        .data!;
    expect(
      hold.toLowerCase(),
      contains('teach'),
      reason: 'The note names the defect and not the cure for it.',
    );
  });

  testWidgets('sharing the frontmost app is a switch the user flips', (
    WidgetTester tester,
  ) async {
    AppSettings? changed;
    await tester.pumpWidget(
      sheet(onClose: () {}, onChanged: (AppSettings value) => changed = value),
    );
    await tester.pump();

    await tester.dragUntilVisible(
      find.byKey(const Key('setting-share-frontmost-app')),
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-share-frontmost-app')));

    expect(changed?.shareFrontmostApp, isTrue);
  });

  testWidgets('the always-listening path admits its English on screen', (
    WidgetTester tester,
  ) async {
    // Holding the key was measured at 3.8% character error in English and
    // the always-listening path at 13.4% — the same app, and nothing on
    // screen said so. The note carries the numbers so "it misheard me"
    // can be answered with "use the other button".
    await tester.pumpWidget(sheet(onClose: () {}, locale: const Locale('en')));
    await tester.pump();

    await tester.dragUntilVisible(
      find.byKey(const Key('setting-hearing-duplex')),
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('13.4%'),
      findsOneWidget,
      reason: 'The measured gap belongs on screen, not only in a doc.',
    );
  });

  testWidgets('the answer style is three named choices, not a number', (
    WidgetTester tester,
  ) async {
    // temperature is a number nobody outside the model has the information
    // to choose. What a user knows is whether they want the same answer
    // twice or a different one.
    AppSettings settings = const AppSettings();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsSheet(
          agentProfile: InMemoryAgentProfileStore(),
          settings: settings,
          onChanged: (AppSettings next) => settings = next,
          onChooseModel: () async => '',
          onClose: () {},
          modelDownloads: downloads,
          onDownloadModel: (ModelCatalogEntry _) {},
          onUseModel: (ModelCatalogEntry _) {},
        ),
      ),
    );
    await tester.pump();
    expect(settings.answerStyle, AnswerStyle.balanced);

    await tester.dragUntilVisible(
      find.byKey(const Key('setting-answer-style-inventive')),
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-answer-style-inventive')));
    await tester.pump();

    expect(settings.answerStyle, AnswerStyle.inventive);
  });
}
