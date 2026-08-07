import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/model/model_catalog.dart';
import 'package:local_agent_macos/features/model/model_download_manager.dart';
import 'package:local_agent_macos/features/model/model_file_service.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

void main() {
  const ModelCatalogEntry small = ModelCatalogEntry(
    id: 'small-model',
    name: 'A small model',
    descriptionKey: ModelDescription.balanced,
    fileName: 'small-model.litertlm',
    url: 'https://example.invalid/small-model.litertlm',
    sizeBytes: 4,
    recommended: true,
  );

  late Directory modelsDirectory;

  setUp(() {
    modelsDirectory = Directory.systemTemp.createTempSync('lulo-default-test');
  });

  tearDown(() {
    if (modelsDirectory.existsSync()) {
      modelsDirectory.deleteSync(recursive: true);
    }
  });

  Future<({List<String> thoughtWith, SettingsStore store})> pumpApp(
    WidgetTester tester, {
    String storedModelPath = '',
  }) async {
    final List<String> thoughtWith = <String>[];
    final SettingsStore store = InMemorySettingsStore();
    await store.save(AppSettings(modelPath: storedModelPath));
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      settingsStore: store,
      changeModel: (String modelPath) async => thoughtWith.add(modelPath),
      modelDownloads: ModelDownloadManager(
        files: ModelFileService(
          modelsDirectory: modelsDirectory,
          fetch: (Uri url) async => throw StateError('not in this test'),
        ),
      ),
      catalog: const <ModelCatalogEntry>[small],
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();
    return (thoughtWith: thoughtWith, store: store);
  }

  testWidgets('a launch with no chosen model adopts the recommended one', (
    WidgetTester tester,
  ) async {
    final File installed = File('${modelsDirectory.path}/${small.fileName}')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);

    final ({List<String> thoughtWith, SettingsStore store}) app = await pumpApp(
      tester,
    );

    expect(app.thoughtWith, <String>[installed.path]);
    expect((await app.store.load()).modelPath, installed.path);
  });

  testWidgets('a launch with nothing installed keeps the preview', (
    WidgetTester tester,
  ) async {
    final ({List<String> thoughtWith, SettingsStore store}) app = await pumpApp(
      tester,
    );

    expect(app.thoughtWith, isEmpty);
    expect((await app.store.load()).modelPath, isEmpty);
  });

  testWidgets('a model the user already chose is left alone', (
    WidgetTester tester,
  ) async {
    File(
      '${modelsDirectory.path}/${small.fileName}',
    ).writeAsBytesSync(<int>[1, 2, 3, 4]);

    final ({List<String> thoughtWith, SettingsStore store}) app = await pumpApp(
      tester,
      storedModelPath: '/their/own/model.litertlm',
    );

    expect(app.thoughtWith, isEmpty);
    expect((await app.store.load()).modelPath, '/their/own/model.litertlm');
  });
}
