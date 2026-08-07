import Darwin
import Foundation
import LiteRTLM

public enum LiteRTLMRuntimeComputeBackend: Equatable, Sendable {
  case gpu
  case cpu(threadCount: Int?)
}

public struct LiteRTLMRuntimeConfiguration: Equatable, Sendable {
  public init(
    primaryBackend: LiteRTLMRuntimeComputeBackend = Self.defaultBackend,
    enableCPUFallback: Bool = true,
    cpuFallbackThreadCount: Int? = max(
      1,
      ProcessInfo.processInfo.activeProcessorCount - 1
    ),
    cacheDirectory: String = Self.defaultCacheDirectory,
    topK: Int = 40
  ) {
    self.primaryBackend = primaryBackend
    self.enableCPUFallback = enableCPUFallback
    self.cpuFallbackThreadCount = cpuFallbackThreadCount
    self.cacheDirectory = cacheDirectory
    self.topK = topK
  }

  public let primaryBackend: LiteRTLMRuntimeComputeBackend
  public let enableCPUFallback: Bool
  public let cpuFallbackThreadCount: Int?
  public let cacheDirectory: String
  public let topK: Int

  public static var defaultBackend: LiteRTLMRuntimeComputeBackend {
    #if arch(arm64)
      .gpu
    #else
      .cpu(threadCount: nil)
    #endif
  }

  public static var defaultCacheDirectory: String {
    let root = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    return root
      .appendingPathComponent("FlutterLocalAgent", isDirectory: true)
      .appendingPathComponent("LiteRTLM", isDirectory: true)
      .path
  }
}

public actor RuntimeGenerationEventRelay {
  public typealias Receiver =
    @Sendable (RuntimeGenerationEvent) async -> Void

  public init() {}

  private var receiver: Receiver?
  private var bufferedEvents: [RuntimeGenerationEvent] = []

  public func attach(_ receiver: @escaping Receiver) async {
    self.receiver = receiver
    let events = bufferedEvents
    bufferedEvents.removeAll()
    for event in events {
      await receiver(event)
    }
  }

  func emit(_ event: RuntimeGenerationEvent) async {
    guard let receiver else {
      bufferedEvents.append(event)
      return
    }
    await receiver(event)
  }
}

enum LiteRTLMDriverBackend: Equatable, Sendable {
  case gpu
  case cpu(threadCount: Int?)
}

struct LiteRTLMDriverLoadRequest: Equatable, Sendable {
  let modelPath: String
  let backend: LiteRTLMDriverBackend
  let maxNumTokens: Int
  let cacheDirectory: String
}

struct LiteRTLMSamplerFingerprint: Equatable, Sendable {
  let topK: Int
  let topP: Double
  let temperature: Double
  let seed: Int
}

struct LiteRTLMDriverGenerationRequest: Equatable, Sendable {
  let sessionId: String
  let systemInstruction: String
  let prompt: String
  let history: [RuntimeConversationTurn]
  let extraContext: [String: [String]]
  let sampler: LiteRTLMSamplerFingerprint
  let maxOutputTokens: Int
  /// The window the model was loaded with.
  ///
  /// Carried because the driver is the only place that holds live
  /// conversations, so it is the only place that can notice one outgrowing
  /// the window — and it cannot notice without knowing how big the window
  /// is. The backend knows, from the model it loaded.
  let contextSize: Int64
}

protocol LiteRTLMRuntimeDriving: Sendable {
  func load(_ request: LiteRTLMDriverLoadRequest) async throws

  func generate(
    _ request: LiteRTLMDriverGenerationRequest,
    onChunk: @escaping @Sendable (String) async -> Void
  ) async throws

  func cancel(sessionId: String) async throws

  func resetSession(sessionId: String) async throws

  func unload() async
}

protocol LiteRTLMRuntimeDriverFactory: Sendable {
  func makeDriver() -> any LiteRTLMRuntimeDriving
}

struct SystemLiteRTLMRuntimeDriverFactory:
  LiteRTLMRuntimeDriverFactory
{
  func makeDriver() -> any LiteRTLMRuntimeDriving {
    SystemLiteRTLMRuntimeDriver()
  }
}

actor SystemLiteRTLMRuntimeDriver: LiteRTLMRuntimeDriving {
  private var engine: Engine?
  private var conversations: [String: Conversation] = [:]
  /// The system message each live conversation was built with, so a profile
  /// the user has since edited can be noticed rather than silently ignored.
  private var systemInstructions: [String: String] = [:]

  /// The sampler each live conversation was constructed with.
  ///
  /// Distinct from `sessionSamplers`, which records what the session has most
  /// recently been *asked* for: the two differ exactly when the user has
  /// changed the answer style and the conversation has not been rebuilt yet.
  private var conversationSamplers: [String: LiteRTLMSamplerFingerprint] = [:]

  func load(_ request: LiteRTLMDriverLoadRequest) async throws {
    try FileManager.default.createDirectory(
      atPath: request.cacheDirectory,
      withIntermediateDirectories: true
    )
    let backend: Backend = switch request.backend {
    case .gpu:
      .gpu
    case .cpu(let threadCount):
      .cpu(threadCount: threadCount)
    }
    let config = try EngineConfig(
      modelPath: request.modelPath,
      backend: backend,
      maxNumTokens: request.maxNumTokens,
      cacheDir: request.cacheDirectory
    )
    let engine = Engine(engineConfig: config)
    try await engine.initialize()
    self.engine = engine
    conversations.removeAll()
    systemInstructions.removeAll()
    conversationSamplers.removeAll()
  }

  func generate(
    _ request: LiteRTLMDriverGenerationRequest,
    onChunk: @escaping @Sendable (String) async -> Void
  ) async throws {
    guard let engine else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    try Task.checkCancellation()
    let conversation: Conversation
    // A profile the user has edited is a different system message, and an
    // answer style they have changed is a different sampler. Neither can be
    // amended inside a prefilled KV cache — the sampler is fixed in
    // ConversationConfig and `sendMessageStream` has no argument for it — so
    // rebuilding the conversation is the only honest answer to either. It
    // costs one prefill of the history, which is what every turn used to
    // cost anyway, and never a model load.
    let staleInstruction =
      systemInstructions[request.sessionId] != nil
      && systemInstructions[request.sessionId] != request.systemInstruction
    let staleSampler =
      conversationSamplers[request.sessionId] != nil
      && conversationSamplers[request.sessionId] != request.sampler
    // A conversation that has run out of window is rebuilt for the same
    // reason an edited profile rebuilds one: a KV cache cannot be amended,
    // and there is no way to drop a prefix of it. The rebuild seeds from the
    // history, which `historyFitting` has already trimmed to fit — so it
    // sheds the accumulated clocks and document passages and keeps what the
    // conversation was about. `getTokenCount` reads the cache itself, which
    // is exact where the seeding path can only estimate; a runtime that
    // refuses to answer leaves the conversation alone rather than throwing
    // it away on every turn.
    let outgrewWindow =
      conversations[request.sessionId].map { conversation in
        guard let held = try? conversation.getTokenCount() else {
          return false
        }
        return !LiteRTLMRuntimeBackend.liveConversationHasRoomForTurn(
          heldTokens: held,
          prompt: request.prompt,
          maxOutputTokens: request.maxOutputTokens,
          contextSize: request.contextSize
        )
      } ?? false
    let stale = staleInstruction || staleSampler || outgrewWindow
    if let existing = conversations[request.sessionId], !stale {
      conversation = existing
    } else {
      if stale {
        try? conversations.removeValue(forKey: request.sessionId)?.cancel()
      }
      let sampler = try SamplerConfig(
        topK: request.sampler.topK,
        topP: Float(request.sampler.topP),
        temperature: Float(request.sampler.temperature),
        seed: request.sampler.seed
      )
      // A conversation the runtime has never held starts empty even when
      // the window above it is full of turns read back from storage. The
      // history seeds it; a session already in `conversations` is its own
      // memory and is left alone.
      conversation = try await engine.createConversation(
        with: ConversationConfig(
          systemMessage: request.systemInstruction.isEmpty
            ? nil
            : Message(request.systemInstruction),
          initialMessages: request.history.map {
            Message($0.text, role: $0.role == .user ? .user : .model)
          },
          samplerConfig: sampler
        )
      )
      conversations[request.sessionId] = conversation
      systemInstructions[request.sessionId] = request.systemInstruction
      // What this conversation was actually built with, so the next turn can
      // tell whether it still matches what the user has chosen.
      conversationSamplers[request.sessionId] = request.sampler
    }
    try Task.checkCancellation()
    let context: [String: Any] = request.extraContext
    for try await message in conversation.sendMessageStream(
      Message(request.prompt),
      extraContext: context,
      maxOutputTokens: request.maxOutputTokens
    ) {
      try Task.checkCancellation()
      await onChunk(message.toString)
    }
  }

  func cancel(sessionId: String) async throws {
    try conversations[sessionId]?.cancel()
  }

  func resetSession(sessionId: String) async throws {
    systemInstructions.removeValue(forKey: sessionId)
    conversationSamplers.removeValue(forKey: sessionId)
    if let conversation = conversations.removeValue(forKey: sessionId) {
      try conversation.cancel()
    }
  }

  func unload() async {
    for conversation in conversations.values {
      try? conversation.cancel()
    }
    conversations.removeAll()
    systemInstructions.removeAll()
    conversationSamplers.removeAll()
    engine = nil
  }
}

public actor LiteRTLMRuntimeBackend: RuntimeBackend {
  public init(
    configuration: LiteRTLMRuntimeConfiguration =
      LiteRTLMRuntimeConfiguration(),
    eventRelay: RuntimeGenerationEventRelay
  ) {
    self.init(
      configuration: configuration,
      eventRelay: eventRelay,
      driverFactory: SystemLiteRTLMRuntimeDriverFactory()
    )
  }

  init(
    configuration: LiteRTLMRuntimeConfiguration,
    eventRelay: RuntimeGenerationEventRelay,
    driverFactory: any LiteRTLMRuntimeDriverFactory
  ) {
    self.configuration = configuration
    self.eventRelay = eventRelay
    self.driverFactory = driverFactory
  }

  public let capabilities = RuntimeCapabilities(
    runtimeName: "litert-lm",
    supportsStreaming: true,
    supportsCancellation: true
  )

  private struct ActiveGeneration {
    let generationId: String
    let sessionId: String
    let token: UInt64
    var nextSequence: Int64
    var task: Task<Void, Never>?

    // The account that names a silent truncation. An answer that stops
    // mid-sentence "completes" like any other; only these numbers can say
    // whether it ran out of output budget, was crowded out by its own
    // history, or simply chose to stop.
    let promptCharacters: Int
    let historyCharacters: Int
    let historyTurns: Int
    let maxOutputTokens: Int
    var outputCharacters: Int = 0
  }

  /// Generations cancelled before their start ever claimed the engine —
  /// each one a start asleep in the drain wait whose caller has already
  /// let it go. Consumed by the start when it wakes; bounded because ids
  /// are never reused.
  private var cancelledBeforeStart: [String] = []

  private let configuration: LiteRTLMRuntimeConfiguration
  private let eventRelay: RuntimeGenerationEventRelay
  private let driverFactory: any LiteRTLMRuntimeDriverFactory
  private var driver: (any LiteRTLMRuntimeDriving)?
  private var loadedModel: RuntimeModelRequest?
  private var sessionSamplers: [String: LiteRTLMSamplerFingerprint] = [:]
  private var activeGeneration: ActiveGeneration?
  /// The decode of a cancelled generation, which still owns the engine.
  private var drainingGeneration: Task<Void, Never>?
  /// Identifies that decode so its own completion is what clears the wait.
  private var drainingToken: UInt64?
  /// How long a new generation waits for an abandoned decode to finish.
  private let drainTimeoutSeconds: TimeInterval = 120
  private var nextGenerationToken: UInt64 = 0

  public func loadModel(
    _ model: RuntimeModelRequest
  ) async throws -> RuntimeModelLoadResult {
    if let loadedModel {
      guard loadedModel == model else {
        throw RuntimeBoundaryError.modelLoadFailed
      }
      return RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    }
    let contextSize = try validateModel(model)
    let primaryRequest = LiteRTLMDriverLoadRequest(
      modelPath: model.modelPath,
      backend: try driverBackend(for: configuration.primaryBackend),
      maxNumTokens: contextSize,
      cacheDirectory: configuration.cacheDirectory
    )
    do {
      let primaryDriver = driverFactory.makeDriver()
      try await primaryDriver.load(primaryRequest)
      driver = primaryDriver
    } catch {
      guard
        configuration.enableCPUFallback,
        case .gpu = configuration.primaryBackend
      else {
        throw RuntimeBoundaryError.modelLoadFailed
      }
      do {
        let fallbackDriver = driverFactory.makeDriver()
        try await fallbackDriver.load(
          LiteRTLMDriverLoadRequest(
            modelPath: model.modelPath,
            backend: try driverBackend(
              for: .cpu(
                threadCount: configuration.cpuFallbackThreadCount
              )
            ),
            maxNumTokens: contextSize,
            cacheDirectory: configuration.cacheDirectory
          )
        )
        driver = fallbackDriver
      } catch {
        throw RuntimeBoundaryError.modelLoadFailed
      }
    }
    loadedModel = model
    sessionSamplers.removeAll()
    return RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
  }

  public func startGeneration(
    _ generation: RuntimeGenerationRequest
  ) async throws -> RuntimeGenerationAcknowledgement {
    guard activeGeneration == nil else {
      // Which guard refused, and what was still holding the slot. A rejection
      // here reaches the user as a bare "Response failed" with no text and no
      // reason, seconds after they interrupted something.
      NSLog(
        "Lulo runtime: start refused, generation %@ still active",
        activeGeneration?.generationId ?? "?"
      )
      throw RuntimeBoundaryError.generationBusy
    }
    // A cancelled generation is abandoned rather than stopped, so its decode
    // may still own the engine. Wait for it before touching the runtime again;
    // overlapping the two would block inside LiteRT with no way back out.
    //
    // The wait is bounded. An unbounded one would turn any runtime stall into
    // a permanently unresponsive app, and reporting the runtime as unavailable
    // is far better than a request that never returns.
    if drainingGeneration != nil {
      let deadline = Date().addingTimeInterval(drainTimeoutSeconds)
      while drainingGeneration != nil, Date() < deadline {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
      guard drainingGeneration == nil else {
        NSLog(
          "Lulo runtime: start refused, abandoned decode still draining after %.0fs",
          drainTimeoutSeconds
        )
        throw RuntimeBoundaryError.runtimeUnavailable
      }
      // Woken, not chosen: every waiter sleeps in this same loop, and the
      // first to wake claims the engine. The rest must see that claim and
      // refuse — proceeding would put two decodes on one engine, the
      // exact overlap this wait exists to prevent.
      guard activeGeneration == nil else {
        NSLog(
          "Lulo runtime: start refused, generation %@ claimed the engine first",
          activeGeneration?.generationId ?? "?"
        )
        throw RuntimeBoundaryError.generationBusy
      }
    }
    // Cancelled while it waited: the caller already let this generation
    // go, and claiming the engine now would burn a whole budget on a
    // decode nobody wants.
    if let fenced = cancelledBeforeStart.firstIndex(
      of: generation.generationId
    ) {
      cancelledBeforeStart.remove(at: fenced)
      NSLog(
        "Lulo runtime: start aborted, generation %@ was cancelled before it began",
        generation.generationId
      )
      throw RuntimeBoundaryError.cancelled
    }
    guard let loadedModel, let driver else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    let request = try validateGeneration(
      generation,
      contextSize: loadedModel.contextSize
    )
    // A sampler the user changed is not an error. LiteRT-LM takes the sampler
    // once, in ConversationConfig — `sendMessageStream` has no argument for
    // it — so a session that has already answered cannot simply be handed a
    // new one. Refusing was safe while the app sent the same three numbers
    // forever; it stopped being safe the moment the answer style became a
    // setting, because refusing fails the turn the user just asked and every
    // turn after it in that conversation.
    //
    // So it is recorded here and acted on where the conversation is built,
    // which rebuilds and re-seeds from history — one prefill, not a model
    // load. The same trade the system instruction already makes.
    sessionSamplers[generation.sessionId] = request.sampler

    let token = nextGenerationToken
    nextGenerationToken &+= 1
    activeGeneration = ActiveGeneration(
      generationId: generation.generationId,
      sessionId: generation.sessionId,
      token: token,
      nextSequence: 0,
      task: nil,
      promptCharacters: request.prompt.count,
      historyCharacters: request.history.reduce(0) { $0 + $1.text.count },
      historyTurns: request.history.count,
      maxOutputTokens: request.maxOutputTokens
    )
    let task = Task { [weak self] in
      guard let self else {
        return
      }
      await self.runGeneration(
        request,
        generationId: generation.generationId,
        token: token,
        driver: driver
      )
    }
    activeGeneration?.task = task
    return RuntimeGenerationAcknowledgement(
      generationId: generation.generationId,
      accepted: true
    )
  }

  public func cancelGeneration(
    generationId: String
  ) async throws -> RuntimeCancellationAcknowledgement {
    guard
      var active = activeGeneration,
      active.generationId == generationId
    else {
      // Nothing running by this name — but its start may be asleep in the
      // drain wait, about to claim the engine for a generation the caller
      // has already let go. The fence makes that start abort when it
      // wakes instead of becoming a zombie decode.
      cancelledBeforeStart.append(generationId)
      if cancelledBeforeStart.count > 32 {
        cancelledBeforeStart.removeFirst()
      }
      return RuntimeCancellationAcknowledgement(
        generationId: generationId,
        acknowledged: false
      )
    }
    // Clearing the active generation first fences any chunk the driver is
    // still producing, so nothing can follow the terminal emitted below.
    activeGeneration = nil
    // The decode is abandoned, not stopped. LiteRT-LM v0.14.0's CancelProcess
    // does not end the running task: it leaves one active task in the
    // callback thread pool permanently, which wedges the engine so completely
    // that a later generation only ever reports started, and even unloadModel
    // blocks. Measured against the real Gemma artifact, the engine never
    // recovered across four minutes. Cancelling the Swift task cannot help
    // either, because the loop is suspended awaiting a stream that stops
    // yielding. So the decode is left to finish on its own token budget while
    // its output is discarded, and the next generation waits for it.
    drainingGeneration = active.task
    drainingToken = active.token
    // A cancelled generation must still reach a terminal event. The
    // coordinator only releases its single generation slot when it observes
    // one, so skipping this would leave every later generation rejected as
    // busy for the lifetime of the process.
    active.nextSequence += 1
    await eventRelay.emit(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: active.nextSequence,
        kind: .cancelled
      )
    )
    return RuntimeCancellationAcknowledgement(
      generationId: generationId,
      acknowledged: true
    )
  }

  public func resetSession(
    sessionId: String
  ) async throws -> RuntimeOperationCompletion {
    guard let driver else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    if let active = activeGeneration, active.sessionId == sessionId {
      activeGeneration = nil
      active.task?.cancel()
      do {
        try await driver.cancel(sessionId: sessionId)
      } catch {
        throw RuntimeBoundaryError.generationFailed
      }
    }
    do {
      try await driver.resetSession(sessionId: sessionId)
    } catch {
      throw RuntimeBoundaryError.generationFailed
    }
    sessionSamplers.removeValue(forKey: sessionId)
    return RuntimeOperationCompletion(completed: true)
  }

  public func unloadModel() async throws -> RuntimeOperationCompletion {
    guard let driver else {
      return RuntimeOperationCompletion(completed: true)
    }
    if let active = activeGeneration {
      activeGeneration = nil
      active.task?.cancel()
      try? await driver.cancel(sessionId: active.sessionId)
    }
    // A pending drain refers to an engine that is about to be torn down, so it
    // must not keep blocking the generation that follows a reload.
    drainingGeneration = nil
    drainingToken = nil
    await driver.unload()
    self.driver = nil
    loadedModel = nil
    sessionSamplers.removeAll()
    return RuntimeOperationCompletion(completed: true)
  }

  private func runGeneration(
    _ request: LiteRTLMDriverGenerationRequest,
    generationId: String,
    token: UInt64,
    driver: any LiteRTLMRuntimeDriving
  ) async {
    await emit(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: 0,
        kind: .started
      ),
      token: token
    )
    do {
      try await driver.generate(request) { [weak self] chunk in
        await self?.receiveChunk(
          chunk,
          generationId: generationId,
          token: token
        )
      }
      await completeGeneration(generationId: generationId, token: token)
    } catch {
      await failGeneration(generationId: generationId, token: token)
    }
    // If this decode was the abandoned one, the engine is free again.
    releaseDrain(token: token)
  }

  /// Marks the abandoned decode as finished so a waiting generation proceeds.
  private func releaseDrain(token: UInt64) {
    guard drainingToken == token else {
      return
    }
    drainingToken = nil
    drainingGeneration = nil
  }

  private func receiveChunk(
    _ chunk: String,
    generationId: String,
    token: UInt64
  ) async {
    guard !chunk.isEmpty, var active = matchingGeneration(
      generationId: generationId,
      token: token
    ) else {
      return
    }
    active.nextSequence += 1
    active.outputCharacters += chunk.count
    activeGeneration = active
    await eventRelay.emit(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: active.nextSequence,
        kind: .delta,
        delta: chunk
      )
    )
  }

  private func completeGeneration(
    generationId: String,
    token: UInt64
  ) async {
    guard var active = matchingGeneration(
      generationId: generationId,
      token: token
    ) else {
      return
    }
    active.nextSequence += 1
    activeGeneration = nil
    NSLog(
      "Lulo generation: completed — %d chars out (cap %d tokens), prompt %d chars, history %d chars in %d turns",
      active.outputCharacters,
      active.maxOutputTokens,
      active.promptCharacters,
      active.historyCharacters,
      active.historyTurns
    )
    await eventRelay.emit(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: active.nextSequence,
        kind: .completed
      )
    )
  }

  private func failGeneration(
    generationId: String,
    token: UInt64
  ) async {
    guard var active = matchingGeneration(
      generationId: generationId,
      token: token
    ) else {
      return
    }
    active.nextSequence += 1
    activeGeneration = nil
    await eventRelay.emit(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: active.nextSequence,
        kind: .failed,
        failureCode: .generationFailed,
        message: "Local inference failed."
      )
    )
  }

  private func emit(
    _ event: RuntimeGenerationEvent,
    token: UInt64
  ) async {
    guard
      activeGeneration?.generationId == event.generationId,
      activeGeneration?.token == token
    else {
      return
    }
    await eventRelay.emit(event)
  }

  private func matchingGeneration(
    generationId: String,
    token: UInt64
  ) -> ActiveGeneration? {
    guard
      let activeGeneration,
      activeGeneration.generationId == generationId,
      activeGeneration.token == token
    else {
      return nil
    }
    return activeGeneration
  }

  private func validateModel(_ model: RuntimeModelRequest) throws -> Int {
    guard
      !model.modelId.isEmpty,
      URL(fileURLWithPath: model.modelPath).pathExtension == "litertlm",
      let contextSize = Int(exactly: model.contextSize),
      contextSize > 0,
      contextSize <= Int(Int32.max)
    else {
      throw RuntimeBoundaryError.modelLoadFailed
    }
    var fileStatus = stat()
    guard
      lstat(model.modelPath, &fileStatus) == 0,
      (fileStatus.st_mode & S_IFMT) == S_IFREG,
      access(model.modelPath, R_OK) == 0
    else {
      throw RuntimeBoundaryError.modelNotInstalled
    }
    return contextSize
  }

  private func driverBackend(
    for backend: LiteRTLMRuntimeComputeBackend
  ) throws -> LiteRTLMDriverBackend {
    switch backend {
    case .gpu:
      return .gpu
    case .cpu(let threadCount):
      if let threadCount {
        guard threadCount > 0, threadCount <= Int(Int32.max) else {
          throw RuntimeBoundaryError.modelLoadFailed
        }
      }
      return .cpu(threadCount: threadCount)
    }
  }

  /// Tokens the chat template spends on one turn's role markers.
  ///
  /// Gemma wraps every turn in `<start_of_turn>role\n` and
  /// `<end_of_turn>\n`. Six covers it with a little to spare, which is the
  /// direction this whole budget errs in.
  static let turnMarkerTokens = 6

  /// A conservative token count for [text], at or above what the tokenizer
  /// will actually produce.
  ///
  /// LiteRT-LM exposes no way to tokenize a string: `getTokenCount()` reads
  /// the KV cache of a conversation that has already been prefilled, which
  /// is the answer arriving after the question. So the budget estimates,
  /// and an estimate that guards against overflow has to sit above the
  /// truth rather than near it.
  ///
  /// Counted in UTF-8 bytes rather than characters, because that is what
  /// the tokenizer's byte fallback is denominated in and it is the one
  /// measure that does not change meaning between scripts.
  ///
  /// One token per three bytes. Han sits at three bytes per character and
  /// Gemma's vocabulary holds the common ones whole, so this charges Han
  /// about one token per character — which is what it costs. English is
  /// one byte per character against a real four or so characters per
  /// token, so it is charged around a third more than it costs. Erring
  /// upward is the point; erring downward reintroduces the overflow.
  ///
  /// A quarter per byte was tried first and is wrong: it prices Han at
  /// 0.75 tokens per character, *below* the real cost, which is the one
  /// direction this estimate must never take. Three unit tests caught it.
  ///
  /// The estimate this replaces charged one token per *character*, which
  /// left Han about right and English overcharged four times over: a
  /// conversation that fits the window whole was cut to a quarter of
  /// itself for a limit that did not exist.
  static func estimatedTokenCount(_ text: String) -> Int {
    let bytes = text.utf8.count
    // Divide rounding up, so no non-empty text is ever free.
    return (bytes + 2) / 3
  }

  /// As much of the tail of [history] as the window can hold once [prompt]
  /// and the reserved [maxOutputTokens] have taken their room, oldest kept
  /// first.
  ///
  /// Seeding a conversation with more than fits does not degrade — it
  /// fails, and the failure arrives as an empty answer, because the turn
  /// that carries the reason is not shown. Measured on a real one: 33
  /// turns and 10,093 characters against a 4,096-token window produced a
  /// stored turn with status failed and no text at all, where the same
  /// prompt without history answered normally.
  ///
  /// The history is not alone in the window. The answer the model is about
  /// to write occupies it, and so does the prompt that provokes it; the
  /// previous fixed third of the window stood in for that arithmetic
  /// without doing it, and was simultaneously too generous when a long
  /// answer was asked for and far too mean for anything written in Latin
  /// script.
  static func historyFitting(
    _ history: [RuntimeConversationTurn],
    systemInstruction: String,
    prompt: String,
    maxOutputTokens: Int,
    contextSize: Int64
  ) -> [RuntimeConversationTurn] {
    let reserved =
      max(0, maxOutputTokens)
      + estimatedTokenCount(prompt)
      + estimatedTokenCount(systemInstruction)
      + turnMarkerTokens
    let budget = max(0, Int(contextSize) - reserved)
    var kept: [RuntimeConversationTurn] = []
    var used = 0
    for turn in history.reversed() {
      let cost = estimatedTokenCount(turn.text) + turnMarkerTokens
      guard used + cost <= budget else { break }
      used += cost
      kept.append(turn)
    }
    return kept.reversed()
  }

  /// Whether a conversation the runtime already holds can take one more turn
  /// without running past the window.
  ///
  /// [historyFitting] bounds the window only where a conversation is built.
  /// Every turn after the first goes to one the runtime already has, and its
  /// KV cache is never re-seeded — so nothing measured it. What accumulates
  /// there is not the user's question either: it is the whole turn
  /// instruction, which carries the memories this question selected, the
  /// clock, and up to `maxDocumentCharacters` of the open document, and then
  /// the answer joins it. Measured with this app's own default profile
  /// against a 4,096-token window: 103 tokens a turn in Chinese with nothing
  /// open, and 224 with a document open — 38 turns and 17 turns before the
  /// cache is gone. Overflow does not degrade; it arrives as an empty
  /// answer, which is what `historyFitting` above exists to prevent on the
  /// one path it covers.
  ///
  /// A conversation with no room is rebuilt from the trimmed history rather
  /// than trimmed in place, because a KV cache cannot be trimmed: the
  /// runtime exposes no way to drop a prefix of one. The rebuild costs a
  /// prefill and sheds every accumulated clock and document passage, keeping
  /// what the conversation was actually about.
  ///
  /// [heldTokens] is what the conversation reports it is holding, which is
  /// an exact count read back from the cache rather than the estimate the
  /// seeding path is forced to use. Everything else is charged the same way
  /// [historyFitting] charges it, so the two paths cannot disagree about how
  /// much room a turn needs.
  static func liveConversationHasRoomForTurn(
    heldTokens: Int,
    prompt: String,
    maxOutputTokens: Int,
    contextSize: Int64
  ) -> Bool {
    let needed =
      heldTokens
      + estimatedTokenCount(prompt)
      + turnMarkerTokens
      + max(0, maxOutputTokens)
    return needed <= Int(contextSize)
  }

  private func validateGeneration(
    _ generation: RuntimeGenerationRequest,
    contextSize: Int64
  ) throws -> LiteRTLMDriverGenerationRequest {
    guard
      !generation.generationId.isEmpty,
      !generation.sessionId.isEmpty,
      !generation.prompt.isEmpty,
      generation.temperature.isFinite,
      (0...2).contains(generation.temperature),
      generation.topP.isFinite,
      generation.topP > 0,
      generation.topP <= 1,
      generation.maxTokens > 0,
      generation.maxTokens <= contextSize,
      let maxTokens = Int(exactly: generation.maxTokens),
      let seed = Int(exactly: generation.seed),
      seed >= Int(Int32.min),
      seed <= Int(Int32.max),
      configuration.topK > 0,
      configuration.topK <= Int(Int32.max)
    else {
      throw RuntimeBoundaryError.generationFailed
    }
    return LiteRTLMDriverGenerationRequest(
      sessionId: generation.sessionId,
      systemInstruction: generation.systemInstruction,
      prompt: generation.prompt,
      history: Self.historyFitting(
        generation.history,
        systemInstruction: generation.systemInstruction,
        prompt: generation.prompt,
        maxOutputTokens: maxTokens,
        contextSize: contextSize
      ),
      extraContext: ["context": generation.context],
      sampler: LiteRTLMSamplerFingerprint(
        topK: configuration.topK,
        topP: generation.topP,
        temperature: generation.temperature,
        seed: seed
      ),
      maxOutputTokens: maxTokens,
      contextSize: contextSize
    )
  }
}
