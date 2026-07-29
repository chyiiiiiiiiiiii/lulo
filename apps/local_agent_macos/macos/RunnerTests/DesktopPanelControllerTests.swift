import AppKit
import XCTest

@testable import local_agent_macos

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
    _ = controller.beginTransition()
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
    // collapse. A window that never changes size never enters that wait.
    XCTAssertEqual(
      conversation,
      orb,
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

    // The conversation is an ordinary window and answers for itself.
    controller.setPresentationMode(.expanded)
    XCTAssertFalse(controller.retainedPanel.ignoresMouseEvents)
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
    // that never activates has no menu bar of its own.
    controller.setPresentationMode(.expanded)
    XCTAssertEqual(panel.level, .normal)
    XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))

    XCTAssertFalse(panel.hidesOnDeactivate)
    XCTAssertEqual(panel.animationBehavior, .none)
  }
}
