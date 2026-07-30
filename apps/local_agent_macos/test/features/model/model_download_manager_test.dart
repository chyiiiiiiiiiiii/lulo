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

  test('progress is told in steps, not per network chunk', () async {
    // A 3.6 GB download arrives in ~55k chunks. Notifying for each one
    // rebuilds the settings sheet hundreds of times a second on the UI
    // isolate, in a repo whose guardrail is p99 build ≤ 12 ms.
    const ModelCatalogEntry chunky = ModelCatalogEntry(
      id: 'chunky-model',
      name: 'A chunky model',
      description: 'Arrives in many pieces.',
      fileName: 'chunky-model.litertlm',
      url: 'https://example.invalid/chunky-model.litertlm',
      sizeBytes: 400,
    );
    final ModelDownloadManager manager = ModelDownloadManager(
      files: ModelFileService(
        modelsDirectory: modelsDirectory,
        fetch: (Uri url) async => ModelBytes(
          totalBytes: 400,
          stream: Stream<List<int>>.fromIterable(
            List<List<int>>.generate(400, (int _) => <int>[0]),
          ),
        ),
      ),
    );
    addTearDown(manager.dispose);
    int told = 0;
    manager.addListener(() => told += 1);

    await manager.download(chunky);

    expect(
      told,
      lessThanOrEqualTo(110),
      reason: 'One notification per network chunk floods the UI isolate.',
    );
  });

  test('a manager disposed mid-download says nothing more', () async {
    final StreamController<List<int>> bytes = StreamController<List<int>>();
    final ModelDownloadManager manager = ModelDownloadManager(
      files: ModelFileService(
        modelsDirectory: modelsDirectory,
        fetch: (Uri url) async =>
            ModelBytes(totalBytes: 4, stream: bytes.stream),
      ),
    );

    final Future<File> arriving = manager.download(entry);
    bytes.add(<int>[1, 2]);
    await Future<void>.delayed(Duration.zero);

    manager.dispose();
    // The bytes keep landing after teardown; a notifyListeners now would
    // throw on a disposed ChangeNotifier.
    bytes.add(<int>[3, 4]);
    await bytes.close();
    await arriving;
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
