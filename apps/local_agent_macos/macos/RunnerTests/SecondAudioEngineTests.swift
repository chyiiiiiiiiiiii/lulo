import AVFoundation
import XCTest

@testable import Lulo

/// Whether a second `AVAudioEngine` can tap the microphone while the
/// conversation's engine already is.
///
/// The whole shape of `docs/decisions/dictation-cannot-share-the-tap.md`
/// rests on this. That document says the next attempt needs its own engine
/// rather than a mode carved out of the conversation's tap — every failure
/// in the reverted version was two features sharing one real-time path and
/// one set of timers. If two engines cannot coexist, that recommendation is
/// wrong and the next person should know before spending a day on it.
///
/// This asks only whether they both run. Whether the buffers are any good
/// needs somebody to speak, which no test here can arrange.
final class SecondAudioEngineTests: XCTestCase {
  func testTwoEnginesCanTapTheInputAtOnce() throws {
    guard ProcessInfo.processInfo.environment["LULO_AUDIO_DEVICE_TESTS"] != nil
    else {
      throw XCTSkip(
        "Set LULO_AUDIO_DEVICE_TESTS to run: this opens the real microphone."
      )
    }

    let first = AVAudioEngine()
    let second = AVAudioEngine()
    defer {
      first.stop()
      second.stop()
      first.inputNode.removeTap(onBus: 0)
      second.inputNode.removeTap(onBus: 0)
    }

    var firstBuffers = 0
    var secondBuffers = 0
    let counting = NSLock()

    for (engine, count) in [(first, { firstBuffers += 1 }), (second, { secondBuffers += 1 })] {
      let format = engine.inputNode.outputFormat(forBus: 0)
      engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) {
        _, _ in
        counting.lock()
        count()
        counting.unlock()
      }
      engine.prepare()
      try engine.start()
    }

    // Long enough for a few buffers at any ordinary sample rate.
    Thread.sleep(forTimeInterval: 0.5)

    counting.lock()
    let (a, b) = (firstBuffers, secondBuffers)
    counting.unlock()

    XCTAssertGreaterThan(a, 0, "the first engine heard nothing")
    XCTAssertGreaterThan(
      b,
      0,
      "the second engine heard nothing — dictation cannot have its own"
    )
  }
}
