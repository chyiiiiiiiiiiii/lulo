import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/transcript_refiner/transcript_shadow_coordinator.dart';

void main() {
  test(
    'submission returns before an accepted provider result arrives',
    () async {
      final Completer<TranscriptProposal> pending =
          Completer<TranscriptProposal>();
      final List<TranscriptShadowResult> results = <TranscriptShadowResult>[];
      final TranscriptShadowCoordinator coordinator =
          TranscriptShadowCoordinator(
            provider: _FunctionProvider((_) => pending.future),
            onResult: results.add,
          );

      coordinator.submit(_request());

      expect(results, isEmpty);
      pending.complete(_proposal());
      await _flushEvents();

      expect(results, hasLength(1));
      expect(results.single.status, TranscriptShadowStatus.accepted);
      expect(results.single.gateDecision?.accepted, isTrue);
      coordinator.dispose();
    },
  );

  test('a newer request is skipped instead of queued while busy', () async {
    final Completer<TranscriptProposal> pending =
        Completer<TranscriptProposal>();
    final List<TranscriptShadowResult> results = <TranscriptShadowResult>[];
    final TranscriptShadowCoordinator coordinator = TranscriptShadowCoordinator(
      provider: _FunctionProvider((_) => pending.future),
      onResult: results.add,
    );

    coordinator.submit(_request());
    coordinator.submit(_request(id: 'request-2'));
    await _flushEvents();

    expect(results, hasLength(1));
    expect(results.single.request.requestId, 'request-2');
    expect(results.single.status, TranscriptShadowStatus.skippedBusy);
    coordinator.dispose();
    pending.complete(_proposal());
    await _flushEvents();
  });

  test('a provider exception becomes redacted failed evidence', () async {
    final List<TranscriptShadowResult> results = <TranscriptShadowResult>[];
    final TranscriptShadowCoordinator coordinator = TranscriptShadowCoordinator(
      provider: _FunctionProvider(
        (_) => Future<TranscriptProposal>.error(StateError('private')),
      ),
      onResult: results.add,
    );

    coordinator.submit(_request());
    await _flushEvents();

    expect(results, hasLength(1));
    expect(results.single.status, TranscriptShadowStatus.failed);
    expect(results.single.proposal, isNull);
    coordinator.dispose();
  });

  test(
    'a response for another request is failed before safety gating',
    () async {
      final List<TranscriptShadowResult> results = <TranscriptShadowResult>[];
      final TranscriptShadowCoordinator coordinator =
          TranscriptShadowCoordinator(
            provider: _FunctionProvider(
              (_) async => _proposal(id: 'different-request'),
            ),
            onResult: results.add,
          );

      coordinator.submit(_request());
      await _flushEvents();

      expect(results.single.status, TranscriptShadowStatus.failed);
      expect(results.single.proposal, isNull);
      coordinator.dispose();
    },
  );

  test('a provider that misses the request deadline times out', () async {
    final Completer<TranscriptProposal> pending =
        Completer<TranscriptProposal>();
    final List<TranscriptShadowResult> results = <TranscriptShadowResult>[];
    final TranscriptShadowCoordinator coordinator = TranscriptShadowCoordinator(
      provider: _FunctionProvider((_) => pending.future),
      onResult: results.add,
    );

    coordinator.submit(_request(deadline: const Duration(milliseconds: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(results.single.status, TranscriptShadowStatus.timedOut);
    expect(results.single.proposal, isNull);
    coordinator.dispose();
    pending.complete(_proposal());
  });

  test('an unsafe proposal is retained only as rejected evidence', () async {
    final List<TranscriptShadowResult> results = <TranscriptShadowResult>[];
    final TranscriptShadowCoordinator coordinator = TranscriptShadowCoordinator(
      provider: _FunctionProvider(
        (_) async => TranscriptProposal(
          requestId: 'request-1',
          refinedTranscript: '完全不同而且改掉原意的長篇內容',
          providerId: 'qwen3-0.6b',
          providerVersion: '1',
          elapsed: const Duration(milliseconds: 10),
        ),
      ),
      onResult: results.add,
    );

    coordinator.submit(_request());
    await _flushEvents();

    expect(results.single.status, TranscriptShadowStatus.rejected);
    expect(results.single.gateDecision?.accepted, isFalse);
    coordinator.dispose();
  });

  test('session cancellation fences a late provider result', () async {
    final Completer<TranscriptProposal> pending =
        Completer<TranscriptProposal>();
    final List<TranscriptShadowResult> results = <TranscriptShadowResult>[];
    final TranscriptShadowCoordinator coordinator = TranscriptShadowCoordinator(
      provider: _FunctionProvider((_) => pending.future),
      onResult: results.add,
    );

    coordinator.submit(_request());
    coordinator.cancelSession();
    pending.complete(_proposal());
    await _flushEvents();

    expect(results, isEmpty);
    coordinator.dispose();
  });

  test('a failing evidence sink cannot escape into live voice', () async {
    final TranscriptShadowCoordinator coordinator = TranscriptShadowCoordinator(
      provider: _FunctionProvider((_) async => _proposal()),
      onResult: (_) => throw StateError('sink failed'),
    );

    coordinator.submit(_request());
    await _flushEvents();

    coordinator.submit(_request(id: 'request-2'));
    await _flushEvents();
    coordinator.dispose();
  });
}

TranscriptProposalRequest _request({
  String id = 'request-1',
  Duration deadline = const Duration(milliseconds: 250),
}) => TranscriptProposalRequest(
  requestId: id,
  rawTranscript: '我用 flutter 開發',
  locale: 'zh-TW',
  protectedVocabulary: const <String>['Flutter'],
  deadline: deadline,
);

TranscriptProposal _proposal({String id = 'request-1'}) => TranscriptProposal(
  requestId: id,
  refinedTranscript: '我用 Flutter 開發',
  providerId: 'qwen3-0.6b',
  providerVersion: '1',
  elapsed: const Duration(milliseconds: 10),
);

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FunctionProvider implements TranscriptProposalProvider {
  const _FunctionProvider(this.callback);

  final Future<TranscriptProposal> Function(TranscriptProposalRequest request)
  callback;

  @override
  Future<TranscriptProposal> propose(TranscriptProposalRequest request) =>
      callback(request);
}
