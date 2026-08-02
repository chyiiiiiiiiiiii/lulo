import 'dart:async';

import 'package:agent_core/agent_core.dart';

/// Runs transcript proposals outside the live conversation path.
final class TranscriptShadowCoordinator {
  /// Creates a single-flight shadow coordinator.
  TranscriptShadowCoordinator({
    required this.provider,
    required this.onResult,
    this.gate = const TranscriptProposalGate(),
  });

  /// Local provider whose result can never become live conversation text.
  final TranscriptProposalProvider provider;

  /// Receives redacted-status and optional explicit evaluation evidence.
  final FutureOr<void> Function(TranscriptShadowResult result) onResult;

  /// Safety policy applied to every returned proposal.
  final TranscriptProposalGate gate;
  int _epoch = 0;
  bool _busy = false;
  bool _disposed = false;

  /// Starts shadow work without delaying the caller.
  void submit(TranscriptProposalRequest request) {
    if (_disposed) {
      return;
    }
    if (_busy) {
      unawaited(
        _deliver(
          TranscriptShadowResult(
            request: request,
            proposal: null,
            gateDecision: null,
            status: TranscriptShadowStatus.skippedBusy,
            elapsed: Duration.zero,
          ),
        ),
      );
      return;
    }
    _busy = true;
    unawaited(_run(request, _epoch));
  }

  Future<void> _run(TranscriptProposalRequest request, int epoch) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final TranscriptProposal proposal = await provider
          .propose(request)
          .timeout(request.deadline);
      stopwatch.stop();
      if (_disposed || epoch != _epoch) {
        return;
      }
      if (proposal.requestId != request.requestId) {
        throw StateError('proposal request identity mismatch');
      }
      final TranscriptProposalDecision decision = gate.evaluate(
        raw: request.rawTranscript,
        proposal: proposal.refinedTranscript,
        protectedVocabulary: request.protectedVocabulary,
      );
      await _deliver(
        TranscriptShadowResult(
          request: request,
          proposal: proposal,
          gateDecision: decision,
          status: decision.accepted
              ? TranscriptShadowStatus.accepted
              : TranscriptShadowStatus.rejected,
          elapsed: stopwatch.elapsed,
        ),
      );
    } on TimeoutException {
      stopwatch.stop();
      if (!_disposed && epoch == _epoch) {
        await _deliver(
          TranscriptShadowResult(
            request: request,
            proposal: null,
            gateDecision: null,
            status: TranscriptShadowStatus.timedOut,
            elapsed: stopwatch.elapsed,
          ),
        );
      }
    } on Object {
      stopwatch.stop();
      if (!_disposed && epoch == _epoch) {
        await _deliver(
          TranscriptShadowResult(
            request: request,
            proposal: null,
            gateDecision: null,
            status: TranscriptShadowStatus.failed,
            elapsed: stopwatch.elapsed,
          ),
        );
      }
    } finally {
      if (epoch == _epoch) {
        _busy = false;
      }
    }
  }

  Future<void> _deliver(TranscriptShadowResult result) async {
    try {
      await onResult(result);
    } on Object {
      // Shadow evidence must never become a live-voice failure.
    }
  }

  /// Fences results belonging to the current voice session.
  void cancelSession() {
    _epoch += 1;
    _busy = false;
  }

  /// Permanently fences all current and future results.
  void dispose() {
    _disposed = true;
    _epoch += 1;
    _busy = false;
  }
}
