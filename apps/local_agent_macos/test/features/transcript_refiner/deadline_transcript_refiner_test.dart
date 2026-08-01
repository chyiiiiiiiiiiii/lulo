import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/transcript_refiner/deadline_transcript_refiner.dart';

void main() {
  test('returns a successful inner refinement', () async {
    final DeadlineTranscriptRefiner refiner = DeadlineTranscriptRefiner(
      _FunctionRefiner((TranscriptRefinementRequest request) async {
        return _result(
          request.rawTranscript,
          TranscriptRefinementStatus.unchanged,
        );
      }),
    );

    final TranscriptRefinement result = await refiner.refine(_request());

    expect(result.status, TranscriptRefinementStatus.unchanged);
    refiner.dispose();
  });

  test('timeout selects exact raw text', () async {
    final Completer<TranscriptRefinement> pending =
        Completer<TranscriptRefinement>();
    final DeadlineTranscriptRefiner refiner = DeadlineTranscriptRefiner(
      _FunctionRefiner((TranscriptRefinementRequest request) => pending.future),
    );

    final TranscriptRefinement result = await refiner.refine(
      _request(deadline: const Duration(milliseconds: 5)),
    );

    expect(result.status, TranscriptRefinementStatus.timedOut);
    expect(result.selectedTranscript, '原始內容');
    refiner.dispose();
  });

  test('exception selects exact raw text', () async {
    final DeadlineTranscriptRefiner refiner = DeadlineTranscriptRefiner(
      _FunctionRefiner((TranscriptRefinementRequest request) async {
        throw StateError('private raw must not be logged');
      }),
    );

    final TranscriptRefinement result = await refiner.refine(_request());

    expect(result.status, TranscriptRefinementStatus.failed);
    expect(result.selectedTranscript, '原始內容');
    expect(result.rejectionReasons, isEmpty);
    refiner.dispose();
  });

  test('dispose releases an in-flight refinement to raw fallback', () async {
    final Completer<TranscriptRefinement> pending =
        Completer<TranscriptRefinement>();
    final DeadlineTranscriptRefiner refiner = DeadlineTranscriptRefiner(
      _FunctionRefiner((TranscriptRefinementRequest request) => pending.future),
    );
    final Future<TranscriptRefinement> future = refiner.refine(_request());

    refiner.dispose();
    final TranscriptRefinement result = await future;

    expect(result.status, TranscriptRefinementStatus.failed);
    expect(result.selectedTranscript, '原始內容');
  });
}

TranscriptRefinementRequest _request({
  Duration deadline = const Duration(milliseconds: 250),
}) => TranscriptRefinementRequest(
  rawTranscript: '原始內容',
  locale: 'zh-TW',
  protectedVocabulary: const <String>['Lulo'],
  deadline: deadline,
);

TranscriptRefinement _result(String raw, TranscriptRefinementStatus status) =>
    TranscriptRefinement(
      rawTranscript: raw,
      proposedTranscript: null,
      selectedTranscript: raw,
      status: status,
      edits: const <TranscriptEdit>[],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: 'test',
      refinerVersion: '1',
      elapsed: Duration.zero,
    );

final class _FunctionRefiner implements TranscriptRefiner {
  const _FunctionRefiner(this._refine);

  final Future<TranscriptRefinement> Function(TranscriptRefinementRequest)
  _refine;

  @override
  Future<TranscriptRefinement> refine(TranscriptRefinementRequest request) =>
      _refine(request);
}
