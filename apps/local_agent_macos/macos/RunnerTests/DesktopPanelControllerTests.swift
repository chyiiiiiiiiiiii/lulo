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
    XCTAssertTrue(panel.contentViewController === viewController)

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

  func testPanelCanJoinSpacesAndRemainAvailableBesideFullscreenApps() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )

    _ = DesktopPanelController(panel: panel) {
      FlutterPanelContent(engine: NSObject(), viewController: NSViewController())
    }

    XCTAssertEqual(panel.level, .floating)
    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    XCTAssertFalse(panel.hidesOnDeactivate)
    XCTAssertEqual(panel.animationBehavior, .none)
  }
}
