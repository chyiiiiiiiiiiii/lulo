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

  /// Starting to listen must not freeze the interface.
  ///
  /// `VoiceHostAdapter` is `@MainActor`, and building the listening graph
  /// used to happen on it: measured on this machine at 1244, 1161 and 1076 ms
  /// across three consecutive starts in one process, so every press of the
  /// microphone button froze the app for over a second. It was not a
  /// first-run cost — `setVoiceProcessingEnabled(true)` alone took 826-960 ms
  /// every single time, and touching `engine.inputNode` another 100-229.
  ///
  /// The threshold is loose on purpose. What is being guarded is the
  /// difference between "off the main thread" and "on it", which is a factor
  /// of fifty; a number tight enough to also police scheduling jitter would
  /// fail on a busy machine and teach everyone to ignore it.
  @available(macOS 26.0, *)
  func testBuildingTheListeningGraphLeavesTheMainThreadFree() throws {
    guard ProcessInfo.processInfo.environment["LULO_AUDIO_DEVICE_TESTS"] != nil
    else {
      throw XCTSkip(
        "Set LULO_AUDIO_DEVICE_TESTS to run: this opens the real microphone."
      )
    }
    guard
      let analyzerFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    else {
      return XCTFail("no format to convert into")
    }

    let finished = DispatchSemaphore(value: 0)
    let built = UncheckedBox<VoiceHostAdapter.ListeningGraph?>(nil)
    DispatchQueue.global(qos: .userInitiated).async {
      // The cold path: no warm engine waiting, so this press pays for one.
      // It is the worst case and the one that used to freeze the app.
      built.value = try? {
        let warm = try VoiceHostAdapter.makeWarmEngine()
        return try VoiceHostAdapter.makeListeningGraph(
          warm: warm,
          analyzerFormat: analyzerFormat,
          mute: MuteBox(),
          heldSpeech: HeldSpeechCaptureBox(),
          utteranceRing: UtteranceRingBox()
        )
      }()
      finished.signal()
    }

    // This thread does what a UI thread does: wake on a frame-sized timer.
    // The longest gap between wakes is how long it was starved for.
    var worstStall = 0.0
    var last = ProcessInfo.processInfo.systemUptime
    while finished.wait(timeout: .now() + 0.016) == .timedOut {
      let now = ProcessInfo.processInfo.systemUptime
      worstStall = max(worstStall, (now - last) * 1000)
      last = now
    }

    let graph = try XCTUnwrap(built.value, "the listening graph was not built")
    graph.engine.stop()
    graph.engine.inputNode.removeTap(onBus: 0)

    XCTAssertLessThan(
      worstStall,
      100,
      "building the listening graph starved the main thread for "
        + String(format: "%.0f ms", worstStall)
    )
  }

  /// A warm engine is what makes the microphone button feel instant.
  ///
  /// Moving the build off the main thread stopped the app freezing, but the
  /// second was still spent and the microphone still took that long to open.
  /// Almost all of it is the engine itself: `setVoiceProcessingEnabled` and
  /// the first touch of `inputNode`, neither of which depends on the session
  /// about to start. Built once and kept, what a press has left to pay is the
  /// tap, the converter, `prepare` and `start` — measured at 80-90 ms against
  /// 1100.
  ///
  /// This is only safe because building does **not** open the microphone.
  /// Measured through `kAudioDevicePropertyDeviceIsRunningSomewhere`, which
  /// is what the system reads to decide the recording indicator: false before
  /// the build, false a second and a half after it, and true only once
  /// `engine.start()` runs. `testAWarmEngineDoesNotHoldTheMicrophone` keeps
  /// that true, because the day it stops being true this app is listening
  /// before anyone asked it to.
  @available(macOS 26.0, *)
  func testAWarmEngineMakesStartingToListenQuick() throws {
    guard ProcessInfo.processInfo.environment["LULO_AUDIO_DEVICE_TESTS"] != nil
    else {
      throw XCTSkip(
        "Set LULO_AUDIO_DEVICE_TESTS to run: this opens the real microphone."
      )
    }
    let analyzerFormat = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    let warm = try VoiceHostAdapter.makeWarmEngine()

    let started = ProcessInfo.processInfo.systemUptime
    let graph = try VoiceHostAdapter.makeListeningGraph(
      warm: warm,
      analyzerFormat: analyzerFormat,
      mute: MuteBox(),
      heldSpeech: HeldSpeechCaptureBox(),
      utteranceRing: UtteranceRingBox()
    )
    let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000

    graph.engine.stop()
    graph.engine.inputNode.removeTap(onBus: 0)

    XCTAssertLessThan(
      elapsed,
      300,
      "starting on a warm engine took "
        + String(format: "%.0f ms", elapsed)
        + " — the point of keeping one is that this is not the second it "
        + "replaces"
    )
  }

  @available(macOS 26.0, *)
  func testAWarmEngineDoesNotHoldTheMicrophone() throws {
    // The whole trade rests on this. An engine kept warm across the time
    // nobody is talking must not be an engine holding the microphone open
    // across the time nobody is talking.
    guard ProcessInfo.processInfo.environment["LULO_AUDIO_DEVICE_TESTS"] != nil
    else {
      throw XCTSkip(
        "Set LULO_AUDIO_DEVICE_TESTS to run: this opens the real microphone."
      )
    }
    let device = try XCTUnwrap(
      InputDevicePolicy.defaultInputDevice(),
      "no default input device to ask about"
    )
    XCTAssertEqual(
      InputDevicePolicy.isRunningSomewhere(device),
      false,
      "something already had the microphone open before this test built "
        + "anything — the result below would mean nothing"
    )

    let warm = try VoiceHostAdapter.makeWarmEngine()
    defer { warm.engine.stop() }

    XCTAssertEqual(
      InputDevicePolicy.isRunningSomewhere(device),
      false,
      "a warm engine opened the microphone; keeping one is not safe"
    )
  }

  @available(macOS 26.0, *)
  func testAWarmEngineDoesNotDuckTheSystemAudio() throws {
    // The other half of the same trade, learned in use: voice processing
    // puts the whole system into call mode — every other app's audio is
    // ducked — from the moment the Voice-Processing I/O unit exists,
    // microphone open or not. A warm engine that carries it means Spotify
    // goes quiet the moment the app launches and stays quiet while nobody
    // is talking. The warm engine is a bare graph; voice processing is
    // enabled at the press, where the ducking belongs.
    let bare = try VoiceHostAdapter.makeBareEngine()
    defer { bare.stop() }

    XCTAssertFalse(
      bare.inputNode.isVoiceProcessingEnabled,
      "a warm engine carried voice processing: system audio is ducked "
        + "while nobody is talking"
    )
  }
}

/// Carries a value out of a background queue in a test.
private final class UncheckedBox<Value>: @unchecked Sendable {
  var value: Value
  init(_ value: Value) { self.value = value }
}
