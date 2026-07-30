import XCTest

@testable import Lulo

final class VoiceActivityTests: XCTestCase {
  func testSpeechOverAQuietRoomEndsTheSilence() {
    let box = VoiceActivityBox()
    var t = 0.0
    for _ in 0..<20 {
      box.observe(rms: 0.001, at: t)
      t += 0.1
    }
    box.observe(rms: 0.05, at: t)
    XCTAssertEqual(box.silence(asOf: t + 0.5), 0.5, accuracy: 0.001)
  }

  func testANeverVoicedRoomReportsEndlessSilence() {
    // Endpointing must never fire before anyone has spoken; a room that
    // has only ever been quiet reports silence without a beginning.
    let box = VoiceActivityBox()
    box.observe(rms: 0.001, at: 0)
    XCTAssertTrue(box.silence(asOf: 1).isInfinite)
  }

  func testSteadyFanNoiseStopsReadingAsVoice() {
    // A fan or an air conditioner holds the room at a constant hum. The
    // floor absorbs it, and the hum stops counting as somebody talking.
    let box = VoiceActivityBox()
    var t = 0.0
    for _ in 0..<2000 {
      box.observe(rms: 0.01, at: t)
      t += 0.05
    }
    XCTAssertGreaterThan(box.silence(asOf: t), 5.0)
  }

  func testALongMonologueIsNotSwallowedByItsOwnFloor() {
    // Speech is bursty: loud syllables with quiet gaps between words. The
    // gaps pull the floor back down, so even a minute of talking must not
    // raise it high enough to stop counting the voice as a voice.
    let box = VoiceActivityBox()
    var t = 0.0
    for _ in 0..<20 {
      box.observe(rms: 0.001, at: t)
      t += 0.085
    }
    for beat in 0..<700 {
      box.observe(rms: beat % 4 == 3 ? 0.005 : 0.05, at: t)
      t += 0.085
    }
    XCTAssertLessThan(box.silence(asOf: t), 0.5)
  }

  func testAVoiceAboveTheFanIsStillHeard() {
    let box = VoiceActivityBox()
    var t = 0.0
    for _ in 0..<2000 {
      box.observe(rms: 0.01, at: t)
      t += 0.05
    }
    box.observe(rms: 0.08, at: t)
    XCTAssertEqual(box.silence(asOf: t + 0.3), 0.3, accuracy: 0.001)
  }
}
