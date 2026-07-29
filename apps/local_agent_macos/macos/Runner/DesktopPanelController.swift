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
  func currentGeometry() -> DesktopTransitionGeometry
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
    // The conversation is an ordinary window and should close, minimise and
    // zoom like one, so the buttons have to exist even though the orb hides
    // them. A nib that omits these masks would leave them nil forever.
    panel.styleMask.formUnion([.closable, .miniaturizable, .resizable])
    Self.applyTitlebarChrome(for: storedMode, on: panel)
    // The two forms have very different sizes, so a remembered frame is a
    // liability: macOS would restore the orb's frame on the next launch and the
    // conversation would open at orb size. Each form positions itself instead.
    panel.setFrameAutosaveName("")
    startTrackingPointer()
  }

  deinit {
    for monitor in pointerMonitors {
      NSEvent.removeMonitor(monitor)
    }
  }

  /// Follows the pointer so the stage only takes the mouse where it is drawn.
  ///
  /// A window that ignores the mouse receives no events at all, so it cannot
  /// notice the pointer coming back. Watching globally is what lets it be
  /// given up and taken again.
  private func startTrackingPointer() {
    let events: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseDragged, .rightMouseDragged,
    ]
    let global = NSEvent.addGlobalMonitorForEvents(matching: events) {
      [weak self] _ in
      self?.updatePointerPassThrough()
    }
    if let global {
      pointerMonitors.append(global)
    }
    let local = NSEvent.addLocalMonitorForEvents(matching: events) {
      [weak self] event in
      self?.updatePointerPassThrough()
      return event
    }
    if let local {
      pointerMonitors.append(local)
    }
  }

  private func updatePointerPassThrough() {
    let wanted = !interactiveRect.contains(NSEvent.mouseLocation)
    if retainedPanel.ignoresMouseEvents != wanted {
      retainedPanel.ignoresMouseEvents = wanted
    }
  }

  /// Recomputes the part of the stage that is currently drawn on.
  private func updateInteractiveRect() {
    let geometry = currentGeometry()
    let placed = storedMode == .orb ? geometry.orb : geometry.conversation
    let frame = retainedPanel.frame
    // Flutter measures from the top-left with y growing downwards; AppKit
    // measures from the bottom-left with y growing upwards.
    interactiveRect = NSRect(
      x: frame.minX + placed.minX,
      y: frame.maxY - placed.maxY,
      width: placed.width,
      height: placed.height
    )
    updatePointerPassThrough()
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

  /// Reports a form change the app should draw, instead of making it happen.
  var onPresentationChangeRequested: ((DesktopPresentationMode) -> Void)?

  /// How long the app is given to start drawing a requested change of form.
  static let transitionRequestGrace: TimeInterval = 0.25
  private var pendingRequest: DispatchWorkItem?
  /// When the current change of form was asked for, for latency reporting.
  private var requestedAt: UInt64?

  /// Where on screen the window currently has something to click on.
  ///
  /// The window is the stage covering both forms and is therefore far larger
  /// than whichever form is showing. Left as it is, it would swallow every
  /// click over that whole area, including ones meant for whatever is behind
  /// it. Only the part actually being drawn takes the mouse.
  private var interactiveRect: NSRect = .zero
  private var pointerMonitors: [Any] = []
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
    storedMode = mode
    Self.applyTitlebarChrome(for: mode, on: retainedPanel)
    let chromed = performanceTimestamp()
    applyFrame(for: mode)
    let framed = performanceTimestamp()
    var focused: UInt64?
    switch mode {
    case .orb:
      // Give up focus so the desktop orb never sits in front of the user's
      // typing target.
      retainedPanel.resignKey()
      focused = performanceTimestamp()
      retainedPanel.orderFrontRegardless()
    case .expanded:
      NSApp.activate(ignoringOtherApps: true)
      focused = performanceTimestamp()
      retainedPanel.orderFrontRegardless()
      retainedPanel.makeKey()
    }
    if let chromed, let framed, let focused,
      let ordered = performanceTimestamp()
    {
      reportPanelPerformance(
        operation: "present_\(mode == .orb ? "orb" : "expanded")",
        stages: [
          "apply_frame": framed - chromed,
          "hand_over_focus": focused - framed,
          "order_front": ordered - focused,
        ]
      )
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
    updateInteractiveRect()
  }

  /// Shows the window buttons with the conversation and hides them with the orb.
  ///
  /// Static and taking its panel so it can run from `init`, before `self` is
  /// fully formed.
  private static func applyTitlebarChrome(
    for mode: DesktopPresentationMode,
    on panel: NSPanel
  ) {
    // The orb is a shader with a soft silhouette resting on the desktop.
    // Chrome floating beside it would frame it as a window again.
    let hidden = mode == .orb
    for button in [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ] {
      panel.standardWindowButton(button)?.isHidden = hidden
    }
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
    // The app answered, so the window must not settle itself underneath it.
    pendingRequest?.cancel()
    pendingRequest = nil
    let answered = performanceTimestamp()
    guard let screen = screenProvider() ?? NSScreen.main else {
      let empty = NSRect.zero
      return Self.transitionGeometry(conversation: empty, orb: empty).geometry
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
    if let requestedAt, let answered, let grown = performanceTimestamp() {
      // Splits the wait before anything can move into the part spent getting
      // the request to the app and back, and the part spent resizing the
      // window. They need different fixes, so they are reported apart.
      reportPanelPerformance(
        operation: "transition_begin",
        stages: [
          "round_trip": answered - requestedAt,
          "grow_window": grown - answered,
        ]
      )
    }
    return geometry
  }

  /// Settles the window into `mode` and lets it take the mouse again.
  func endTransition(_ mode: DesktopPresentationMode) {
    precondition(Thread.isMainThread)
    let landed = performanceTimestamp()
    if mode == storedMode {
      // The form did not change after all, so nothing reports it; the frame
      // still has to come back from the canvas.
      applyFrame(for: mode)
    } else {
      setPresentationMode(mode)
    }
    if let landed, let settled = performanceTimestamp(), let requestedAt {
      reportPanelPerformance(
        operation: "transition_end",
        stages: [
          "settle_window": settled - landed,
          "whole_change": settled - requestedAt,
        ]
      )
    }
    requestedAt = nil
    isTransitioning = false
    // Handed back to the pointer, which decides it from where the cursor is.
    updateInteractiveRect()
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

  /// Where each form sits inside the window, which never changes size.
  func currentGeometry() -> DesktopTransitionGeometry {
    precondition(Thread.isMainThread)
    guard let screen = screenProvider() ?? NSScreen.main else {
      return Self.transitionGeometry(conversation: .zero, orb: .zero).geometry
    }
    let visible = screen.visibleFrame
    return Self.transitionGeometry(
      conversation: conversationFrame(in: visible),
      orb: orbFrame(in: visible)
    ).geometry
  }

  /// The one frame the window keeps, whichever form it is showing.
  ///
  /// Both forms are drawn inside it and the window itself never changes size.
  /// Resizing a window that hosts the engine blocks until the engine returns a
  /// frame at the new size, and that wait is released by a one second timeout
  /// rather than by the frame arriving — measured at 1.004s on every collapse,
  /// a number too round to be work. A window that keeps one size never enters
  /// that wait, and there is nothing left for a change of form to stall on.
  func stageFrame(in visible: NSRect) -> NSRect {
    return Self.transitionGeometry(
      conversation: conversationFrame(in: visible),
      orb: orbFrame(in: visible)
    ).canvas
  }

  private func applyFrame(for mode: DesktopPresentationMode) {
    guard let screen = screenProvider() ?? NSScreen.main else {
      return
    }
    if mode == .expanded {
      hasPresentedExpanded = true
    }
    retainedPanel.setFrame(stageFrame(in: screen.visibleFrame), display: true)
    updateInteractiveRect()
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
    requestPresentationMode(storedMode == .expanded ? .orb : .expanded)
  }

  /// Asks the app to draw the change of form, and settles the window if it
  /// does not answer.
  ///
  /// The hotkey and the menu bar are native, so moving the window here would
  /// mean the app only ever heard about a change after it had happened and
  /// the presence could never be drawn travelling. Asking first hands that
  /// over. The fallback exists because a hotkey that depends on the Dart side
  /// being responsive is a hotkey that stops working under load.
  private func requestPresentationMode(_ mode: DesktopPresentationMode) {
    guard let request = onPresentationChangeRequested else {
      setPresentationMode(mode)
      return
    }
    pendingRequest?.cancel()
    let fallback = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pendingRequest = nil
      self.setPresentationMode(mode)
    }
    requestedAt = performanceTimestamp()
    pendingRequest = fallback
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.transitionRequestGrace,
      execute: fallback
    )
    request(mode)
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
