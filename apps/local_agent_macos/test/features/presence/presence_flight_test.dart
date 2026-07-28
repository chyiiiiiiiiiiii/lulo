import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/presence_flight.dart';

void main() {
  const Rect from = Rect.fromLTWH(100, 100, 56, 56);
  const Rect to = Rect.fromLTWH(1100, 660, 148, 148);

  test('the presence leaves and arrives exactly where it is expected', () {
    // Whatever happens in between, both ends have to be the real anchors, or
    // the presence jumps as the window settles.
    expect(presenceFlightRect(from: from, to: to, t: 0), from);
    expect(presenceFlightRect(from: from, to: to, t: 1), to);
  });

  test('the presence arcs instead of sliding along a straight line', () {
    final Rect middle = presenceFlightRect(from: from, to: to, t: 0.5);
    final Offset straight = Offset.lerp(from.center, to.center, 0.5)!;

    // A thrown object does not travel along the line between its ends, and a
    // presence that does reads as a widget being repositioned.
    expect(
      (middle.center - straight).distance,
      greaterThan(24),
      reason: 'The presence slid straight to its destination.',
    );
    // Bowed outward from the direction of travel, not sagging into it.
    expect(middle.center.dy, lessThan(straight.dy));
  });

  test('the presence keeps its size in step with its position', () {
    final Rect middle = presenceFlightRect(from: from, to: to, t: 0.5);

    expect(middle.width, greaterThan(from.width));
    expect(middle.width, lessThan(to.width));
    expect(middle.width, middle.height);
  });

  test('an overshooting spring still leaves the presence on the canvas', () {
    // A lively spring passes its target before settling back. The canvas ends
    // exactly at the resting place, so an unclamped overshoot is drawn off
    // the edge of the window.
    final Rect past = presenceFlightRect(
      from: from,
      to: to,
      t: 1.08,
      bounds: const Rect.fromLTWH(0, 0, 1248, 808),
    );

    expect(past.right, lessThanOrEqualTo(1248));
    expect(past.bottom, lessThanOrEqualTo(808));
  });
}
