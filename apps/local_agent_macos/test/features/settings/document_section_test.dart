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

  Widget sheet({
    required Future<String?> Function() open,
    required ValueNotifier<String?> name,
    VoidCallback? close,
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
      openDocument: open,
      closeDocument: close ?? () => name.value = null,
      openDocumentName: name,
    ),
  );

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  testWidgets('an open file is named, so the user knows it is being read', (
    WidgetTester tester,
  ) async {
    // Answers may now draw on a file. A user who cannot see which one has no
    // way to check the answer against it.
    final ValueNotifier<String?> name = ValueNotifier<String?>(null);
    addTearDown(name.dispose);
    await tester.pumpWidget(
      sheet(
        open: () async {
          name.value = '租約';
          return '租約';
        },
        name: name,
      ),
    );
    await tester.pump();

    await tap(tester, const Key('setting-document-choose'));

    expect(find.textContaining('租約'), findsOneWidget);
  });

  testWidgets('it can be closed again', (WidgetTester tester) async {
    final ValueNotifier<String?> name = ValueNotifier<String?>('租約');
    addTearDown(name.dispose);
    await tester.pumpWidget(sheet(open: () async => '租約', name: name));
    await tester.pump();

    await tap(tester, const Key('setting-document-close'));

    expect(find.byKey(const Key('setting-document-choose')), findsOneWidget);
  });

  testWidgets('a file that cannot be read says so', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<String?> name = ValueNotifier<String?>(null);
    addTearDown(name.dispose);
    await tester.pumpWidget(sheet(open: () async => null, name: name));
    await tester.pump();

    await tap(tester, const Key('setting-document-choose'));

    expect(find.textContaining('could not be read'), findsOneWidget);
  });

  testWidgets('backing out of the panel is not a failure', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<String?> name = ValueNotifier<String?>(null);
    addTearDown(name.dispose);
    await tester.pumpWidget(sheet(open: () async => '', name: name));
    await tester.pump();

    await tap(tester, const Key('setting-document-choose'));

    expect(find.textContaining('could not be read'), findsNothing);
  });
}
