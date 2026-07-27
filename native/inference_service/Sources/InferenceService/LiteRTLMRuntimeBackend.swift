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
  let prompt: String
  let extraContext: [String: [String]]
  let sampler: LiteRTLMSamplerFingerprint
  let maxOutputTokens: Int
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
    if let existing = conversations[request.sessionId] {
      conversation = existing
    } else {
      let sampler = try SamplerConfig(
        topK: request.sampler.topK,
        topP: Float(request.sampler.topP),
        temperature: Float(request.sampler.temperature),
        seed: request.sampler.seed
      )
      conversation = try await engine.createConversation(
        with: ConversationConfig(samplerConfig: sampler)
      )
      conversations[request.sessionId] = conversation
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
    if let conversation = conversations.removeValue(forKey: sessionId) {
      try conversation.cancel()
    }
  }

  func unload() async {
    for conversation in conversations.values {
      try? conversation.cancel()
    }
    conversations.removeAll()
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
  }

  private let configuration: LiteRTLMRuntimeConfiguration
  private let eventRelay: RuntimeGenerationEventRelay
  private let driverFactory: any LiteRTLMRuntimeDriverFactory
  private var driver: (any LiteRTLMRuntimeDriving)?
  private var loadedModel: RuntimeModelRequest?
  private var sessionSamplers: [String: LiteRTLMSamplerFingerprint] = [:]
  private var activeGeneration: ActiveGeneration?
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
    guard let loadedModel, let driver else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    guard activeGeneration == nil else {
      throw RuntimeBoundaryError.generationBusy
    }
    let request = try validateGeneration(
      generation,
      contextSize: loadedModel.contextSize
    )
    if let sampler = sessionSamplers[generation.sessionId] {
      guard sampler == request.sampler else {
        throw RuntimeBoundaryError.generationFailed
      }
    } else {
      sessionSamplers[generation.sessionId] = request.sampler
    }

    let token = nextGenerationToken
    nextGenerationToken &+= 1
    activeGeneration = ActiveGeneration(
      generationId: generation.generationId,
      sessionId: generation.sessionId,
      token: token,
      nextSequence: 0,
      task: nil
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
      active.generationId == generationId,
      let driver
    else {
      return RuntimeCancellationAcknowledgement(
        generationId: generationId,
        acknowledged: false
      )
    }
    // Clearing the active generation first fences any chunk the driver is
    // still producing, so nothing can follow the terminal emitted below.
    activeGeneration = nil
    active.task?.cancel()
    do {
      try await driver.cancel(sessionId: active.sessionId)
    } catch {
      throw RuntimeBoundaryError.generationFailed
    }
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
      prompt: generation.prompt,
      extraContext: ["context": generation.context],
      sampler: LiteRTLMSamplerFingerprint(
        topK: configuration.topK,
        topP: generation.topP,
        temperature: generation.temperature,
        seed: seed
      ),
      maxOutputTokens: maxTokens
    )
  }
}
