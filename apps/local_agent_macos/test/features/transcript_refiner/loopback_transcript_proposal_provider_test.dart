import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/transcript_refiner/loopback_transcript_proposal_provider.dart';

void main() {
  test('accepts only literal HTTP loopback endpoints', () {
    for (final String value in <String>[
      'https://127.0.0.1:46559/refine',
      'http://localhost:46559/refine',
      'http://192.168.1.2:46559/refine',
      'http://user:pass@127.0.0.1:46559/refine',
      'http://127.0.0.1/refine',
      'http://127.0.0.1:46559/refine?next=remote',
      'http://127.0.0.1:46559/refine#fragment',
    ]) {
      expect(
        () => LoopbackTranscriptProposalProvider(endpoint: Uri.parse(value)),
        throwsArgumentError,
        reason: value,
      );
    }

    final LoopbackTranscriptProposalProvider ipv4 =
        LoopbackTranscriptProposalProvider(
          endpoint: Uri.parse('http://127.0.0.1:46559/refine'),
        );
    final LoopbackTranscriptProposalProvider ipv6 =
        LoopbackTranscriptProposalProvider(
          endpoint: Uri.parse('http://[::1]:46559/refine'),
        );
    ipv4.dispose();
    ipv6.dispose();
  });

  test('posts the minimal schema and decodes matching evidence', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Completer<Map<String, Object?>> received =
        Completer<Map<String, Object?>>();
    server.listen((HttpRequest request) async {
      received.complete(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, Object?>,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'requestId': 'request-1',
          'refinedTranscript': '我用 Flutter',
          'providerId': 'qwen3-0.6b',
          'providerVersion': 'mlx-1',
        }),
      );
      await request.response.close();
    });
    final LoopbackTranscriptProposalProvider provider =
        LoopbackTranscriptProposalProvider(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/refine'),
        );

    final TranscriptProposal proposal = await provider.propose(
      TranscriptProposalRequest(
        requestId: 'request-1',
        rawTranscript: '我用 flutter',
        locale: 'zh-TW',
        protectedVocabulary: const <String>['Flutter'],
        deadline: const Duration(milliseconds: 250),
        caseId: 'private-case',
      ),
    );

    expect(await received.future, <String, Object?>{
      'schemaVersion': 1,
      'requestId': 'request-1',
      'locale': 'zh-TW',
      'rawTranscript': '我用 flutter',
      'protectedVocabulary': <Object?>['Flutter'],
    });
    expect(proposal.refinedTranscript, '我用 Flutter');
    expect(proposal.providerId, 'qwen3-0.6b');
    expect(proposal.providerVersion, 'mlx-1');
    provider.dispose();
    await server.close(force: true);
  });

  test(
    'rejects redirects malformed mismatched and oversized responses',
    () async {
      await _expectRejected(status: HttpStatus.serviceUnavailable, body: '{}');
      await _expectRejected(
        status: HttpStatus.found,
        body: '{}',
        location: 'http://example.com/refine',
      );
      await _expectRejected(body: 'not-json');
      await _expectRejected(
        body: jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'requestId': 'another-request',
          'refinedTranscript': '修訂',
          'providerId': 'qwen',
          'providerVersion': '1',
        }),
      );
      await _expectRejected(
        body: jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'requestId': 'request-1',
          'refinedTranscript': '  ',
          'providerId': 'qwen',
          'providerVersion': '1',
        }),
      );
      await _expectRejected(body: 'x' * 64, maxResponseBytes: 16);
    },
  );
}

Future<void> _expectRejected({
  int status = HttpStatus.ok,
  required String body,
  String? location,
  int maxResponseBytes = 16384,
}) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    request.response.statusCode = status;
    if (location != null) {
      request.response.headers.set(HttpHeaders.locationHeader, location);
    }
    request.response.write(body);
    await request.response.close();
  });
  final LoopbackTranscriptProposalProvider provider =
      LoopbackTranscriptProposalProvider(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/refine'),
        maxResponseBytes: maxResponseBytes,
      );
  try {
    await expectLater(provider.propose(_request()), throwsA(isA<Object>()));
  } finally {
    provider.dispose();
    await server.close(force: true);
  }
}

TranscriptProposalRequest _request() => TranscriptProposalRequest(
  requestId: 'request-1',
  rawTranscript: '原始內容',
  locale: 'zh-TW',
  protectedVocabulary: const <String>[],
  deadline: const Duration(milliseconds: 250),
);
