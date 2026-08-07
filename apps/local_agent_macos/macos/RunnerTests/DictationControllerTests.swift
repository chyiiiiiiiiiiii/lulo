import XCTest

@testable import Lulo

/// Hold a key anywhere in macOS, speak, release, and have the words land on
/// the clipboard.
///
/// The version that was reverted carved this out of the conversation's own
/// microphone tap, and every guard it needed broke something else in that
/// tap — `docs/decisions/dictation-cannot-share-the-tap.md` has the four
/// failures. This one owns its audio, so there is no VAD to freeze, no
/// endpointer to mislead, no half-duplex mute to bypass, and no shared
/// buffer to reset. What is tested here is the orchestration: the audio, the
/// recogniser and the pasteboard are all injected.
@MainActor
final class DictationControllerTests: XCTestCase {
  /// An audio source that records what it was asked to do and hands back
  /// whatever the test says the microphone heard.
  private final class FakeSource: DictationAudioCapturing {
    var starts = 0
    var stops = 0
    var startError: Error?
    var clip: HeldSpeechClip? = HeldSpeechClip(
      samples: [0.1, 0.2],
      sampleRate: 48_000
    )

    func start() throws {
      starts += 1
      if let startError {
        throw startError
      }
    }

    func stop() -> HeldSpeechClip? {
      stops += 1
      return clip
    }
  }

  private struct SomeAudioFailure: Error {}

  /// A controller wired to fakes, with the transcript and the outcomes the
  /// test wants to look at.
  private struct Harness {
    let controller: DictationController
    let source: FakeSource
    let copied: () -> [String]
    let outcomes: () -> [DictationOutcome]
  }

  private func makeHarness(
    transcript: @escaping (HeldSpeechClip) async -> String?
  ) -> Harness {
    let source = FakeSource()
    let copiedBox = Box<[String]>([])
    let outcomeBox = Box<[DictationOutcome]>([])
    let controller = DictationController(
      source: source,
      transcribe: transcript,
      deliver: { copiedBox.value.append($0) },
      report: { outcomeBox.value.append($0) }
    )
    return Harness(
      controller: controller,
      source: source,
      copied: { copiedBox.value },
      outcomes: { outcomeBox.value }
    )
  }

  private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
  }

  func testWhatWasHeardLandsOnTheClipboard() async {
    let harness = makeHarness(transcript: { _ in "今天天氣如何" })

    harness.controller.pressed()
    await harness.controller.released()

    XCTAssertEqual(harness.copied(), ["今天天氣如何"])
    XCTAssertEqual(harness.outcomes(), [.copied(characters: 6)])
    XCTAssertEqual(harness.source.starts, 1)
    XCTAssertEqual(harness.source.stops, 1)
  }

  func testAHoldThatHeardNothingCopiesNothing() async {
    // The clipboard holds whatever the user put there last, and replacing it
    // with an empty string is how somebody pastes nothing into a document
    // and finds out much later.
    let harness = makeHarness(transcript: { _ in "   " })

    harness.controller.pressed()
    await harness.controller.released()

    XCTAssertEqual(harness.copied(), [])
    XCTAssertEqual(harness.outcomes(), [.heardNothing])
  }

  func testAnUnreachableRecogniserIsNotTheSameAsHearingNothing() async {
    // Two failures, two different fixes: one says start the sidecar, the
    // other says say it again. `transcribeHeld` already keeps them apart and
    // this is where that distinction is finally worth something.
    let harness = makeHarness(transcript: { _ in nil })

    harness.controller.pressed()
    await harness.controller.released()

    XCTAssertEqual(harness.copied(), [])
    XCTAssertEqual(harness.outcomes(), [.recogniserUnreachable])
  }

  func testAMicrophoneThatWillNotOpenIsReportedOnThePress() async {
    // Reported when it happens rather than on release: the user is holding a
    // key expecting to be heard, and the sooner they know nothing is being
    // recorded the less they have to say twice.
    let harness = makeHarness(transcript: { _ in "unreachable" })
    harness.source.startError = SomeAudioFailure()

    harness.controller.pressed()

    XCTAssertEqual(harness.outcomes(), [.microphoneUnavailable])

    await harness.controller.released()

    XCTAssertEqual(harness.copied(), [], "a hold that never began has no audio")
    XCTAssertEqual(harness.outcomes(), [.microphoneUnavailable])
    XCTAssertEqual(harness.source.stops, 0)
  }

  func testKeyRepeatDoesNotRestartTheHold() async {
    // Carbon delivers extra presses for one physical hold. Restarting the
    // capture on each of them throws away everything said so far, and
    // `HeldSpeechCaptureBox.begin()` deliberately will not guard this — it
    // resets unconditionally so push-to-talk can recover from a release
    // Carbon never delivered. The guard belongs here.
    let harness = makeHarness(transcript: { _ in "kept" })

    harness.controller.pressed()
    harness.controller.pressed()
    harness.controller.pressed()

    XCTAssertEqual(harness.source.starts, 1)

    await harness.controller.released()

    XCTAssertEqual(harness.copied(), ["kept"])
  }

  func testAReleaseWithNoHoldDoesNothing() async {
    // Carbon addresses hotkeys globally and this app registers two. A
    // release that arrives without its press must not transcribe silence.
    let harness = makeHarness(transcript: { _ in "should not happen" })

    await harness.controller.released()

    XCTAssertEqual(harness.source.stops, 0)
    XCTAssertEqual(harness.copied(), [])
    XCTAssertEqual(harness.outcomes(), [])
  }

  func testTheNextHoldWorksAfterOneThatFailed() async {
    // A failed hold must leave the controller armed. The reverted version
    // did not: a hold whose release never arrived left the capture active
    // and routed every later buffer away, and the conversation went deaf
    // with nothing said about it.
    let harness = makeHarness(transcript: { _ in nil })

    harness.controller.pressed()
    await harness.controller.released()
    harness.controller.pressed()
    await harness.controller.released()

    XCTAssertEqual(harness.source.starts, 2)
    XCTAssertEqual(harness.outcomes(), [
      .recogniserUnreachable, .recogniserUnreachable,
    ])
  }

  func testASilentHoldNeverReachesTheRecogniser() async {
    // No clip means the microphone was open and heard nothing at all. There
    // is nothing to send, and sending it would spend a sidecar round trip to
    // be told so.
    let harness = makeHarness(transcript: { _ in
      XCTFail("an empty hold must not be transcribed")
      return nil
    })
    harness.source.clip = nil

    harness.controller.pressed()
    await harness.controller.released()

    XCTAssertEqual(harness.outcomes(), [.heardNothing])
  }
}
