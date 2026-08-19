import XCTest

@testable import Lulo

final class UtteranceRingTests: XCTestCase {
  func testClipSinceReturnsJustTheTail() {
    // Two seconds of audio at a toy rate; asking from the halfway mark
    // must return the second half, not the whole session.
    let ring = UtteranceRingBox(capacitySeconds: 60)
    ring.append([Float](repeating: 0.1, count: 100), sampleRate: 100, at: 1.0)
    ring.append([Float](repeating: 0.2, count: 100), sampleRate: 100, at: 2.0)

    let clip = ring.clip(since: 1.0)
    XCTAssertEqual(clip?.samples.count, 100)
    XCTAssertEqual(clip?.sampleRate, 100)
    XCTAssertEqual(clip?.samples.first, 0.2)
  }

  func testAskingFromBeforeTheAudioReturnsWhatIsHeld() {
    let ring = UtteranceRingBox(capacitySeconds: 60)
    ring.append([Float](repeating: 0.1, count: 100), sampleRate: 100, at: 1.0)

    XCTAssertEqual(ring.clip(since: -5)?.samples.count, 100)
  }

  func testAnEmptyRingHasNoClip() {
    XCTAssertNil(UtteranceRingBox(capacitySeconds: 60).clip(since: 0))
  }

  func testAClipCannotStartAfterItsOwnEnd() {
    let ring = UtteranceRingBox(capacitySeconds: 60)
    ring.append([Float](repeating: 0.1, count: 100), sampleRate: 100, at: 1.0)

    XCTAssertNil(ring.clip(since: 2.0))
  }

  func testTheRingStaysBounded() {
    // Ten "seconds" of audio into a two-second ring: the oldest samples
    // must be gone, and what survives is the newest tail.
    let ring = UtteranceRingBox(capacitySeconds: 2)
    for second in 0..<10 {
      ring.append(
        [Float](repeating: Float(second), count: 100),
        sampleRate: 100,
        at: TimeInterval(second + 1)
      )
    }

    let clip = ring.clip(since: -1)
    XCTAssertNotNil(clip)
    XCTAssertLessThanOrEqual(clip!.samples.count, 250)
    XCTAssertEqual(clip!.samples.last, 9)
  }

  func testASampleRateChangeDropsTheOldAudio() {
    // A device swap mid-session changes the rate; stitching old samples to
    // the new clock would play them at the wrong speed.
    let ring = UtteranceRingBox(capacitySeconds: 60)
    ring.append([Float](repeating: 0.1, count: 100), sampleRate: 100, at: 1.0)
    ring.append([Float](repeating: 0.2, count: 50), sampleRate: 50, at: 2.0)

    let clip = ring.clip(since: -5)
    XCTAssertEqual(clip?.samples.count, 50)
    XCTAssertEqual(clip?.sampleRate, 50)
  }
}
