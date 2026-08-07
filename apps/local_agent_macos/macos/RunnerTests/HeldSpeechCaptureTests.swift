import XCTest

@testable import Lulo

final class HeldSpeechCaptureTests: XCTestCase {
  func testOnlyWhatIsHeardWhileHoldingIsKept() {
    let box = HeldSpeechCaptureBox()
    box.append([0.1, 0.2], sampleRate: 48_000)
    box.begin()
    box.append([0.3, 0.4], sampleRate: 48_000)
    box.append([0.5], sampleRate: 48_000)
    let clip = box.end()
    XCTAssertEqual(clip?.samples, [0.3, 0.4, 0.5])
    XCTAssertEqual(clip?.sampleRate, 48_000)
  }

  func testTheClipIsHandedOverExactlyOnce() {
    let box = HeldSpeechCaptureBox()
    box.begin()
    box.append([0.3], sampleRate: 48_000)
    XCTAssertNotNil(box.end())
    XCTAssertNil(box.end())
    box.append([0.4], sampleRate: 48_000)
    XCTAssertNil(box.end(), "appends outside a hold are dropped")
  }

  func testAnEmptyHoldYieldsNoClip() {
    let box = HeldSpeechCaptureBox()
    box.begin()
    XCTAssertNil(box.end())
  }

  func testABeginWithNoReleaseStartsCleanRatherThanMerging() {
    // Carbon does not guarantee a release when the modifiers are lifted
    // before the key, so a hold can end without anyone being told. An
    // unconditional reset here is the only thing that recovers from it —
    // without it the next hold hands the recogniser both holds' audio, and
    // the batch transcript replaces the streamed one.
    let box = HeldSpeechCaptureBox()
    box.begin()
    box.append([0.1], sampleRate: 16000)
    box.begin()
    box.append([0.9], sampleRate: 16000)

    XCTAssertEqual(box.end()?.samples, [0.9])
  }
}
