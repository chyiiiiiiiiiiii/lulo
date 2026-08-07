import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/model/first_run.dart';
import 'package:local_agent_macos/features/model/model_catalog.dart';
import 'package:local_agent_macos/features/model/model_download_manager.dart';
import 'package:local_agent_macos/features/model/model_file_service.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

/// The first launch, which until now was the app pretending to work.
///
/// With no model installed Lulo answers from a built-in preview that says the
/// same thing every time, and the way to fix that was three sections down a
/// settings sheet the user had no reason to open. A first launch has exactly
/// one thing to do, and this is it.
void main() {
  late Directory directory;
  late ModelDownloadManager downloads;
  late Completer<Never> never;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('lulo-first-run-');
    never = Completer<Never>();
    downloads = ModelDownloadManager(
      files: ModelFileService(
        modelsDirectory: directory,
        fetch: (Uri url) => never.future,
      ),
    );
  });

  tearDown(() {
    downloads.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<int> pump(
    WidgetTester tester, {
    VoidCallback? onDownload,
    VoidCallback? onDismiss,
  }) async {
    int downloaded = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FirstRun(
          downloads: downloads,
          entry: recommendedModel,
          onDownload: () {
            downloaded += 1;
            onDownload?.call();
          },
          onDismiss: onDismiss ?? () {},
        ),
      ),
    );
    return downloaded;
  }

  testWidgets('it names the one thing the app still needs', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const Key('first-run')), findsOneWidget);
    expect(find.textContaining(recommendedModel.name), findsOneWidget);
    // The size is the part that decides whether now is a good moment.
    expect(find.textContaining('GB'), findsOneWidget);
  });

  testWidgets('the one button starts the download', (
    WidgetTester tester,
  ) async {
    int downloaded = 0;
    await pump(tester, onDownload: () => downloaded += 1);

    await tester.tap(find.byKey(const Key('first-run-download')));
    await tester.pump();

    expect(downloaded, 1);
  });

  testWidgets('a download in flight replaces the button with its progress', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    unawaited(downloads.download(recommendedModel));
    await tester.pump();

    expect(find.byKey(const Key('first-run-progress')), findsOneWidget);
    expect(
      find.byKey(const Key('first-run-download')),
      findsNothing,
      reason: 'the download could be started a second time on top of itself',
    );
  });

  testWidgets('a download that did not finish says so and can be retried', (
    WidgetTester tester,
  ) async {
    final ModelDownloadManager failing = ModelDownloadManager(
      files: ModelFileService(
        modelsDirectory: directory,
        fetch: (Uri url) async => throw const SocketException('no route'),
      ),
    );
    addTearDown(failing.dispose);
    // Run for real: the file service touches the disk on its way to failing,
    // and a pumped clock does not let real I/O finish.
    await tester.runAsync(() async {
      try {
        await failing.download(recommendedModel);
      } on Object {
        // The failure is the point; the manager records it.
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FirstRun(
          downloads: failing,
          entry: recommendedModel,
          onDownload: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('first-run-failure')), findsOneWidget);
    expect(
      find.byKey(const Key('first-run-download')),
      findsOneWidget,
      reason: 'a failed download left the user with nothing to press',
    );
  });

  testWidgets('the user can decline and look around', (
    WidgetTester tester,
  ) async {
    int dismissed = 0;
    await pump(tester, onDismiss: () => dismissed += 1);

    await tester.tap(find.byKey(const Key('first-run-dismiss')));
    await tester.pump();

    expect(dismissed, 1);
  });
}
