import 'dart:async';
import 'dart:io';

import 'model_catalog.dart';

/// A model's bytes on their way in: how many there will be, and the stream.
final class ModelBytes {
  /// Describes one incoming download.
  const ModelBytes({required this.totalBytes, required this.stream});

  /// How many bytes the sender says are coming.
  final int totalBytes;

  /// The bytes themselves.
  final Stream<List<int>> stream;
}

/// Fetches the bytes behind [url].
///
/// The seam the tests stand behind; the default implementation speaks HTTPS.
typedef ModelByteFetcher = Future<ModelBytes> Function(Uri url);

/// How far along a download is.
final class ModelDownloadProgress {
  /// Describes one moment of one download.
  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// Bytes safely on disk so far.
  final int receivedBytes;

  /// Bytes the whole model is.
  final int totalBytes;

  /// The fraction done, between 0 and 1.
  double get fraction => totalBytes <= 0 ? 0 : receivedBytes / totalBytes;
}

/// Puts catalog models on disk and answers what is already there.
final class ModelFileService {
  /// Creates the service over [modelsDirectory], fetching with [fetch].
  ModelFileService({
    required Directory modelsDirectory,
    ModelByteFetcher? fetch,
  }) : this._(modelsDirectory, fetch ?? _fetchOverHttps);

  ModelFileService._(this._modelsDirectory, this._fetch);

  final Directory _modelsDirectory;
  final ModelByteFetcher _fetch;

  /// Where [entry] lives once installed.
  File fileFor(ModelCatalogEntry entry) =>
      File('${_modelsDirectory.path}/${entry.fileName}');

  /// Whether the whole of [entry] is already on disk.
  ///
  /// The whole of it: a size that disagrees with the catalog is a truncated
  /// copy from an interrupted past, not an installed model.
  bool isInstalled(ModelCatalogEntry entry) {
    final File file = fileFor(entry);
    return file.existsSync() && file.lengthSync() == entry.sizeBytes;
  }

  /// Downloads [entry], telling its progress as the bytes land.
  ///
  /// The bytes go into a working file beside the destination and are renamed
  /// into place only once every one of them has arrived, so a crash or a
  /// dropped connection can never leave behind something that looks like a
  /// model. A stream that ends early without an error is treated as the
  /// error it is.
  Stream<ModelDownloadProgress> download(ModelCatalogEntry entry) async* {
    _modelsDirectory.createSync(recursive: true);
    final File working = File('${fileFor(entry).path}.part');
    final IOSink sink = working.openWrite();
    int received = 0;
    try {
      final ModelBytes bytes = await _fetch(Uri.parse(entry.url));
      await for (final List<int> chunk in bytes.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield ModelDownloadProgress(
          receivedBytes: received,
          totalBytes: bytes.totalBytes,
        );
      }
      await sink.flush();
      await sink.close();
      if (received != bytes.totalBytes) {
        throw StateError(
          'The download ended after $received of ${bytes.totalBytes} bytes.',
        );
      }
      if (received != entry.sizeBytes) {
        // The sender was consistent with itself but not with the catalog:
        // the upstream file changed, or it is not the model at all. Loading
        // it would run a model the catalog no longer describes, and
        // isInstalled would call it not-installed forever.
        throw StateError(
          'The download is $received bytes where the catalog pins '
          '${entry.sizeBytes}.',
        );
      }
      working.renameSync(fileFor(entry).path);
    } on Object {
      // The close of a failed write can itself throw the buffered error;
      // swallowed here so the cleanup still runs and the first error is the
      // one the caller sees.
      try {
        await sink.close();
      } on Object {
        // Already failing; the original error is the story.
      }
      if (working.existsSync()) {
        working.deleteSync();
      }
      rethrow;
    }
  }

  /// The default fetcher: HTTPS with the sender's own length declaration.
  static Future<ModelBytes> _fetchOverHttps(Uri url) async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(url);
    request.followRedirects = true;
    request.maxRedirects = 10;
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      client.close(force: true);
      throw HttpException(
        'The model host answered ${response.statusCode}.',
        uri: url,
      );
    }
    // Piped through a controller rather than transformed in place: a
    // consumer that cancels mid-download fires neither done nor error, and
    // the client and its socket would outlive the download they carried.
    final StreamController<List<int>> bytes = StreamController<List<int>>();
    late final StreamSubscription<List<int>> forwarding;
    forwarding = response.listen(
      bytes.add,
      onError: (Object error, StackTrace stackTrace) {
        client.close(force: true);
        bytes.addError(error, stackTrace);
      },
      onDone: () {
        client.close();
        unawaited(bytes.close());
      },
    );
    bytes.onCancel = () async {
      await forwarding.cancel();
      client.close(force: true);
    };
    return ModelBytes(totalBytes: response.contentLength, stream: bytes.stream);
  }
}
