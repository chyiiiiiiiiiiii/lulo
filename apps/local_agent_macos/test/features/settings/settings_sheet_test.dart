import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/model/model_catalog.dart';
import 'package:local_agent_macos/features/model/model_download_manager.dart';
import 'package:local_agent_macos/features/model/model_file_service.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/features/settings/settings_sheet.dart';

void main() {
  final ModelDownloadManager downloads = ModelDownloadManager(
    files: ModelFileService(
      modelsDirectory: Directory('${Directory.systemTemp.path}/lulo-unused'),
      fetch: (Uri url) async => throw StateError('not in this test'),
    ),
  );
  tearDownAll(downloads.dispose);

  Widget sheet({required VoidCallback onClose}) => MaterialApp(
    home: SettingsSheet(
      settings: const AppSettings(),
      onChanged: (AppSettings _) {},
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
}
