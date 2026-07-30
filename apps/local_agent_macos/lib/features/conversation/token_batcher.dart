import 'dart:async';

/// One scheduled batch flush, cancellable exactly once.
abstract interface class CancelBatch {
  /// Stops the scheduled flush from running. Safe to call twice.
  void cancel();
}

/// Schedules a batch flush a little while from now.
///
/// The seam the tests stand behind; production uses [TimerBatchScheduler].
abstract interface class BatchScheduler {
  /// Runs [callback] after [delay], unless cancelled first.
  CancelBatch schedule(Duration delay, void Function() callback);
}

/// The production scheduler: a plain one-shot timer.
final class TimerBatchScheduler implements BatchScheduler {
  /// Creates the timer-backed scheduler.
  const TimerBatchScheduler();

  @override
  CancelBatch schedule(Duration delay, void Function() callback) =>
      _CancelTimer(Timer(delay, callback));
}

final class _CancelTimer implements CancelBatch {
  _CancelTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// Coalesces token deltas to at most one combined delta per frame interval.
///
/// A model can emit tokens far faster than a display can show them, and every
/// delta rebuilds the streaming turn. Batching aligns those rebuilds with the
/// frame instead of the network. Ordering is preserved; nothing is dropped;
/// [flush] hands over whatever is pending so a terminal event never races its
/// own last tokens.
final class TokenBatcher {
  /// Creates a batcher that emits through [onBatch] once per [interval].
  TokenBatcher({
    required void Function(String combined) onBatch,
    BatchScheduler scheduler = const TimerBatchScheduler(),
    Duration interval = const Duration(microseconds: 8333),
  }) : _onBatch = onBatch,
       _scheduler = scheduler,
       _interval = interval;

  final void Function(String combined) _onBatch;
  final BatchScheduler _scheduler;
  final Duration _interval;

  final StringBuffer _pending = StringBuffer();
  CancelBatch? _scheduled;
  bool _disposed = false;

  /// Buffers [delta]; the first delta of an idle interval starts the frame.
  void add(String delta) {
    if (_disposed) {
      return;
    }
    _pending.write(delta);
    _scheduled ??= _scheduler.schedule(_interval, flush);
  }

  /// Emits everything pending now, ahead of the scheduled frame.
  void flush() {
    _scheduled?.cancel();
    _scheduled = null;
    if (_disposed || _pending.isEmpty) {
      return;
    }
    final String combined = _pending.toString();
    _pending.clear();
    _onBatch(combined);
  }

  /// Releases the scheduled frame without emitting what is pending.
  void dispose() {
    _disposed = true;
    _scheduled?.cancel();
    _scheduled = null;
    _pending.clear();
  }
}
