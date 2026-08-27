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

  /// Whether the window is the screen, which keeps the window buttons away
  /// until the pointer visits the top edge.
  var fullScreen: Bool = false
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
    onDragBy: @escaping (CGFloat, CGFloat) -> Void,
    onAction: @escaping (String) -> Void
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
    let catcher = OrbCatcherView(
      onSummon: onSummon,
      onDragBy: onDragBy,
      onAction: onAction
    )
    panel.contentView = catcher
    self.panel = panel
    self.catcher = catcher
  }

  private let panel: NSPanel
  private let catcher: OrbCatcherView

  /// What the strip offers, in the order it should offer it.
  var actions: [OrbAction] = [] {
    didSet {
      guard actions != oldValue else {
        return
      }
      catcher.actions = actions
      if let placed = placedOrb, let visible = placedVisible {
        place(over: placed, within: visible)
      }
    }
  }

  private var placedOrb: NSRect?
  private var placedVisible: NSRect?

  /// Puts the catcher over the orb and its strip beside it, or takes it away.
  ///
  /// The panel has to be large enough to hold both, because the strip is drawn
  /// into it — but it only *claims* the strip while the strip is showing. The
  /// window server routes a see-through window's clicks by the alpha it draws,
  /// so the part of this panel that is drawing nothing is not in anybody's way.
  func place(over rect: NSRect?, within visible: NSRect?) {
    guard let rect else {
      placedOrb = nil
      placedVisible = nil
      catcher.dismissStrip()
      panel.orderOut(nil)
      return
    }
    placedOrb = rect
    placedVisible = visible
    let strip =
      visible.flatMap {
        OrbActionStrip.layout(orb: rect, count: actions.count, within: $0)
      }
    let frame = strip.map { rect.union($0.strip) } ?? rect
    panel.setFrame(frame, display: false)
    catcher.describe(
      orb: NSRect(
        x: rect.minX - frame.minX,
        y: rect.minY - frame.minY,
        width: rect.width,
        height: rect.height
      ),
      strip: strip.map { layout in
        OrbStripLayout(
          strip: layout.strip.offsetBy(dx: -frame.minX, dy: -frame.minY),
          buttons: layout.buttons.map {
            $0.offsetBy(dx: -frame.minX, dy: -frame.minY)
          },
          above: layout.above
        )
      }
    )
    panel.orderFrontRegardless()
  }

  /// Whether the catcher is on screen, for tests.
  var isPlaced: Bool { panel.isVisible }

  /// Its identity to the window server, so a test can ask who owns a point.
  var windowNumber: Int { panel.windowNumber }

  /// The frame the catcher currently stands in, for tests.
  var frame: NSRect { panel.frame }

  /// Whether the strip is currently drawn, for tests.
  var stripIsShowing: Bool { catcher.stripIsShowing }

  /// Shows the strip without waiting out the dwell, for tests.
  func revealStripNow() { catcher.revealStrip() }

  /// How far a press may travel and still count as a click.
  static let dragSlop: CGFloat = 3
}

/// Turns presses on the orb into a summon, a drag, or one of its actions.
final class OrbCatcherView: NSView {
  init(
    onSummon: @escaping () -> Void,
    onDragBy: @escaping (CGFloat, CGFloat) -> Void,
    onAction: @escaping (String) -> Void
  ) {
    self.onSummon = onSummon
    self.onDragBy = onDragBy
    self.onAction = onAction
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  private let onSummon: () -> Void
  private let onDragBy: (CGFloat, CGFloat) -> Void
  private let onAction: (String) -> Void
  private var travelled: CGFloat = 0

  /// Which button the press started on, so a press that slid off does nothing.
  private var pressedButton: Int?

  /// What the strip offers.
  var actions: [OrbAction] = [] {
    didSet { needsDisplay = true }
  }

  /// Where the orb's square sits inside this view.
  private var orbRect: NSRect = .zero

  /// Where the strip sits inside this view, if there is one to draw.
  private var strip: OrbStripLayout?

  /// Whether the strip is currently drawn.
  private(set) var stripIsShowing = false

  /// Which button the pointer is over, or nil.
  private var hovered: Int?

  private var dwellTimer: Timer?

  /// Tells the view where the orb and its strip stand inside it.
  func describe(orb: NSRect, strip: OrbStripLayout?) {
    orbRect = orb
    self.strip = strip
    if strip == nil {
      dismissStrip()
    }
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  /// Shows the strip now, rather than after the dwell.
  func revealStrip() {
    dwellTimer?.invalidate()
    dwellTimer = nil
    guard strip != nil, !actions.isEmpty, !stripIsShowing else {
      return
    }
    stripIsShowing = true
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  /// Takes the strip away and stops any dwell that was counting towards it.
  func dismissStrip() {
    dwellTimer?.invalidate()
    dwellTimer = nil
    guard stripIsShowing || hovered != nil else {
      return
    }
    stripIsShowing = false
    hovered = nil
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
  }

  /// Faint enough that no display can show it, solid enough to be there.
  ///
  /// The window server decides which window a click belongs to from the alpha
  /// a see-through window actually draws, not from its frame, so a catcher
  /// that painted nothing was not invisible but absent: every click on the orb
  /// went through it to the desktop and the agent answered only the hotkey.
  /// Anything below one part in 255 rounds away to nothing again.
  static let catchingTint = NSColor(white: 0, alpha: 0.01)

  /// How much of the orb's square is body solid enough to catch clicks in.
  ///
  /// The tint above has to be drawn to be there at all, so wherever it reaches
  /// past the orb it is the only thing on that pixel and its edge stands on the
  /// desktop as a faint circle. Filling the whole square put that edge a full
  /// half-side out, where the orb draws nothing — and took every click within
  /// it away from whatever the user actually meant to hit.
  ///
  /// So the catcher stops inside the body rather than at its outermost vapour.
  /// Read off the capture in
  /// `integration_test/agent_presence_silhouette_test.dart`, where the resting
  /// orb still paints 90/255 at this fraction and nothing at all past 0.725.
  static let bodyFraction: CGFloat = 0.62

  /// The part of [bounds] this view catches in, centred and circular.
  static func catchingCircle(in bounds: NSRect) -> NSRect {
    let diameter = min(bounds.width, bounds.height) * bodyFraction
    return NSRect(
      x: bounds.midX - diameter / 2,
      y: bounds.midY - diameter / 2,
      width: diameter,
      height: diameter
    )
  }

  /// Draws the orb's own body, so the desktop around it stays passable.
  ///
  /// While the strip is showing the whole panel is claimed instead, because
  /// the gap between the orb and the capsule is drawn by nobody — and a gap
  /// the window server hands to the desktop is a gap the pointer disappears
  /// into on its way to the buttons, taking the strip with it.
  override func draw(_ dirtyRect: NSRect) {
    Self.catchingTint.setFill()
    NSBezierPath(ovalIn: Self.catchingCircle(in: orbRect)).fill()
    guard stripIsShowing, let strip else {
      return
    }
    NSBezierPath(rect: Self.bridge(from: orbRect, to: strip)).fill()
    drawCapsule(strip.strip)
    for (index, rect) in strip.buttons.enumerated() where index < actions.count {
      draw(actions[index], in: rect, hovered: hovered == index)
    }
  }

  /// The claimed path between the orb's body and the capsule.
  ///
  /// The gap between them is drawn by nobody, and a gap the window server
  /// hands to the desktop is a gap the pointer disappears into on its way to
  /// the buttons: `mouseExited` fires, the strip goes away, and it can never
  /// be reached. So it is claimed — but only as wide as the capsule and only
  /// as far as the orb's centre, rather than the whole panel.
  ///
  /// The difference is measurable. The catching tint has to be drawn to exist
  /// at all, so on a flat sky it is a real step of about 3/255 wherever it is
  /// the only thing on the pixel. Claiming the whole panel put that step
  /// around a rectangle standing well clear of everything drawn; this keeps it
  /// under the capsule, where there is already a capsule.
  static func bridge(from orb: NSRect, to strip: OrbStripLayout) -> NSRect {
    let capsule = strip.strip
    let top = max(capsule.maxY, orb.midY)
    let bottom = min(capsule.minY, orb.midY)
    return NSRect(
      x: capsule.minX,
      y: bottom,
      width: capsule.width,
      height: top - bottom
    )
  }

  private func drawCapsule(_ rect: NSRect) {
    let path = NSBezierPath(
      roundedRect: rect,
      xRadius: OrbActionStrip.cornerRadius,
      yRadius: OrbActionStrip.cornerRadius
    )
    NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
    path.fill()
    NSColor.separatorColor.setStroke()
    path.lineWidth = 1
    path.stroke()
  }

  private func draw(_ action: OrbAction, in rect: NSRect, hovered: Bool) {
    if hovered || action.engaged {
      let highlight = NSBezierPath(
        roundedRect: rect.insetBy(dx: 1, dy: 1),
        xRadius: (rect.height - 2) / 2,
        yRadius: (rect.height - 2) / 2
      )
      (action.engaged
        ? NSColor.controlAccentColor
        : NSColor.separatorColor.withAlphaComponent(0.5)).setFill()
      highlight.fill()
    }
    let tint = action.engaged ? NSColor.white : NSColor.labelColor
    guard
      let symbol = NSImage(
        systemSymbolName: action.symbol,
        accessibilityDescription: action.label
      )?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
      )
    else {
      return
    }
    // Tinted inside an image of its own, never against this view's backing.
    // `sourceAtop` composites over whatever is already opaque underneath, and
    // underneath here is the capsule — so tinting in place painted a solid
    // block of label colour across the whole button with the glyph knocked
    // out of it. Given its own context, the only alpha to sit atop is the
    // symbol's.
    let size = symbol.size
    let tinted = NSImage(size: size, flipped: false) { bounds in
      symbol.draw(in: bounds)
      tint.set()
      bounds.fill(using: .sourceAtop)
      return true
    }
    tinted.draw(
      in: NSRect(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2,
        width: size.width,
        height: size.height
      )
    )
  }

  /// Answers the very first click even when the app is not in front, or the
  /// click that reaches a background app is spent activating it and the agent
  /// would have to be clicked twice.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [
          .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect,
        ],
        owner: self,
        userInfo: nil
      )
    )
  }

  override func mouseEntered(with event: NSEvent) {
    beginDwell()
  }

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let index = buttonIndex(at: point)
    if index != hovered {
      hovered = index
      needsDisplay = true
    }
    if !stripIsShowing && dwellTimer == nil {
      beginDwell()
    }
  }

  override func mouseExited(with event: NSEvent) {
    dismissStrip()
  }

  private func beginDwell() {
    guard !stripIsShowing, strip != nil, !actions.isEmpty else {
      return
    }
    dwellTimer?.invalidate()
    dwellTimer = Timer.scheduledTimer(
      withTimeInterval: OrbActionStrip.dwell,
      repeats: false
    ) { [weak self] _ in
      self?.revealStrip()
    }
  }

  /// Which button contains [point], while there is a strip showing to hit.
  private func buttonIndex(at point: NSPoint) -> Int? {
    guard stripIsShowing, let strip else {
      return nil
    }
    for (index, rect) in strip.buttons.enumerated() where index < actions.count {
      if rect.contains(point) {
        return index
      }
    }
    return nil
  }

  override func mouseDown(with event: NSEvent) {
    travelled = 0
    pressedButton = buttonIndex(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    // A press that began on a button is a press, not a handle: dragging the
    // whole agent off the screen by its microphone is not what was meant.
    guard pressedButton == nil else {
      return
    }
    travelled += abs(event.deltaX) + abs(event.deltaY)
    onDragBy(event.deltaX, event.deltaY)
  }

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let pressed = pressedButton {
      pressedButton = nil
      travelled = 0
      if buttonIndex(at: point) == pressed, pressed < actions.count {
        onAction(actions[pressed].id)
      }
      return
    }
    if travelled <= OrbInputPanel.dragSlop, buttonIndex(at: point) == nil {
      onSummon()
    }
    travelled = 0
  }

  override func resetCursorRects() {
    // A rectangle is the only shape a cursor rect comes in, so this is the
    // circle's box. It cannot reach past the catching circle in the directions
    // that matter, because the pointer only arrives here at all where the
    // window server already decided this window owns the point.
    addCursorRect(Self.catchingCircle(in: orbRect), cursor: .pointingHand)
    guard stripIsShowing, let strip else {
      return
    }
    for rect in strip.buttons {
      addCursorRect(rect, cursor: .pointingHand)
    }
  }

  /// The strip's buttons, so VoiceOver can reach what the pointer can.
  ///
  /// The orb itself is reached through Flutter's semantics on
  /// `DesktopOrbSurface`; these are drawn by AppKit and have no such path.
  override func accessibilityChildren() -> [Any]? {
    guard let strip else {
      return nil
    }
    return zip(actions, strip.buttons).map { action, rect in
      let element = NSAccessibilityElement()
      element.setAccessibilityRole(.button)
      element.setAccessibilityLabel(action.label)
      element.setAccessibilityParent(self)
      element.setAccessibilityFrameInParentSpace(rect)
      return element
    }
  }
}

protocol DesktopPanelControlling: AnyObject {
  var isVisible: Bool { get }
  var presentationMode: DesktopPresentationMode { get }
  func show()
  func hide()
  func toggle()
  func setPresentationMode(_ mode: DesktopPresentationMode)
  func setOrbActions(_ actions: [OrbAction])
  func moveBy(deltaX: CGFloat, deltaY: CGFloat)
  func setWindowBehaviour(keepOrbOnTop: Bool, followAcrossSpaces: Bool)
  func currentGeometry() -> DesktopTransitionGeometry
  func beginTransition(to target: DesktopPresentationMode)
    -> DesktopTransitionGeometry
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

  /// The frosted glass under the conversation, as a window of its own.
  ///
  /// Deliberately not a view inside the conversation's window: an
  /// NSVisualEffectView blurring behind that window intermittently took the
  /// window's whole mouse with it — every click and every scroll — measured
  /// 2026-08-18 on the same build with the view in and out of the stage. A
  /// separate window that ignores the mouse outright cannot repeat that,
  /// whatever the window server makes of the blur. Without the pane the
  /// panel is clear for the orb's sake, and the conversation's translucent
  /// surface would sit over whatever windows happen to be behind it, crisp
  /// and unreadable.
  private(set) lazy var glassWindow: NSWindow = {
    let glass = NSWindow(
      contentRect: retainedPanel.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    glass.isOpaque = false
    glass.backgroundColor = .clear
    glass.hasShadow = false
    glass.ignoresMouseEvents = true
    glass.isReleasedWhenClosed = false
    glass.animationBehavior = .none
    let pane = NSVisualEffectView(frame: glass.contentLayoutRect)
    pane.autoresizingMask = [.width, .height]
    pane.blendingMode = .behindWindow
    pane.material = .hudWindow
    pane.state = .active
    // The same rounding the Flutter side draws (`windowCornerRadius`),
    // applied as a mask because a plain layer radius does not clip a
    // behind-window blur's backdrop.
    pane.maskImage = Self.roundedCornerMask(radius: 12)
    glass.contentView = pane
    return glass
  }()

  /// Built the first time the agent rests, never during init.
  private lazy var orbInput: OrbInputPanel = OrbInputPanel(
    onSummon: { [weak self] in self?.requestPresentationMode(.expanded) },
    onDragBy: { [weak self] dx, dy in self?.moveBy(deltaX: dx, deltaY: dy) },
    onAction: { [weak self] id in self?.onOrbActionInvoked?(id) }
  )

  /// Whether the orb's catcher is on screen, for tests.
  var orbInputIsPlaced: Bool { orbInput.isPlaced }

  /// The catcher itself, so a test can ask what it is showing.
  var orbInputPanel: OrbInputPanel { orbInput }

  /// The user pressed one of the buttons on the resting orb's strip.
  var onOrbActionInvoked: ((String) -> Void)?

  /// Tells the resting orb what to offer the next time it is hovered.
  func setOrbActions(_ actions: [OrbAction]) {
    precondition(Thread.isMainThread)
    orbInput.actions = actions
  }
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
    updateGlass()
    updateInteractiveRect()
  }

  /// Rides the glass under the conversation, and only under the conversation.
  ///
  /// The resting orb sits on the bare desktop, and during a change of form the
  /// conversation shrinks out from under what would be a full-size pane, so
  /// both take it away.
  private func updateGlass() {
    if storedMode == .expanded && !isTransitioning {
      glassWindow.setFrame(retainedPanel.frame, display: false)
      glassWindow.level = retainedPanel.level
      if glassWindow.parent !== retainedPanel {
        retainedPanel.addChildWindow(glassWindow, ordered: .below)
      }
    } else if glassWindow.parent != nil {
      retainedPanel.removeChildWindow(glassWindow)
      glassWindow.orderOut(nil)
    }
  }

  /// A stretchable rounded rectangle for the glass's corners.
  ///
  /// The Flutter side clips the conversation to `windowCornerRadius`; the
  /// glass under it has to end at the same corner or it pokes out as four
  /// square ones.
  private static func roundedCornerMask(radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(
      size: NSSize(width: edge, height: edge),
      flipped: false
    ) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(
      top: radius,
      left: radius,
      bottom: radius,
      right: radius
    )
    image.resizingMode = .stretch
    return image
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
    orbInput.place(
      over: storedMode == .orb ? orbScreenRect(geometry.orb) : nil,
      within: currentScreen()?.visibleFrame
    )
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

  /// The size the stage first opens at.
  ///
  /// Only the first placement uses it; from then on the window is whatever the
  /// user has made it.
  private let expandedSize: NSSize = NSSize(width: 720, height: 560)
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
    // Written down before the mode flips, or the frame the conversation is
    // leaving would be forgotten the moment it left. Never during a drawn
    // transition: by then the window has already glided towards the orb's
    // corner, and that corner is not where the user keeps their conversation.
    if !isTransitioning {
      rememberExpandedFrame()
    }
    storedMode = mode
    Self.applyTitlebarChrome(for: mode, on: retainedPanel)
    applyWindowBehaviour(for: mode)
    updateGlass()
    let chromed = performanceTimestamp()
    placeStageIfNeeded()
    // Each form has its home: the orb the screen's corner, the conversation
    // wherever the user had it. Reached here as well as through a drawn
    // transition, because the hotkey's fallback settles the window without
    // one and must land in the same place.
    if !isTransitioning && !isFullScreen {
      retainedPanel.setFrame(homeFrame(for: mode), display: true)
      updateInteractiveRect()
    }
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
      retainedPanel.isFloatingPanel = true
      // The resting orb may sit over another app's full screen, but it is not
      // itself a thing to make full screen.
      retainedPanel.collectionBehavior.subtract([.fullScreenPrimary])
      retainedPanel.collectionBehavior.formUnion([.fullScreenAuxiliary])
    case .expanded:
      // An accessory app has no menu bar at all, so its own commands would
      // have nowhere to live. The conversation is a real window and the app
      // becomes a real app for as long as it is showing.
      NSApp.setActivationPolicy(.regular)
      retainedPanel.level = .normal
      retainedPanel.styleMask.remove(.nonactivatingPanel)
      // A floating panel is what AppKit refuses to make full screen, and the
      // conversation is an ordinary window: its green button offers Full
      // Screen like anyone else's.
      retainedPanel.isFloatingPanel = false
      retainedPanel.collectionBehavior.subtract([.fullScreenAuxiliary])
      retainedPanel.collectionBehavior.formUnion([.fullScreenPrimary])
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
      retainedPanel.collectionBehavior.formUnion([.canJoinAllSpaces])
    } else {
      retainedPanel.collectionBehavior.subtract([.canJoinAllSpaces])
      retainedPanel.collectionBehavior.formUnion([.managed])
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

  /// Turns the window into the canvas the change of form is drawn on.
  ///
  /// The window covers both forms wherever it stands, so nothing has to grow;
  /// it stops answering the mouse while the presence is in flight and puts its
  /// chrome away — the buttons belong to the conversation, and left standing
  /// they hang beside a form that is visibly shrinking out from underneath
  /// them.
  ///
  /// It also starts gliding towards the target form's home, keeping its size:
  /// collapsing goes to the screen's corner, summoning back to wherever the
  /// user had the conversation. Moving alongside the flight rather than after
  /// it is what makes the presence appear to travel to the corner of the
  /// screen, not to the corner of a window that then jumps. Only the origin
  /// moves, so the engine is never asked for a frame at a new size and the
  /// resize stall stays gone.
  func beginTransition(
    to target: DesktopPresentationMode
  ) -> DesktopTransitionGeometry {
    precondition(Thread.isMainThread)
    // The app answered, so the window must not settle itself underneath it.
    pendingRequest?.cancel()
    pendingRequest = nil
    let answered = performanceTimestamp()
    // The conversation's place is written down before the window starts
    // moving away from it.
    rememberExpandedFrame()
    isTransitioning = true
    updateGlass()
    Self.applyTitlebarChrome(for: .orb, on: retainedPanel)
    retainedStage.interactiveRect = .zero
    retainedPanel.orderFrontRegardless()
    let home = homeFrame(for: target)
    // Never while the window is the screen: a full-screen window's frame
    // belongs to the system, and setting it from here fights the Space.
    if !isFullScreen && home != retainedPanel.frame {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.22
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        retainedPanel.animator().setFrame(home, display: true)
      }
    }
    if let requestedAt, let answered, let ready = performanceTimestamp() {
      reportPanelPerformance(
        operation: "transition_begin",
        stages: [
          "round_trip": answered - requestedAt,
          "prepare_canvas": ready - answered,
        ]
      )
    }
    return currentGeometry()
  }

  /// Settles the window into `mode` and lets it take the mouse again.
  func endTransition(_ mode: DesktopPresentationMode) {
    precondition(Thread.isMainThread)
    let landed = performanceTimestamp()
    // Parked exactly at the target form's home, however far the glide got —
    // unless the window is the screen, whose frame belongs to the system.
    if !isFullScreen {
      retainedPanel.setFrame(homeFrame(for: mode), display: true)
    }
    if mode == storedMode {
      // The form did not change after all; the buttons it hid for the journey
      // still have to come back.
      Self.applyTitlebarChrome(for: mode, on: retainedPanel)
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
    updateGlass()
    // Handed back to the pointer, which decides it from where the cursor is.
    updateInteractiveRect()
  }

  /// Where the orb rests inside the stage, in screen coordinates.
  ///
  /// In the stage's own corner: the orb lives inside the conversation's
  /// rectangle so that the window is never larger than the conversation — any
  /// part of the window the conversation does not fill answers the mouse as an
  /// invisible wall over the desktop.
  private func orbRect(inStage frame: NSRect) -> NSRect {
    let side = Self.orbSide
    return NSRect(
      x: frame.maxX - side,
      y: frame.minY,
      width: side,
      height: side
    )
  }

  /// Where each form sits inside the window, as the window currently stands.
  ///
  /// Derived from the window's own frame rather than recomputed from the
  /// screen, so wherever the user has dragged or resized it is where the forms
  /// are. A geometry that answered from the screen instead is what kept
  /// snapping the window back to its birth corner on every change of form.
  func currentGeometry() -> DesktopTransitionGeometry {
    precondition(Thread.isMainThread)
    let frame = retainedPanel.frame
    var geometry = Self.transitionGeometry(
      conversation: frame,
      orb: orbRect(inStage: frame)
    ).geometry
    geometry.fullScreen = isFullScreen
    return geometry
  }

  /// Where the stage first opens: by the lower trailing corner, clear of the
  /// Dock, which is the corner the resting orb lives in.
  private func initialStageFrame(in visible: NSRect) -> NSRect {
    let size = expandedSize
    return NSRect(
      x: visible.maxX - size.width - Self.orbMargin,
      y: visible.minY + Self.orbMargin,
      width: size.width,
      height: size.height
    )
  }

  /// Whether the stage has been given its first place on a screen.
  private var hasPlacedStage = false

  /// The conversation's frame as the user last had it.
  ///
  /// The orb always goes home to the screen's corner, so without this the
  /// conversation would be summoned back at the orb's corner rather than
  /// where the user had put it.
  private var rememberedExpandedFrame: NSRect?

  /// Places the stage the first time, and afterwards leaves it alone.
  ///
  /// Once only, deliberately: after this the frame belongs to the user.
  /// Wherever they drag or resize the window is where it stays, through every
  /// collapse and summon. Re-deriving the frame here on each change of form is
  /// what kept teleporting the window back to its opening corner.
  private func placeStageIfNeeded() {
    if !hasPlacedStage, let screen = currentScreen() {
      hasPlacedStage = true
      let frame = initialStageFrame(in: screen.visibleFrame)
      rememberedExpandedFrame = frame
      retainedPanel.setFrame(frame, display: true)
    }
    updateInteractiveRect()
  }

  /// Where the window sits for [mode], as the user has arranged things.
  ///
  /// The two forms have two homes. The conversation lives wherever the user
  /// dragged and sized it. The resting orb lives in the screen's lower
  /// trailing corner — always, because a resting place that wandered with the
  /// window meant collapsing left the orb wherever work happened to be. Only
  /// the origin differs: the window never changes size for a change of form,
  /// which is what keeps the engine out of the resize stall.
  private func homeFrame(for mode: DesktopPresentationMode) -> NSRect {
    let current = retainedPanel.frame
    switch mode {
    case .expanded:
      var home = rememberedExpandedFrame ?? current
      // The size belongs to the user's latest resize even if the remembered
      // origin is older.
      home.size = current.size
      return home
    case .orb:
      guard let screen = currentScreen() else {
        return current
      }
      let visible = screen.visibleFrame
      return NSRect(
        x: visible.maxX - Self.orbMargin - current.width,
        y: visible.minY + Self.orbMargin,
        width: current.width,
        height: current.height
      )
    }
  }

  /// Follows the user resizing the window, including into full screen.
  ///
  /// The forms are laid out against the window's frame, so when the frame
  /// changes the app has to hear about it or the conversation keeps drawing at
  /// the size the window no longer is.
  func windowDidResize(_ notification: Notification) {
    guard !isTransitioning else {
      return
    }
    rememberExpandedFrame()
    // Moving is inherited from being a child window; resizing is not.
    updateGlass()
    updateInteractiveRect()
    onGeometryChanged?(currentGeometry())
  }

  /// Follows the user dragging the window, which chooses where the
  /// conversation is summoned back to.
  func windowDidMove(_ notification: Notification) {
    guard !isTransitioning else {
      return
    }
    rememberExpandedFrame()
  }

  /// Writes down the conversation's place whenever the user changes it.
  ///
  /// Only the conversation's: the orb going home to its corner, or being
  /// dragged around the desktop, says nothing about where the user wants
  /// their conversation.
  private func rememberExpandedFrame() {
    if storedMode == .expanded && !isFullScreen {
      rememberedExpandedFrame = retainedPanel.frame
    }
  }

  /// Reports the stage's geometry whenever the window's frame changes it.
  var onGeometryChanged: ((DesktopTransitionGeometry) -> Void)?

  /// Stands in for the real full-screen bit in tests.
  ///
  /// AppKit refuses to set `.fullScreen` on a window outside a real
  /// full-screen transition, so the tests that pin full-screen behaviour need
  /// somewhere else to say it.
  var isFullScreenOverride: (() -> Bool)?

  /// Whether the window is currently the screen.
  private var isFullScreen: Bool {
    isFullScreenOverride?() ?? retainedPanel.styleMask.contains(.fullScreen)
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
      // The first appearance chooses the resting corner; every later one keeps
      // whatever place the user has given the window since.
      placeStageIfNeeded()
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
