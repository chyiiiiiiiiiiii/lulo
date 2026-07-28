import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/physics.dart';

/// How the presence settles when it is thrown between its two forms.
///
/// Underdamped on purpose: it passes its destination slightly and comes back,
/// which is what makes it read as something with weight rather than a widget
/// being repositioned. The overshoot is small enough to stay believable and is
/// kept on the canvas by [presenceFlightRect].
const SpringDescription presenceFlightSpring = SpringDescription(
  mass: 1,
  stiffness: 170,
  damping: 21,
);

/// How far the path bows away from the straight line between the two ends.
///
/// Expressed as a fraction of the distance travelled, so a short hop curves as
/// much as a long one relative to how far it goes.
const double _arcDepth = 0.16;

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
