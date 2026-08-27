import AppKit
import XCTest

@testable import Lulo

@MainActor
final class DesktopPanelControllerTests: XCTestCase {
  func testToggleRetainsOnePanelAndOneFlutterEngine() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    let engine = NSObject()
    let viewController = NSViewController()
    var contentFactoryCalls = 0

    let controller = DesktopPanelController(panel: panel) {
      contentFactoryCalls += 1
      return FlutterPanelContent(engine: engine, viewController: viewController)
    }

    XCTAssertEqual(contentFactoryCalls, 1)
    XCTAssertTrue(controller.retainedPanel === panel)
    XCTAssertTrue(controller.retainedEngine === engine)
    // The window hosts the Flutter view inside a view that decides where it
    // answers the mouse, so it is a subview rather than the content itself.
    XCTAssertTrue(controller.retainedViewController === viewController)
    XCTAssertTrue(viewController.view.superview === panel.contentView)
    XCTAssertTrue(panel.contentView is StagePassThroughView)

    controller.show()
    controller.toggle()
    controller.toggle()
    controller.hide()

    XCTAssertEqual(contentFactoryCalls, 1)
    XCTAssertTrue(controller.retainedPanel === panel)
    XCTAssertTrue(controller.retainedEngine === engine)
  }

  func testTransitionCanvasCoversBothFormsMeasuredTheWayFlutterLaysOut() {
    // Screen coordinates: y grows upwards from the bottom of the screen.
    let conversation = NSRect(x: 100, y: 300, width: 720, height: 560)
    let orb = NSRect(x: 1200, y: 32, width: 168, height: 168)

    let (canvas, geometry) = DesktopPanelController.transitionGeometry(
      conversation: conversation,
      orb: orb
    )

    // The canvas has to contain both, or the presence would be clipped part
    // way through the move.
    XCTAssertEqual(canvas, NSRect(x: 100, y: 32, width: 1268, height: 828))
    XCTAssertEqual(geometry.size, CGSize(width: 1268, height: 828))

    // Inside the canvas y grows downwards, because that is how Flutter places
    // things. The conversation is the topmost form, so it starts at zero.
    XCTAssertEqual(
      geometry.conversation,
      CGRect(x: 0, y: 0, width: 720, height: 560)
    )
    // The orb rests near the bottom trailing corner, so it lands low and late
    // in both axes.
    XCTAssertEqual(geometry.orb, CGRect(x: 1100, y: 660, width: 168, height: 168))
  }

  func testTransitionCanvasDoesNotGrowWhenOneFormAlreadyContainsTheOther() {
    let conversation = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let orb = NSRect(x: 1200, y: 40, width: 168, height: 168)

    let (canvas, geometry) = DesktopPanelController.transitionGeometry(
      conversation: conversation,
      orb: orb
    )

    XCTAssertEqual(canvas, conversation)
    XCTAssertEqual(geometry.orb, CGRect(x: 1200, y: 692, width: 168, height: 168))
  }

  func testWindowButtonsBelongToTheConversationAndNotToTheOrb() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    let controller = DesktopPanelController(panel: panel) {
      FlutterPanelContent(engine: NSObject(), viewController: NSViewController())
    }
    let buttons: [NSWindow.ButtonType] = [
      .closeButton, .miniaturizeButton, .zoomButton,
    ]

    // The orb is a shader with a soft silhouette resting on the desktop.
    // Window chrome floating beside it would frame it as a window again.
    controller.setPresentationMode(.orb)
    for button in buttons {
      XCTAssertTrue(
        panel.standardWindowButton(button)?.isHidden ?? false,
        "\(button) was visible beside the orb"
      )
    }

    // The conversation is an ordinary window and should close and zoom like
    // one, so the buttons come back with it.
    controller.setPresentationMode(.expanded)
    for button in buttons {
      XCTAssertFalse(
        panel.standardWindowButton(button)?.isHidden ?? true,
        "\(button) stayed hidden on the conversation"
      )
    }
  }

  func testTheHotkeyAsksTheAppToDrawTheChangeOfForm() {
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.expanded)
    var requested: [DesktopPresentationMode] = []
    controller.onPresentationChangeRequested = { requested.append($0) }

    controller.toggle()

    // Asking rather than acting is what lets the presence be drawn travelling
    // between the two forms.
    XCTAssertEqual(requested, [.orb])
    XCTAssertEqual(controller.presentationMode, .expanded)

    // Answering cancels the fallback, so the window stays on the canvas for
    // as long as the app needs to draw the move.
    _ = controller.beginTransition(to: .orb)
    let settled = expectation(description: "the window was not settled for us")
    settled.isInverted = true
    DispatchQueue.main.asyncAfter(
      deadline: .now() + DesktopPanelController.transitionRequestGrace * 3
    ) {
      if controller.presentationMode == .orb { settled.fulfill() }
    }
    wait(for: [settled], timeout: 1)

    controller.endTransition(.orb)
    XCTAssertEqual(controller.presentationMode, .orb)
  }

  func testAnUnansweredRequestStillMovesTheWindow() {
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.expanded)
    // An app that never answers, which is what a wedged Dart isolate looks
    // like from here. The hotkey has to keep working anyway.
    controller.onPresentationChangeRequested = { _ in }

    controller.toggle()
    XCTAssertEqual(controller.presentationMode, .expanded)

    let settled = expectation(description: "the window settled itself")
    DispatchQueue.main.asyncAfter(
      deadline: .now() + DesktopPanelController.transitionRequestGrace * 3
    ) {
      if controller.presentationMode == .orb { settled.fulfill() }
    }
    wait(for: [settled], timeout: 2)
  }

  func testTheConversationRestsOnFrostedGlassAndTheOrbOnBareDesktop() {
    let controller = Self.makeController()
    let glass = controller.glassWindow
    // A window of its own underneath the conversation, never a view inside
    // it: an NSVisualEffectView in the conversation's own window
    // intermittently took the window's whole mouse with it — every click
    // and every scroll — and a window that ignores the mouse outright
    // cannot repeat that.
    XCTAssertTrue(glass.ignoresMouseEvents)
    let pane = glass.contentView as? NSVisualEffectView
    XCTAssertEqual(pane?.blendingMode, .behindWindow)
    XCTAssertEqual(pane?.state, .active)

    // The conversation is the visible form by default, so the glass rides
    // under it, at its exact frame.
    XCTAssertTrue(
      controller.retainedPanel.childWindows?.contains(glass) ?? false
    )
    XCTAssertEqual(glass.frame, controller.retainedPanel.frame)
    // The resting orb sits on the bare desktop; a glass rectangle behind it
    // would frame the vapour in a window again.
    controller.setPresentationMode(.orb)
    XCTAssertFalse(
      controller.retainedPanel.childWindows?.contains(glass) ?? false
    )
    XCTAssertFalse(glass.isVisible)
    controller.setPresentationMode(.expanded)
    XCTAssertTrue(
      controller.retainedPanel.childWindows?.contains(glass) ?? false
    )
  }

  func testTheGlassStaysAwayWhileTheChangeOfFormIsDrawn() {
    let controller = Self.makeController()
    let glass = controller.glassWindow
    func underConversation() -> Bool {
      controller.retainedPanel.childWindows?.contains(glass) ?? false
    }

    // Collapsing: the conversation shrinks out from under a full-size pane of
    // glass, so the glass has to leave the moment the flight starts.
    _ = controller.beginTransition(to: .orb)
    XCTAssertFalse(underConversation())
    controller.endTransition(.orb)
    XCTAssertFalse(underConversation())

    // Summoning: the glass waits until the conversation has landed.
    _ = controller.beginTransition(to: .expanded)
    XCTAssertFalse(underConversation())
    controller.endTransition(.expanded)
    XCTAssertTrue(underConversation())
  }

  func testTheGlassFollowsAResizedConversation() {
    let controller = Self.makeController()
    let panel = controller.retainedPanel
    // Moving is inherited from being a child window; resizing is not, and a
    // pane left at the old size pokes out of the corner of a shrunk window.
    panel.setFrame(
      NSRect(x: 40, y: 60, width: 900, height: 700),
      display: false
    )
    controller.windowDidResize(
      Notification(name: NSWindow.didResizeNotification, object: panel)
    )
    XCTAssertEqual(controller.glassWindow.frame, panel.frame)
  }

  private static func makeController() -> DesktopPanelController {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    return DesktopPanelController(panel: panel) {
      FlutterPanelContent(engine: NSObject(), viewController: NSViewController())
    }
  }

  func testTheWindowIsTheSameSizeInBothForms() {
    let controller = Self.makeController()
    controller.show()

    controller.setPresentationMode(.expanded)
    let conversation = controller.retainedPanel.frame

    controller.setPresentationMode(.orb)
    let orb = controller.retainedPanel.frame

    // Resizing a window that hosts the engine blocks until the engine returns
    // a frame at the new size, and that wait is released by a one second
    // timeout rather than by the frame arriving. Measured at 1.004s on every
    // collapse. A change of form may move the window — the orb goes home to
    // the screen's corner — but it must never change its size.
    XCTAssertEqual(
      conversation.size,
      orb.size,
      "The window changed size between forms and will stall for a second"
    )

    // It has to be large enough for both, or one of them is cut off.
    XCTAssertTrue(orb.width >= 720 && orb.height >= 560)
  }

  func testTheRestingAgentStandsInNobodysWay() {
    let controller = Self.makeController()
    controller.show()

    // Returning nil from a view's hitTest is not enough on a titled window:
    // the frame still takes the event, so the transparent stage stood as an
    // invisible wall over everything behind it. A resident assistant must not
    // be in the way of anything, so while it rests it gives up the mouse.
    controller.setPresentationMode(.orb)
    XCTAssertTrue(
      controller.retainedPanel.ignoresMouseEvents,
      "The resting agent is still taking clicks meant for other apps"
    )

    // Giving up the mouse takes the orb's own clicks with it, so something
    // the size of the orb and nothing more has to carry them back.
    XCTAssertTrue(
      controller.orbInputIsPlaced,
      "Nothing is left to click the resting agent with"
    )

    // The conversation is an ordinary window and answers for itself.
    controller.setPresentationMode(.expanded)
    XCTAssertFalse(controller.retainedPanel.ignoresMouseEvents)
    XCTAssertFalse(
      controller.orbInputIsPlaced,
      "The catcher stayed over a conversation that answers for itself"
    )
  }

  func testTheMenuBarSaysWhatTheAgentIsAndWhatItHasBeenDoing() {
    // A menu holding show/hide and quit is a menu with no reason to be
    // opened. Half of what a resident app is worth is in this menu, and it
    // was empty.
    let controller = Self.makeController()
    let menu = MenuBarController(
      panelController: controller,
      statusBar: NSStatusBar()
    )

    menu.apply(
      MenuBarController.State(
        conversations: [
          (id: "a", title: "週末計畫"),
          (id: "b", title: "明天台中天氣如何"),
          (id: "c", title: "how do I run the tests"),
          (id: "d", title: "one too many"),
        ],
        modelName: "gemma-4-E4B-it",
        activity: "Thinking…",
        canStartVoice: true,
        labels: MenuBarController.Labels(
          show: "顯示 Lulo",
          hide: "隱藏 Lulo",
          talk: "跟 Lulo 說話",
          recent: "最近",
          quit: "結束 Lulo"
        )
      )
    )

    let titles = menu.itemsForTesting.map(\.title)
    // The menu's own words come from Dart, so they follow the system language
    // like everything else the user reads.
    XCTAssertTrue(titles.contains("結束 Lulo"))
    XCTAssertTrue(titles.contains("Thinking…"))
    XCTAssertTrue(titles.contains("gemma-4-E4B-it"))
    XCTAssertTrue(titles.contains("週末計畫"))
    // A menu is a shortcut, not a browser: the whole list already exists
    // inside the app.
    XCTAssertFalse(
      titles.contains("one too many"),
      "The menu listed more conversations than it promises to"
    )
  }

  func testChoosingAConversationFromTheMenuNamesTheRightOne() {
    // The identifier travels on the item, so the handler never has to find
    // the conversation again by title or by position — which is the kind of
    // thing that survives every test and then opens the wrong one.
    let controller = Self.makeController()
    let menu = MenuBarController(
      panelController: controller,
      statusBar: NSStatusBar()
    )
    var chosen: [String] = []
    menu.onConversationChosen = { chosen.append($0) }
    menu.apply(
      MenuBarController.State(
        conversations: [(id: "a", title: "第一則"), (id: "b", title: "第二則")],
        modelName: "",
        activity: "",
        canStartVoice: false
      )
    )

    guard
      let second = menu.itemsForTesting.first(where: { $0.title == "第二則" })
    else {
      return XCTFail("The menu did not list the second conversation")
    }
    _ = second.target?.perform(second.action, with: second)

    XCTAssertEqual(chosen, ["b"])
  }

  func testAMenuWithNothingToSayStillShowsAndQuits() {
    let controller = Self.makeController()
    let menu = MenuBarController(
      panelController: controller,
      statusBar: NSStatusBar()
    )

    let titles = menu.itemsForTesting.map(\.title)
    // The default labels stand in until Dart has said anything, so the menu
    // is never a list of blanks.
    XCTAssertTrue(titles.contains("Quit Lulo"))
    XCTAssertTrue(titles.contains(where: { $0.hasSuffix("Lulo") }))
  }

  func testAClickOnTheRestingOrbReachesTheCatcher() {
    // The window server, not AppKit, decides which window a click belongs to,
    // and for a window it can see through it decides on the drawn alpha rather
    // than on the frame. A catcher that painted nothing was therefore not
    // merely invisible but absent: every click went straight through to the
    // desktop and the orb answered nothing but the hotkey. Asking the server
    // who owns the point is the only check that catches that — the frame was
    // right the whole time it was broken.
    guard let screen = NSScreen.main else {
      return XCTFail("There is no screen to rest the orb on")
    }
    let catcher = OrbInputPanel(
      onSummon: {}, onDragBy: { _, _ in }, onAction: { _ in })
    let side = DesktopPanelController.orbSide
    let visible = screen.visibleFrame
    let rect = NSRect(
      x: visible.midX - side / 2,
      y: visible.midY - side / 2,
      width: side,
      height: side
    )
    func stackAt(_ x: CGFloat, _ y: CGFloat) -> [Int] {
      Self.stack(at: NSPoint(x: x, y: y))
    }
    catcher.place(over: rect, within: visible)
    // The server takes the window's shape from the drawing, so it is given the
    // run loop long enough to have received it.
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    defer { catcher.place(over: nil, within: nil) }

    let centreStack = stackAt(rect.midX, rect.midY)
    XCTAssertTrue(
      Self.window(catcher.windowNumber, ownsPointIn: centreStack),
      """
      A click on the resting orb went straight through the catcher. \
      catcher \(catcher.windowNumber), stack there \(centreStack)
      """
    )

    // And nothing beyond the orb itself: a corner of the square clear of it
    // still belongs to whatever is behind, because a resident assistant must
    // not be in anyone's way.
    XCTAssertFalse(
      Self.window(
        catcher.windowNumber, ownsPointIn: stackAt(rect.minX + 4, rect.minY + 4)),
      "The catcher took a click that was clear of the orb"
    )

    // Nor the ring between the body and the edge of the square. The catcher
    // used to fill the whole square with its circle, so it owned every point
    // within half a side of the centre while the orb is drawn to well under
    // that: clicking a file on the desktop beside the orb summoned the
    // conversation, and the tint the catcher has to draw to be there at all
    // had nothing of the orb over it to hide under.
    XCTAssertFalse(
      Self.window(
        catcher.windowNumber,
        ownsPointIn: stackAt(rect.midX + side / 2 * 0.85, rect.midY)),
      "The catcher took a click on the desktop beside the orb"
    )

    // The body itself still answers, all the way to where it is solidly drawn.
    XCTAssertTrue(
      Self.window(
        catcher.windowNumber,
        ownsPointIn: stackAt(rect.midX + side / 2 * 0.5, rect.midY)),
      "A click on the orb's own body went through the catcher"
    )
  }

  /// Every window the server says owns [point], topmost first.
  ///
  /// `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` alone answers
  /// which window is *on top* there, and that is a different question from
  /// the one this test asks. Anything at a higher window level owns every
  /// point underneath it: measured on one machine, a menu-bar utility drawing
  /// a layer-4 overlay across the screen centre, against the catcher's
  /// `.floating` layer 3. That made this test report that a click went
  /// straight through the orb — the exact bug it exists to catch — because
  /// somebody else's app was running.
  ///
  /// Walking the stack asks what the catcher itself draws, which is the thing
  /// that was broken and the thing worth guarding. A catcher that paints
  /// nothing is absent from the stack at every point, so this still fails
  /// exactly where it used to.
  static func stack(at point: NSPoint) -> [Int] {
    var found: [Int] = []
    var below = 0
    // Bounded: the server can hand back a cycle if the stack changes under
    // the walk, and a test that hangs is worse than one that is wrong.
    for _ in 0..<64 {
      let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: below)
      guard number > 0, !found.contains(number) else {
        break
      }
      found.append(number)
      below = number
    }
    return found
  }

  static func window(_ number: Int, ownsPointIn stack: [Int]) -> Bool {
    stack.contains(number)
  }

  func testTheMenuBarSaysHowADictationWent() {
    // A dictation happens while the user is working in somebody else's app,
    // so anything drawn inside Lulo's own window is drawn where nobody is
    // looking. Four outcomes, four different things to do about them, and a
    // line for each — a single "dictation failed" sends the user to try the
    // three that cannot help.
    let controller = MenuBarController(
      panelController: Self.makeController(),
      statusBar: NSStatusBar()
    )

    XCTAssertNil(
      controller.dictationNoticeForTesting,
      "nothing to say before anything has been dictated"
    )

    controller.reportDictation(.copied(characters: 12))
    XCTAssertEqual(controller.dictationNoticeForTesting, "Copied 12 characters")

    controller.reportDictation(.recogniserUnreachable)
    XCTAssertEqual(
      controller.dictationNoticeForTesting,
      "The recogniser is not running",
      "the sidecar being down is its own answer, not \"heard nothing\""
    )

    controller.reportDictation(.heardNothing)
    XCTAssertEqual(
      controller.dictationNoticeForTesting,
      "Heard nothing — say it again"
    )

    controller.reportDictation(.microphoneUnavailable)
    XCTAssertEqual(
      controller.dictationNoticeForTesting,
      "The microphone would not open"
    )

    XCTAssertTrue(
      controller.itemsForTesting.contains {
        $0.title == "The microphone would not open"
      },
      "the notice has to be in the menu, not only in the field behind it"
    )
  }

  func testTheWindowStaysWhereTheUserPutIt() {
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.expanded)
    let placed = controller.retainedPanel.frame

    // The user drags the window somewhere of their own choosing.
    controller.moveBy(deltaX: -180, deltaY: -120)
    let chosen = controller.retainedPanel.frame
    XCTAssertNotEqual(chosen, placed)

    // Collapsing sends the orb home: whatever place the conversation was
    // dragged to, the resting presence lives in the screen's lower trailing
    // corner. A resting place that wandered with the window left the orb
    // wherever work happened to be.
    controller.setPresentationMode(.orb)
    guard let visible = controller.retainedPanel.screen?.visibleFrame
      ?? NSScreen.main?.visibleFrame
    else {
      return XCTFail("No screen to rest on")
    }
    let atRest = controller.retainedPanel.frame
    XCTAssertEqual(atRest.maxX, visible.maxX - DesktopPanelController.orbMargin)
    XCTAssertEqual(atRest.minY, visible.minY + DesktopPanelController.orbMargin)
    XCTAssertEqual(atRest.size, chosen.size)

    // And summoning brings the conversation back to where the user had it,
    // not to the corner the orb rests in.
    controller.setPresentationMode(.expanded)
    XCTAssertEqual(controller.retainedPanel.frame, chosen)

    // Through a drawn change of form as well as the hotkey's fallback.
    _ = controller.beginTransition(to: .orb)
    controller.endTransition(.orb)
    XCTAssertEqual(controller.retainedPanel.frame, atRest)
    _ = controller.beginTransition(to: .expanded)
    controller.endTransition(.expanded)
    XCTAssertEqual(controller.retainedPanel.frame, chosen)
  }

  func testAFullScreenWindowIsNeverMovedByAChangeOfForm() {
    // A full-screen window's frame belongs to the system: setting it from
    // here fights the Space it lives in. The change of form is still drawn —
    // the orb rests in the stage's own corner — but the window stays exactly
    // the screen. AppKit refuses to set the real mask bit outside a genuine
    // transition, so the tests say it through the override.
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.expanded)
    controller.isFullScreenOverride = { true }
    let frame = controller.retainedPanel.frame

    _ = controller.beginTransition(to: .orb)
    controller.endTransition(.orb)
    XCTAssertEqual(controller.retainedPanel.frame, frame)

    controller.setPresentationMode(.expanded)
    XCTAssertEqual(controller.retainedPanel.frame, frame)

    // And the geometry says the window is the screen, which is how the app
    // knows the buttons are away.
    XCTAssertTrue(controller.currentGeometry().fullScreen)
  }

  func testResizingTheWindowReportsTheNewGeometry() {
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.expanded)
    var reported: [DesktopTransitionGeometry] = []
    controller.onGeometryChanged = { reported.append($0) }

    // The user makes the window larger; the forms are laid out against its
    // frame, so the app has to hear about the new one or the conversation
    // keeps drawing at the size the window no longer is.
    //
    // Asked for 900x700 and asserted against those numbers, this passed on a
    // large display and failed on a small one: AppKit constrains a titled
    // window to the screen it is on, so what the window becomes is not always
    // what it was told. The invariant is not the size — it is that what the
    // app is told matches what the window actually is.
    var frame = controller.retainedPanel.frame
    frame.size = NSSize(width: 900, height: 700)
    controller.retainedPanel.setFrame(frame, display: true)
    let became = controller.retainedPanel.frame.size

    XCTAssertNotEqual(
      became,
      NSSize(width: 480, height: 640),
      "The window did not resize at all, so nothing was under test"
    )
    XCTAssertEqual(reported.last?.size, became)
    XCTAssertEqual(
      reported.last?.conversation,
      CGRect(origin: .zero, size: became),
      "The conversation does not fill the resized window"
    )
  }

  func testTheButtonsAreAwayWhileTheChangeOfFormIsDrawn() {
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.expanded)
    let close = controller.retainedPanel.standardWindowButton(.closeButton)
    XCTAssertEqual(close?.isHidden, false)

    // The buttons belong to the conversation. Left standing while it shrinks,
    // they hang detached beside a form that is visibly leaving underneath
    // them.
    _ = controller.beginTransition(to: .orb)
    XCTAssertEqual(close?.isHidden, true)

    // And they come back with the conversation, including when the change of
    // form lands back where it started.
    controller.endTransition(.expanded)
    XCTAssertEqual(close?.isHidden, false)
  }

  func testTheWindowIsNoBiggerThanTheConversationItIsShowing() {
    // The window is the union of both forms, and it answers the mouse across
    // the whole of its frame however little it draws there — measured: a
    // titled window claims every point it covers whatever its content's alpha
    // is. Any part of the window the conversation does not fill is therefore
    // an invisible wall over the desktop, which is exactly what a resident
    // assistant must never be.
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.expanded)
    let geometry = controller.currentGeometry()

    XCTAssertEqual(geometry.size, controller.retainedPanel.frame.size)
    XCTAssertEqual(
      geometry.conversation,
      CGRect(origin: .zero, size: geometry.size),
      "The window is larger than the conversation, and the difference is a wall"
    )
    // Which holds only because the agent rests inside the conversation's own
    // rectangle rather than somewhere the window would have to stretch to.
    XCTAssertTrue(
      geometry.conversation.contains(geometry.orb),
      "The orb rests outside the conversation, so the window covers both"
    )
  }

  func testTheStageOnlyAnswersTheMouseWhereItIsDrawn() {
    let controller = Self.makeController()
    controller.show()
    controller.setPresentationMode(.orb)
    guard let stage = controller.retainedPanel.contentView as? StagePassThroughView
    else {
      return XCTFail("The window is not hosting the pass-through stage")
    }

    // Watching the pointer instead needs accessibility permission, and without
    // it the window can never notice the pointer coming back — it goes deaf
    // once and stays that way. Returning nil from hitTest needs no permission.
    let orb = stage.interactiveRect
    XCTAssertFalse(orb.isEmpty, "Nothing on the stage answers the mouse")
    XCTAssertNotNil(stage.hitTest(stage.convert(CGPoint(x: orb.midX, y: orb.midY), to: stage.superview)))

    let outside = CGPoint(x: orb.midX, y: orb.minY - 40)
    XCTAssertNil(
      stage.hitTest(stage.convert(outside, to: stage.superview)),
      "A click clear of the orb was swallowed instead of passing through"
    )
  }

  func testSummoningTheConversationDoesNotCarryYouToAnotherSpace() {
    let controller = Self.makeController()
    controller.show()
    controller.setWindowBehaviour(keepOrbOnTop: true, followAcrossSpaces: true)

    controller.setPresentationMode(.expanded)

    // Binding the window to one Space and then activating the app is what
    // makes macOS carry the user off to that Space. A summoned assistant
    // appears where the user already is; it does not take them somewhere else
    // and leave them to find their way back.
    XCTAssertTrue(
      controller.retainedPanel.collectionBehavior.contains(.canJoinAllSpaces),
      "The conversation was tied to one Space, so summoning it moves the user"
    )

    // Unless the user asked for the opposite, in which case it stays where it
    // was opened and summoning it is their way of going back to it.
    controller.setWindowBehaviour(keepOrbOnTop: true, followAcrossSpaces: false)
    XCTAssertFalse(
      controller.retainedPanel.collectionBehavior.contains(.canJoinAllSpaces)
    )
  }

  func testEachFormBehavesLikeTheKindOfWindowItIs() {
    let controller = Self.makeController()
    let panel = controller.retainedPanel
    controller.show()

    // The orb is a resting presence: above other work, on every Space, and
    // never taking focus from whatever the user is typing into.
    controller.setPresentationMode(.orb)
    XCTAssertEqual(panel.level, .floating)
    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))

    // The conversation is an ordinary window. Floating it above everything is
    // the wrong default for something the user reads and types in, and a panel
    // that never activates has no menu bar of its own. Which Space it is on is
    // deliberately not part of that — see the test above.
    controller.setPresentationMode(.expanded)
    XCTAssertEqual(panel.level, .normal)
    XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))

    XCTAssertFalse(panel.hidesOnDeactivate)
    XCTAssertEqual(panel.animationBehavior, .none)
  }

  // MARK: - The strip under the resting orb

  /// The home corner is where the orb spends most of its life, and there is
  /// not enough screen under it there — so the strip goes over it instead of
  /// off the bottom of the display.
  func testTheStripGoesOverTheOrbWhenThereIsNoRoomBeneathIt() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let home = NSRect(
      x: visible.maxX - DesktopPanelController.orbMargin
        - DesktopPanelController.orbSide,
      y: visible.minY + DesktopPanelController.orbMargin,
      width: DesktopPanelController.orbSide,
      height: DesktopPanelController.orbSide
    )

    guard let layout = OrbActionStrip.layout(orb: home, count: 3, within: visible)
    else {
      return XCTFail("three actions must produce a strip")
    }

    XCTAssertTrue(layout.above, "at the home corner the strip has to go up")
    XCTAssertGreaterThanOrEqual(layout.strip.minY, visible.minY)
    XCTAssertLessThanOrEqual(layout.strip.maxY, visible.maxY)
  }

  func testTheStripGoesUnderAnOrbWithRoomBeneathIt() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let midScreen = NSRect(x: 600, y: 400, width: 168, height: 168)

    guard
      let layout = OrbActionStrip.layout(orb: midScreen, count: 2, within: visible)
    else {
      return XCTFail("two actions must produce a strip")
    }

    XCTAssertFalse(layout.above)
    // Measured from where the orb stops painting, not from the square it is
    // drawn in: a gap taken from the square would leave the strip floating a
    // visible distance from an orb that ended long before it.
    let bodyBottom =
      midScreen.midY - midScreen.height * OrbActionStrip.orbSilhouetteFraction / 2
    XCTAssertEqual(
      layout.strip.maxY, bodyBottom - OrbActionStrip.orbGap, accuracy: 0.001)
    XCTAssertEqual(layout.strip.midX, midScreen.midX, accuracy: 0.001)
  }

  func testTheStripStaysOnTheScreenBesideAnOrbDraggedToTheEdge() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let atTheEdge = NSRect(x: visible.maxX - 40, y: 400, width: 168, height: 168)

    guard
      let layout = OrbActionStrip.layout(orb: atTheEdge, count: 3, within: visible)
    else {
      return XCTFail("three actions must produce a strip")
    }

    XCTAssertLessThanOrEqual(layout.strip.maxX, visible.maxX)
    XCTAssertGreaterThanOrEqual(layout.strip.minX, visible.minX)
  }

  func testAnOrbWithNothingToOfferHasNoStrip() {
    XCTAssertNil(
      OrbActionStrip.layout(
        orb: NSRect(x: 0, y: 0, width: 168, height: 168),
        count: 0,
        within: NSRect(x: 0, y: 0, width: 1440, height: 900)
      )
    )
  }

  func testTheButtonsSitInsideTheirOwnCapsuleInOrder() {
    guard
      let layout = OrbActionStrip.layout(
        orb: NSRect(x: 600, y: 400, width: 168, height: 168),
        count: 3,
        within: NSRect(x: 0, y: 0, width: 1440, height: 900)
      )
    else {
      return XCTFail("three actions must produce a strip")
    }

    XCTAssertEqual(layout.buttons.count, 3)
    for button in layout.buttons {
      XCTAssertTrue(layout.strip.contains(button))
    }
    XCTAssertLessThan(layout.buttons[0].midX, layout.buttons[1].midX)
    XCTAssertLessThan(layout.buttons[1].midX, layout.buttons[2].midX)
  }

  /// The tint has to be drawn to exist at all, so wherever it is the only
  /// thing on a pixel it is a real step of about 3/255 on a flat desktop.
  /// The path claimed between the orb and its capsule is therefore only as
  /// wide as the capsule and only as far as the orb's centre — not the whole
  /// panel, which stood a rectangle's worth of that step out in the open.
  func testThePathToTheStripIsClaimedNoWiderThanTheStrip() {
    let orb = NSRect(x: 600, y: 400, width: 168, height: 168)
    guard
      let layout = OrbActionStrip.layout(
        orb: orb,
        count: 3,
        within: NSRect(x: 0, y: 0, width: 1440, height: 900)
      )
    else {
      return XCTFail("three actions must produce a strip")
    }

    let bridge = OrbCatcherView.bridge(from: orb, to: layout)

    XCTAssertEqual(bridge.width, layout.strip.width, accuracy: 0.001)
    XCTAssertLessThan(bridge.width, orb.width)
    // It has to actually meet both ends, or the pointer falls through
    // between them and takes the strip with it.
    XCTAssertTrue(bridge.intersects(layout.strip))
    XCTAssertTrue(bridge.intersects(OrbCatcherView.catchingCircle(in: orb)))
  }

  /// The strip is drawn into the catcher's own panel, so that panel has to be
  /// big enough to hold both — and it must still claim only what it draws,
  /// or the desktop under the strip's rectangle stops answering the mouse
  /// whenever the agent is merely resting there.
  func testTheCatcherGrowsToHoldTheStripAndClaimsItOnlyWhileItShows() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    let controller = DesktopPanelController(panel: panel) {
      FlutterPanelContent(engine: NSObject(), viewController: NSViewController())
    }
    controller.show()
    controller.setPresentationMode(.orb)
    let withoutActions = controller.orbInputPanel.frame

    controller.setOrbActions([
      OrbAction(id: "talk", symbol: "mic", label: "Talk", engaged: false),
      OrbAction(id: "look", symbol: "eye", label: "Look", engaged: false),
    ])
    let withActions = controller.orbInputPanel.frame

    XCTAssertGreaterThan(withActions.height, withoutActions.height)
    XCTAssertFalse(
      controller.orbInputPanel.stripIsShowing,
      "a strip nobody is pointing at must not be drawn"
    )

    controller.orbInputPanel.revealStripNow()
    XCTAssertTrue(controller.orbInputPanel.stripIsShowing)

    // Going back to the conversation takes the whole catcher away, strip
    // included, rather than leaving a row of buttons on the desktop.
    controller.setPresentationMode(.expanded)
    XCTAssertFalse(controller.orbInputPanel.stripIsShowing)
  }
}
