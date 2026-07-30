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
@available(macOS 26.0, *)
final class VoiceHostAdapter: NSObject, VoiceHostApi {
  private let events: VoiceHostEvents
  private let synthesizer = AVSpeechSynthesizer()

  private var audioEngine: AVAudioEngine?
  private var listeningTask: Task<Void, Never>?
  private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

  init(events: VoiceHostEvents) {
    self.events = events
    super.init()
    synthesizer.delegate = self
  }

  // MARK: - VoiceHostApi

  func startListening(completion: @escaping (Result<Void, Error>) -> Void) {
    guard listeningTask == nil else {
      completion(.success(()))
      return
    }
    Task { @MainActor in
      do {
        try await self.beginListening()
        completion(.success(()))
      } catch {
        self.stopAudio()
        completion(.failure(PigeonError(
          code: "listening-failed",
          message: String(describing: error),
          details: nil
        )))
      }
    }
  }

  func stopListening(completion: @escaping (Result<Void, Error>) -> Void) {
    stopAudio()
    listeningTask?.cancel()
    listeningTask = nil
    emit(.listeningStopped)
    completion(.success(()))
  }

  func speak(text: String, completion: @escaping (Result<Void, Error>) -> Void) {
    let utterance = AVSpeechUtterance(string: text)
    synthesizer.speak(utterance)
    completion(.success(()))
  }

  func stopSpeaking(completion: @escaping (Result<Void, Error>) -> Void) {
    synthesizer.stopSpeaking(at: .immediate)
    completion(.success(()))
  }

  // MARK: - Listening pipeline

  @MainActor
  private func beginListening() async throws {
    guard await Self.microphonePermitted() else {
      throw VoiceHostError.microphoneDenied
    }
    guard
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale.current
      )
    else {
      throw VoiceHostError.localeUnsupported
    }
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults],
      attributeOptions: []
    )
    // The transcription model is a system asset; the first run downloads it.
    if let installation = try await AssetInventory.assetInstallationRequest(
      supporting: [transcriber]
    ) {
      try await installation.downloadAndInstall()
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
      )
    else {
      throw VoiceHostError.audioFormatUnavailable
    }

    let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
    inputBuilder = builder

    let engine = AVAudioEngine()
    audioEngine = engine
    let input = engine.inputNode
    let microphoneFormat = input.outputFormat(forBus: 0)
    guard
      let converter = AVAudioConverter(
        from: microphoneFormat,
        to: analyzerFormat
      )
    else {
      throw VoiceHostError.audioFormatUnavailable
    }
    input.installTap(onBus: 0, bufferSize: 4096, format: microphoneFormat) {
      [weak self] buffer, _ in
      guard let self, let converted = Self.convert(buffer, with: converter, to: analyzerFormat)
      else {
        return
      }
      self.inputBuilder?.yield(AnalyzerInput(buffer: converted))
    }
    engine.prepare()
    try engine.start()

    listeningTask = Task { [weak self] in
      do {
        try await analyzer.start(inputSequence: inputSequence)
        for try await result in transcriber.results {
          let text = String(result.text.characters)
          guard !text.isEmpty else { continue }
          self?.emit(result.isFinal ? .finalTranscript : .partialTranscript, text: text)
        }
      } catch is CancellationError {
        // Stopped on purpose; nothing to report.
      } catch {
        self?.emit(.voiceFailed, text: String(describing: error))
        await MainActor.run { self?.stopAudio() }
      }
    }
    emit(.listeningStarted)
  }

  private func stopAudio() {
    inputBuilder?.finish()
    inputBuilder = nil
    if let engine = audioEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    audioEngine = nil
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

  private static func convert(
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
    DispatchQueue.main.async { [events] in
      events.onVoiceEvent(
        event: HostVoiceEvent(type: type, text: text),
        completion: { _ in }
      )
    }
  }
}

// MARK: - AVSpeechSynthesizerDelegate

@available(macOS 26.0, *)
extension VoiceHostAdapter: AVSpeechSynthesizerDelegate {
  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didStart utterance: AVSpeechUtterance
  ) {
    emit(.speakingStarted)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    emit(.speakingFinished)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    emit(.speakingFinished)
  }
}

/// What can go wrong before transcription even starts.
enum VoiceHostError: Error {
  case microphoneDenied
  case localeUnsupported
  case audioFormatUnavailable
}
