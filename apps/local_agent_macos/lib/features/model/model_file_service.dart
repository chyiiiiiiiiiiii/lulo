import 'dart:async';
import 'dart:convert' show ByteConversionSink;
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

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

/// Fetches the bytes behind [url] from byte [start] onward.
///
/// For picking a dropped download back up; the returned stream carries only
/// the remaining bytes.
typedef ModelRangeFetcher = Future<ModelBytes> Function(Uri url, int start);

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
  ///
  /// [fetchFrom] resumes a dropped download from its working file; leaving it
  /// out starts every download from the beginning.
  ModelFileService({
    required Directory modelsDirectory,
    ModelByteFetcher? fetch,
    ModelRangeFetcher? fetchFrom,
  }) : this._(
         modelsDirectory,
         fetch ?? _fetchOverHttps,
         fetchFrom ?? (fetch == null ? _fetchOverHttpsFrom : null),
       );

  ModelFileService._(this._modelsDirectory, this._fetch, this._fetchFrom);

  final Directory _modelsDirectory;
  final ModelByteFetcher _fetch;
  final ModelRangeFetcher? _fetchFrom;

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
    // What a dropped attempt already brought home is picked back up rather
    // than fetched again — gigabytes on a flaky network are worth keeping.
    // Anything longer than the whole model is a corrupt past, not progress.
    int already = working.existsSync() ? working.lengthSync() : 0;
    final ModelRangeFetcher? fetchFrom = _fetchFrom;
    if (already > entry.sizeBytes || fetchFrom == null || already == 0) {
      already = 0;
    }
    final IOSink sink = working.openWrite(
      mode: already > 0 ? FileMode.append : FileMode.write,
    );
    int received = already;
    // Hashed as it streams, so verification costs no second pass over
    // gigabytes once the last byte lands. A resumed attempt hashes the kept
    // bytes first, so the pin still covers the whole file.
    final AccumulatorSink<Digest> digestSink = AccumulatorSink<Digest>();
    final ByteConversionSink hashing = sha256.startChunkedConversion(
      digestSink,
    );
    try {
      if (already > 0) {
        await for (final List<int> kept in working.openRead(0, already)) {
          hashing.add(kept);
        }
      }
      final ModelBytes bytes = (already > 0 && fetchFrom != null)
          ? await fetchFrom(Uri.parse(entry.url), already)
          : await _fetch(Uri.parse(entry.url));
      final int expectedTotal = already + bytes.totalBytes;
      await for (final List<int> chunk in bytes.stream) {
        sink.add(chunk);
        hashing.add(chunk);
        received += chunk.length;
        yield ModelDownloadProgress(
          receivedBytes: received,
          totalBytes: expectedTotal,
        );
      }
      await sink.flush();
      await sink.close();
      if (received != expectedTotal) {
        throw StateError(
          'The download ended after $received of $expectedTotal bytes.',
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
      hashing.close();
      final String arrived = digestSink.events.single.toString();
      final String? pinned = entry.sha256;
      if (pinned != null && arrived != pinned) {
        throw StateError(
          'The download hashes to $arrived where the catalog pins $pinned.',
        );
      }
      working.renameSync(fileFor(entry).path);
    } on Object catch (error) {
      // The close of a failed write can itself throw the buffered error;
      // swallowed here so the cleanup still runs and the first error is the
      // one the caller sees.
      try {
        await sink.close();
      } on Object {
        // Already failing; the original error is the story.
      }
      // A connection that fell over leaves its progress for next time; a
      // file the catalog disowns is deleted, or every retry would refuse
      // the same corrupt bytes forever.
      if (error is StateError && working.existsSync()) {
        working.deleteSync();
      }
      rethrow;
    }
  }

  /// The default resume fetcher: HTTPS with a Range header.
  static Future<ModelBytes> _fetchOverHttpsFrom(Uri url, int start) =>
      _fetchHttps(url, start: start);

  /// The default fetcher: HTTPS with the sender's own length declaration.
  static Future<ModelBytes> _fetchOverHttps(Uri url) => _fetchHttps(url);

  static Future<ModelBytes> _fetchHttps(Uri url, {int start = 0}) async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(url);
    request.followRedirects = true;
    request.maxRedirects = 10;
    if (start > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
    }
    final HttpClientResponse response = await request.close();
    final int wanted = start > 0 ? HttpStatus.partialContent : HttpStatus.ok;
    if (response.statusCode != wanted) {
      client.close(force: true);
      throw HttpException(
        'The model host answered ${response.statusCode} where $wanted was '
        'asked for.',
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
