import AppKit
import XCTest

@testable import Lulo

@MainActor
final class AppDelegateWindowResolutionTests: XCTestCase {
  func testPrefersConnectedMainWindowOutletBeforeApplicationWindowEnumeration() {
    let outlet = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    let enumerated = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )

    let resolved = resolveMainFlutterWindow(
      outletWindow: outlet,
      applicationWindows: [enumerated]
    )

    XCTAssertTrue(resolved === outlet)
  }

  func testFallsBackToApplicationWindowEnumeration() {
    let enumerated = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )

    let resolved = resolveMainFlutterWindow(
      outletWindow: NSWindow(),
      applicationWindows: [NSWindow(), enumerated]
    )

    XCTAssertTrue(resolved === enumerated)
  }
}
