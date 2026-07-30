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
    let endpointTask: Task<Void, Never>
    let configObserver: NSObjectProtocol
  }

  /// A volatile transcript is on screen and unsettled.
  private var utteranceInProgress = false

  /// When the current utterance's first volatile arrived.
  ///
  /// The VAD's clock freezes while the microphone is muted, so right after
  /// an answer its "last voice" is minutes stale. The endpointer must only
  /// trust a silence measured against voice heard for THIS utterance, or
  /// the first volatile after an answer would be finalized on the spot —
  /// the user's sentence cut off at its first word.
  private var utteranceHeardAt: TimeInterval = .infinity

  /// The endpointer has already asked for this utterance; asked once.
  private var endpointFinalizeRequested = false

  /// How much silence after speech means the user has finished talking.
  ///
  /// The transcriber's own endpointing waits out several seconds, and the
  /// Dart fallback another 1.5; this is what makes the answer feel like a
  /// reply instead of a delayed message.
  private static let endpointSilence: TimeInterval = 0.8

  private var session: ListeningSession?

  /// Bumped on every start and stop; an in-flight start that no longer
  /// matches gives up quietly. The asset download inside `begin` can take
  /// minutes on first run, and every await inside it is a window.
  private var sessionCounter = 0
  private var starting = false

  /// Read on the real-time audio thread, written here.
  private let mute = MuteBox()

  /// Utterances in flight, streamed one sentence at a time.
  ///
  /// The mute and the SpeakingFinished event belong to the whole answer:
  /// the first sentence mutes, and only the last one back unmutes —
  /// otherwise sentence one's return reopens the microphone while
  /// sentences two onward are still playing, and the agent hears itself.
  private var outstandingUtterances = 0

  /// Bumped by stopSpeaking; an utterance still in flight to the sidecar
  /// captures it at entry, and a stale one must not fall back to the
  /// system voice after the user has already barged over it.
  private var speakEpoch = 0

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
    // would report success while opening nothing. Speech state resets too:
    // a fallback utterance whose terminal callback never came must not
    // leave the microphone muted for the rest of the session.
    sessionCounter += 1
    starting = false
    speakEpoch += 1
    unmuteGeneration += 1
    outstandingUtterances = 0
    speakingReported = false
    mute.muted = false
    endSession()
    emit(.listeningStopped)
    completion(.success(()))
  }

  func finalizeUtterance(completion: @escaping (Result<Void, Error>) -> Void) {
    // The transcriber's endpointing waits out a long silence; the app calls
    // this when the partial has visibly stopped changing, and whatever is
    // pending settles as a final right away.
    guard let session else {
      completion(.success(()))
      return
    }
    let analyzer = session.analyzer
    Task {
      try? await analyzer.finalize(through: nil)
      completion(.success(()))
    }
  }

  func speak(
    text: String,
    voice: String?,
    language: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    utteranceBegan()
    let epoch = speakEpoch
    Task { @MainActor in
      let spoke = await self.speakThroughSidecar(
        text: text,
        voice: voice,
        language: language
      )
      if !spoke && epoch == self.speakEpoch {
        // The resident voice is not running: fall back to the system
        // synthesizer rather than going silent. The delegate's
        // didFinish/didCancel ends this utterance. A stale epoch means the
        // user barged over this sentence while it was in flight, and it
        // must not be read after all.
        let utterance = AVSpeechUtterance(string: text)
        if let systemVoice = Self.bestVoice() {
          utterance.voice = systemVoice
        }
        self.synthesizer.speak(utterance)
      } else {
        self.utteranceEnded()
      }
    }
    completion(.success(()))
  }

  /// Cancels a pending delayed unmute when a newer speech state supersedes
  /// it.
  private var unmuteGeneration = 0

  /// Whether SpeakingStarted has been reported without its Finished yet.
  ///
  /// The unmute hangover can bridge two utterances: the second begins
  /// while the first's Finished is still pending, and the pair must not
  /// double-report.
  private var speakingReported = false

  private func utteranceBegan() {
    outstandingUtterances += 1
    unmuteGeneration += 1
    if outstandingUtterances == 1 {
      // Muted before the first sample leaves the speaker, not when a
      // delegate reports it: the gap is exactly long enough for the agent
      // to hear its own opening words.
      mute.muted = true
      if !speakingReported {
        speakingReported = true
        emit(.speakingStarted)
      }
    }
  }

  private func utteranceEnded() {
    outstandingUtterances = max(0, outstandingUtterances - 1)
    if outstandingUtterances == 0 {
      // The speaker's tail is still in the air when the sidecar returns;
      // unmuting on its heels lets the agent transcribe its own last
      // word. The microphone stays shut a beat longer.
      unmuteGeneration += 1
      let generation = unmuteGeneration
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(300))
        guard
          generation == self.unmuteGeneration,
          self.outstandingUtterances == 0
        else {
          return
        }
        self.mute.muted = false
        self.speakingReported = false
        self.emit(.speakingFinished)
      }
    }
  }

  /// Speaks through the resident Qwen3-TTS sidecar; false when unreachable.
  ///
  /// The sidecar blocks until playback finishes or is stopped, which is
  /// exactly the SpeakingFinished signal.
  private func speakThroughSidecar(
    text: String,
    voice: String?,
    language: String?
  ) async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:46557/speak") else {
      return false
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    var payload: [String: String] = ["text": text, "voice": voice ?? "ryan"]
    if let language {
      payload["lang"] = language
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }

  /// The highest-quality installed voice for the user's language.
  ///
  /// Premium and enhanced voices are the ones that do not sound like a
  /// machine; they exist once the user has downloaded them in System
  /// Settings, and the default compact voice is the fallback.
  private static func bestVoice() -> AVSpeechSynthesisVoice? {
    let wanted = Locale.preferredLanguages.first ?? "en"
    let prefix = String(wanted.prefix(2))
    let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language.hasPrefix(prefix)
    }
    return candidates.first { $0.quality == .premium }
      ?? candidates.first { $0.quality == .enhanced }
      ?? candidates.first
  }

  func stopSpeaking(completion: @escaping (Result<Void, Error>) -> Void) {
    speakEpoch += 1
    synthesizer.stopSpeaking(at: .immediate)
    if let url = URL(string: "http://127.0.0.1:46557/stop") {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.timeoutInterval = 3
      URLSession.shared.dataTask(with: request).resume()
    }
    // The outstanding requests unwind through their own returns; the mute
    // lifts when the count reaches zero.
    completion(.success(()))
  }

  // MARK: - Listening pipeline

  private func begin(id: Int) async throws {
    guard await Self.microphonePermitted() else {
      throw VoiceHostError.microphoneDenied
    }
    try guardCurrent(id)
    // The user's language, not the app bundle's: an unlocalized bundle
    // reports English as Locale.current, and a zh-TW speaker would be
    // transcribed into romanized noise.
    guard let locale = await Self.preferredTranscriberLocale() else {
      throw VoiceHostError.localeUnsupported
    }
    NSLog("Lulo voice: transcribing as %@", locale.identifier)
    try guardCurrent(id)
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      // fastResults trades a little accuracy for volatile results that
      // arrive while the words are still being said; the finals settle the
      // spelling afterwards. Without it the first partial could trail the
      // speech by many seconds, and the endpointer starved.
      reportingOptions: [.volatileResults, .fastResults],
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
    // Deliberately NOT voice-processing: enabling it turns the input node
    // into a nine-channel unit whose first channel is not the microphone,
    // and the transcriber hears silence. Half-duplex muting already keeps
    // the agent from hearing itself.
    let microphoneFormat = input.outputFormat(forBus: 0)
    // The microphone is an array — three channels built in, more on
    // aggregates — and which channel carries the voice is the device's
    // business. Each buffer is mixed down by taking its loudest channel,
    // then converted to what the analyzer wants.
    guard
      let monoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: microphoneFormat.sampleRate,
        channels: 1,
        interleaved: false
      ),
      let converter = AVAudioConverter(from: monoFormat, to: analyzerFormat)
    else {
      throw VoiceHostError.audioFormatUnavailable
    }

    let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
    // The tap runs on the real-time audio thread. It captures only values
    // it owns — the continuation, the converter, and the boxes — never
    // the adapter, whose state belongs to the main actor.
    let muteBox = mute
    let vad = VoiceActivityBox()
    input.installTap(onBus: 0, bufferSize: 4096, format: microphoneFormat) {
      buffer, _ in
      if muteBox.muted {
        return
      }
      guard
        let (mono, rms) = VoiceHostAdapter.loudestChannel(
          of: buffer,
          as: monoFormat
        ),
        let converted = VoiceHostAdapter.convert(
          mono,
          with: converter,
          to: analyzerFormat
        ),
        converted.frameLength > 0
      else {
        return
      }
      vad.observe(rms: rms, at: ProcessInfo.processInfo.systemUptime)
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
            // Bookkeeping belongs to the current session only: a stale
            // session's trailing results still reach the other side, but
            // must not steer the new session's endpointer.
            if let self, id == self.sessionCounter {
              if !result.isFinal && !self.utteranceInProgress {
                self.utteranceHeardAt = ProcessInfo.processInfo.systemUptime
              }
              self.utteranceInProgress = !result.isFinal
              if result.isFinal {
                self.endpointFinalizeRequested = false
                NSLog("Lulo voice: final (%d chars)", text.count)
              }
            }
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
    // The transcriber's own endpointing waits out seconds of silence
    // before settling an utterance. This loop settles it as soon as the
    // room has actually gone quiet after speech, which is what makes the
    // agent answer when the user stops talking rather than a beat later.
    let endpointTask = Task { @MainActor [weak self] in
      var ticks = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(150))
        self?.checkEndpoint(id: id, vad: vad, analyzer: analyzer)
        ticks += 1
        if ticks % 20 == 0 {
          // Calibration heartbeat: what the room sounds like, every ~3s.
          let (floor, peak) = vad.snapshot()
          NSLog("Lulo voice: vad floor %.4f peak %.4f", floor, peak)
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
      endpointTask: endpointTask,
      configObserver: configObserver
    )
    emit(.listeningStarted)
  }

  /// Settles the utterance in progress once the room has gone quiet.
  private func checkEndpoint(
    id: Int,
    vad: VoiceActivityBox,
    analyzer: SpeechAnalyzer
  ) {
    guard
      id == sessionCounter,
      utteranceInProgress,
      !endpointFinalizeRequested,
      !mute.muted
    else {
      return
    }
    let silence = vad.silence(asOf: ProcessInfo.processInfo.systemUptime)
    guard silence.isFinite, silence > Self.endpointSilence else {
      return
    }
    // Recognition trails the voice it heard, so the first volatile may
    // arrive after the room already went quiet — the margin covers that
    // lag. Anything staler than the utterance is the pre-answer past.
    guard vad.lastVoiceAt() >= utteranceHeardAt - 1.5 else {
      return
    }
    endpointFinalizeRequested = true
    NSLog("Lulo voice: endpointing after %.2fs of silence", silence)
    Task {
      try? await analyzer.finalize(through: nil)
    }
  }

  private func guardCurrent(_ id: Int) throws {
    if id != sessionCounter {
      throw CancellationError()
    }
  }

  private func endSession() {
    guard let session else { return }
    NotificationCenter.default.removeObserver(session.configObserver)
    session.endpointTask.cancel()
    utteranceInProgress = false
    utteranceHeardAt = .infinity
    endpointFinalizeRequested = false
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

  /// The first of the user's preferred languages the transcriber speaks.
  private static func preferredTranscriberLocale() async -> Locale? {
    for language in Locale.preferredLanguages {
      if let match = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: language)
      ) {
        return match
      }
    }
    return await SpeechTranscriber.supportedLocale(equivalentTo: .current)
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

  /// The channel with the most energy in [buffer], as a mono copy, with
  /// that channel's RMS for the endpointer.
  ///
  /// Microphone arrays and aggregate devices put the voice on a channel of
  /// their own choosing; picking by loudness finds it without asking.
  private static nonisolated func loudestChannel(
    of buffer: AVAudioPCMBuffer,
    as monoFormat: AVAudioFormat
  ) -> (AVAudioPCMBuffer, Float)? {
    guard
      let channels = buffer.floatChannelData,
      buffer.frameLength > 0,
      let mono = AVAudioPCMBuffer(
        pcmFormat: monoFormat,
        frameCapacity: buffer.frameLength
      ),
      let monoData = mono.floatChannelData
    else {
      return nil
    }
    let frames = Int(buffer.frameLength)
    var loudest = 0
    var loudestEnergy: Float = -1
    for channel in 0..<Int(buffer.format.channelCount) {
      var energy: Float = 0
      let data = channels[channel]
      for frame in 0..<frames {
        energy += data[frame] * data[frame]
      }
      if energy > loudestEnergy {
        loudestEnergy = energy
        loudest = channel
      }
    }
    monoData[0].update(from: channels[loudest], count: frames)
    mono.frameLength = buffer.frameLength
    return (mono, (loudestEnergy / Float(frames)).squareRoot())
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
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.utteranceEnded() }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.utteranceEnded() }
  }
}

/// When the room last sounded like somebody talking, over an adaptive
/// noise floor.
///
/// The audio tap reports every buffer's RMS; the floor follows the room —
/// falling quickly into quiet, climbing slowly through steady hum — so a
/// fan is absorbed while a voice above it still registers. Read and
/// written across the audio thread and the main actor.
final class VoiceActivityBox: @unchecked Sendable {
  private let lock = NSLock()
  private var lastVoice: TimeInterval = -.infinity
  private var floor: Float = 0.002

  /// A voice must rise this far above the floor, and above an absolute
  /// quiet-room minimum, before it counts.
  private static let floorRatio: Float = 3
  private static let minimumVoice: Float = 0.004

  /// Records one buffer's loudness at [now], in seconds on any steady
  /// clock.
  func observe(rms: Float, at now: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    if rms < floor {
      floor = 0.9 * floor + 0.1 * rms
    } else {
      // Slowly: a long monologue must not raise the floor high enough to
      // swallow its own voice. Speech is bursty — every inter-word dip
      // pulls the floor back down fast — but steady hum climbs it all the
      // way and is absorbed within a couple of minutes.
      floor = 0.998 * floor + 0.002 * rms
    }
    if rms > max(Self.minimumVoice, floor * Self.floorRatio) {
      lastVoice = now
    }
    if rms > peak {
      peak = rms
    }
  }

  /// Seconds since a voice was last heard; infinite before the first one.
  func silence(asOf now: TimeInterval) -> TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return now - lastVoice
  }

  /// When a voice was last heard, on the clock [observe] was given.
  func lastVoiceAt() -> TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return lastVoice
  }

  /// The floor and loudest RMS since the last snapshot, for calibration.
  func snapshot() -> (floor: Float, peak: Float) {
    lock.lock()
    defer { lock.unlock() }
    let seen = peak
    peak = 0
    return (floor, seen)
  }

  private var peak: Float = 0
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
