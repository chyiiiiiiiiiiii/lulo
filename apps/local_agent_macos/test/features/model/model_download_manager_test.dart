import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/model/model_catalog.dart';
import 'package:local_agent_macos/features/model/model_download_manager.dart';
import 'package:local_agent_macos/features/model/model_file_service.dart';

void main() {
  late Directory modelsDirectory;

  setUp(() {
    modelsDirectory = Directory.systemTemp.createTempSync('lulo-manager-test');
  });

  tearDown(() {
    if (modelsDirectory.existsSync()) {
      modelsDirectory.deleteSync(recursive: true);
    }
  });

  const ModelCatalogEntry entry = ModelCatalogEntry(
    id: 'test-model',
    name: 'A test model',
    description: 'Small enough to hold in one hand.',
    fileName: 'test-model.litertlm',
    url: 'https://example.invalid/test-model.litertlm',
    sizeBytes: 4,
  );

  test('a model arrives through downloading and settles installed', () async {
    final StreamController<List<int>> bytes = StreamController<List<int>>();
    int fetches = 0;
    final ModelDownloadManager manager = ModelDownloadManager(
      files: ModelFileService(
        modelsDirectory: modelsDirectory,
        fetch: (Uri url) async {
          fetches += 1;
          return ModelBytes(totalBytes: 4, stream: bytes.stream);
        },
      ),
    );
    addTearDown(manager.dispose);
    int told = 0;
    manager.addListener(() => told += 1);

    expect(manager.stateOf(entry), ModelInstallState.notInstalled);

    final Future<File> installed = manager.download(entry);
    final Future<File> again = manager.download(entry);
    await Future<void>.delayed(Duration.zero);
    expect(manager.stateOf(entry), ModelInstallState.downloading);

    bytes.add(<int>[1, 2]);
    await Future<void>.delayed(Duration.zero);
    expect(manager.progressOf(entry)?.receivedBytes, 2);

    bytes.add(<int>[3, 4]);
    await bytes.close();
    expect((await installed).path, (await again).path);
    expect(fetches, 1, reason: 'Asking twice must not download twice.');
    expect(manager.stateOf(entry), ModelInstallState.installed);
    expect(told, greaterThanOrEqualTo(3));
  });

  test('a failed download stands back up as not installed', () async {
    final ModelDownloadManager manager = ModelDownloadManager(
      files: ModelFileService(
        modelsDirectory: modelsDirectory,
        fetch: (Uri url) async =>
            throw const SocketException('no network today'),
      ),
    );
    addTearDown(manager.dispose);

    await expectLater(manager.download(entry), throwsA(isA<SocketException>()));

    expect(manager.stateOf(entry), ModelInstallState.notInstalled);
  });

  test('what is already on disk is simply installed', () async {
    File(
      '${modelsDirectory.path}/${entry.fileName}',
    ).writeAsBytesSync(<int>[1, 2, 3, 4]);
    final ModelDownloadManager manager = ModelDownloadManager(
      files: ModelFileService(
        modelsDirectory: modelsDirectory,
        fetch: (Uri url) async => throw StateError('nothing to fetch'),
      ),
    );
    addTearDown(manager.dispose);

    expect(manager.stateOf(entry), ModelInstallState.installed);
    expect(manager.installedFileOf(entry)?.path, endsWith(entry.fileName));
  });
}
