import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/physics.dart';

/// How the presence settles when it is thrown between its two forms.
///
/// Underdamped on purpose: it passes its destination slightly and comes back,
/// which is what makes it read as something with weight rather than a widget
/// being repositioned. The overshoot is kept on the canvas by
/// [presenceFlightRect].
///
/// Tuned for when it *arrives*, which is set by the damped frequency
/// `sqrt(stiffness) * sqrt(1 - zeta^2)` and not by how fast the spring stops
/// wobbling afterwards. Damping it harder lowers that frequency and makes the
/// agent take longer to get there, which is the opposite of what it looks
/// like it should do. Speed comes from stiffness instead.
const SpringDescription presenceFlightSpring = SpringDescription(
  mass: 1,
  stiffness: 290,
  damping: 25,
);

/// When the journey counts as over.
///
/// The default tolerance is far tighter than the eye, and waiting for it left
/// the presence sitting still at its destination while the window had not
/// settled yet — a pause with nothing happening in it. Progress runs 0 to 1
/// across the whole journey, so a thousandth of it is well under a pixel.
const Tolerance presenceFlightTolerance = Tolerance(
  distance: 0.004,
  velocity: 0.08,
);

/// Radius of the window's own corners, in logical points.
///
/// The conversation is normally rounded by AppKit's window mask. During a
/// change of form the window is the canvas covering both shapes, so that mask
/// rounds the canvas instead and the conversation drawn inside it would have
/// hard square corners unless it rounds itself.
const double windowCornerRadius = 12;

/// How far the path bows away from the straight line between the two ends.
///
/// Expressed as a fraction of the distance travelled, so a short hop curves as
/// much as a long one relative to how far it goes.
const double _arcDepth = 0.16;

/// How far the conversation shrinks as it goes.
///
/// Small. It is leaving with the presence, not being thrown itself, and a
/// large scale reads as a separate animation competing with the one that
/// matters.
const double _conversationShrink = 0.06;

/// How long the conversation takes to go once it has been asked to.
///
/// Runs on its own clock rather than on the flight's, because the flight
/// cannot begin until the window has been resized and its surface
/// reallocated — measured at about a quarter of a second, as long as the
/// flight itself, with the screen completely still throughout. Leaving needs
/// none of that, so it starts on the keystroke and covers the wait.
const Duration leavingDuration = Duration(milliseconds: 190);

/// How solid the conversation is [progress] of the way through leaving.
double leavingOpacityAt(double progress) {
  final double gone = clampDouble(progress, 0, 1);
  return (1 + math.cos(math.pi * gone)) / 2;
}

/// How large the conversation is [progress] of the way through leaving.
double leavingScaleAt(double progress) =>
    1 - (1 - leavingOpacityAt(progress)) * _conversationShrink;

/// Where the presence is when it is [t] of the way between [from] and [to].
///
/// Position follows a curve rather than the line between the two ends, because
/// nothing thrown travels in a straight line and a presence that does looks
/// repositioned rather than moved. Size runs alongside it.
///
/// [t] may pass 1 while the spring settles. [bounds] clamps the result so that
/// overshoot is not drawn outside the window, whose edge is usually exactly
/// where the presence comes to rest.
Rect presenceFlightRect({
  required Rect from,
  required Rect to,
  required double t,
  Rect? bounds,
}) {
  final Offset start = from.center;
  final Offset end = to.center;
  final Offset travel = end - start;

  // Perpendicular to the direction of travel, on the outward side, so the
  // presence rises away from its path before falling into place.
  final double distance = travel.distance;
  final Offset lift = distance == 0
      ? Offset.zero
      : Offset(travel.dy, -travel.dx) / distance * (distance * _arcDepth);
  final Offset control = start + travel / 2 + lift;

  // A quadratic curve through that control point. Evaluated rather than
  // clamped at t, so a spring that passes 1 keeps following the same path
  // instead of stopping dead on the target.
  final double u = 1 - t;
  final Offset centre = start * (u * u) + control * (2 * u * t) + end * (t * t);

  final double extent = lerpDouble(from.width, to.width, t)!;
  final Rect rect = Rect.fromCenter(
    center: centre,
    width: extent,
    height: extent,
  );
  if (bounds == null) {
    return rect;
  }
  // Only the position is pulled back; the size it reached is what it is.
  return rect.shift(
    Offset(
      _pullBack(rect.left, rect.right, bounds.left, bounds.right),
      _pullBack(rect.top, rect.bottom, bounds.top, bounds.bottom),
    ),
  );
}

/// How far an edge pair has to move to sit inside its limits.
double _pullBack(double low, double high, double min, double max) {
  if (low < min) {
    return math.min(min - low, max - high);
  }
  if (high > max) {
    return math.max(max - high, min - low);
  }
  return 0;
}
