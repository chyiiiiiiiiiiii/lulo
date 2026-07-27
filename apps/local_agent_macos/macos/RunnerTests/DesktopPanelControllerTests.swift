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
