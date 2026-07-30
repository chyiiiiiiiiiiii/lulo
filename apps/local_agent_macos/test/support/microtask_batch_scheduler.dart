import 'dart:async';

import 'package:local_agent_macos/features/conversation/token_batcher.dart';

/// A scheduler whose frame is the next microtask.
///
/// For tests about domain behavior rather than frame pacing: deltas become
/// visible after any `await`, without waiting a real frame interval.
final class MicrotaskBatchScheduler implements BatchScheduler {
  @override
  CancelBatch schedule(Duration delay, void Function() callback) {
    final _CancellableMicrotask scheduled = _CancellableMicrotask(callback);
    scheduleMicrotask(scheduled.run);
    return scheduled;
  }
}

final class _CancellableMicrotask implements CancelBatch {
  _CancellableMicrotask(this._callback);

  final void Function() _callback;
  bool _cancelled = false;

  void run() {
    if (!_cancelled) {
      _callback();
    }
  }

  @override
  void cancel() {
    _cancelled = true;
  }
}
