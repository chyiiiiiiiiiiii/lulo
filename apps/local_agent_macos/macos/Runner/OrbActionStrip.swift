import AppKit

/// One button on the strip the resting orb shows under the pointer.
///
/// The words arrive from Dart already in the user's language, like the menu
/// bar's; only the identifier travels back.
struct OrbAction: Equatable {
  /// What to send back when this button is pressed.
  let id: String

  /// The SF Symbol drawn on it.
  let symbol: String

  /// What it is called, for the tooltip and for VoiceOver.
  let label: String

  /// Whether it is currently on — a microphone that is already listening.
  let engaged: Bool
}

/// Where the strip stands beside the orb, and the rectangles it needs.
struct OrbStripLayout: Equatable {
  /// The capsule itself.
  let strip: NSRect

  /// One rectangle per action, leading to trailing.
  let buttons: [NSRect]

  /// Whether it had to go over the orb instead of under it.
  let above: Bool
}

/// The geometry of the strip, as a pure function of where the orb is.
///
/// Kept apart from the view so it can be tested without a window, for the same
/// reason `DesktopPanelController.transitionGeometry` is.
enum OrbActionStrip {
  /// One button's square.
  static let buttonSide: CGFloat = 30

  /// Between two buttons.
  static let buttonGap: CGFloat = 4

  /// Between a button and the capsule's edge.
  static let padding: CGFloat = 7

  /// Between the orb's own light and the capsule.
  static let orbGap: CGFloat = 6

  /// How close to the screen's edge the capsule may come.
  static let screenInset: CGFloat = 6

  /// Where the orb stops painting, as a fraction of the square it is drawn in.
  ///
  /// The same 0.725 that `integration_test/agent_presence_silhouette_test.dart`
  /// measures off the real shader. Measuring the gap from the square's edge
  /// instead would leave the strip floating a visible distance from an orb
  /// that ended long before it.
  static let orbSilhouetteFraction: CGFloat = 0.725

  /// The capsule's height, which does not depend on how many buttons it holds.
  static var height: CGFloat { buttonSide + padding * 2 }

  /// The capsule's width for [count] buttons.
  static func width(count: Int) -> CGFloat {
    CGFloat(count) * buttonSide
      + CGFloat(max(count - 1, 0)) * buttonGap
      + padding * 2
  }

  /// Where the strip goes for an orb at [orb] on a screen showing [visible].
  ///
  /// Under the orb, unless the orb is resting in its home corner where there
  /// is not that much screen left below it — then over it. The home corner is
  /// the common case, not the exception, so a strip that only ever went
  /// downwards would spend most of its life off the bottom of the screen.
  static func layout(orb: NSRect, count: Int, within visible: NSRect)
    -> OrbStripLayout?
  {
    guard count > 0 else {
      return nil
    }
    let capsuleWidth = width(count: count)
    let capsuleHeight = height
    let bodyRadius = min(orb.width, orb.height) * orbSilhouetteFraction / 2
    var above = false
    var y = orb.midY - bodyRadius - orbGap - capsuleHeight
    if y < visible.minY + screenInset {
      above = true
      y = orb.midY + bodyRadius + orbGap
    }
    y = min(y, visible.maxY - capsuleHeight - screenInset)
    var x = orb.midX - capsuleWidth / 2
    x = min(
      max(x, visible.minX + screenInset),
      max(visible.maxX - capsuleWidth - screenInset, visible.minX + screenInset)
    )
    let strip = NSRect(x: x, y: y, width: capsuleWidth, height: capsuleHeight)
    let buttons = (0..<count).map { index in
      NSRect(
        x: strip.minX + padding + CGFloat(index) * (buttonSide + buttonGap),
        y: strip.minY + padding,
        width: buttonSide,
        height: buttonSide
      )
    }
    return OrbStripLayout(strip: strip, buttons: buttons, above: above)
  }

  /// How long the pointer must rest on the orb before the strip appears.
  ///
  /// A strip that appeared the instant the pointer crossed the orb would fire
  /// every time the user swept past it on the way to something else, which is
  /// most of the times a pointer is over a corner of the screen.
  static let dwell: TimeInterval = 0.25

  /// The capsule's corner radius: a full stadium, the shape macOS uses for
  /// a floating row of controls.
  static var cornerRadius: CGFloat { height / 2 }
}
