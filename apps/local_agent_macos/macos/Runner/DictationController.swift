import AVFoundation
import AppKit
import Foundation

/// What one dictation ended as.
///
/// Four states because they send the user to do four different things:
/// paste it, say it again, check the microphone, start the sidecar. One
/// message covering all four sends them to do the three that cannot help.
enum DictationOutcome: Equatable {
  /// The words are on the clipboard.
  case copied(characters: Int)
  /// The microphone was open and there was nothing in it to transcribe.
  case heardNothing
  /// The microphone would not open, so nothing was recorded at all.
  case microphoneUnavailable
  /// The batch recogniser could not be reached — it lives outside this
  /// repository and is started by hand.
  case recogniserUnreachable
}

/// Somewhere for a dictation to get its audio from.
///
/// Its own, deliberately. The reverted version took a mode out of the
/// conversation's tap, and every guard that needed broke one of the four
/// things sharing it. See `docs/decisions/dictation-cannot-share-the-tap.md`.
@MainActor
protocol DictationAudioCapturing: AnyObject {
  /// Opens the microphone and starts collecting; throws if it will not open.
  func start() throws
  /// Stops collecting and hands over what was heard, once.
  func stop() -> HeldSpeechClip?
}

/// One hold of the dictation key, from press to clipboard.
///
/// Knows nothing about the conversation and cannot reach it: the transcript
/// must never stop an answer being written, take the agent's turn, or come
/// back as a question somebody asked. Keeping this side of the app entirely
/// out of Dart makes all three structurally impossible rather than merely
/// handled.
@MainActor
final class DictationController {
  /// What the batch recogniser heard, or nil when it could not be reached.
  typealias Transcribe = (HeldSpeechClip) async -> String?
  /// Puts the words where the user can paste them.
  typealias Deliver = (String) -> Void
  /// Says how it went, somewhere the user is actually looking.
  typealias Report = (DictationOutcome) -> Void

  private let source: any DictationAudioCapturing
  private let transcribe: Transcribe
  private let deliver: Deliver
  private let report: Report

  /// Whether a hold is in progress.
  ///
  /// This is the key-repeat guard, and it lives here rather than in
  /// `HeldSpeechCaptureBox.begin()`, which resets unconditionally on purpose
  /// so push-to-talk can recover from a release Carbon never delivered.
  /// Moving the guard down there is what cost push-to-talk that recovery the
  /// first time this feature was built.
  private var holding = false

  init(
    source: any DictationAudioCapturing,
    transcribe: @escaping Transcribe,
    deliver: @escaping Deliver,
    report: @escaping Report
  ) {
    self.source = source
    self.transcribe = transcribe
    self.deliver = deliver
    self.report = report
  }

  /// The dictation key went down.
  func pressed() {
    guard !holding else {
      // Carbon delivers extra presses for one physical hold; restarting here
      // would throw away everything said so far.
      return
    }
    do {
      try source.start()
      holding = true
    } catch {
      // Said now rather than on release. The user is holding a key expecting
      // to be heard, and the sooner they know nothing is being recorded the
      // less they have to say twice.
      NSLog("Lulo dictation: microphone unavailable (%@)", String(describing: error))
      report(.microphoneUnavailable)
    }
  }

  /// The dictation key came up.
  func released() async {
    guard holding else {
      // A release with no press of ours. Carbon's ids are global and this
      // app registers two hotkeys, so this is worth refusing rather than
      // transcribing silence.
      return
    }
    // Cleared before anything that can fail, so a hold that goes wrong still
    // leaves the next one able to start. The reverted version left a failed
    // hold active and routed every later buffer away from the conversation,
    // which went deaf with nothing said about it.
    holding = false
    guard let clip = source.stop() else {
      report(.heardNothing)
      return
    }
    guard let text = await transcribe(clip) else {
      report(.recogniserUnreachable)
      return
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      // The clipboard holds whatever the user put there last. Replacing it
      // with nothing is how somebody pastes an empty string into a document
      // and finds out much later.
      report(.heardNothing)
      return
    }
    deliver(trimmed)
    report(.copied(characters: trimmed.count))
  }
}

/// Dictation's own microphone: one `AVAudioEngine`, opened on the press and
/// closed on the release.
///
/// Its own, and nothing else's. The reverted attempt took a mode out of the
/// conversation's tap and every guard it needed broke one of the four things
/// sharing it — a VAD whose `lastVoice` froze, an endpointer that then fired
/// *sooner*, a half-duplex mute bypassed in the one mode with no echo
/// canceller, and a buffer nothing reset. None of them exist here.
///
/// No voice processing. The echo canceller is there so the microphone can
/// stay open while the agent talks, and the agent is not talking: this is a
/// key held down in somebody else's app. Skipping it is also what makes this
/// engine cheap to build — measured on the conversation's engine, enabling it
/// is 826-960 ms of the ~1100.
@MainActor
final class DictationAudioEngine: DictationAudioCapturing {
  private let capture = HeldSpeechCaptureBox()
  private var engine: AVAudioEngine?

  func start() throws {
    // A fresh engine per hold. Keeping one warm is what the conversation's
    // side does and is worth ~1 s there, but this one has no voice processing
    // to build and holding an input node open between holds is a microphone
    // this app has no reason to have open.
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    let box = capture
    box.begin()
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
      guard let channel = buffer.floatChannelData?[0] else { return }
      box.append(
        Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
        sampleRate: buffer.format.sampleRate
      )
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      // Nothing half-built survives a failed press: the next one starts from
      // an empty box and no engine, which is what makes a failure recoverable
      // rather than the beginning of a stuck state.
      input.removeTap(onBus: 0)
      _ = box.end()
      throw error
    }
    self.engine = engine
  }

  func stop() -> HeldSpeechClip? {
    guard let engine else {
      return nil
    }
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    self.engine = nil
    return capture.end()
  }
}

/// Puts [text] on the clipboard, which needs no entitlement to write.
@MainActor
func copyToPasteboard(_ text: String) {
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  pasteboard.setString(text, forType: .string)
}
