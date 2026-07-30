import AVFoundation
import FlutterMacOS
import Speech

/// The ears and the mouth behind the Flutter voice pipeline.
///
/// Listening runs the microphone through SpeechAnalyzer's on-device
/// transcriber and reports volatile results as partial transcripts and
/// finalized ones as utterances. Speaking goes through AVSpeechSynthesizer.
/// Everything is reported back over the pigeon event channel; failures are
/// events too, because the conversation loop must survive a microphone that
/// went away.
///
/// Half-duplex by design: while the synthesizer speaks, the microphone feed
/// into the analyzer is muted, so the agent can never hear itself through
/// the speakers and answer its own answer. Barge-in by voice during speech
/// returns once echo cancellation has been tuned on real hardware.
@available(macOS 26.0, *)
@MainActor
final class VoiceHostAdapter: NSObject, VoiceHostApi {
  private let events: VoiceHostEvents
  private let synthesizer = AVSpeechSynthesizer()

  /// Everything one listening run owns, torn down as one.
  private struct ListeningSession {
    let engine: AVAudioEngine
    let builder: AsyncStream<AnalyzerInput>.Continuation
    let analyzer: SpeechAnalyzer
    let resultsTask: Task<Void, Never>
    let configObserver: NSObjectProtocol
  }

  private var session: ListeningSession?

  /// Bumped on every start and stop; an in-flight start that no longer
  /// matches gives up quietly. The asset download inside `begin` can take
  /// minutes on first run, and every await inside it is a window.
  private var sessionCounter = 0
  private var starting = false

  /// Read on the real-time audio thread, written here.
  private let mute = MuteBox()

  init(events: VoiceHostEvents) {
    self.events = events
    super.init()
    synthesizer.delegate = self
  }

  // MARK: - VoiceHostApi

  func startListening(completion: @escaping (Result<Void, Error>) -> Void) {
    guard session == nil, !starting else {
      completion(.success(()))
      return
    }
    starting = true
    sessionCounter += 1
    let id = sessionCounter
    Task { @MainActor in
      do {
        try await self.begin(id: id)
        if id == self.sessionCounter {
          self.starting = false
        }
        completion(.success(()))
      } catch is CancellationError {
        // Stopped while still starting: nothing runs, nothing to report.
        // The flag belongs to whoever started most recently.
        if id == self.sessionCounter {
          self.starting = false
        }
        completion(.success(()))
      } catch {
        if id == self.sessionCounter {
          self.starting = false
        }
        completion(.failure(PigeonError(
          code: "listening-failed",
          message: String(describing: error),
          details: nil
        )))
      }
    }
  }

  func stopListening(completion: @escaping (Result<Void, Error>) -> Void) {
    // Invalidates any start still on its way through permission dialogs or
    // the asset download, as well as the running session. The starting flag
    // falls with it, or a retry during the invalidated start's long await
    // would report success while opening nothing.
    sessionCounter += 1
    starting = false
    endSession()
    emit(.listeningStopped)
    completion(.success(()))
  }

  func speak(text: String, completion: @escaping (Result<Void, Error>) -> Void) {
    // Muted before the first sample leaves the speaker, not when the
    // delegate reports it: the gap is exactly long enough for the agent to
    // hear its own opening words.
    mute.muted = true
    synthesizer.speak(AVSpeechUtterance(string: text))
    completion(.success(()))
  }

  func stopSpeaking(completion: @escaping (Result<Void, Error>) -> Void) {
    synthesizer.stopSpeaking(at: .immediate)
    mute.muted = false
    completion(.success(()))
  }

  // MARK: - Listening pipeline

  private func begin(id: Int) async throws {
    guard await Self.microphonePermitted() else {
      throw VoiceHostError.microphoneDenied
    }
    try guardCurrent(id)
    guard
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale.current
      )
    else {
      throw VoiceHostError.localeUnsupported
    }
    try guardCurrent(id)
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults],
      attributeOptions: []
    )
    // The transcription model is a system asset; the first run downloads
    // it, which can take minutes.
    if let installation = try await AssetInventory.assetInstallationRequest(
      supporting: [transcriber]
    ) {
      try await installation.downloadAndInstall()
    }
    try guardCurrent(id)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
      )
    else {
      throw VoiceHostError.audioFormatUnavailable
    }
    try guardCurrent(id)

    let engine = AVAudioEngine()
    let input = engine.inputNode
    // Echo cancellation, so what little leaks past the half-duplex mute —
    // and one day full-duplex barge-in — does not feed the transcriber the
    // speaker's own output. Best effort: some devices refuse.
    try? input.setVoiceProcessingEnabled(true)
    let microphoneFormat = input.outputFormat(forBus: 0)
    guard
      let converter = AVAudioConverter(
        from: microphoneFormat,
        to: analyzerFormat
      )
    else {
      throw VoiceHostError.audioFormatUnavailable
    }

    let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
    // The tap runs on the real-time audio thread. It captures only values
    // it owns — the continuation, the converter, and the mute box — never
    // the adapter, whose state belongs to the main actor.
    let muteBox = mute
    input.installTap(onBus: 0, bufferSize: 4096, format: microphoneFormat) {
      buffer, _ in
      if muteBox.muted {
        return
      }
      guard
        let converted = VoiceHostAdapter.convert(
          buffer,
          with: converter,
          to: analyzerFormat
        ),
        converted.frameLength > 0
      else {
        return
      }
      builder.yield(AnalyzerInput(buffer: converted))
    }
    engine.prepare()
    try engine.start()

    let resultsTask = Task { [weak self] in
      do {
        try await analyzer.start(inputSequence: inputSequence)
        for try await result in transcriber.results {
          let text = String(result.text.characters)
          guard !text.isEmpty else { continue }
          await MainActor.run {
            self?.emit(
              result.isFinal ? .finalTranscript : .partialTranscript,
              text: text
            )
          }
        }
      } catch is CancellationError {
        // Stopped on purpose; nothing to report.
      } catch {
        await MainActor.run {
          self?.pipelineFailed(String(describing: error))
        }
      }
    }
    // The device can change out from under a running engine — AirPods
    // arriving, a USB microphone leaving — and the tap simply goes silent.
    // Reported as a failure so the other side never shows a live button
    // over a dead pipeline.
    let configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.pipelineFailed("the audio device changed")
      }
    }

    session = ListeningSession(
      engine: engine,
      builder: builder,
      analyzer: analyzer,
      resultsTask: resultsTask,
      configObserver: configObserver
    )
    emit(.listeningStarted)
  }

  private func guardCurrent(_ id: Int) throws {
    if id != sessionCounter {
      throw CancellationError()
    }
  }

  private func endSession() {
    guard let session else { return }
    NotificationCenter.default.removeObserver(session.configObserver)
    session.builder.finish()
    session.engine.inputNode.removeTap(onBus: 0)
    session.engine.stop()
    let analyzer = session.analyzer
    let resultsTask = session.resultsTask
    // Finalization drains what the transcriber still holds — the trailing
    // words of an utterance stopped mid-sentence — through the results
    // sequence, so its consumer must still be alive to deliver them. The
    // cancel afterwards ends the consumer once the drain has returned; it
    // is ordering, not a hang guard — an analyzer that never returned
    // would leave the task parked, and a timeout race can be added if that
    // ever shows up in practice. On a plain disable the Dart side is
    // already deaf by the time the tail arrives, which is intended: the
    // user asked for silence.
    Task {
      try? await analyzer.finalizeAndFinishThroughEndOfInput()
      resultsTask.cancel()
    }
    self.session = nil
  }

  private func pipelineFailed(_ message: String) {
    sessionCounter += 1
    endSession()
    emit(.voiceFailed, text: message)
  }

  private static func microphonePermitted() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .audio)
    default:
      return false
    }
  }

  private static nonisolated func convert(
    _ buffer: AVAudioPCMBuffer,
    with converter: AVAudioConverter,
    to format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
    guard
      let converted = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: capacity
      )
    else {
      return nil
    }
    var handedOver = false
    var conversionError: NSError?
    converter.convert(to: converted, error: &conversionError) { _, status in
      if handedOver {
        status.pointee = .noDataNow
        return nil
      }
      handedOver = true
      status.pointee = .haveData
      return buffer
    }
    return conversionError == nil ? converted : nil
  }

  private func emit(_ type: HostVoiceEventType, text: String? = nil) {
    events.onVoiceEvent(
      event: HostVoiceEvent(type: type, text: text),
      completion: { _ in }
    )
  }
}

// MARK: - AVSpeechSynthesizerDelegate

@available(macOS 26.0, *)
extension VoiceHostAdapter: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didStart utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.emit(.speakingStarted) }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      self.mute.muted = false
      self.emit(.speakingFinished)
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      self.mute.muted = false
      self.emit(.speakingFinished)
    }
  }
}

/// A boolean the audio thread may read while the main actor writes.
final class MuteBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var muted: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }
  }
}

/// What can go wrong before transcription even starts.
enum VoiceHostError: Error {
  case microphoneDenied
  case localeUnsupported
  case audioFormatUnavailable
}
