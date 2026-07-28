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

  test('the conversation goes as the presence leaves, not after it lands', () {
    // The complaint this exists for: the presence reached the desktop and the
    // window was still sitting there at full strength, then vanished.
    expect(conversationOpacityAt(t: 0, collapsing: true), 1);
    expect(
      conversationOpacityAt(t: 0.3, collapsing: true),
      lessThan(0.5),
      reason: 'The window was still solid a third of the way through.',
    );
    expect(
      conversationOpacityAt(t: 0.55, collapsing: true),
      0,
      reason: 'The window outlived the presence it belongs to.',
    );
  });

  test('the conversation arrives with the presence, not before it', () {
    expect(conversationOpacityAt(t: 0, collapsing: false), 0);
    expect(
      conversationOpacityAt(t: 0.3, collapsing: false),
      0,
      reason: 'The window appeared while the presence was still travelling.',
    );
    expect(conversationOpacityAt(t: 1, collapsing: false), 1);
  });

  test('a settling spring never drives opacity out of range', () {
    for (final double t in <double>[-0.05, 1.08, 1.2]) {
      for (final bool collapsing in <bool>[true, false]) {
        final double opacity = conversationOpacityAt(
          t: t,
          collapsing: collapsing,
        );
        expect(opacity, inInclusiveRange(0, 1), reason: 't=$t');
      }
    }
  });

  test('the conversation shrinks away rather than only fading', () {
    final double early = conversationScaleAt(t: 0.05, collapsing: true);
    final double late = conversationScaleAt(t: 0.5, collapsing: true);

    expect(early, closeTo(1, 0.02));
    expect(late, lessThan(early));
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
