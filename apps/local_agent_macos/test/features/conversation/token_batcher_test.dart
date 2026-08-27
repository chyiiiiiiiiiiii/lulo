import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/token_batcher.dart';

void main() {
  const Duration frame = Duration(microseconds: 8333);

  test('deltas inside one frame arrive as one combined delta', () {
    fakeAsync((FakeAsync clock) {
      final List<String> batches = <String>[];
      final TokenBatcher batcher = TokenBatcher(
        onBatch: batches.add,
        scheduler: TimerBatchScheduler(),
        interval: frame,
      );

      batcher.add('A');
      batcher.add('B');
      batcher.add('C');
      expect(batches, isEmpty, reason: 'Nothing may emit before the frame.');

      clock.elapse(frame);
      expect(batches, <String>['ABC']);

      batcher.dispose();
    });
  });

  test('deltas in later frames arrive later, in order', () {
    fakeAsync((FakeAsync clock) {
      final List<String> batches = <String>[];
      final TokenBatcher batcher = TokenBatcher(
        onBatch: batches.add,
        scheduler: TimerBatchScheduler(),
        interval: frame,
      );

      batcher.add('A');
      clock.elapse(frame);
      batcher.add('B');
      batcher.add('C');
      clock.elapse(frame);

      expect(batches, <String>['A', 'BC']);
      batcher.dispose();
    });
  });

  test('flush hands over what is pending without waiting for the frame', () {
    // A terminal event must never race its own last tokens: the completed
    // turn is built from the projected text, so everything pending has to be
    // in it first.
    fakeAsync((FakeAsync clock) {
      final List<String> batches = <String>[];
      final TokenBatcher batcher = TokenBatcher(
        onBatch: batches.add,
        scheduler: TimerBatchScheduler(),
        interval: frame,
      );

      batcher.add('A');
      batcher.add('B');
      batcher.flush();
      expect(batches, <String>['AB']);

      clock.elapse(frame);
      expect(batches, <String>[
        'AB',
      ], reason: 'The scheduled frame must not emit what flush already did.');
      batcher.dispose();
    });
  });

  test('an empty flush says nothing', () {
    fakeAsync((FakeAsync clock) {
      final List<String> batches = <String>[];
      final TokenBatcher batcher = TokenBatcher(
        onBatch: batches.add,
        scheduler: TimerBatchScheduler(),
        interval: frame,
      );

      batcher.flush();
      expect(batches, isEmpty);
      batcher.dispose();
    });
  });

  test('dispose releases the scheduled frame without emitting', () {
    fakeAsync((FakeAsync clock) {
      final List<String> batches = <String>[];
      TokenBatcher(
          onBatch: batches.add,
          scheduler: TimerBatchScheduler(),
          interval: frame,
        )
        ..add('A')
        ..dispose();

      clock.elapse(frame * 4);
      expect(batches, isEmpty);
      expect(
        clock.pendingTimers,
        isEmpty,
        reason: 'Dispose left scheduled work behind.',
      );
    });
  });

  test('cancelling a scheduled batch twice is one cancellation', () {
    fakeAsync((FakeAsync clock) {
      int ran = 0;
      final CancelBatch scheduled = TimerBatchScheduler().schedule(
        frame,
        () => ran += 1,
      );

      scheduled.cancel();
      scheduled.cancel();
      clock.elapse(frame * 2);

      expect(ran, 0);
    });
  });
}
