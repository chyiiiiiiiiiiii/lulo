import 'dart:async';

import 'package:agent_core/agent_core.dart';

/// Bounds refinement latency and converts every failure mode to exact raw text.
final class DeadlineTranscriptRefiner implements TranscriptRefiner {
  /// Creates a deadline wrapper around [inner].
  DeadlineTranscriptRefiner(this._inner);

  final TranscriptRefiner _inner;
  final Completer<void> _disposed = Completer<void>();
  bool _busy = false;

  @override
  Future<TranscriptRefinement> refine(
    TranscriptRefinementRequest request,
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    if (_disposed.isCompleted || _busy) {
      stopwatch.stop();
      return _fallback(
        request,
        TranscriptRefinementStatus.failed,
        stopwatch.elapsed,
      );
    }
    _busy = true;
    try {
      final _DeadlineOutcome outcome = await Future.any<_DeadlineOutcome>(
        <Future<_DeadlineOutcome>>[
          _inner
              .refine(request)
              .then<_DeadlineOutcome>(_DeadlineSuccess.new)
              .catchError((Object _, StackTrace _) => const _DeadlineFailed()),
          Future<_DeadlineOutcome>.delayed(
            request.deadline,
            () => const _DeadlineTimedOut(),
          ),
          _disposed.future.then<_DeadlineOutcome>(
            (void _) => const _DeadlineDisposed(),
          ),
        ],
      );
      stopwatch.stop();
      return switch (outcome) {
        _DeadlineSuccess(:final TranscriptRefinement value) => value,
        _DeadlineTimedOut() => _fallback(
          request,
          TranscriptRefinementStatus.timedOut,
          stopwatch.elapsed,
        ),
        _DeadlineFailed() || _DeadlineDisposed() => _fallback(
          request,
          TranscriptRefinementStatus.failed,
          stopwatch.elapsed,
        ),
      };
    } finally {
      _busy = false;
    }
  }

  /// Releases waiting calls without waiting for their inner futures.
  void dispose() {
    if (!_disposed.isCompleted) {
      _disposed.complete();
    }
  }
}

TranscriptRefinement _fallback(
  TranscriptRefinementRequest request,
  TranscriptRefinementStatus status,
  Duration elapsed,
) => TranscriptRefinement(
  rawTranscript: request.rawTranscript,
  proposedTranscript: null,
  selectedTranscript: request.rawTranscript,
  status: status,
  edits: const <TranscriptEdit>[],
  rejectionReasons: const <TranscriptRejectionReason>[],
  refinerId: 'deadline-fallback',
  refinerVersion: '1',
  elapsed: elapsed,
);

sealed class _DeadlineOutcome {
  const _DeadlineOutcome();
}

final class _DeadlineSuccess extends _DeadlineOutcome {
  const _DeadlineSuccess(this.value);

  final TranscriptRefinement value;
}

final class _DeadlineTimedOut extends _DeadlineOutcome {
  const _DeadlineTimedOut();
}

final class _DeadlineFailed extends _DeadlineOutcome {
  const _DeadlineFailed();
}

final class _DeadlineDisposed extends _DeadlineOutcome {
  const _DeadlineDisposed();
}
