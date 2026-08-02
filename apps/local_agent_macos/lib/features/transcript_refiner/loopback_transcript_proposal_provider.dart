import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_core/agent_core.dart';

/// Optional developer provider restricted to a literal loopback HTTP route.
final class LoopbackTranscriptProposalProvider
    implements TranscriptProposalProvider {
  /// Creates a provider without opening a connection.
  factory LoopbackTranscriptProposalProvider({
    required Uri endpoint,
    HttpClient? client,
    int maxResponseBytes = 16384,
  }) {
    final bool loopback =
        endpoint.host == '127.0.0.1' || endpoint.host == '::1';
    if (endpoint.scheme != 'http' ||
        !loopback ||
        !endpoint.hasPort ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        maxResponseBytes <= 0) {
      throw ArgumentError('endpoint must be a literal loopback HTTP URI');
    }
    return LoopbackTranscriptProposalProvider._(
      endpoint,
      client ?? HttpClient(),
      client == null,
      maxResponseBytes,
    );
  }

  const LoopbackTranscriptProposalProvider._(
    this.endpoint,
    this._client,
    this._ownsClient,
    this.maxResponseBytes,
  );

  /// Exact loopback route used for every request.
  final Uri endpoint;

  /// Maximum accepted response body size.
  final int maxResponseBytes;

  final HttpClient _client;
  final bool _ownsClient;

  @override
  Future<TranscriptProposal> propose(TranscriptProposalRequest request) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final HttpClientRequest outgoing = await _client.postUrl(endpoint);
    outgoing
      ..followRedirects = false
      ..maxRedirects = 0;
    outgoing.headers.contentType = ContentType.json;
    outgoing.write(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'requestId': request.requestId,
        'locale': request.locale,
        'rawTranscript': request.rawTranscript,
        'protectedVocabulary': request.protectedVocabulary,
      }),
    );
    final HttpClientResponse response = await outgoing.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('proposal provider returned non-200 status');
    }
    final BytesBuilder body = BytesBuilder(copy: false);
    int length = 0;
    await for (final List<int> chunk in response) {
      length += chunk.length;
      if (length > maxResponseBytes) {
        throw const FormatException('proposal response exceeds byte limit');
      }
      body.add(chunk);
    }
    stopwatch.stop();
    final Object? decoded = jsonDecode(utf8.decode(body.takeBytes()));
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 1 ||
        decoded['requestId'] != request.requestId) {
      throw const FormatException('invalid proposal response envelope');
    }
    return TranscriptProposal(
      requestId: _nonEmpty(decoded, 'requestId'),
      refinedTranscript: _nonEmpty(decoded, 'refinedTranscript'),
      providerId: _nonEmpty(decoded, 'providerId'),
      providerVersion: _nonEmpty(decoded, 'providerVersion'),
      elapsed: stopwatch.elapsed,
    );
  }

  /// Closes the internally created HTTP client.
  void dispose() {
    if (_ownsClient) {
      _client.close(force: true);
    }
  }
}

String _nonEmpty(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('invalid proposal response field: $key');
  }
  return value;
}
