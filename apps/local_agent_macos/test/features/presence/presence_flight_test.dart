import 'dart:ui';

import 'package:flutter/physics.dart';
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

  test('the presence is home before the wait becomes noticeable', () {
    // The fault this guards: the presence reached the desktop and then sat
    // there while the spring's tail was still being declared settled, which
    // reads as the agent freezing on arrival.
    //
    // What decides when it arrives is the damped frequency, not how fast the
    // envelope decays. Damping the spring harder lowers that frequency and
    // makes the arrival later, which is the trap this exists to catch.
    final SpringSimulation flight = SpringSimulation(
      presenceFlightSpring,
      0,
      1,
      0,
    );

    double arrival = 0;
    while (arrival < 2 && flight.x(arrival) < 1) {
      arrival += 1 / 240;
    }

    expect(
      arrival,
      lessThan(0.32),
      reason: 'The presence took ${arrival.toStringAsFixed(2)}s to arrive.',
    );
    // Still thrown rather than eased into place: it passes the target.
    expect(flight.x(arrival + 0.02), greaterThan(1));
  });

  test('leaving starts before the canvas it will be drawn on exists', () {
    // Preparing the canvas means resizing the window and reallocating the
    // surface behind it, and nothing can move until that returns. Measured at
    // roughly a quarter of a second — as long as the whole flight — during
    // which the screen was completely still after the user asked for it.
    //
    // The conversation's departure does not depend on any of that, so it is
    // driven on its own and begins on the keystroke.
    expect(leavingOpacityAt(0), 1);
    // What matters is that the answer to the keystroke is visible almost at
    // once, not that it is finished quickly.
    expect(
      leavingOpacityAt(0.15),
      lessThan(0.95),
      reason: 'The screen was still unchanged after the user asked.',
    );
    expect(leavingOpacityAt(0.5), lessThanOrEqualTo(0.5));
    expect(leavingOpacityAt(1), 0);
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
