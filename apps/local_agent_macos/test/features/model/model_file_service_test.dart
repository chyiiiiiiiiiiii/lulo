import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/model/model_catalog.dart';
import 'package:local_agent_macos/features/model/model_file_service.dart';

void main() {
  late Directory modelsDirectory;

  setUp(() {
    modelsDirectory = Directory.systemTemp.createTempSync('lulo-models-test');
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
    sizeBytes: 10,
  );

  ModelFileService service(ModelByteFetcher fetch) =>
      ModelFileService(modelsDirectory: modelsDirectory, fetch: fetch);

  test('the catalog leads with the recommended model', () {
    // What "default" means in practice: the first thing offered.
    expect(modelCatalog.first.recommended, isTrue);
    expect(modelCatalog.first.id, 'gemma-4-E4B-it');
    expect(
      modelCatalog.map((ModelCatalogEntry entry) => entry.recommended),
      <bool>[true, false],
    );
  });

  test(
    'a download arrives whole, with its progress told along the way',
    () async {
      Future<ModelBytes> fetch(Uri url) async => ModelBytes(
        totalBytes: 10,
        stream: Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2, 3, 4],
          <int>[5, 6, 7, 8],
          <int>[9, 10],
        ]),
      );

      final List<ModelDownloadProgress> progress = await service(
        fetch,
      ).download(entry).toList();

      expect(progress.map((ModelDownloadProgress p) => p.receivedBytes), <int>[
        4,
        8,
        10,
      ]);
      expect(progress.last.totalBytes, 10);
      final File installed = File('${modelsDirectory.path}/${entry.fileName}');
      expect(installed.existsSync(), isTrue);
      expect(installed.lengthSync(), 10);
      expect(
        modelsDirectory
            .listSync()
            .map((FileSystemEntity e) => e.path)
            .where((String path) => path.endsWith('.part')),
        isEmpty,
        reason: 'The working file must not survive a finished download.',
      );
    },
  );

  test('a download that dies mid-stream leaves nothing behind', () async {
    Future<ModelBytes> fetch(Uri url) async => ModelBytes(
      totalBytes: 10,
      stream: () async* {
        yield <int>[1, 2, 3, 4];
        throw const SocketException('the connection fell over');
      }(),
    );

    await expectLater(
      service(fetch).download(entry).toList(),
      throwsA(isA<SocketException>()),
    );

    expect(
      modelsDirectory.listSync(),
      isEmpty,
      reason: 'A failed download must not leave part-files or a broken model.',
    );
  });

  test('a download that comes up short is an error, not a model', () async {
    // A truncated stream that ends politely is the dangerous case: every
    // byte arrived without an exception, but the model is incomplete.
    Future<ModelBytes> fetch(Uri url) async => ModelBytes(
      totalBytes: 10,
      stream: Stream<List<int>>.value(<int>[1, 2, 3, 4]),
    );

    await expectLater(
      service(fetch).download(entry).toList(),
      throwsA(isA<StateError>()),
    );
    expect(modelsDirectory.listSync(), isEmpty);
  });

  test('what is installed can be asked for by entry', () async {
    Future<ModelBytes> fetch(Uri url) async => ModelBytes(
      totalBytes: 10,
      stream: Stream<List<int>>.value(List<int>.generate(10, (int i) => i)),
    );
    final ModelFileService files = service(fetch);
    expect(files.isInstalled(entry), isFalse);

    await files.download(entry).drain<void>();

    expect(files.isInstalled(entry), isTrue);
    expect(files.fileFor(entry).path, endsWith('test-model.litertlm'));
  });
}
