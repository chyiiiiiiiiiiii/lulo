import 'dart:async';
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
  late Directory modelsDirectory;

  setUp(() {
    modelsDirectory = Directory.systemTemp.createTempSync('lulo-rows-test');
  });

  tearDown(() {
    if (modelsDirectory.existsSync()) {
      modelsDirectory.deleteSync(recursive: true);
    }
  });

  const ModelCatalogEntry small = ModelCatalogEntry(
    id: 'small-model',
    name: 'A small model',
    descriptionKey: ModelDescription.balanced,
    fileName: 'small-model.litertlm',
    url: 'https://example.invalid/small-model.litertlm',
    sizeBytes: 4,
  );

  ModelDownloadManager manager({ModelByteFetcher? fetch}) =>
      ModelDownloadManager(
        files: ModelFileService(
          modelsDirectory: modelsDirectory,
          fetch:
              fetch ?? (Uri url) async => throw StateError('not in this test'),
        ),
      );

  Widget sheet({
    required ModelDownloadManager modelDownloads,
    AppSettings settings = const AppSettings(),
    ValueChanged<ModelCatalogEntry>? onDownloadModel,
    ValueChanged<ModelCatalogEntry>? onUseModel,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsSheet(
      agentProfile: InMemoryAgentProfileStore(),
      settings: settings,
      onChanged: (AppSettings _) {},
      onChooseModel: () async => '',
      onClose: () {},
      modelDownloads: modelDownloads,
      catalog: const <ModelCatalogEntry>[small],
      onDownloadModel: onDownloadModel ?? (ModelCatalogEntry _) {},
      onUseModel: onUseModel ?? (ModelCatalogEntry _) {},
    ),
  );

  testWidgets('the voice it speaks with can be chosen', (
    WidgetTester tester,
  ) async {
    final ModelDownloadManager downloads = manager();
    addTearDown(downloads.dispose);
    final List<AppSettings> changed = <AppSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsSheet(
          agentProfile: InMemoryAgentProfileStore(),
          settings: const AppSettings(),
          onChanged: changed.add,
          onChooseModel: () async => '',
          onClose: () {},
          modelDownloads: downloads,
          catalog: const <ModelCatalogEntry>[small],
          onDownloadModel: (ModelCatalogEntry _) {},
          onUseModel: (ModelCatalogEntry _) {},
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('setting-tts-voice')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('setting-tts-voice-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vivian').last);
    await tester.pumpAndSettle();

    expect(changed.last.ttsVoice, 'vivian');
  });

  testWidgets('a model not yet here offers itself for download', (
    WidgetTester tester,
  ) async {
    final ModelDownloadManager downloads = manager();
    addTearDown(downloads.dispose);
    final List<ModelCatalogEntry> asked = <ModelCatalogEntry>[];
    await tester.pumpWidget(
      sheet(modelDownloads: downloads, onDownloadModel: asked.add),
    );
    await tester.pump();

    expect(find.text('A small model'), findsOneWidget);
    await tester.tap(find.byKey(const Key('model-download-small-model')));

    expect(asked.map((ModelCatalogEntry e) => e.id), <String>['small-model']);
  });

  testWidgets('a download shows how far along it is', (
    WidgetTester tester,
  ) async {
    final StreamController<List<int>> bytes = StreamController<List<int>>();
    final ModelDownloadManager downloads = manager(
      fetch: (Uri url) async => ModelBytes(totalBytes: 4, stream: bytes.stream),
    );
    addTearDown(downloads.dispose);
    await tester.pumpWidget(sheet(modelDownloads: downloads));
    await tester.pump();

    // The download writes real files, which a widget test's fake clock never
    // lets finish; runAsync lets the real world turn while the sheet watches.
    final Future<File> arriving = (await tester.runAsync<Future<File>>(
      () async {
        final Future<File> arriving = downloads.download(small);
        bytes.add(<int>[1, 2]);
        await Future<void>.delayed(Duration.zero);
        return arriving;
      },
    ))!;
    await tester.pump();

    final ProgressIndicator progress = tester.widget(
      find.byKey(const Key('model-progress-small-model')),
    );
    expect((progress as LinearProgressIndicator).value, 0.5);

    await tester.runAsync(() async {
      bytes.add(<int>[3, 4]);
      await bytes.close();
      await arriving;
    });
    await tester.pump();
    expect(find.byKey(const Key('model-progress-small-model')), findsNothing);
  });

  testWidgets('a failed download owns up and offers a retry', (
    WidgetTester tester,
  ) async {
    final ModelDownloadManager downloads = manager(
      fetch: (Uri url) async => throw const SocketException('no network'),
    );
    addTearDown(downloads.dispose);
    await tester.pumpWidget(sheet(modelDownloads: downloads));
    await tester.pump();

    await tester.runAsync(() async {
      try {
        await downloads.download(small);
      } on Object {
        // The failure itself is the scenario.
      }
    });
    await tester.pump();

    expect(find.byKey(const Key('model-failure-small-model')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('an installed model is one press from being thought with', (
    WidgetTester tester,
  ) async {
    File(
      '${modelsDirectory.path}/${small.fileName}',
    ).writeAsBytesSync(<int>[1, 2, 3, 4]);
    final ModelDownloadManager downloads = manager();
    addTearDown(downloads.dispose);
    final List<ModelCatalogEntry> used = <ModelCatalogEntry>[];
    await tester.pumpWidget(
      sheet(modelDownloads: downloads, onUseModel: used.add),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('model-use-small-model')));

    expect(used.map((ModelCatalogEntry e) => e.id), <String>['small-model']);
  });

  testWidgets('the model being thought with says so instead of offering', (
    WidgetTester tester,
  ) async {
    final File installed = File('${modelsDirectory.path}/${small.fileName}')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final ModelDownloadManager downloads = manager();
    addTearDown(downloads.dispose);
    await tester.pumpWidget(
      sheet(
        modelDownloads: downloads,
        settings: AppSettings(modelPath: installed.path),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('model-active-small-model')), findsOneWidget);
    expect(find.byKey(const Key('model-use-small-model')), findsNothing);
  });
}
