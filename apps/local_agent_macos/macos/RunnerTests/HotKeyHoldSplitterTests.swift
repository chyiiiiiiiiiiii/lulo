import XCTest

@testable import Lulo

@MainActor
final class HotKeyHoldSplitterTests: XCTestCase {
  private var taps = 0
  private var began = 0
  private var ended = 0
  private var pending: (() -> Void)?

  private func makeSplitter() -> HotKeyHoldSplitter {
    HotKeyHoldSplitter(
      onTap: { self.taps += 1 },
      onHoldBegan: { self.began += 1 },
      onHoldEnded: { self.ended += 1 },
      schedule: { work in
        self.pending = work
        return { self.pending = nil }
      }
    )
  }

  func testAQuickPressIsATap() {
    let splitter = makeSplitter()
    splitter.pressed()
    splitter.released()
    XCTAssertEqual(taps, 1)
    XCTAssertEqual(began, 0)
    XCTAssertEqual(ended, 0)
    XCTAssertNil(pending, "the hold timer must be cancelled by the tap")
  }

  func testAPressThatOutlivesTheThresholdIsAHold() {
    let splitter = makeSplitter()
    splitter.pressed()
    pending?()  // the threshold elapses
    XCTAssertEqual(began, 1)
    XCTAssertEqual(taps, 0)
    splitter.released()
    XCTAssertEqual(ended, 1)
    XCTAssertEqual(taps, 0, "a hold's release is not also a tap")
  }

  func testASecondPressWhileHoldingChangesNothing() {
    let splitter = makeSplitter()
    splitter.pressed()
    pending?()
    splitter.pressed()
    XCTAssertEqual(began, 1)
    splitter.released()
    XCTAssertEqual(ended, 1)
  }

  func testAStrayReleaseIsIgnored() {
    let splitter = makeSplitter()
    splitter.released()
    XCTAssertEqual(taps, 0)
    XCTAssertEqual(ended, 0)
  }
}
