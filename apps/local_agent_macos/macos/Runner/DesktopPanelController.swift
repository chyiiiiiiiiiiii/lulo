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


/// Carries the resting orb's clicks, because the window itself must not.
///
/// While the agent rests, the window covering both forms gives up the mouse
/// so that nothing behind it is blocked. That takes the orb's own clicks with
/// it, so this panel — the size of the orb and nothing more — gets them back.
/// The orb itself is still drawn by the engine behind it.
final class OrbInputPanel {
  /// Creates the catcher, off screen until the agent rests.
  init(
    onSummon: @escaping () -> Void,
    onDragBy: @escaping (CGFloat, CGFloat) -> Void
  ) {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
    panel.contentView = OrbCatcherView(onSummon: onSummon, onDragBy: onDragBy)
    self.panel = panel
  }

  private let panel: NSPanel

  /// Puts the catcher exactly over the orb, or takes it away.
  func place(over rect: NSRect?) {
    guard let rect else {
      panel.orderOut(nil)
      return
    }
    panel.setFrame(rect, display: false)
    panel.orderFrontRegardless()
  }

  /// Whether the catcher is on screen, for tests.
  var isPlaced: Bool { panel.isVisible }

  /// What it covers, for tests.
  var placedFrame: NSRect { panel.frame }

  /// Its identity to the window server, so a test can ask who owns a point.
  var windowNumber: Int { panel.windowNumber }

  /// How far a press may travel and still count as a click.
  static let dragSlop: CGFloat = 3
}

/// Turns presses on the orb into either a summon or a drag.
final class OrbCatcherView: NSView {
  init(
    onSummon: @escaping () -> Void,
    onDragBy: @escaping (CGFloat, CGFloat) -> Void
  ) {
    self.onSummon = onSummon
    self.onDragBy = onDragBy
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  private let onSummon: () -> Void
  private let onDragBy: (CGFloat, CGFloat) -> Void
  private var travelled: CGFloat = 0

  /// Faint enough that no display can show it, solid enough to be there.
  ///
  /// The window server decides which window a click belongs to from the alpha
  /// a see-through window actually draws, not from its frame, so a catcher
  /// that painted nothing was not invisible but absent: every click on the orb
  /// went through it to the desktop and the agent answered only the hotkey.
  /// Anything below one part in 255 rounds away to nothing again.
  static let catchingTint = NSColor(white: 0, alpha: 0.01)

  /// Draws the orb's own circle, so the corners of the square stay passable.
  override func draw(_ dirtyRect: NSRect) {
    Self.catchingTint.setFill()
    NSBezierPath(ovalIn: bounds).fill()
  }

  /// Answers the very first click even when the app is not in front, or the
  /// click that reaches a background app is spent activating it and the agent
  /// would have to be clicked twice.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) { travelled = 0 }

  override func mouseDragged(with event: NSEvent) {
    travelled += abs(event.deltaX) + abs(event.deltaY)
    onDragBy(event.deltaX, event.deltaY)
  }

  override func mouseUp(with event: NSEvent) {
    if travelled <= OrbInputPanel.dragSlop { onSummon() }
    travelled = 0
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }
}

protocol DesktopPanelControlling: AnyObject {
  var isVisible: Bool { get }
  var presentationMode: DesktopPresentationMode { get }
  func show()
  func hide()
  func toggle()
  func setPresentationMode(_ mode: DesktopPresentationMode)
  func moveBy(deltaX: CGFloat, deltaY: CGFloat)
  func setWindowBehaviour(keepOrbOnTop: Bool, followAcrossSpaces: Bool)
  func currentGeometry() -> DesktopTransitionGeometry
  func beginTransition() -> DesktopTransitionGeometry
  func endTransition(_ mode: DesktopPresentationMode)
}

/// The window's content, which only answers the mouse where it is drawn.
///
/// The window is the stage covering both forms and is far larger than
/// whichever one is showing, so left alone it would swallow every click across
/// that whole area — including ones meant for whatever is behind it. Returning
/// nil from `hitTest` is what makes AppKit hand the event to the window below,
/// and it needs no permission to do it: watching the pointer with a global
/// event monitor does, and without that permission the window can never notice
/// the pointer coming back and stays deaf forever.
final class StagePassThroughView: NSView {
  /// The part of this view that is drawn on, in its own coordinates.
  var interactiveRect: NSRect = .zero

  /// Measured from the top-left, so the rectangles the app works in can be
  /// used here without being flipped first.
  override var isFlipped: Bool { true }

  /// Keeps the hosted content filling the stage.
  ///
  /// Set outright rather than by autoresizing, which scales proportionally and
  /// therefore keeps a subview that started with no bounds at no bounds — the
  /// app renders nothing and only the window chrome shows.
  override func layout() {
    super.layout()
    for subview in subviews where subview.frame != bounds {
      subview.frame = bounds
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    guard interactiveRect.contains(local) else {
      return nil
    }
    return super.hitTest(point)
  }
}

struct FlutterPanelContent {
  let engine: AnyObject
  let viewController: NSViewController
}

final class DesktopPanelController: NSObject, DesktopPanelControlling, NSWindowDelegate {
  private static let performanceMetricsEnabled =
    ProcessInfo.processInfo.environment["LOCAL_AGENT_PANEL_METRICS"] == "1"

  private(set) var retainedPanel: NSPanel
  private(set) var retainedEngine: AnyObject
  /// Held here because the window no longer owns it through a content
  /// controller.
  private(set) var retainedViewController: NSViewController!
  private var retainedStage: StagePassThroughView!

  /// Built the first time the agent rests, never during init.
  private lazy var orbInput: OrbInputPanel = OrbInputPanel(
    onSummon: { [weak self] in self?.requestPresentationMode(.expanded) },
    onDragBy: { [weak self] dx, dy in self?.moveBy(deltaX: dx, deltaY: dy) }
  )

  /// Whether the orb's catcher is on screen, for tests.
  var orbInputIsPlaced: Bool { orbInput.isPlaced }
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
    super.init()

    // The Flutter view is hosted inside a view that decides where the window
    // answers the mouse, so `contentViewController` cannot own the content.
    let stage = StagePassThroughView(frame: panel.contentLayoutRect)
    stage.autoresizingMask = [.width, .height]
    let hosted = content.viewController.view
    stage.addSubview(hosted)
    retainedViewController = content.viewController
    retainedStage = stage
    panel.contentView = stage
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
    panel.delegate = self
    applyWindowBehaviour(for: storedMode)
    updateInteractiveRect()
  }

  /// Tells the content which part of the stage is currently drawn on.
  private func updateInteractiveRect() {
    let geometry = currentGeometry()
    retainedStage.interactiveRect =
      storedMode == .orb ? geometry.orb : geometry.conversation
    // Returning nil from a view's hitTest is not enough on a titled window:
    // the window's own frame still takes the event, so the transparent stage
    // stood as an invisible wall across the desktop and nothing behind it
    // could be clicked. While the agent rests it gives up the mouse outright.
    // A resident assistant must not be in the way of anything.
    retainedPanel.ignoresMouseEvents = storedMode == .orb
    orbInput.place(over: storedMode == .orb ? orbScreenRect(geometry.orb) : nil)
  }

  /// Where a rectangle placed inside the stage sits on the screen.
  private func orbScreenRect(_ placed: CGRect) -> NSRect {
    let frame = retainedPanel.frame
    // Flutter measures from the top-left with y growing downwards; AppKit
    // measures from the bottom-left with y growing upwards.
    return NSRect(
      x: frame.minX + placed.minX,
      y: frame.maxY - placed.maxY,
      width: placed.width,
      height: placed.height
    )
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

  /// Whether the conversation frame has been applied at least once.
  private var hasPresentedExpanded = false
  /// Whether the agent has already settled on a display.
  private var hasChosenDisplay = false

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
    applyWindowBehaviour(for: mode)
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

  /// Whether the resting orb floats above other windows.
  private var keepOrbOnTop = true
  /// Whether the resting orb follows the user between Spaces.
  private var followAcrossSpaces = true

  /// Applies the user's choices about how the resting orb behaves.
  func setWindowBehaviour(keepOrbOnTop: Bool, followAcrossSpaces: Bool) {
    precondition(Thread.isMainThread)
    self.keepOrbOnTop = keepOrbOnTop
    self.followAcrossSpaces = followAcrossSpaces
    applyWindowBehaviour(for: storedMode)
  }

  /// Puts the conversation away rather than closing the agent.
  ///
  /// Lulo is resident: it has no closed state, only a resting one. Letting the
  /// close button do what it usually does would take the agent off the screen
  /// with nothing left to bring it back but the hotkey.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    precondition(Thread.isMainThread)
    if storedMode == .expanded {
      requestPresentationMode(.orb)
    }
    return false
  }

  /// Makes the window behave like what it currently is.
  ///
  /// The conversation is an ordinary window: it sits in the normal order, it
  /// activates the app so the menu bar is its own, and it belongs to one
  /// Space. The orb is a resting presence: it floats above other work, follows
  /// the user between Spaces, and never takes focus from what they are typing
  /// into.
  private func applyWindowBehaviour(for mode: DesktopPresentationMode) {
    switch mode {
    case .orb:
      // Back to an accessory: no Dock tile and no menu bar for something that
      // is only a presence on the desktop.
      NSApp.setActivationPolicy(.accessory)
      retainedPanel.level = keepOrbOnTop ? .floating : .normal
      retainedPanel.styleMask.insert(.nonactivatingPanel)
    case .expanded:
      // An accessory app has no menu bar at all, so its own commands would
      // have nowhere to live. The conversation is a real window and the app
      // becomes a real app for as long as it is showing.
      NSApp.setActivationPolicy(.regular)
      retainedPanel.level = .normal
      retainedPanel.styleMask.remove(.nonactivatingPanel)
    }
    applySpaceBehaviour()
  }

  /// Puts the window on the Spaces the user asked for, in either form.
  ///
  /// The conversation used to be tied to a single Space, on the reasoning that
  /// an ordinary window belongs to one. But this window is not opened, it is
  /// summoned — and summoning activates the app, which is what makes macOS
  /// carry the user off to whichever Space the window was tied to. An
  /// assistant answering a keystroke has to appear where the user already is.
  ///
  /// The one setting decides it for both forms, because a user who asked the
  /// resting orb to stay on one Space did not ask for the conversation to
  /// follow them everywhere.
  private func applySpaceBehaviour() {
    if followAcrossSpaces {
      retainedPanel.collectionBehavior.subtract([.managed])
      retainedPanel.collectionBehavior.formUnion([
        .canJoinAllSpaces, .fullScreenAuxiliary,
      ])
    } else {
      retainedPanel.collectionBehavior.subtract([.canJoinAllSpaces])
      retainedPanel.collectionBehavior.formUnion([
        .managed, .fullScreenAuxiliary,
      ])
    }
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
    guard let screen = currentScreen() else {
      let empty = NSRect.zero
      return Self.transitionGeometry(conversation: empty, orb: empty).geometry
    }
    isTransitioning = true
    let visible = screen.visibleFrame
    let (canvas, geometry) = Self.transitionGeometry(
      conversation: conversationFrame(in: visible),
      orb: orbFrame(in: visible)
    )
    retainedStage.interactiveRect = .zero
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
  ///
  /// Around the corner the agent rests in, and large enough to contain that
  /// resting place. The window is the union of both forms, and a window
  /// answers the mouse across the whole of its frame however little it draws
  /// there, so a conversation opening anywhere else leaves a wide margin of
  /// window with nothing in it — an invisible wall over the desktop, measured
  /// at half again the conversation's width and height. Sharing the orb's
  /// corner makes the union the conversation itself, and there is no margin
  /// left to be in anyone's way. It is also simply where a presence that lives
  /// in this corner should open from.
  private func conversationFrame(in visible: NSRect) -> NSRect {
    let size = expandedSize
    return NSRect(
      x: visible.maxX - size.width - Self.orbMargin,
      y: visible.minY + Self.orbMargin,
      width: size.width,
      height: size.height
    )
  }

  /// Where each form sits inside the window, which never changes size.
  func currentGeometry() -> DesktopTransitionGeometry {
    precondition(Thread.isMainThread)
    guard let screen = currentScreen() else {
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
    guard let screen = currentScreen() else {
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

  /// Centres the agent on the display the pointer is on.
  ///
  /// Only used the first time it appears. Doing it on every show dragged the
  /// agent onto whichever display the cursor happened to be over, so putting
  /// the conversation away could carry it to another screen.
  private func moveToActiveDisplay() {
    guard !hasChosenDisplay, let screen = screenProvider() else {
      return
    }
    hasChosenDisplay = true
    let visibleFrame = screen.visibleFrame
    let origin = NSPoint(
      x: visibleFrame.midX - retainedPanel.frame.width / 2,
      y: visibleFrame.midY - retainedPanel.frame.height / 2
    )
    retainedPanel.setFrameOrigin(origin)
  }

  /// The display the agent is already on.
  ///
  /// Deliberately not the one the pointer happens to be over. Asking the
  /// pointer meant every change of form dragged the agent onto whichever
  /// display the cursor was on at that instant, so putting the conversation
  /// away could move it to another screen entirely. It stays where it is; the
  /// pointer only decides where it appears the very first time.
  private func currentScreen() -> NSScreen? {
    retainedPanel.screen ?? screenProvider() ?? NSScreen.main
  }

  private static func screenAtPointer() -> NSScreen? {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
      ?? NSScreen.main
  }
}
