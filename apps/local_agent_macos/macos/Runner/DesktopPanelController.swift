import AppKit

/// How the always-on-screen window is presented.
enum DesktopPresentationMode: Equatable {
  /// A small transparent presence that lives on the desktop.
  case orb
  /// The full conversation surface.
  case expanded
}

/// Where each form sits inside the window that covers both of them.
///
/// Measured from the top-left of that window with y growing downwards, which
/// is how Flutter lays out, rather than AppKit's bottom-left origin.
struct DesktopTransitionGeometry: Equatable {
  let size: CGSize
  let conversation: CGRect
  let orb: CGRect
}

protocol DesktopPanelControlling: AnyObject {
  var isVisible: Bool { get }
  var presentationMode: DesktopPresentationMode { get }
  func show()
  func hide()
  func toggle()
  func setPresentationMode(_ mode: DesktopPresentationMode)
  func moveBy(deltaX: CGFloat, deltaY: CGFloat)
  func beginTransition() -> DesktopTransitionGeometry
  func endTransition(_ mode: DesktopPresentationMode)
}

struct FlutterPanelContent {
  let engine: AnyObject
  let viewController: NSViewController
}

final class DesktopPanelController: DesktopPanelControlling {
  private static let performanceMetricsEnabled =
    ProcessInfo.processInfo.environment["LOCAL_AGENT_PANEL_METRICS"] == "1"

  private(set) var retainedPanel: NSPanel
  private(set) var retainedEngine: AnyObject
  private let screenProvider: () -> NSScreen?

  init(
    panel: NSPanel,
    screenProvider: @escaping () -> NSScreen? = DesktopPanelController.screenAtPointer,
    contentFactory: () -> FlutterPanelContent
  ) {
    precondition(Thread.isMainThread)
    let content = contentFactory()
    retainedPanel = panel
    retainedEngine = content.engine
    self.screenProvider = screenProvider

    panel.contentViewController = content.viewController
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.styleMask.insert(.nonactivatingPanel)
    panel.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])

    // The orb is drawn by a shader with a soft, partly transparent silhouette,
    // so the window itself must contribute no background and no rectangular
    // shadow. Otherwise the vapour sits inside a visible box.
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovableByWindowBackground = true
    // A titlebar would frame the vapour in chrome, so the content runs the full
    // height and the standard buttons are hidden. The titled mask itself is
    // kept because a borderless panel cannot take key for the conversation.
    panel.styleMask.insert(.fullSizeContentView)
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    for button in [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ] {
      panel.standardWindowButton(button)?.isHidden = true
    }
    // The two forms have very different sizes, so a remembered frame is a
    // liability: macOS would restore the orb's frame on the next launch and the
    // conversation would open at orb size. Each form positions itself instead.
    panel.setFrameAutosaveName("")
  }

  /// Size the window returns to when the conversation is shown.
  ///
  /// Deliberately a fixed starting size rather than whatever the window happens
  /// to be at construction: at that point the window may still be carrying the
  /// orb's frame, which would make the conversation open at orb size. It is
  /// updated only when the user leaves the conversation, so a resize is kept.
  private var expandedSize: NSSize = NSSize(width: 720, height: 560)
  private var storedMode: DesktopPresentationMode = .expanded
  /// Whether the window is currently the canvas that covers both forms.
  private var isTransitioning = false
  /// Whether the conversation frame has been applied at least once.
  private var hasPresentedExpanded = false

  /// Reports every mode change, including ones the hotkey initiates, so the
  /// Flutter surface can render the matching form.
  var onPresentationModeChanged: ((DesktopPresentationMode) -> Void)?

  var presentationMode: DesktopPresentationMode {
    storedMode
  }

  func setPresentationMode(_ mode: DesktopPresentationMode) {
    precondition(Thread.isMainThread)
    guard mode != storedMode else {
      return
    }
    // Only remember a size the conversation actually used. At launch the mode
    // is nominally expanded while the window still carries its loaded frame,
    // and adopting that would fix the conversation at the wrong size.
    // While transitioning the frame is the canvas covering both forms, not a
    // size the conversation ever used; beginTransition already recorded the
    // real one before growing.
    if storedMode == .expanded, hasPresentedExpanded, !isTransitioning {
      expandedSize = retainedPanel.frame.size
    }
    storedMode = mode
    applyFrame(for: mode)
    switch mode {
    case .orb:
      // Give up focus so the desktop orb never sits in front of the user's
      // typing target.
      retainedPanel.resignKey()
      retainedPanel.orderFrontRegardless()
    case .expanded:
      NSApp.activate(ignoringOtherApps: true)
      retainedPanel.orderFrontRegardless()
      retainedPanel.makeKey()
    }
    onPresentationModeChanged?(mode)
  }

  /// Drags the window by a delta expressed in Flutter's coordinates.
  ///
  /// Flutter measures downwards and AppKit upwards, so the vertical delta is
  /// inverted here rather than at the call site.
  func moveBy(deltaX: CGFloat, deltaY: CGFloat) {
    precondition(Thread.isMainThread)
    let origin = retainedPanel.frame.origin
    retainedPanel.setFrameOrigin(
      NSPoint(x: origin.x + deltaX, y: origin.y - deltaY)
    )
  }

  /// Places both screen rects inside the window that covers them.
  ///
  /// Pure so the flip between AppKit's upward y and Flutter's downward y can be
  /// tested without a window or a screen.
  static func transitionGeometry(
    conversation: NSRect,
    orb: NSRect
  ) -> (canvas: NSRect, geometry: DesktopTransitionGeometry) {
    let canvas = conversation.union(orb)
    func placed(_ rect: NSRect) -> CGRect {
      CGRect(
        x: rect.minX - canvas.minX,
        y: canvas.maxY - rect.maxY,
        width: rect.width,
        height: rect.height
      )
    }
    return (
      canvas,
      DesktopTransitionGeometry(
        size: canvas.size,
        conversation: placed(conversation),
        orb: placed(orb)
      )
    )
  }

  /// Grows the window to cover both forms and stops it taking the mouse.
  ///
  /// The presence has to be drawn travelling between two places that no single
  /// form's window contains, so for the length of the move the window is the
  /// union of both and Flutter owns every pixel of it. The window is inert
  /// while it is this large, otherwise it would swallow clicks meant for
  /// whatever is underneath.
  func beginTransition() -> DesktopTransitionGeometry {
    precondition(Thread.isMainThread)
    guard let screen = screenProvider() ?? NSScreen.main else {
      let empty = NSRect.zero
      return Self.transitionGeometry(conversation: empty, orb: empty).geometry
    }
    // Remember the conversation's size before growing. Leaving the expanded
    // form normally records it, but during a transition the frame is the
    // union, and adopting that would reopen the conversation at canvas size.
    if storedMode == .expanded, hasPresentedExpanded {
      expandedSize = retainedPanel.frame.size
    }
    isTransitioning = true
    let visible = screen.visibleFrame
    let (canvas, geometry) = Self.transitionGeometry(
      conversation: conversationFrame(in: visible),
      orb: orbFrame(in: visible)
    )
    retainedPanel.ignoresMouseEvents = true
    retainedPanel.setFrame(canvas, display: true)
    retainedPanel.orderFrontRegardless()
    return geometry
  }

  /// Settles the window into `mode` and lets it take the mouse again.
  func endTransition(_ mode: DesktopPresentationMode) {
    precondition(Thread.isMainThread)
    retainedPanel.ignoresMouseEvents = false
    if mode == storedMode {
      // The form did not change after all, so nothing reports it; the frame
      // still has to come back from the canvas.
      applyFrame(for: mode)
    } else {
      setPresentationMode(mode)
    }
    isTransitioning = false
  }

  /// Where the orb rests on `visible`, in screen coordinates.
  ///
  /// Parked near the lower trailing corner, clear of the Dock.
  private func orbFrame(in visible: NSRect) -> NSRect {
    let side = Self.orbSide
    return NSRect(
      x: visible.maxX - side - Self.orbMargin,
      y: visible.minY + Self.orbMargin,
      width: side,
      height: side
    )
  }

  /// Where the conversation opens on `visible`, in screen coordinates.
  private func conversationFrame(in visible: NSRect) -> NSRect {
    let size = expandedSize
    return NSRect(
      x: visible.midX - size.width / 2,
      y: visible.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  private func applyFrame(for mode: DesktopPresentationMode) {
    guard let screen = screenProvider() ?? NSScreen.main else {
      return
    }
    let visible = screen.visibleFrame
    switch mode {
    case .orb:
      retainedPanel.setFrame(orbFrame(in: visible), display: true)
    case .expanded:
      hasPresentedExpanded = true
      retainedPanel.setFrame(conversationFrame(in: visible), display: true)
    }
  }

  /// Edge length of the desktop orb, in points.
  static let orbSide: CGFloat = 168
  /// Gap kept between the orb and the screen edges.
  static let orbMargin: CGFloat = 32

  var isVisible: Bool {
    retainedPanel.isVisible
  }

  func show() {
    precondition(Thread.isMainThread)
    let startedAt = performanceTimestamp()
    if !retainedPanel.isVisible {
      // Position for the current form: centring the orb would drop it in the
      // middle of the screen instead of its resting corner.
      applyFrame(for: storedMode)
    }
    let movedAt = performanceTimestamp()
    // The resting orb must never pull focus away from what the user is typing
    // into, so only the conversation form activates and takes key.
    let takesFocus = storedMode == .expanded
    if takesFocus {
      NSApp.activate(ignoringOtherApps: true)
    }
    let activatedAt = performanceTimestamp()
    retainedPanel.orderFrontRegardless()
    let orderedAt = performanceTimestamp()
    if takesFocus {
      retainedPanel.makeKey()
    }
    let completedAt = performanceTimestamp()
    if let startedAt, let movedAt, let activatedAt, let orderedAt, let completedAt {
      reportPanelPerformance(
        operation: "show",
        stages: [
          "move": movedAt - startedAt,
          "activate": activatedAt - movedAt,
          "order": orderedAt - activatedAt,
          "make_key": completedAt - orderedAt,
          "total": completedAt - startedAt,
        ]
      )
    }
  }

  func hide() {
    precondition(Thread.isMainThread)
    let startedAt = performanceTimestamp()
    retainedPanel.orderOut(nil)
    let completedAt = performanceTimestamp()
    if let startedAt, let completedAt {
      reportPanelPerformance(
        operation: "hide",
        stages: ["order_out": completedAt - startedAt, "total": completedAt - startedAt]
      )
    }
  }

  private func reportPanelPerformance(
    operation: String,
    stages: [String: UInt64]
  ) {
    let fields = stages.keys.sorted().map { key in
      "\"\(key)_micros\":\(stages[key]! / 1_000)"
    }.joined(separator: ",")
    print("panel_native_metric {\"operation\":\"\(operation)\",\(fields)}")
  }

  private func performanceTimestamp() -> UInt64? {
    guard Self.performanceMetricsEnabled else {
      return nil
    }
    return DispatchTime.now().uptimeNanoseconds
  }

  /// Switches between the desktop orb and the conversation.
  ///
  /// The window stays on screen in both forms, because the orb is the agent's
  /// resting presence rather than a hidden window. If it was ordered out
  /// entirely, this brings the orb back first.
  func toggle() {
    precondition(Thread.isMainThread)
    guard isVisible else {
      setPresentationMode(.orb)
      show()
      return
    }
    setPresentationMode(storedMode == .expanded ? .orb : .expanded)
  }

  private func moveToActiveDisplay() {
    guard let screen = screenProvider() else {
      return
    }
    let visibleFrame = screen.visibleFrame
    let origin = NSPoint(
      x: visibleFrame.midX - retainedPanel.frame.width / 2,
      y: visibleFrame.midY - retainedPanel.frame.height / 2
    )
    retainedPanel.setFrameOrigin(origin)
  }

  private static func screenAtPointer() -> NSScreen? {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
      ?? NSScreen.main
  }
}
