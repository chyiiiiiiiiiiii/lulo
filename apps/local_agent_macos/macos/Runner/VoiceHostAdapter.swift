import AVFoundation
import FlutterMacOS
import Speech

/// The ears and the mouth behind the Flutter voice pipeline.
///
/// Listening runs the microphone through SpeechAnalyzer's on-device
/// transcriber and reports volatile results as partial transcripts and
/// finalized ones as utterances. Speaking goes through the Qwen3-TTS
/// sidecar — one resident voice, no system-synthesizer stand-in.
/// Everything is reported back over the pigeon event channel; failures are
/// events too, because the conversation loop must survive a microphone that
/// went away.
///
/// Full duplex where the platform allows it: the sidecar renders PCM, the
/// app plays it through its own voice-processed output, and the system
/// echo canceller keeps the agent's voice out of its own microphone — so
/// the user interrupts by simply talking, as with a person. Where voice
/// processing cannot be enabled, the half-duplex fallback mutes the
/// microphone and lets the sidecar play the sentence itself.
@available(macOS 26.0, *)
@MainActor
final class VoiceHostAdapter: NSObject, VoiceHostApi {
  private let events: VoiceHostEvents

  /// Everything one listening run owns, torn down as one.
  private struct ListeningSession {
    let engine: AVAudioEngine
    let builder: AsyncStream<AnalyzerInput>.Continuation
    let analyzer: SpeechAnalyzer
    let resultsTask: Task<Void, Never>
    let endpointTask: Task<Void, Never>
    let configObserver: NSObjectProtocol
    /// The mouth, when this session owns playback (full duplex).
    let playerNode: AVAudioPlayerNode?
    /// What the sidecar's PCM arrives as: float32 mono at its sample rate.
    let renderFormat: AVAudioFormat?
  }

  /// True while the session's echo-cancelled output lets the microphone
  /// stay open during speech. Decided per session in [begin].
  private var fullDuplex = false

  /// Headphone mode: the sidecar speaks, the engine only listens, and the
  /// microphone never mutes — there is no echo path to protect it from.
  private var openMicWithoutCanceller = false

  /// Control messages ride their own connection pool. /speak requests
  /// block until playback finishes, and enough of them queued fills
  /// URLSession.shared's per-host pool — measured in use: thirteen stops
  /// logged, none delivered, ninety seconds of uninterruptible playback
  /// while /stop waited in line behind the very speech it was meant to
  /// end.
  private let controlSession = URLSession(configuration: .ephemeral)

  /// Whose turn it is and when its clocks were last true. Kept as one
  /// value so it can be exercised without an audio device; see [SpeechTurn].
  private var turn = SpeechTurn()

  /// What the recogniser should lean towards, growing with the answers
  /// spoken aloud. Outlives any one listening session on purpose: the
  /// conversation does too.
  private var vocabulary = SpokenVocabularyBook(
    seeds: VoiceHostAdapter.spokenVocabulary
  )
  private var vocabularyRefresh: Task<Void, Never>?

  /// The vocabulary the analyzer was last actually given.
  ///
  /// Kept so a scheduled refresh can tell whether anything changed since.
  /// Cleared with the session, because a new analyzer starts with none.
  private var appliedVocabulary: [String] = []


  /// What the microphone heard during a hotkey hold, kept for the
  /// recogniser evaluation.
  private let heldSpeech = HeldSpeechCaptureBox()

  /// The streaming session's last minute of audio, so a doubted utterance
  /// can be re-heard by the batch recogniser.
  private let utteranceRing = UtteranceRingBox()

  /// When the audio of the utterance on screen began, as the ring's clock
  /// tells it, or infinite when no utterance has been heard.
  ///
  /// Set from the utterance's first volatile with the same 1.5s margin the
  /// endpointer uses, because recognition trails the voice it heard. Kept
  /// past the final on purpose: the re-hear request arrives after.
  private var utteranceAudioStartedAt: TimeInterval = .infinity

  /// Whether the next non-empty volatile starts a new utterance's audio.
  private var utteranceAudioOpen = false

  /// When the utterance on screen settled, as the ring's clock tells it.
  ///
  /// The re-hear clips to just before this instant: the endpointer waited
  /// out at least 0.55s of silence before asking, so everything after
  /// (settled - 0.3s) is quiet room the batch recogniser would only spend
  /// real time listening to.
  private var utteranceAudioSettledAt: TimeInterval = .infinity

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

  /// An engine built and waiting, so a press of the microphone button pays
  /// the AUVP initialization (17-81ms) instead of the ~1s graph build.
  ///
  /// Holds no microphone: building one leaves
  /// `kAudioDevicePropertyDeviceIsRunningSomewhere` false, and only
  /// `engine.start()` turns it true. And it holds no voice processing —
  /// which is what ducks every other app's audio system-wide — because
  /// that is enabled at the press by `finishWarmEngine`.
  /// `testAWarmEngineDoesNotHoldTheMicrophone` and
  /// `testAWarmEngineDoesNotDuckTheSystemAudio` keep both halves honest.
  private var warmEngine: AVAudioEngine?

  /// A warm-up in flight, so two of them never run at once.
  private var warmingUp: Task<Void, Never>?

  /// [speakEpoch], readable from the render loop off the main actor.
  private let speakEpochBox = EpochBox()

  /// Bumped by stopSpeaking; an utterance still in flight to the sidecar
  /// captures it at entry, and a stale one must not fall back to the
  /// system voice after the user has already barged over it.
  private var speakEpoch = 0

  init(events: VoiceHostEvents) {
    self.events = events
    super.init()
    // Build the engine now, while nobody is waiting for it. This app is
    // resident — launched once and summoned repeatedly — so the second it
    // costs is spent at launch instead of in front of the user on the first
    // press. It opens no microphone; see `warmEngine`.
    warmUpEngine()
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
        try await self.beginRetryingOutputRefusal(id: id)
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

  /// Runs begin(id:), retrying the output unit's transient refusal.
  ///
  /// -10875 out of the output unit is the graph refusing to initialize
  /// while a Bluetooth route is still settling; the same start succeeds
  /// once the route holds still. begin() assigns session only as its last
  /// step, so a failed attempt leaves nothing to unwind.
  private func beginRetryingOutputRefusal(id: Int) async throws {
    var attempt = 0
    while true {
      do {
        try await begin(id: id)
        return
      } catch {
        if !(error is CancellationError),
          (error as NSError).code == -10875,
          attempt < 2,
          id == sessionCounter
        {
          attempt += 1
          NSLog(
            "Lulo voice: output refused to initialize (-10875); attempt %d",
            attempt + 1
          )
          try? await Task.sleep(for: .seconds(1))
          continue
        }
        throw error
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
    speakEpochBox.epoch = speakEpoch
    turn.listeningStopped()
    mute.muted = false
    // The audio window closes with the session: a re-hear that arrives
    // after a stop must not carve a clip out of a dead session's tail.
    utteranceAudioStartedAt = .infinity
    utteranceAudioSettledAt = .infinity
    utteranceAudioOpen = false
    endSession()
    emit(.listeningStopped)
    completion(.success(()))
  }

  func reHearUtterance(completion: @escaping (Result<String, Error>) -> Void) {
    // The second listen for a doubted sentence: the same audio the
    // streaming recogniser just settled, carved from the session ring and
    // put to the batch recogniser that hears this user better. Empty for
    // "nothing to re-hear" and "could not answer" alike — the caller's
    // streamed transcript stands either way.
    let start = utteranceAudioStartedAt
    // 0.3s back from the settle keeps at least a beat of trailing silence
    // (the endpointer waited out 0.55s or more before asking) while cutting
    // the second-plus of quiet room between the silence, the final's
    // arrival, and this call — time the batch recogniser would otherwise
    // spend listening to nothing at roughly real time.
    let end = utteranceAudioSettledAt - 0.3
    guard start.isFinite, let clip = utteranceRing.clip(since: start, until: end)
    else {
      completion(.success(""))
      return
    }
    let terms = vocabulary.all
    Task { @MainActor in
      guard let url = await HeldSpeech.writeHeldClip(clip) else {
        completion(.success(""))
        return
      }
      let heard = await HeldSpeech.transcribeHeld(url, terms: terms)
      NSLog(
        "Lulo voice: re-heard %.1fs -> %d chars",
        Double(clip.samples.count) / clip.sampleRate,
        heard?.count ?? -1
      )
      completion(.success(heard ?? ""))
    }
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
    if vocabulary.learn(from: text) {
      scheduleVocabularyRefresh()
    }
    let epoch = speakEpoch
    NSLog(
      "Lulo speak: begin %d chars at epoch %d (outstanding %d)",
      text.count,
      epoch,
      turn.outstanding
    )
    Task { @MainActor in
      let spoke: Bool
      if self.fullDuplex,
        let player = self.session?.playerNode,
        let format = self.session?.renderFormat
      {
        // Off the main actor deliberately: this streams tens of thousands
        // of bytes per second of audio, and doing that on the actor that
        // also schedules the buffers made the speech stutter after the
        // first sentence — the reader starving the player it feeds.
        spoke = await Task.detached(priority: .userInitiated) {
          await self.renderAndPlay(
            text: text,
            voice: voice,
            language: language,
            epoch: epoch,
            player: player,
            format: format
          )
        }.value
      } else if epoch == self.speakEpoch {
        spoke = await self.speakThroughSidecar(
          text: text,
          voice: voice,
          language: language,
          epoch: epoch
        )
      } else {
        // Barged over while waiting its turn: not even sent. The render
        // path holds the same line inside its byte loop; without this the
        // sidecar path re-queued every stopped sentence as fresh work.
        spoke = true
      }
      if !spoke && epoch == self.speakEpoch {
        // The resident voice failed for this sentence. Deliberately NO
        // system-synthesizer fallback: a different voice cutting in
        // mid-answer reads as the agent changing person, which is worse
        // than a skipped sentence that is still on screen.
        NSLog("Lulo voice: sidecar declined a sentence (%d chars)", text.count)
      }
      self.utteranceEnded()
    }
    completion(.success(()))
  }

  /// Streams the sidecar's PCM into the session's player node, returning
  /// once this sentence has been fully heard or barged over.
  ///
  /// Buffers append to whatever is already scheduled, so consecutive
  /// sentences of one answer play back to back with no seam. The epoch is
  /// checked as the bytes arrive: a barge-in stops the download, and the
  /// player was already silenced by stopSpeaking.
  nonisolated private func renderAndPlay(
    text: String,
    voice: String?,
    language: String?,
    epoch: Int,
    player: AVAudioPlayerNode,
    format: AVAudioFormat
  ) async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:46557/render") else {
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
      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        return false
      }
      var pcm = [UInt8]()
      pcm.reserveCapacity(38_400)
      func scheduleBuffered(atLeast minimum: Int) {
        let usable = (pcm.count / 4) * 4
        guard usable >= minimum, usable > 0,
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(usable / 4)
          )
        else {
          return
        }
        let frames = usable / 4
        pcm.withUnsafeBytes { raw in
          buffer.floatChannelData![0].update(
            from: raw.baseAddress!.assumingMemoryBound(to: Float.self),
            count: frames
          )
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.removeFirst(usable)
        player.scheduleBuffer(buffer)
        if !player.isPlaying {
          player.play()
        }
      }
      var abandoned = false
      for try await byte in bytes {
        if epoch != self.speakEpochBox.epoch {
          // Barged over: stop pulling audio; the player is already quiet.
          if !abandoned {
            abandoned = true
            NSLog(
              "Lulo speak: ABORTED at epoch %d, now %d",
              epoch,
              self.speakEpochBox.epoch
            )
          }
          bytes.task.cancel()
          return true
        }
        pcm.append(byte)
        if pcm.count >= 19_200 {
          // 0.2s of audio at a time: enough to start almost immediately,
          // steady enough not to starve the output.
          scheduleBuffered(atLeast: 19_200)
        }
      }
      scheduleBuffered(atLeast: 4)
      guard epoch == self.speakEpochBox.epoch else {
        return true
      }
      // Heard to the end: a one-frame tail whose playback callback is the
      // drain signal. stopSpeaking's player.stop() fires it early, which
      // is exactly what a barge-in needs.
      await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        // Exactly once, from whichever of the three arrives first. A bare
        // continuation here leaked the whole utterance: a buffer scheduled
        // onto a stopped player never plays back, so .dataPlayedBack never
        // fired, renderAndPlay never returned, and utteranceEnded never ran.
        // outstandingUtterances then stayed above zero for the life of the
        // process — no SpeakingStarted or SpeakingFinished again, the agent
        // permanently "speaking" and permanently silent. Observed in use:
        // ninety seconds of WHILE SPEAKING partials in a silent room.
        let once = ResumeOnce(done)
        guard
          let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)
        else {
          once.resume()
          return
        }
        tail.frameLength = 1
        player.scheduleBuffer(tail, completionCallbackType: .dataPlayedBack) {
          _ in
          once.resume()
        }
        // A tail scheduled onto a node that is not running would sit there
        // unplayed, waiting for a play() that a finished answer never makes.
        if !player.isPlaying {
          player.play()
        }
        // stopSpeaking bumps the epoch; endSession stops the player without
        // doing so. Neither can deliver the callback, and both must end this
        // wait — with an absolute cap so no future stop path can leak it
        // again by forgetting to signal.
        self.pollForDrain(
          epoch: epoch,
          player: player,
          resume: once,
          deadline: Date().addingTimeInterval(180)
        )
      }
      return true
    } catch {
      return false
    }
  }

  /// Ends a drain wait that its playback callback can no longer end.
  ///
  /// Two stop paths cannot deliver `.dataPlayedBack`: `stopSpeaking`, which
  /// bumps the epoch, and `endSession`, which stops the player without
  /// touching it. Both are checked, and the deadline covers whatever is
  /// added next.
  nonisolated private func pollForDrain(
    epoch: Int,
    player: AVAudioPlayerNode,
    resume: ResumeOnce,
    deadline: Date
  ) {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
      [weak self] in
      guard let self else {
        resume.resume()
        return
      }
      if epoch != self.speakEpochBox.epoch || !player.isPlaying {
        resume.resume()
        return
      }
      guard Date() < deadline else {
        NSLog("Lulo voice: drain never completed; releasing the utterance")
        resume.resume()
        return
      }
      self.pollForDrain(
        epoch: epoch,
        player: player,
        resume: resume,
        deadline: deadline
      )
    }
  }

  /// Words the recogniser should lean towards when the audio is ambiguous.
  ///
  /// Deliberately short. Contextual biasing trades general accuracy for
  /// these terms, so a long list of rarely-spoken words costs more than it
  /// returns; this is the vocabulary this app is actually talked to about.
  static let spokenVocabulary: [String] = [
    "Flutter", "Dart", "Swift", "SwiftUI", "Xcode", "Kotlin",
    "React Native", "Blogger", "GitHub", "Google", "Apple", "Android",
    "iOS", "macOS", "Gemma", "LiteRT", "Lulo", "MLX", "Codex",
    "cross-platform", "framework", "widget", "repository", "commit",
    "Claude", "Anthropic", "AI", "API", "LLM", "MCP", "TTS", "app",
  ]

  /// Hands the recogniser the newest vocabulary, a beat after the answer
  /// that taught it — one update per burst of sentences, not one per chunk.
  private func scheduleVocabularyRefresh() {
    guard vocabularyRefresh == nil else { return }
    vocabularyRefresh = Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      self.vocabularyRefresh = nil
      guard let analyzer = self.session?.analyzer else { return }
      let terms = self.vocabulary.all
      // Replacing the recogniser's context costs it, and by the time this
      // fires the list is often the one already in force: opening the ears
      // pushes the profile across and `begin()` applies it, which used to
      // arm this timer to apply the identical list again two seconds later,
      // once per session for nothing.
      guard terms != self.appliedVocabulary else { return }
      let context = AnalysisContext()
      context.contextualStrings[.general] = terms
      do {
        try await analyzer.setContext(context)
        self.appliedVocabulary = terms
        NSLog(
          "Lulo voice: listening for %d terms",
          terms.count
        )
      } catch {
        NSLog(
          "Lulo voice: vocabulary update refused (%@)",
          String(describing: error)
        )
      }
    }
  }

  private func utteranceBegan() {
    let began = turn.began(at: ProcessInfo.processInfo.systemUptime)
    if began.shouldMute, !fullDuplex, !openMicWithoutCanceller {
      // Muted before the first sample leaves the speaker, not when a
      // delegate reports it: the gap is exactly long enough for the
      // agent to hear its own opening words. Full duplex keeps the
      // microphone open instead — the echo canceller carries the load.
      mute.muted = true
    }
    if began.shouldReportStart {
      emit(.speakingStarted)
    }
  }

  private func utteranceEnded() {
    guard
      let generation = turn.ended(at: ProcessInfo.processInfo.systemUptime)
    else { return }
    Task { @MainActor in
      // The speaker's tail is still in the air when the sidecar returns;
      // unmuting on its heels lets the agent transcribe its own last word.
      // The microphone stays shut a beat longer.
      try? await Task.sleep(for: .milliseconds(300))
      guard
        self.turn.liftMute(generation: generation)
      else {
        return
      }
      if !self.fullDuplex {
        self.mute.muted = false
        // Whatever utterance was pending went in before the answer; it was
        // answered. Full duplex never muted, never froze the VAD's clock,
        // and the user may be mid-interruption — its state must survive.
        self.turn.microphoneReopened(at: ProcessInfo.processInfo.systemUptime)
      }
      self.emit(.speakingFinished)
    }
  }

  /// Speaks through the resident Qwen3-TTS sidecar; false when unreachable.
  ///
  /// The sidecar blocks until playback finishes or is stopped, which is
  /// exactly the SpeakingFinished signal.
  private func speakThroughSidecar(
    text: String,
    voice: String?,
    language: String?,
    epoch: Int
  ) async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:46557/speak") else {
      return false
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    // The epoch rides along because delivery order does not: a request
    // that sat in the connection pool through a stop arrives after the
    // sidecar's own epoch bumped, looking like fresh work. The sidecar
    // compares this against the epoch /stop declared dead and drops it.
    var payload: [String: Any] = [
      "text": text,
      "voice": voice ?? "ryan",
      "epoch": epoch,
    ]
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

  /// The global hotkey's hold, reported to the conversation as an event:
  /// pressed is the user talking, released is the speech complete. The
  /// Dart side owns what that means; this side only relays the key.
  func hotKeyHold(began: Bool) {
    if began {
      heldSpeech.begin()
    } else if let clip = heldSpeech.end() {
      recognizeHeldClip(clip)
    }
    emit(began ? .holdToTalkPressed : .holdToTalkReleased)
  }

  /// Hands one held utterance to the batch recogniser and reports what it
  /// heard. An unreachable recogniser reports empty, promptly — the app
  /// falls back to the streamed transcript instead of waiting out its
  /// backstop.
  private func recognizeHeldClip(_ clip: HeldSpeechClip) {
    let terms = vocabulary.all
    Task { @MainActor in
      var heard: String?
      if let url = await HeldSpeech.writeHeldClip(clip) {
        heard = await HeldSpeech.transcribeHeld(url, terms: terms)
      }
      // The conversation treats unreachable and heard-nothing alike: either
      // way the streamed transcript stands.
      self.emit(.heldTranscript, text: heard ?? "")
    }
  }

  func chooseRecording(
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    let panel = NSOpenPanel()
    panel.title = "Choose a recording"
    panel.message = "Pick the audio Lulo should write out."
    panel.allowedContentTypes = [.audio, .movie]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    // Backing out is an answer, not a failure.
    guard panel.runModal() == .OK, let url = panel.url else {
      completion(.success(""))
      return
    }
    completion(.success(url.path))
  }

  func transcribeRecording(
    path: String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    let terms = vocabulary.all
    Task { @MainActor in
      // The same route the hold key uses, with a budget for a whole
      // recording rather than one held sentence. Breeze-ASR-25 runs at
      // roughly a quarter of real time, so this covers about forty minutes
      // of audio; past that the sidecar is still working and this has
      // stopped waiting, which is reported as having heard nothing.
      let heard = await HeldSpeech.transcribeHeld(
        URL(fileURLWithPath: path),
        terms: terms,
        timeout: 600
      )
      completion(.success(heard ?? ""))
    }
  }

  func useUnfinishedEndings(
    endings: [String],
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    turn.unfinishedEndings = endings
    NSLog("Lulo voice: %d unfinished endings from the profile", endings.count)
    completion(.success(()))
  }

  func useSpokenVocabulary(
    terms: [String],
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    vocabulary.adopt(terms)
    NSLog("Lulo voice: %d vocabulary terms from the profile", terms.count)
    // Through the same debounce as a term learned from an answer, so a
    // profile saved keystroke by keystroke costs one context update rather
    // than one per letter.
    scheduleVocabularyRefresh()
    completion(.success(()))
  }

  func stopSpeaking(completion: @escaping (Result<Void, Error>) -> Void) {
    speakEpoch += 1
    speakEpochBox.epoch = speakEpoch
    NSLog(
      "Lulo speak: STOP -> epoch %d (outstanding %d)",
      speakEpoch,
      turn.outstanding
    )
    // Full duplex: silence the local player at once; the /stop below also
    // makes the sidecar abandon whatever it was still rendering.
    session?.playerNode?.stop()
    if let url = URL(string: "http://127.0.0.1:46557/stop") {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.timeoutInterval = 3
      request.httpBody = try? JSONSerialization.data(
        withJSONObject: ["epoch": speakEpoch]
      )
      controlSession.dataTask(with: request).resume()
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
      // Asked for, and so far only reported. Measured over the private
      // corpus the score separates the words the recogniser got right from
      // the ones it did not, and nothing in the app had ever looked at it.
      // What to do about a low one is a decision that needs its own
      // evidence; knowing it is low costs nothing.
      attributeOptions: [.transcriptionConfidence]
    )
    // The transcription model is a system asset; the first run downloads
    // it, which can take minutes.
    if let installation = try await AssetInventory.assetInstallationRequest(
      supporting: [transcriber]
    ) {
      try await installation.downloadAndInstall()
    }
    try guardCurrent(id)
    // Terms this conversation is about, handed to the recogniser as a bias.
    //
    // Without them a product name is transcribed as whatever ordinary words
    // it sounds like — "Flutter" came back as "Flocker" and then "Frant",
    // and the model then answered a question about a thing that does not
    // exist. This is the standard remedy; every production speech stack has
    // a name for it (LiveKit calls them keyterms, most vendors call it
    // contextual biasing) and Apple's is contextualStrings.
    let context = AnalysisContext()
    let terms = vocabulary.all
    context.contextualStrings[.general] = terms
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    try await analyzer.setContext(context)
    appliedVocabulary = terms
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
      )
    else {
      throw VoiceHostError.audioFormatUnavailable
    }
    try guardCurrent(id)

    // The engine is built ahead of time and off the main thread. Both
    // matter and they fix different things: off the main thread is why the
    // app no longer freezes for a second on every press, and ahead of time
    // is why the microphone now opens in 80-90 ms instead of 1100. See
    // `makeWarmEngine`.
    let muteBox = mute
    let heldSpeechBox = heldSpeech
    let warm = try await takeWarmEngine()
    let graph: ListeningGraph
    do {
      graph = try Self.makeListeningGraph(
        warm: warm,
        analyzerFormat: analyzerFormat,
        mute: muteBox,
        heldSpeech: heldSpeechBox,
        utteranceRing: utteranceRing
      )
    } catch {
      // A warm engine that will not take a session is not worth keeping.
      warm.engine.stop()
      throw error
    }
    // A stop that arrived while the graph was being built owns the outcome.
    // It is a whole second now, which is long enough for the user to change
    // their mind in.
    do {
      try guardCurrent(id)
    } catch {
      graph.engine.stop()
      graph.engine.inputNode.removeTap(onBus: 0)
      graph.builder.finish()
      throw error
    }
    let engine = graph.engine
    let builder = graph.builder
    let inputSequence = graph.inputSequence
    let vad = graph.vad
    let playerNode = graph.playerNode
    let renderFormat = graph.renderFormat
    fullDuplex = graph.fullDuplex
    openMicWithoutCanceller = graph.openMicWithoutCanceller

    let resultsTask = Task { [weak self, vad] in
      do {
        try await analyzer.start(inputSequence: inputSequence)
        for try await result in transcriber.results {
          let text = String(result.text.characters)
          // Read once, outside the bookkeeping branch: the score is what
          // the app shows the user, not only what the log records.
          let weakest =
            result.isFinal
            ? lowestTranscriptionConfidence(in: result.text) : nil
          await MainActor.run {
            // Bookkeeping belongs to the current session only: a stale
            // session's trailing results still reach the other side, but
            // must not steer the new session's endpointer. It also runs
            // for empty results: a finalize that produced nothing must
            // still clear the endpointer's request flag, or the fast
            // path stays latched off for the rest of the session.
            if let self, id == self.sessionCounter {
              if result.isFinal {
                // How long the transcriber took to answer the endpointer.
                // It sits between "the room went quiet" and "the question
                // exists", and nothing else on either side can see it: the
                // endpointer only knows it asked, and Dart only knows the
                // answer arrived. Infinite means this final settled on the
                // transcriber's own schedule, with nobody asking.
                let asked = self.turn.finalizeAskedAt
                let waited =
                  asked.isFinite
                  ? ProcessInfo.processInfo.systemUptime - asked
                  : -1
                self.turn.settled()
                // The audio window stays where it is — the re-hear request
                // arrives after this final — but the next volatile belongs
                // to a new utterance.
                self.utteranceAudioOpen = false
                self.utteranceAudioSettledAt =
                  ProcessInfo.processInfo.systemUptime
                NSLog(
                  "Lulo voice: final (%d chars) %.2fs after the ask, "
                    + "weakest span %@",
                  text.count,
                  waited,
                  weakest.map { String(format: "%.2f", $0) } ?? "unscored"
                )
              } else if !text.isEmpty {
                // Who is talking, and how loudly, at the moment a partial
                // arrives. Full duplex made every partial a barge-in
                // candidate: one non-empty partial cancels the whole answer,
                // and a cancelled answer is never spoken, so a single
                // misheard blip can silence the agent for the rest of the
                // session. This line is what says whether the blip was the
                // user, the room, or the agent's own voice getting past the
                // canceller — the peak next to it is the evidence.
                let (floor, peak) = vad.snapshot()
                NSLog(
                  "Lulo voice: partial (%d chars) peak %.4f floor %.4f%@%@",
                  text.count,
                  peak,
                  floor,
                  self.turn.outstanding > 0 ? " WHILE SPEAKING" : "",
                  self.mute.muted ? " muted" : ""
                )
                let heardAt = ProcessInfo.processInfo.systemUptime
                if !self.utteranceAudioOpen {
                  // Recognition trails the voice it heard: the first
                  // volatile can arrive over a second after the words
                  // began, so the audio window opens behind it by the same
                  // margin the endpointer allows.
                  self.utteranceAudioOpen = true
                  self.utteranceAudioStartedAt = heardAt - 1.5
                }
                self.turn.heardVolatile(text: text, at: heardAt)
              }
            }
            guard !text.isEmpty else { return }
            self?.emit(
              result.isFinal ? .finalTranscript : .partialTranscript,
              text: text,
              confidence: weakest,
              speechMs: Int64((vad.speechRun() * 1000).rounded())
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
        // The silence threshold is 0.8s, but the endpointer only notices it
        // at a tick, so the tick interval is added to every turn as jitter.
        // At 150ms that was up to a seventh of a second of pure waiting on
        // top of a wait that is already the largest item in the budget; at
        // 50ms it is a twentieth. Nothing else changes — checkEndpoint's
        // guards are all thresholds, so asking more often only finds the
        // crossing sooner, and endpointFinalizeRequested still means the
        // transcriber is asked exactly once per utterance.
        try? await Task.sleep(for: .milliseconds(50))
        self?.checkEndpoint(id: id, vad: vad, analyzer: analyzer)
        ticks += 1
        if ticks % 60 == 0 {
          // Calibration heartbeat: what the room sounds like, every ~3s.
          // "(utterance pending)" persisting here is the endpointer
          // declining to fire — the VAD never heard this utterance, and
          // the Dart settle fallback is doing the work.
          let (floor, peak) = vad.snapshot()
          let pending = self?.turn.utteranceInProgress == true
          NSLog(
            "Lulo voice: vad floor %.4f peak %.4f%@",
            floor,
            peak,
            pending ? " (utterance pending)" : ""
          )
        }
      }
    }
    // The device can change out from under a running engine — AirPods
    // arriving, a USB microphone leaving — and the tap simply goes silent.
    // Rebuilt rather than reported: Bluetooth routes do this as a matter
    // of course, idling and waking and renegotiating, and each one used
    // to surface as "Voice stopped: the audio device changed" over a
    // microphone the user never touched. Only a rebuild that itself
    // fails is a failure.
    let configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.audioDeviceChanged()
      }
    }

    session = ListeningSession(
      engine: engine,
      builder: builder,
      analyzer: analyzer,
      resultsTask: resultsTask,
      endpointTask: endpointTask,
      configObserver: configObserver,
      playerNode: playerNode,
      renderFormat: renderFormat
    )
    emit(.listeningStarted)
  }

  /// One listening session's audio, built whole.
  ///
  /// `@unchecked Sendable` because `AVAudioEngine` is not: the graph is
  /// built on one background thread, handed over once, and touched only on
  /// the main actor afterwards. Nothing shares it while it crosses.
  struct ListeningGraph: @unchecked Sendable {
    let engine: AVAudioEngine
    let builder: AsyncStream<AnalyzerInput>.Continuation
    let inputSequence: AsyncStream<AnalyzerInput>
    let vad: VoiceActivityBox
    let playerNode: AVAudioPlayerNode?
    let renderFormat: AVAudioFormat?
    /// Whether the echo canceller took both ends, so the microphone can
    /// stay open while the agent talks.
    let fullDuplex: Bool
    /// Headphones: the microphone stays open with no canceller, because
    /// there is nothing in the room to cancel.
    let openMicWithoutCanceller: Bool
  }

  /// Builds the whole listening graph, off the main thread.
  ///
  /// `nonisolated` is the entire point. This is a second of **synchronous**
  /// CoreAudio, and this class is `@MainActor`, so it used to run on the
  /// thread that draws: measured on one machine across three consecutive
  /// starts in one process, 1244, 1161 and 1076 ms, of which
  /// `setVoiceProcessingEnabled(true)` alone was 826-960 and the first touch
  /// of `inputNode` another 100-229. Not a first-run cost — every press of
  /// the microphone button paid it, and the interface froze for the whole of
  /// it. Built on a background thread instead, the main thread's worst stall
  /// over the same work measures 23 ms, and
  /// `testBuildingTheListeningGraphLeavesTheMainThreadFree` keeps it there.
  ///
  /// This does not make listening start any sooner. The second is still
  /// spent; it is spent somewhere the user can keep using the app. Removing
  /// it altogether means holding a voice-processing unit open before anyone
  /// has asked to be heard, which costs a privacy indicator and a battery,
  /// and needs its own measurement before anybody trades for it.
  ///
  /// The boxes are passed in rather than read off `self`: they are the only
  /// adapter state the audio thread is allowed to touch, and every one of
  /// them is already `Sendable`.
  /// The expensive half of the listening graph, which no session owns.
  ///
  /// `setVoiceProcessingEnabled` and the first touch of `inputNode` are
  /// almost the whole second, and neither depends on the session about to
  /// start — so this is built once and kept. What a press of the microphone
  /// button then pays is the tap, the converter, `prepare` and `start`,
  /// measured at 80-90 ms against 1100.
  ///
  /// Safe only because building does **not** open the microphone. Measured
  /// through `kAudioDevicePropertyDeviceIsRunningSomewhere`, the property
  /// the system reads to decide the recording indicator: false before the
  /// build, false a second and a half after it, and true only once
  /// `engine.start()` runs. `testAWarmEngineDoesNotHoldTheMicrophone` pins
  /// that, because the day it stops holding, this app is listening before
  /// anyone asked.
  /// Builds the engine without its voice processing: the half that is safe
  /// to keep warm.
  ///
  /// Voice processing puts the whole system into call mode — every other
  /// app's audio is ducked from the moment the Voice-Processing I/O unit
  /// exists, microphone open or not. Learned in use: Spotify went quiet
  /// the moment the app launched, and stayed quiet while nobody was
  /// talking, because the warm engine carried the unit. So the warm half
  /// is the bare graph (with the main mixer touched, which must happen
  /// before voice processing ever reshapes it), and [finishWarmEngine]
  /// enables the unit at the press — where the ducking belongs, measured
  /// at 17-81ms of AUVP initialization against the ~1s the bare build
  /// costs.
  nonisolated static func makeBareEngine() throws -> AVAudioEngine {
    let engine = AVAudioEngine()
    _ = engine.inputNode
    _ = engine.mainMixerNode
    return engine
  }

  nonisolated static func makeWarmEngine() throws -> WarmVoiceEngine {
    try finishWarmEngine(makeBareEngine())
  }

  /// Decides this press's audio arrangement and enables voice processing.
  ///
  /// Run at the press rather than at warm-up, for two reasons that point
  /// the same way: the ducking starts here, and the output transport the
  /// decision reads is the one the user has *now*, not the one they had
  /// at launch.
  nonisolated static func finishWarmEngine(
    _ engine: AVAudioEngine
  ) throws -> WarmVoiceEngine {
    let input = engine.inputNode
    var duplex = false
    var openMic = false
    if let outputTransport = InputDevicePolicy.defaultOutputTransport(),
      InputDevicePolicy.skipsEchoCancellation(outputTransport: outputTransport)
    {
      // Headphones: the far end goes into the user's ears and never
      // reaches the room, so there is nothing for a canceller to subtract
      // — and a Bluetooth output is unusable under this engine anyway.
      // Touching the output side while the route renegotiates its profile
      // failed start after start, first as kAUInitialize -10875 in the
      // voice-processing unit, then — with voice processing skipped — as
      // IsFormatSampleRateAndChannelCountValid(outputHWFormat) on the
      // plain output, the device mid-switch reporting no sample rate at
      // all. The engine that only listens initializes no output unit, so
      // neither failure exists: the sidecar speaks through its own
      // player, the microphone stays open, and interruption still works.
      openMic = true
    } else {
      // The main mixer must exist before voice processing reshapes the
      // graph. Instantiated afterwards it lands on 44.1kHz against 48kHz
      // hardware, and the output unit then refuses to initialize the
      // moment a player node is connected to it — kAUInitialize -10875 on
      // engine start, which reads as "voice processing is impossible
      // here" and is nothing of the sort. Six trials: input-only, input
      // and output, output-only, and no voice processing at all, each
      // with and without a player node. Only the ones that touched the
      // mixer first started.
      _ = engine.mainMixerNode
      // Voice processing gives the engine the system echo canceller: what
      // this process plays through its own output is subtracted from its
      // own microphone, so the microphone can stay open while the agent
      // talks and the user can interrupt by talking over it.
      // The canceller lives in one Voice-Processing I/O unit that owns
      // both ends of the audio. Enabling it on the input alone gives the
      // microphone side and leaves playback on a plain output unit, so
      // the unit has no far-end reference and there is nothing for it to
      // subtract. That was this app's arrangement, and the microphone was
      // never deaf — it simply heard the agent. Measured in use: nineteen
      // partial transcripts arrived while speaking, spelling out
      // "Flonter Google的這個技" in the agent's own words, at a peak of
      // 0.1443 against a 0.0021 noise floor. The first of them cancelled
      // the answer it came from.
      do {
        try input.setVoiceProcessingEnabled(true)
        do {
          try engine.outputNode.setVoiceProcessingEnabled(true)
          duplex = true
        } catch {
          // Input-only voice processing is worse than none at all: the
          // microphone stays open and nothing removes the agent from it.
          // Undo it so the half-duplex path, which mutes instead, takes
          // over.
          try? input.setVoiceProcessingEnabled(false)
          NSLog(
            "Lulo voice: output voice processing refused (%@); half-duplex",
            String(describing: error)
          )
        }
      } catch {
        NSLog(
          "Lulo voice: voice processing unavailable (%@); half-duplex",
          String(describing: error)
        )
      }
    }
    NSLog(
      "Lulo voice: %@",
      openMic
        ? "open microphone (headphones; the sidecar speaks, nothing echoes)"
        : duplex
          ? "full duplex (echo cancellation on both ends)"
          : "half duplex (microphone mutes while speaking)"
    )
    // Before the format is read: the format belongs to the device. The
    // output stays where the user put it — only the ears move.
    if let transport = InputDevicePolicy.defaultInputTransport(),
      InputDevicePolicy.pinsBuiltInMicrophone(transport: transport),
      let builtIn = InputDevicePolicy.builtInMicrophone()
    {
      do {
        try input.auAudioUnit.setDeviceID(builtIn)
        NSLog(
          "Lulo voice: bluetooth input declined; listening through the built-in microphone"
        )
      } catch {
        NSLog(
          "Lulo voice: could not pin the built-in microphone (%@)",
          String(describing: error)
        )
      }
    }
    return WarmVoiceEngine(
      engine: engine,
      fullDuplex: duplex,
      openMicWithoutCanceller: openMic
    )
  }

  /// An engine built ahead of time, with no session on it yet.
  ///
  /// `@unchecked Sendable` for the same reason `ListeningGraph` is: built on
  /// one background thread, handed over once, and touched only on the main
  /// actor afterwards.
  struct WarmVoiceEngine: @unchecked Sendable {
    let engine: AVAudioEngine
    let fullDuplex: Bool
    let openMicWithoutCanceller: Bool
  }

  /// Wires one session onto a warm engine and starts it.
  ///
  /// Everything here is cheap — the costly part is [makeWarmEngine], which
  /// this takes as an argument rather than doing again.
  nonisolated static func makeListeningGraph(
    warm: WarmVoiceEngine,
    analyzerFormat: AVAudioFormat,
    mute: MuteBox,
    heldSpeech: HeldSpeechCaptureBox,
    utteranceRing: UtteranceRingBox
  ) throws -> ListeningGraph {
    let engine = warm.engine
    let input = engine.inputNode
    let duplex = warm.fullDuplex
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
    let heldSpeechBox = heldSpeech
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
      let now = ProcessInfo.processInfo.systemUptime
      vad.observe(rms: rms, at: now)
      let monoSamples = Array(
        UnsafeBufferPointer(
          start: mono.floatChannelData![0],
          count: Int(mono.frameLength)
        )
      )
      heldSpeechBox.append(monoSamples, sampleRate: mono.format.sampleRate)
      utteranceRing.append(
        monoSamples,
        sampleRate: mono.format.sampleRate,
        at: now
      )
      builder.yield(AnalyzerInput(buffer: converted))
    }
    // The mouth: sidecar PCM plays through this node, inside the voice-
    // processed output so the echo canceller knows what to subtract.
    var playerNode: AVAudioPlayerNode?
    var renderFormat: AVAudioFormat?
    if duplex,
      let pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
      )
    {
      let player = AVAudioPlayerNode()
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: pcmFormat)
      playerNode = player
      renderFormat = pcmFormat
    }
    engine.prepare()
    try engine.start()
    return ListeningGraph(
      engine: engine,
      builder: builder,
      inputSequence: inputSequence,
      vad: vad,
      playerNode: playerNode,
      renderFormat: renderFormat,
      fullDuplex: duplex,
      openMicWithoutCanceller: warm.openMicWithoutCanceller
    )
  }
  /// Settles the utterance in progress once the room has gone quiet.
  private func checkEndpoint(
    id: Int,
    vad: VoiceActivityBox,
    analyzer: SpeechAnalyzer
  ) {
    guard id == sessionCounter else {
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    if turn.muteOverdue(now: now) {
      // The sidecar took a sentence and never gave it back. Waiting out
      // /speak's own timeout means a full two minutes of a microphone that
      // looks live and hears nothing; the ears come back now and the
      // sentence is abandoned where it stands.
      NSLog("Lulo voice: the sidecar went quiet; opening the microphone")
      turn.abandonSpeech()
      mute.muted = false
      turn.microphoneReopened(at: now)
      emit(.speakingFinished)
      return
    }
    guard !mute.muted else {
      return
    }
    let silence = vad.silence(asOf: now)
    guard
      turn.shouldFinalize(
        silence: silence,
        lastVoiceAt: vad.lastVoiceAt(),
        endpointSilence: Self.endpointSilence,
        now: now
      )
    else {
      return
    }
    turn.askedToFinalize(at: now)
    NSLog("Lulo voice: endpointing after %.2fs of silence", silence)
    Task {
      try? await analyzer.finalize(through: nil)
    }
  }

  /// The engine to start this session on, waiting for it or building one.
  ///
  /// Consumed: a session owns the engine it runs on, and `endSession` hands
  /// it back. Building here rather than failing is what makes the warm-up an
  /// optimization instead of a precondition — the first press after launch,
  /// or one that beats the warm-up, simply pays what it always paid.
  private func takeWarmEngine() async throws -> WarmVoiceEngine {
    // A warm-up already running is worth waiting for. Building a second
    // engine beside it pays the same second twice and leaves one of them to
    // be thrown away.
    if let warmingUp {
      await warmingUp.value
    }
    if let bare = warmEngine {
      warmEngine = nil
      return try await Task.detached(priority: .userInitiated) {
        try Self.finishWarmEngine(bare)
      }.value
    }
    return try await Task.detached(priority: .userInitiated) {
      try Self.makeWarmEngine()
    }.value
  }

  /// Builds the next engine while nobody is waiting for it.
  ///
  /// This app is resident — launched once and summoned repeatedly — so the
  /// second belongs in the gaps rather than in front of the user. At
  /// `.utility` because nothing is blocked on it; the press that cannot wait
  /// takes the `.userInitiated` path in `takeWarmEngine` instead.
  func warmUpEngine() {
    guard warmEngine == nil, warmingUp == nil, session == nil else {
      return
    }
    // Not under XCTest. The test host is the real app, so this would build a
    // real audio engine on a background thread at the moment the window
    // tests are measuring clicks and frames — `main.dart` keeps the real
    // model off the test host for the same reason. Nothing here is what
    // those tests are about, and the device tests that *are* about it build
    // their own.
    guard NSClassFromString("XCTestCase") == nil else {
      return
    }
    warmingUp = Task { @MainActor [weak self] in
      let startedAt = ProcessInfo.processInfo.systemUptime
      let built = try? await Task.detached(priority: .utility) {
        try Self.makeBareEngine()
      }.value
      // What the warm-up really costs in this app, as opposed to in a test
      // host or a bare script. Both of those were measured and neither is
      // this process: the test host runs the whole app delegate beside it,
      // and a script runs nothing. A press that lands inside this window
      // waits for it, so the number is worth having.
      NSLog(
        "Lulo voice: warm engine %@ in %.0f ms",
        built == nil ? "failed" : "ready",
        (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
      )
      guard let self else {
        built?.stop()
        return
      }
      self.warmingUp = nil
      guard self.warmEngine == nil, let built else {
        built?.stop()
        return
      }
      self.warmEngine = built
    }
  }

  /// Throws away the waiting engine, when what it was built against is gone.
  private func discardWarmEngine() {
    warmEngine?.stop()
    warmEngine = nil
  }

  private func guardCurrent(_ id: Int) throws {
    if id != sessionCounter {
      throw CancellationError()
    }
  }

  private func endSession() {
    guard let session else { return }
    NotificationCenter.default.removeObserver(session.configObserver)
    session.playerNode?.stop()
    session.endpointTask.cancel()
    turn.sessionEnded()
    session.builder.finish()
    session.engine.inputNode.removeTap(onBus: 0)
    session.engine.stop()
    // NOT back to the warm pool, deliberately. This engine carries the
    // Voice-Processing I/O unit, and that unit ducks every other app's
    // audio system-wide for as long as it exists — recycling it kept
    // Spotify quiet from the first press to app quit. Dropped instead, so
    // the unit deallocates and the room's audio comes back; the re-warm
    // below builds a bare engine that carries no such unit.
    if let player = session.playerNode {
      session.engine.detach(player)
    }
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
    // The next session builds a new analyzer, which starts with no context
    // of its own. Leaving this set would let the refresh decide the terms
    // were already in force and skip applying them to it.
    appliedVocabulary = []
    // The next press deserves the same fast start this one had. Holding to
    // talk opens and closes a session per turn now, so a warm engine that
    // was only ever built at launch would make every turn after the first
    // pay the ~1s build in front of the user.
    warmUpEngine()
  }

  /// The device changed under the running engine: rebuild on the settled
  /// route. Changes arrive in bursts, so the first one waits them out.
  private func audioDeviceChanged() {
    guard session != nil, !rebuildingAfterDeviceChange else {
      return
    }
    rebuildingAfterDeviceChange = true
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(600))
      self.rebuildingAfterDeviceChange = false
      guard self.session != nil else {
        // Stopped on purpose in the meantime; nothing to rebuild.
        return
      }
      NSLog("Lulo voice: the audio device changed; rebuilding the session")
      // The same speech-state reset as pipelineFailed, without the verdict.
      self.speakEpoch += 1
      self.speakEpochBox.epoch = self.speakEpoch
      self.turn.listeningStopped()
      self.mute.muted = false
      self.endSession()
      // The engine endSession just handed back was built against the device
      // that has gone away. Keeping it is how the rebuild lands back on the
      // route it was rebuilding away from.
      self.discardWarmEngine()
      self.sessionCounter += 1
      let id = self.sessionCounter
      do {
        try await self.beginRetryingOutputRefusal(id: id)
      } catch is CancellationError {
        // Superseded by a newer start or stop; theirs to report.
      } catch {
        self.pipelineFailed(String(describing: error))
      }
    }
  }

  private var rebuildingAfterDeviceChange = false

  private func pipelineFailed(_ message: String) {
    // The same speech-state reset as stopListening: a device change mid-
    // answer must not leave the mute box latched shut for the session
    // that comes after, nor speakingReported swallowing its first
    // SpeakingStarted. The starting flag falls too — a failure landing
    // inside startListening's await would otherwise leave it latched, and
    // the next tap on the microphone button would "succeed" opening
    // nothing.
    sessionCounter += 1
    starting = false
    speakEpoch += 1
    speakEpochBox.epoch = speakEpoch
    turn.listeningStopped()
    mute.muted = false
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

  private func emit(
    _ type: HostVoiceEventType,
    text: String? = nil,
    confidence: Double? = nil,
    speechMs: Int64? = nil
  ) {
    events.onVoiceEvent(
      event: HostVoiceEvent(
        type: type,
        text: text,
        confidence: confidence,
        speechMs: speechMs
      ),
      completion: { _ in }
    )
  }
}

/// One held utterance's audio, as captured.
struct HeldSpeechClip {
  let samples: [Float]
  let sampleRate: Double
}

/// Collects the microphone's samples for the duration of one hold.
///
/// Exists for the recogniser evaluation: the same audio Apple transcribed
/// is written to disk, so a candidate recogniser can be judged on real
/// utterances instead of benchmarks. Appends land on the audio thread,
/// begin and end on the main one; the lock is held only long enough to
/// move samples.
final class HeldSpeechCaptureBox: @unchecked Sendable {
  private let lock = NSLock()
  private var samples: [Float] = []
  private var rate: Double = 0
  private var active = false

  /// Starts a hold, discarding anything left from the last one.
  ///
  /// Unconditional on purpose. Carbon does not guarantee a release event
  /// when the modifiers are lifted before the key, so a hold can end without
  /// anyone being told; resetting here is the only thing that recovers from
  /// it. A caller that needs to tell key-repeat from a fresh press has to
  /// say so at the call site, the way `HotKeyHoldSplitter` does.
  func begin() {
    lock.lock()
    defer { lock.unlock() }
    active = true
    samples.removeAll(keepingCapacity: true)
    rate = 0
  }

  func append(_ newSamples: [Float], sampleRate: Double) {
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }
    samples.append(contentsOf: newSamples)
    rate = sampleRate
  }

  /// The clip this hold heard, exactly once; nil for an empty hold.
  func end() -> HeldSpeechClip? {
    lock.lock()
    defer { lock.unlock() }
    active = false
    guard !samples.isEmpty, rate > 0 else { return nil }
    let clip = HeldSpeechClip(samples: samples, sampleRate: rate)
    samples.removeAll(keepingCapacity: false)
    return clip
  }
}

/// The streaming session's last minute of microphone audio, kept so a
/// settled utterance the recogniser doubted can be listened to again.
///
/// The batch recogniser is measured 2-4x better than the streaming one on
/// the same audio, but it needs the audio — which the streaming path used
/// to feed to the analyzer and drop. This ring holds it, time-addressed,
/// so `reHearUtterance` can carve out exactly the utterance that settled.
/// Appends land on the audio thread, clips are taken on the main one; the
/// lock is held only long enough to move samples.
final class UtteranceRingBox: @unchecked Sendable {
  private let lock = NSLock()
  private var samples: [Float] = []
  private var rate: Double = 0
  private var endsAt: TimeInterval = .infinity
  private let capacitySeconds: TimeInterval

  init(capacitySeconds: TimeInterval = 60) {
    self.capacitySeconds = capacitySeconds
  }

  /// Adds one tap buffer, [now] being the uptime its last sample was heard.
  func append(_ newSamples: [Float], sampleRate: Double, at now: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    if rate != sampleRate {
      // A device swap changes the clock; old samples stitched onto the new
      // one would play at the wrong speed.
      samples.removeAll(keepingCapacity: true)
      rate = sampleRate
    }
    samples.append(contentsOf: newSamples)
    endsAt = now
    // Trimmed in chunks rather than per append: removeFirst shifts the
    // whole array, so doing it every 85ms buffer would move the full
    // minute of audio each time.
    let capacity = Int(capacitySeconds * rate)
    if samples.count > capacity + capacity / 4 {
      samples.removeFirst(samples.count - capacity)
    }
  }

  /// The audio heard from [start] to [end] (or to the latest sample), or
  /// nil where the ring holds nothing of it.
  ///
  /// The until-bound exists because the re-hear fires a beat after the
  /// endpointer's silence: the tail of the ring is quiet room, and the
  /// batch recogniser runs near real time, so every second of it is a
  /// second the user waits for nothing.
  func clip(
    since start: TimeInterval,
    until end: TimeInterval = .infinity
  ) -> HeldSpeechClip? {
    lock.lock()
    defer { lock.unlock() }
    guard rate > 0, !samples.isEmpty, endsAt.isFinite, start < endsAt else {
      return nil
    }
    let boundedEnd = min(end, endsAt)
    guard start < boundedEnd else { return nil }
    let dropped = min(samples.count, Int((endsAt - boundedEnd) * rate))
    let available = samples.count - dropped
    let count = min(available, Int((boundedEnd - start) * rate))
    guard count > 0 else { return nil }
    return HeldSpeechClip(
      samples: Array(samples[(available - count)..<available]),
      sampleRate: rate
    )
  }
}

/// The words this conversation is actually about, offered to the
/// recogniser as bias.
///
/// The static seed list only covers what the app is usually talked to
/// about. The terms that matter most are the ones the agent just said —
/// the user's next sentence quotes them back, and an unbiased recogniser
/// turns "hot reload" into whatever ordinary words it sounds like. The
/// agent's answers are clean text, so every Latin phrase spoken aloud is
/// learned here; user transcripts are never learned, because they are the
/// recogniser's own guesses and would only reinforce its mistakes.
///
/// Bounded, oldest-out: contextual biasing trades general accuracy for the
/// listed terms, so the book holds the current conversation, not a career.
///
/// Measured against the private corpus, through both the file path and the
/// streaming one the app actually uses, a thirty-two term list changed the
/// transcript by not one character. That is not proof the API does nothing —
/// twelve clean recordings is a small test and the terms have to be
/// acoustically plausible before a bias can pick them — but nothing here has
/// ever been shown to work, so do not build on it without measuring first.
struct SpokenVocabularyBook {
  static let capacity = 40

  private let seeds: [String]
  private var adopted: [String] = []
  private var learned: [String] = []
  private var known: Set<String>

  init(seeds: [String]) {
    self.seeds = seeds
    self.known = Set(seeds.map { $0.lowercased() })
  }

  /// Every term the recogniser should lean towards, the user's own first.
  ///
  /// The user's words outrank the seeds because the seeds are a guess made
  /// by whoever wrote the app and the adopted list is what the person doing
  /// the talking actually typed. Biasing trades general accuracy for the
  /// length of the list, so the order is the priority and each word appears
  /// once: the app's own built-in vocabulary and this file's seed list were
  /// written separately and overlap on nine terms, which on a fresh install
  /// is a fifth of the list saying the same words twice.
  var all: [String] {
    let mine = Set(adopted.map { $0.lowercased() })
    return adopted + seeds.filter { !mine.contains($0.lowercased()) } + learned
  }

  /// Takes [terms] as the user's vocabulary, replacing whatever was there.
  ///
  /// Replaces rather than adds: the agent profile is a watched file, so what
  /// it says now is the whole answer and a word the user deleted has to stop
  /// being listened for. What was learned from answers otherwise survives —
  /// that is this conversation's own context, not a setting.
  mutating func adopt(_ terms: [String]) {
    var seen = Set<String>()
    adopted = terms.compactMap { term -> String? in
      let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return seen.insert(trimmed.lowercased()).inserted ? trimmed : nil
    }
    if adopted.count > Self.capacity {
      // Bounded for the same reason `learned` is, and said out loud rather
      // than trimmed in silence: a profile long enough to hit this is one
      // somebody hand-edited, and a list that quietly stops at forty looks
      // from the outside like biasing that stopped working.
      NSLog(
        "Lulo voice: profile lists %d terms, biasing towards the first %d",
        adopted.count,
        Self.capacity
      )
      adopted = Array(adopted.prefix(Self.capacity))
      seen = Set(adopted.map { $0.lowercased() })
    }
    // A word the user has now listed is no longer one to have learned:
    // leaving it in both would list it twice, and evicting it from `learned`
    // later would drop the key that adoption is also relying on.
    learned.removeAll { seen.contains($0.lowercased()) }
    // Rebuilt rather than inserted into, or a term dropped from the profile
    // would stay unlearnable for the rest of the process.
    known = Set((adopted + seeds + learned).map { $0.lowercased() })
  }

  /// Learns the Latin phrases of [text]; true when anything was new.
  mutating func learn(from text: String) -> Bool {
    var added = false
    for term in Self.latinPhrases(in: text) {
      let key = term.lowercased()
      guard !known.contains(key) else { continue }
      known.insert(key)
      learned.append(term)
      added = true
      if learned.count > Self.capacity {
        known.remove(learned.removeFirst().lowercased())
      }
    }
    return added
  }

  /// Maximal runs of Latin words, kept as phrases: "hot reload" biases as
  /// itself, not as two unrelated words. Single letters and bare numbers
  /// are noise, not vocabulary.
  private static let latinPhrase = try! NSRegularExpression(
    pattern: "[A-Za-z][A-Za-z0-9+#'.-]*(?: [A-Za-z][A-Za-z0-9+#'.-]*)*"
  )

  private static func latinPhrases(in text: String) -> [String] {
    let range = NSRange(text.startIndex..., in: text)
    return latinPhrase.matches(in: text, range: range).compactMap { match in
      guard let found = Range(match.range, in: text) else { return nil }
      var term = String(text[found])
      while let last = term.last, ".,'-".contains(last) {
        term.removeLast()
      }
      return term.count >= 2 ? term : nil
    }
  }
}

/// The weakest span's confidence in a settled transcript, or nil when the
/// recogniser scored none of it.
///
/// The sentence is worth its weakest span rather than its average: one bad
/// word is enough to make the whole thing wrong, and averaging buries a 0.31
/// under a dozen 1.00s — which is exactly the case worth catching.
@available(macOS 26.0, *)
func lowestTranscriptionConfidence(in text: AttributedString) -> Double? {
  var lowest: Double?
  for run in text.runs {
    guard let confidence = run.transcriptionConfidence else { continue }
    lowest = min(lowest ?? confidence, confidence)
  }
  return lowest
}

/// Which microphone the listening engine should actually use.
///
/// A Bluetooth headset as the default input puts a telephony microphone
/// under the voice-processing unit, and what arrives from it is silence —
/// measured with AirPods Pro: vad peak 0.0000 across a whole spoken
/// sentence, four pipeline restarts, nothing heard. Worn headphones also
/// remove the room echo the canceller exists for, so the built-in
/// microphone is strictly better there. Any other transport — USB,
/// aggregate, built-in — is a working device, possibly deliberately
/// chosen, and stays.
enum InputDevicePolicy {
  static func pinsBuiltInMicrophone(transport: UInt32) -> Bool {
    transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  /// Whether playback through this output can skip the echo canceller.
  ///
  /// Headphones deliver the far end into the user's ears: nothing reaches
  /// the room, so there is no echo to cancel — and the voice-processing
  /// unit is exactly what fights Bluetooth routes, -10875 out of the
  /// output unit on start after start while the route renegotiates. The
  /// microphone stays open either way; only the canceller is skipped.
  static func skipsEchoCancellation(outputTransport: UInt32) -> Bool {
    outputTransport == kAudioDeviceTransportTypeBluetooth
      || outputTransport == kAudioDeviceTransportTypeBluetoothLE
  }

  /// Transport of the system's default input device, or nil if unknowable.
  static func defaultInputTransport() -> UInt32? {
    defaultDeviceTransport(kAudioHardwarePropertyDefaultInputDevice)
  }

  /// Transport of the system's default output device, or nil if unknowable.
  static func defaultOutputTransport() -> UInt32? {
    defaultDeviceTransport(kAudioHardwarePropertyDefaultOutputDevice)
  }

  private static func defaultDeviceTransport(
    _ selector: AudioObjectPropertySelector
  ) -> UInt32? {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &device
      ) == noErr, device != kAudioObjectUnknown
    else {
      return nil
    }
    return transport(of: device)
  }

  /// The system's default input device, or nil if unknowable.
  static func defaultInputDevice() -> AudioDeviceID? {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &device
      ) == noErr, device != kAudioObjectUnknown
    else {
      return nil
    }
    return device
  }

  /// Whether any process currently has [device] running.
  ///
  /// This is the property the system itself reads to decide whether to light
  /// the recording indicator, which makes it the honest way to ask "is this
  /// app listening" — as opposed to "does this app have an engine".
  static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard
      AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        == noErr
    else {
      return nil
    }
    return running != 0
  }

  /// The machine's own microphone, if it has one.
  static func builtInMicrophone() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(0)
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size
      ) == noErr
    else {
      return nil
    }
    var devices = [AudioDeviceID](
      repeating: 0,
      count: Int(size) / MemoryLayout<AudioDeviceID>.size
    )
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &devices
      ) == noErr
    else {
      return nil
    }
    return devices.first { device in
      transport(of: device) == kAudioDeviceTransportTypeBuiltIn
        && hasInputStreams(device)
    }
  }

  private static func transport(of device: AudioDeviceID) -> UInt32? {
    var transport = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard
      AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        == noErr
    else {
      return nil
    }
    return transport
  }

  private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(0)
    guard
      AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr
    else {
      return false
    }
    return size > 0
  }
}

/// Whether the words heard so far look like the end of a thought.
///
/// The endpointer's only other evidence is silence, and silence does not
/// separate the two things it has to tell apart: the corpus behind
/// `docs/decisions/voice-turn-latency.md` has mid-utterance pauses of 1.02s
/// against an 0.8s threshold, and Smart Turn v3.2 scored the two cases
/// 0.973–0.988 apart from each other — no threshold exists between them.
///
/// What does separate them is the word the pause landed after. A sentence
/// that stops on 「然後」 has not stopped; one that stops on 「可以嗎」 has.
/// This is a lexicon rather than a model on purpose: it is checkable against
/// a list of things people say, it costs nothing on a 50ms tick, and it is
/// wrong in ways that can be read off the table rather than guessed at.
enum TurnCompletion: Equatable {
  /// The words carry no signal either way; the ordinary silence applies.
  case unknown

  /// A thought still in progress — give it longer before submitting.
  case continuing

  /// A question or statement that has visibly landed — submit sooner.
  case settled

  // The words and thresholds are not written here. They live in
  // `TurnCompletion` in `agent_core` and reach this file through
  // `GeneratedTurnTakingLexicon.swift`, which `verify.dart` regenerates and
  // diffs — so a word added on one side and not the other fails the gate
  // instead of quietly making two platforms disagree about when a sentence
  // has ended. The *matcher* below stays native because it is consulted on a
  // 50ms tick inside the audio path; see `pigeons/voice_host_api.dart`.

  /// How much longer a half-finished thought is given.
  ///
  /// Sized to clear the corpus's longest mid-utterance pause: 0.8 + 0.6 is
  /// 1.4s, against the 1.02s of `short-answer-not-yet`.
  static let continuingGrace = TurnTakingLexicon.continuingGrace

  /// How much sooner a visibly finished question is submitted.
  ///
  /// Deliberately small. Every millisecond taken off the wait is a
  /// millisecond of a user's trailing word that can be cut off, and being
  /// cut off is a worse failure than being answered a quarter-second late.
  static let settledSaving = TurnTakingLexicon.settledSaving

  /// How much has to have been said before "finished" is believable.
  ///
  /// A bare 「嗎」 is one misheard syllable, not a question, and shortening
  /// the endpoint on a mishearing is how a user gets cut off mid-word.
  static let syllablesToBeFinished = TurnTakingLexicon.syllablesToBeFinished

  /// Endings that introduce more words after a pause.
  private static let continuingSuffixes = TurnTakingLexicon.continuingSuffixes

  /// The same, in Latin script, matched as a whole final word.
  private static let continuingWords = TurnTakingLexicon.continuingWords

  /// Endings that mean the question has been asked.
  private static let settledSuffixes = TurnTakingLexicon.settledSuffixes

  /// What the recogniser writes when it believes the sentence ended.
  private static let terminalPunctuation = TurnTakingLexicon.terminalPunctuation

  /// What [text] says about whether the speaker has finished.
  ///
  /// [alsoUnfinished] is the user's own way of trailing off, from the agent
  /// profile. The built-in list is a guess at how people pause mid-thought;
  /// a filler nobody else uses is exactly what decides whether being cut off
  /// mid-sentence ever stops happening, and it cannot be guessed from here.
  static func of(
    _ text: String,
    alsoUnfinished: [String] = []
  ) -> TurnCompletion {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.last else { return .unknown }
    let bare = trimmed.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
    )
    guard !bare.isEmpty else { return .unknown }
    if isContinuing(bare, alsoUnfinished: alsoUnfinished) { return .continuing }
    guard syllables(bare) >= syllablesToBeFinished else { return .unknown }
    if terminalPunctuation.contains(last) { return .settled }
    if settledSuffixes.contains(where: { bare.hasSuffix($0) }) { return .settled }
    return .unknown
  }

  /// How much longer than [endpointSilence] this text has to stay quiet.
  static func requiredSilence(
    after text: String,
    endpointSilence: TimeInterval,
    alsoUnfinished: [String] = []
  ) -> TimeInterval {
    switch of(text, alsoUnfinished: alsoUnfinished) {
    case .continuing: return endpointSilence + continuingGrace
    case .settled: return max(0, endpointSilence - settledSaving)
    case .unknown: return endpointSilence
    }
  }

  private static func isContinuing(
    _ bare: String,
    alsoUnfinished: [String]
  ) -> Bool {
    if continuingSuffixes.contains(where: { bare.hasSuffix($0) }) { return true }
    // An empty entry is a suffix of every string, which would hold every
    // turn open for an extra 0.6s and read exactly like the model being slow.
    for entry in alsoUnfinished {
      let written = entry.trimmingCharacters(in: .whitespacesAndNewlines)
      if !written.isEmpty, bare.hasSuffix(written) { return true }
    }
    let lastWord = bare.lowercased().split(separator: " ").last.map(String.init)
    return lastWord.map(continuingWords.contains) ?? false
  }

  /// Roughly how much speech [text] is.
  ///
  /// A CJK character is one syllable; a run of Latin letters or digits is
  /// one however long it is. Counting characters instead makes "the" three
  /// times the utterance that 「嗎」 is, which is backwards.
  static func syllables(_ text: String) -> Int {
    var count = 0
    var inLatinRun = false
    let skipped = CharacterSet.whitespacesAndNewlines
      .union(.punctuationCharacters)
      .union(.symbols)
    for character in text {
      guard let scalar = character.unicodeScalars.first else { continue }
      // The comma the recogniser writes between clauses is not speech, and
      // counting it made a two-syllable scrap look long enough to shorten on.
      if skipped.contains(scalar) {
        inLatinRun = false
        continue
      }
      let isLatin =
        CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
      if isLatin {
        if !inLatinRun {
          count += 1
          inLatinRun = true
        }
      } else {
        inLatinRun = false
        count += 1
      }
    }
    return count
  }
}

/// Whose turn it is, and when the clocks the endpointer trusts were last
/// true.
///
/// This is the most intricate state in the voice pipeline and the one whose
/// failures look least like themselves: getting it wrong presents as "the
/// transcriber is bad", never as "the bookkeeping is wrong". It lives here,
/// apart from the adapter, so it can be reached without an audio device and
/// therefore tested — the adapter keeps the effects (the mute, the events,
/// the sleeping), and this keeps the decisions.
///
/// Every clock is in seconds on any steady monotonic source; the caller
/// supplies it, so a test can run a conversation in a microsecond.
struct SpeechTurn {
  /// Creates the bookkeeping, optionally knowing the user's own fillers.
  init(unfinishedEndings: [String] = []) {
    self.unfinishedEndings = unfinishedEndings
  }

  /// The user's own ways of leaving a sentence unfinished, from the agent
  /// profile. Replaced wholesale whenever Dart sends a new list.
  var unfinishedEndings: [String]

  /// A volatile transcript is on screen and unsettled.
  private(set) var utteranceInProgress = false

  /// Latest volatile words, kept only until this utterance settles.
  ///
  /// A few conversational prefixes are complete-looking commands on their
  /// own but commonly introduce a correction after a long pause. The user's
  /// Taiwan Mandarin corpus contains both "等一下……還沒" and
  /// "我想問的是……如果"; the ordinary 800ms endpoint split both in half.
  private(set) var volatileText = ""

  /// When the current utterance's first volatile arrived.
  ///
  /// The VAD's clock freezes while the microphone is muted, so right after
  /// an answer its "last voice" is minutes stale. A silence is only
  /// trustworthy measured against voice heard for THIS utterance.
  private(set) var heardAt: TimeInterval = .infinity

  /// When the microphone last reopened after the agent spoke. Anything the
  /// VAD heard before this is the pre-answer past — the mute was unmeasured
  /// dead time, and a silence spanning it is not one anybody observed.
  private(set) var muteLiftedAt: TimeInterval = -.infinity

  /// The endpointer has already asked for this utterance; asked once.
  private(set) var finalizeRequested = false

  /// When it asked, so an ask that is never answered can be repeated.
  private(set) var finalizeAskedAt: TimeInterval = .infinity

  /// How long an unanswered finalize is waited out before asking again.
  ///
  /// The analyzer accepting a finalize and then emitting nothing at all —
  /// no final, not even an empty result — leaves nothing to clear the
  /// latch, and the fast endpointer stays off for the rest of the session
  /// while every turn quietly falls back to the Dart settle. The symptom
  /// is "everything got about 1.5 seconds slower at some point", with no
  /// event anywhere saying so. Asking again costs one redundant finalize
  /// on a stream that has already settled, which is harmless; not asking
  /// costs the rest of the session.
  static let reaskUnansweredFinalize: TimeInterval = 3

  /// Sentences in flight to the sidecar.
  ///
  /// The mute and the speaking events belong to the whole answer: the first
  /// sentence mutes and only the last one back unmutes, or sentence one's
  /// return reopens the microphone while two onward are still playing.
  private(set) var outstanding = 0

  /// Bumped whenever the speaking state moves; a pending unmute that no
  /// longer matches has been superseded and must not fire.
  private(set) var unmuteGeneration = 0

  /// Whether a start has been reported without its finish yet. The unmute
  /// hangover can bridge two utterances, and the pair must not double-report.
  private(set) var speakingReported = false

  /// When a sentence last began or finished, so a wedged one can be seen.
  private(set) var lastProgressAt: TimeInterval = .infinity

  /// The longest the microphone may stay shut with no sentence starting or
  /// finishing before it is forced open.
  ///
  /// /speak is answered only once the sidecar has played the sentence
  /// through, and waits 120 seconds for that. If the model wedges inside
  /// the render, the request never returns, outstanding never reaches zero,
  /// and the mute never lifts: every buffer is dropped before the VAD sees
  /// it, checkEndpoint returns immediately, and the agent is completely
  /// deaf — while the button still shows a live microphone, because
  /// nothing in the audio path failed. Every other way the mute can stick
  /// has an escape; this one had none but the user noticing.
  ///
  /// Generous on purpose: it measures a sentence making no progress, not an
  /// answer taking its time. Ten seconds of speech for fifty characters is
  /// ordinary, and a long answer is many sentences, each one refreshing it.
  static let muteCeiling: TimeInterval = 45

  /// What the caller must do now that a sentence has begun.
  struct Began {
    /// This is the first sentence of an answer: shut the microphone.
    let shouldMute: Bool

    /// Nothing has announced this answer yet.
    let shouldReportStart: Bool
  }

  /// A volatile transcript arrived with words in it.
  mutating func heardVolatile(at now: TimeInterval) {
    heardVolatile(text: "", at: now)
  }

  /// A volatile transcript arrived with its current local text.
  mutating func heardVolatile(text: String, at now: TimeInterval) {
    if !utteranceInProgress {
      heardAt = now
    }
    utteranceInProgress = true
    volatileText = text
  }

  /// A result settled the utterance, final or empty.
  ///
  /// Runs for empty results too: a finalize that produced nothing must still
  /// clear the request, or the fast path stays latched off for the session.
  mutating func settled() {
    utteranceInProgress = false
    volatileText = ""
    finalizeRequested = false
    finalizeAskedAt = .infinity
  }

  /// The endpointer has asked the transcriber to finalize.
  mutating func askedToFinalize(at now: TimeInterval) {
    finalizeRequested = true
    finalizeAskedAt = now
  }

  /// Whether the room has been quiet long enough, for long enough, and
  /// against voice recent enough to belong to this utterance.
  ///
  /// Recognition trails the voice it heard, so the first volatile may arrive
  /// after the room already went quiet; [margin] covers that lag.
  func shouldFinalize(
    silence: TimeInterval,
    lastVoiceAt: TimeInterval,
    endpointSilence: TimeInterval,
    now: TimeInterval,
    margin: TimeInterval = 1.5
  ) -> Bool {
    guard utteranceInProgress else { return false }
    if finalizeRequested {
      guard now - finalizeAskedAt >= Self.reaskUnansweredFinalize else {
        return false
      }
    }
    let requiredSilence = TurnCompletion.requiredSilence(
      after: volatileText,
      endpointSilence: endpointSilence,
      alsoUnfinished: unfinishedEndings
    )
    guard silence.isFinite, silence > requiredSilence else { return false }
    return lastVoiceAt >= max(heardAt - margin, muteLiftedAt)
  }

  /// One sentence of an answer has been handed to the sidecar.
  mutating func began(at now: TimeInterval) -> Began {
    lastProgressAt = now
    outstanding += 1
    unmuteGeneration += 1
    let first = outstanding == 1
    let report = first && !speakingReported
    if report {
      speakingReported = true
    }
    return Began(shouldMute: first, shouldReportStart: report)
  }

  /// One sentence has been heard to its end, or barged over.
  ///
  /// Returns the generation a delayed unmute must present to
  /// [liftMute(generation:)], or nil while sentences are still in flight.
  mutating func ended(at now: TimeInterval) -> Int? {
    lastProgressAt = now
    // Nothing of ours is in flight, so this sentence belongs to a session
    // that has already been stopped and reset — /speak waits up to two
    // minutes, long enough for the user to have turned the microphone off,
    // back on, and started a new sentence. Clamping to zero and continuing
    // would hand it an unmute for a mute it never took, and reset the
    // clocks under whatever is being said now.
    guard outstanding > 0 else { return nil }
    outstanding -= 1
    guard outstanding == 0 else { return nil }
    unmuteGeneration += 1
    return unmuteGeneration
  }

  /// Whether the microphone has been shut too long with nothing moving.
  func muteOverdue(now: TimeInterval) -> Bool {
    guard outstanding > 0 else { return false }
    return now - lastProgressAt > Self.muteCeiling
  }

  /// Give up on whatever is still in flight and open the microphone.
  mutating func abandonSpeech() {
    outstanding = 0
    unmuteGeneration += 1
    speakingReported = false
    lastProgressAt = .infinity
  }

  /// Whether a delayed unmute still speaks for the current state.
  ///
  /// The speaker's tail is still in the air when the sidecar returns, so the
  /// microphone stays shut a beat longer; anything that happened during that
  /// beat supersedes this.
  mutating func liftMute(generation: Int) -> Bool {
    guard generation == unmuteGeneration, outstanding == 0 else {
      return false
    }
    speakingReported = false
    return true
  }

  /// The answer is over and the microphone is open again: the endpointer
  /// starts the next turn clean and trusts nothing heard before now.
  mutating func microphoneReopened(at now: TimeInterval) {
    muteLiftedAt = now
    utteranceInProgress = false
    volatileText = ""
    heardAt = .infinity
    finalizeRequested = false
    finalizeAskedAt = .infinity
  }

  /// A session ended: forget the utterance, keep nothing to steer the next.
  mutating func sessionEnded() {
    utteranceInProgress = false
    volatileText = ""
    heardAt = .infinity
    finalizeRequested = false
    finalizeAskedAt = .infinity
  }

  /// Listening stopped outright. Speech state resets too, or a sentence
  /// whose terminal callback never came leaves the microphone shut.
  mutating func listeningStopped() {
    unmuteGeneration += 1
    outstanding = 0
    speakingReported = false
    sessionEnded()
  }
}

/// When the room last sounded like somebody talking, over an adaptive
/// noise floor.
///
/// The audio tap reports every buffer's RMS; the floor is the quietest
/// second in the last ten (minimum statistics). Speech always has dips —
/// breaths, inter-word gaps — that hold its floor low, however long the
/// monologue; a fan never dips, so its own level becomes the floor within
/// the window and it stops reading as a voice. Read and written across
/// the audio thread and the main actor.
final class VoiceActivityBox: @unchecked Sendable {
  private let lock = NSLock()
  private var lastVoice: TimeInterval = -.infinity

  /// When the burst of speech being heard right now began.
  ///
  /// The one turn-taking signal that needs no words: a backchannel is short
  /// in every language studied and a request to take the floor is not, so
  /// this is what stops 「うんうん」 or 「네네」 from ending an answer in a
  /// language whose acknowledgements nobody has listed. It is also earlier
  /// than the transcript, which has to be recognised first.
  private var speechStartedAt: TimeInterval = -.infinity

  /// How much silence ends a burst rather than falling inside one.
  ///
  /// Deliberately far below the endpointer's 0.8s: this measures one run of
  /// voice, not one turn. Ordinary inter-word gaps in read Mandarin sit
  /// around 0.26s (see docs/decisions/voice-turn-latency.md), so 0.35s keeps
  /// a sentence together while a real stop still starts a new burst.
  private static let burstGap: TimeInterval = 0.35

  /// Per-second minima, newest last; the floor is the smallest of these.
  private var minima: [Float] = []
  private var windowMin: Float = .greatestFiniteMagnitude
  private var windowStart: TimeInterval = -.infinity

  private static let windowSeconds = 10

  /// A voice must rise this far above the floor, and above an absolute
  /// quiet-room minimum, before it counts.
  ///
  /// The ratio is a cliff at 20·log10(3) ≈ 9.5dB: speech whose quietest
  /// 85ms in every recent second sits within 9.5dB of its syllables — in
  /// practice, speech over a loud steady background — goes undetected,
  /// and the endpointer declines in favor of the slower Dart settle.
  private static let floorRatio: Float = 3
  private static let minimumVoice: Float = 0.004

  /// Records one buffer's loudness at [now], in seconds on any steady
  /// clock.
  func observe(rms: Float, at now: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    if now - windowStart >= 1 {
      if windowMin < .greatestFiniteMagnitude {
        minima.append(windowMin)
        if minima.count > Self.windowSeconds {
          minima.removeFirst()
        }
      }
      windowMin = .greatestFiniteMagnitude
      windowStart = now
    }
    windowMin = min(windowMin, rms)
    if rms > max(Self.minimumVoice, currentFloor * Self.floorRatio) {
      if now - lastVoice > Self.burstGap {
        speechStartedAt = now
      }
      lastVoice = now
    }
    if rms > peak {
      peak = rms
    }
  }

  private var currentFloor: Float {
    min(minima.min() ?? windowMin, windowMin)
  }

  /// Seconds since a voice was last heard; infinite before the first one.
  func silence(asOf now: TimeInterval) -> TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return now - lastVoice
  }

  /// How long the current burst of speech has run, or zero before the
  /// first one.
  ///
  /// Measured to the last voice rather than to now, so it is the length of
  /// speech actually heard and not speech plus the pause after it.
  func speechRun() -> TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    guard lastVoice.isFinite, speechStartedAt.isFinite else { return 0 }
    return max(0, lastVoice - speechStartedAt)
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
    let floor = currentFloor
    return (floor == .greatestFiniteMagnitude ? 0 : floor, seen)
  }

  private var peak: Float = 0
}

/// A boolean the audio thread may read while the main actor writes.
/// The speaking epoch, readable off the main actor.
///
/// The render loop runs away from the main actor so it cannot starve the
/// audio it is feeding, which means it cannot read `speakEpoch` directly.
/// stopSpeaking writes here too, and a barge-in is seen within one buffer.
final class EpochBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  var epoch: Int {
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

/// Resumes a continuation exactly once, from any thread.
///
/// The playback callback, the barge-in poll and the deadline all race to end
/// the same wait; resuming a continuation twice is a crash, never resuming it
/// is the leak this exists to close.
private final class ResumeOnce: @unchecked Sendable {
  init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func resume() {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume()
  }
}

/// Held speech on its way to the batch recogniser.
///
/// Lifted out of `VoiceHostAdapter` because none of it needs that class or
/// the macOS 26 it is gated on: one writes a WAV, one deletes old ones, and
/// one posts a path to a sidecar over loopback. Dictation needs all three
/// and must not carry a version requirement it has no use for.
enum HeldSpeech {
  /// Deletes held-speech WAVs older than an hour.
  ///
  /// These are recordings of somebody's voice. They were written to be
  /// re-listened to while recognisers were being compared, and nothing ever
  /// removed them, so they accumulated for as long as the machine ran. An
  /// hour is long enough to still have the clip that just went wrong.
  static func sweepHeldClips() {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory
    guard
      let entries = try? manager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey]
      )
    else {
      return
    }
    let cutoff = Date().addingTimeInterval(-3600)
    for entry in entries where entry.lastPathComponent.hasPrefix("lulo-held-") {
      let modified = try? entry.resourceValues(
        forKeys: [.contentModificationDateKey]
      ).contentModificationDate
      if let modified, modified < cutoff {
        try? manager.removeItem(at: entry)
      }
    }
  }

  /// Writes one held utterance to a WAV beside the logs — the same audio
  /// Apple heard, kept so recognisers can be judged on real utterances.
  static func writeHeldClip(_ clip: HeldSpeechClip) async -> URL? {
    await Task.detached(priority: .userInitiated) { () -> URL? in
      // Off the main thread, alongside the write that needs it anyway.
      HeldSpeech.sweepHeldClips()
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          String(format: "lulo-held-%.0f.wav", Date().timeIntervalSince1970)
        )
      guard
        let format = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: clip.sampleRate,
          channels: 1,
          interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(
          pcmFormat: format,
          frameCapacity: AVAudioFrameCount(clip.samples.count)
        )
      else {
        return nil
      }
      clip.samples.withUnsafeBufferPointer { raw in
        buffer.floatChannelData![0].update(
          from: raw.baseAddress!,
          count: clip.samples.count
        )
      }
      buffer.frameLength = AVAudioFrameCount(clip.samples.count)
      do {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        NSLog(
          "Lulo ptt: captured %.1fs -> %@",
          Double(clip.samples.count) / clip.sampleRate,
          url.path
        )
        return url
      } catch {
        NSLog("Lulo ptt: clip not written (%@)", String(describing: error))
        return nil
      }
    }.value
  }

  /// What the batch recogniser heard in [url], or empty when it could not
  /// answer.
  /// The batch recogniser's answer, or nil when it could not be reached.
  ///
  /// Nil and empty are different answers, even though this caller treats
  /// them alike: the streamed transcript stands either way. They are kept
  /// apart because "the recogniser is not running" and "the recogniser
  /// heard nothing" are different things to tell anyone who asks, and
  /// collapsing them at the boundary loses that for good.
  static func transcribeHeld(
    _ url: URL,
    terms: [String],
    timeout: TimeInterval = 15
  ) async -> String? {
    guard let endpoint = URL(string: "http://127.0.0.1:46558/transcribe")
    else {
      return nil
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["path": url.path, "terms": terms]
    )
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200,
        let payload = try? JSONSerialization.jsonObject(with: data)
          as? [String: Any],
        payload["ok"] as? Bool == true,
        let text = payload["text"] as? String
      else {
        return nil
      }
      NSLog("Lulo ptt: batch recogniser heard %d chars", text.count)
      return text
    } catch {
      NSLog(
        "Lulo ptt: batch recogniser unreachable (%@)",
        String(describing: error)
      )
      return nil
    }
  }
}
