import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

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

  test('every catalog entry pins its checksum', () {
    // Fixtures may skip the pin; the models the app really offers may not.
    for (final ModelCatalogEntry entry in modelCatalog) {
      expect(
        entry.sha256,
        isNotNull,
        reason: '${entry.id} offers a download it cannot verify.',
      );
      expect(entry.sha256, hasLength(64));
    }
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

  test('a death mid-stream leaves the working file for next time', () async {
    // 3.4 GB on a flaky network: what has already arrived is worth keeping.
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

    final File working = File('${modelsDirectory.path}/${entry.fileName}.part');
    expect(working.existsSync(), isTrue);
    expect(working.lengthSync(), 4);
    expect(
      File('${modelsDirectory.path}/${entry.fileName}').existsSync(),
      isFalse,
      reason: 'A broken download must never look like a model.',
    );
  });

  test('a download picks up where the last one fell over', () async {
    final List<int> whole = List<int>.generate(10, (int i) => i);
    final ModelCatalogEntry pinned = ModelCatalogEntry(
      id: 'test-model',
      name: 'A test model',
      description: 'Small enough to hold in one hand.',
      fileName: 'test-model.litertlm',
      url: 'https://example.invalid/test-model.litertlm',
      sizeBytes: 10,
      sha256: sha256.convert(whole).toString(),
    );
    File(
      '${modelsDirectory.path}/${pinned.fileName}.part',
    ).writeAsBytesSync(whole.sublist(0, 4));
    final List<int> resumedFrom = <int>[];
    final ModelFileService files = ModelFileService(
      modelsDirectory: modelsDirectory,
      fetch: (Uri url) async =>
          throw StateError('a resume must not start over'),
      fetchFrom: (Uri url, int start) async {
        resumedFrom.add(start);
        return ModelBytes(
          totalBytes: 10 - start,
          stream: Stream<List<int>>.value(whole.sublist(start)),
        );
      },
    );

    final List<ModelDownloadProgress> progress = await files
        .download(pinned)
        .toList();

    expect(resumedFrom, <int>[4]);
    expect(progress.last.receivedBytes, 10);
    expect(progress.last.totalBytes, 10);
    expect(files.isInstalled(pinned), isTrue);
    expect(
      File('${modelsDirectory.path}/${pinned.fileName}').readAsBytesSync(),
      whole,
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

  test('a download that disagrees with the catalog is refused', () async {
    // The upstream repo can be re-uploaded at a different size. Accepting it
    // would load a model the catalog no longer describes, and isInstalled
    // would call it not-installed forever — an endless Download button over
    // a model that is already answering.
    Future<ModelBytes> fetch(Uri url) async => ModelBytes(
      totalBytes: 4,
      stream: Stream<List<int>>.value(<int>[1, 2, 3, 4]),
    );

    await expectLater(
      service(fetch)
          .download(
            const ModelCatalogEntry(
              id: 'test-model',
              name: 'A test model',
              description: 'Small enough to hold in one hand.',
              fileName: 'test-model.litertlm',
              url: 'https://example.invalid/test-model.litertlm',
              sizeBytes: 10,
            ),
          )
          .toList(),
      throwsA(isA<StateError>()),
    );
    expect(modelsDirectory.listSync(), isEmpty);
  });

  test('a download whose bytes are not the catalog'
      's is refused', () async {
    // Right length, wrong content: a tampered or corrupted file must not
    // become a model, no matter how politely it arrived.
    Future<ModelBytes> fetch(Uri url) async => ModelBytes(
      totalBytes: 10,
      stream: Stream<List<int>>.value(
        List<int>.generate(10, (int i) => 99 - i),
      ),
    );

    await expectLater(
      service(fetch)
          .download(
            ModelCatalogEntry(
              id: 'test-model',
              name: 'A test model',
              description: 'Small enough to hold in one hand.',
              fileName: 'test-model.litertlm',
              url: 'https://example.invalid/test-model.litertlm',
              sizeBytes: 10,
              sha256: sha256
                  .convert(List<int>.generate(10, (int i) => i))
                  .toString(),
            ),
          )
          .toList(),
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
