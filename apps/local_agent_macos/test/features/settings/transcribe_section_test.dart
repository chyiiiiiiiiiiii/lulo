import 'dart:io';

import 'package:flutter/material.dart';
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

  Widget sheet(
    Future<(TranscribeOutcome, String?)> Function() run, {
    Future<(TranscribeOutcome, String?)> Function()? saveHeld,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsSheet(
      agentProfile: InMemoryAgentProfileStore(),
      settings: const AppSettings(),
      onChanged: (AppSettings _) {},
      onChooseModel: () async => '',
      onClose: () {},
      modelDownloads: downloads,
      onDownloadModel: (ModelCatalogEntry _) {},
      onUseModel: (ModelCatalogEntry _) {},
      transcribeRecording: run,
      saveHeldTranscript:
          saveHeld ?? () async => (TranscribeOutcome.backedOut, null),
    ),
  );

  Future<void> tapChoose(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('setting-transcribe-choose')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('setting-transcribe-choose')));
    await tester.pump();
  }

  testWidgets('a written-out recording says where it went', (
    WidgetTester tester,
  ) async {
    // The recogniser is installed and tuned for this user's language, and
    // until now the only way to reach it was to hold a key at a live
    // microphone — a recording they already had could not use it.
    await tester.pumpWidget(
      sheet(() async => (TranscribeOutcome.saved, '課堂錄音.txt')),
    );
    await tester.pump();

    await tapChoose(tester);
    await tester.pump();

    expect(find.textContaining('課堂錄音.txt'), findsOneWidget);
  });

  testWidgets('nothing coming back points at the transcriber', (
    WidgetTester tester,
  ) async {
    // The commonest cause by far is the sidecar not running, and the
    // section next to this one names it.
    await tester.pumpWidget(
      sheet(() async => (TranscribeOutcome.failed, null)),
    );
    await tester.pump();

    await tapChoose(tester);
    await tester.pump();

    expect(find.textContaining('not running'), findsOneWidget);
  });

  testWidgets('backing out of the panel is not a failure', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      sheet(() async => (TranscribeOutcome.backedOut, null)),
    );
    await tester.pump();

    await tapChoose(tester);
    await tester.pump();

    expect(find.textContaining('Nothing came back'), findsNothing);
    expect(find.textContaining('Saved as'), findsNothing);
  });

  testWidgets('a thrown failure is reported rather than escaping', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      sheet(() async => throw StateError('the host is gone')),
    );
    await tester.pump();

    await tapChoose(tester);
    await tester.pump();

    expect(find.textContaining('Nothing came back'), findsOneWidget);
  });

  testWidgets('a surface with no recogniser shows no section', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsSheet(
          agentProfile: InMemoryAgentProfileStore(),
          settings: const AppSettings(),
          onChanged: (AppSettings _) {},
          onChooseModel: () async => '',
          onClose: () {},
          modelDownloads: downloads,
          onDownloadModel: (ModelCatalogEntry _) {},
          onUseModel: (ModelCatalogEntry _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('setting-transcribe')), findsNothing);
  });

  testWidgets('a cancelled save keeps the transcript and offers it again', (
    WidgetTester tester,
  ) async {
    // Ten minutes of the recogniser's work must not disappear because
    // somebody changed their mind about a folder. Saving again rather than
    // transcribing again: the text is already in hand.
    int transcriptions = 0;
    int saves = 0;
    await tester.pumpWidget(
      sheet(
        () async {
          transcriptions += 1;
          return (TranscribeOutcome.heldUnsaved, null);
        },
        saveHeld: () async {
          saves += 1;
          return (TranscribeOutcome.saved, '課堂錄音.txt');
        },
      ),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('setting-transcribe-choose')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('setting-transcribe-choose')));
    await tester.pump();

    expect(find.textContaining('not saved'), findsOneWidget);

    await tester.tap(find.byKey(const Key('setting-transcribe-save-again')));
    await tester.pump();

    expect(saves, 1);
    expect(
      transcriptions,
      1,
      reason: 'saving again must not ask the recogniser to redo the work',
    );
    expect(find.textContaining('課堂錄音.txt'), findsOneWidget);
  });
}
