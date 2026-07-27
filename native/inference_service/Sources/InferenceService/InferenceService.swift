public struct RuntimeRequestEnvelope: Equatable, Sendable {
  public init(
    schemaVersion: Int64,
    requestId: String,
    timestampMicros: Int64
  ) {
    self.schemaVersion = schemaVersion
    self.requestId = requestId
    self.timestampMicros = timestampMicros
  }

  public let schemaVersion: Int64
  public let requestId: String
  public let timestampMicros: Int64
}

public struct RuntimeCapabilities: Equatable, Sendable {
  public init(
    runtimeName: String,
    supportsStreaming: Bool,
    supportsCancellation: Bool
  ) {
    self.runtimeName = runtimeName
    self.supportsStreaming = supportsStreaming
    self.supportsCancellation = supportsCancellation
  }

  public let runtimeName: String
  public let supportsStreaming: Bool
  public let supportsCancellation: Bool
}

public struct RuntimeHandshakeResult: Equatable, Sendable {
  public init(
    schemaVersion: Int64,
    runtimeName: String,
    supportsStreaming: Bool,
    supportsCancellation: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.runtimeName = runtimeName
    self.supportsStreaming = supportsStreaming
    self.supportsCancellation = supportsCancellation
  }

  public let schemaVersion: Int64
  public let runtimeName: String
  public let supportsStreaming: Bool
  public let supportsCancellation: Bool
}

public struct RuntimeModelRequest: Equatable, Sendable {
  public init(modelId: String, modelPath: String, contextSize: Int64) {
    self.modelId = modelId
    self.modelPath = modelPath
    self.contextSize = contextSize
  }

  public let modelId: String
  public let modelPath: String
  public let contextSize: Int64
}

public struct RuntimeModelLoadResult: Equatable, Sendable {
  public init(modelId: String, loaded: Bool) {
    self.modelId = modelId
    self.loaded = loaded
  }

  public let modelId: String
  public let loaded: Bool
}

public struct RuntimeGenerationRequest: Equatable, Sendable {
  public init(
    generationId: String,
    sessionId: String,
    prompt: String,
    context: [String],
    temperature: Double,
    topP: Double,
    maxTokens: Int64,
    seed: Int64
  ) {
    self.generationId = generationId
    self.sessionId = sessionId
    self.prompt = prompt
    self.context = context
    self.temperature = temperature
    self.topP = topP
    self.maxTokens = maxTokens
    self.seed = seed
  }

  public let generationId: String
  public let sessionId: String
  public let prompt: String
  public let context: [String]
  public let temperature: Double
  public let topP: Double
  public let maxTokens: Int64
  public let seed: Int64
}

public struct RuntimeGenerationAcknowledgement: Equatable, Sendable {
  public init(generationId: String, accepted: Bool) {
    self.generationId = generationId
    self.accepted = accepted
  }

  public let generationId: String
  public let accepted: Bool
}

public struct RuntimeCancellationAcknowledgement: Equatable, Sendable {
  public init(generationId: String, acknowledged: Bool) {
    self.generationId = generationId
    self.acknowledged = acknowledged
  }

  public let generationId: String
  public let acknowledged: Bool
}

public struct RuntimeOperationCompletion: Equatable, Sendable {
  public init(completed: Bool) {
    self.completed = completed
  }

  public let completed: Bool
}

public enum RuntimeGenerationEventKind: Equatable, Sendable {
  case started
  case delta
  case completed
  case cancelled
  case failed
}

public enum RuntimeFailureCode: Equatable, Sendable {
  case modelNotInstalled
  case modelLoadFailed
  case runtimeUnavailable
  case generationBusy
  case generationFailed
  case cancelled
  case protocolMismatch
}

public struct RuntimeGenerationEvent: Equatable, Sendable {
  public init(
    generationId: String,
    sequence: Int64,
    kind: RuntimeGenerationEventKind,
    delta: String? = nil,
    failureCode: RuntimeFailureCode? = nil,
    message: String? = nil
  ) {
    self.generationId = generationId
    self.sequence = sequence
    self.kind = kind
    self.delta = delta
    self.failureCode = failureCode
    self.message = message
  }

  public let generationId: String
  public let sequence: Int64
  public let kind: RuntimeGenerationEventKind
  public let delta: String?
  public let failureCode: RuntimeFailureCode?
  public let message: String?
}

public protocol RuntimeGenerationEventSink: AnyObject {
  func send(_ event: RuntimeGenerationEvent)
}

public protocol RuntimeScheduledTask: AnyObject {
  func cancel()
}

public protocol RuntimeEventScheduling: AnyObject {
  func schedule(
    afterMilliseconds delayMilliseconds: Int,
    _ operation: @escaping () -> Void
  ) -> RuntimeScheduledTask
}

public final class GenerationEventBridge {
  public init(
    sink: RuntimeGenerationEventSink,
    scheduler: RuntimeEventScheduling,
    coalescingMilliseconds: Int
  ) {
    precondition((8...16).contains(coalescingMilliseconds))
    self.sink = sink
    self.scheduler = scheduler
    self.coalescingMilliseconds = coalescingMilliseconds
  }

  private var sink: RuntimeGenerationEventSink?
  private let scheduler: RuntimeEventScheduling
  private let coalescingMilliseconds: Int
  private var generationId: String?
  private var lastSequence: Int64?
  private var pendingDelta = ""
  private var pendingDeltaSequence: Int64?
  private var scheduledFlush: RuntimeScheduledTask?
  private var isTerminal = false
  private var isDisposed = false

  public func receive(_ event: RuntimeGenerationEvent) {
    guard !isDisposed, !isTerminal else {
      return
    }
    if let generationId {
      guard
        event.generationId == generationId,
        event.kind != .started,
        event.sequence > (lastSequence ?? -1)
      else {
        return
      }
    } else {
      guard
        event.kind == .started,
        !event.generationId.isEmpty,
        event.sequence >= 0
      else {
        return
      }
      generationId = event.generationId
    }

    if event.kind == .delta {
      guard let delta = event.delta else {
        return
      }
      lastSequence = event.sequence
      pendingDelta.append(delta)
      pendingDeltaSequence = event.sequence
      if scheduledFlush == nil {
        scheduledFlush = scheduler.schedule(
          afterMilliseconds: coalescingMilliseconds
        ) { [weak self] in
          self?.scheduledFlush = nil
          self?.emitPendingDelta()
        }
      }
      return
    }

    if isTerminalEvent(event.kind) {
      scheduledFlush?.cancel()
      scheduledFlush = nil
      emitPendingDelta()
    }
    lastSequence = event.sequence
    sink?.send(event)
    isTerminal = isTerminalEvent(event.kind)
  }

  public func dispose() {
    guard !isDisposed else {
      return
    }
    isDisposed = true
    scheduledFlush?.cancel()
    scheduledFlush = nil
    pendingDelta = ""
    pendingDeltaSequence = nil
    sink = nil
  }

  private func emitPendingDelta() {
    guard
      !isDisposed,
      !pendingDelta.isEmpty,
      let generationId,
      let pendingDeltaSequence,
      let sink
    else {
      return
    }
    let delta = pendingDelta
    pendingDelta = ""
    self.pendingDeltaSequence = nil
    sink.send(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: pendingDeltaSequence,
        kind: .delta,
        delta: delta
      )
    )
  }

  private func isTerminalEvent(_ kind: RuntimeGenerationEventKind) -> Bool {
    switch kind {
    case .completed, .cancelled, .failed:
      true
    case .started, .delta:
      false
    }
  }
}

public enum RuntimeBoundaryError: Error, Equatable, Sendable {
  case protocolMismatch
}

public protocol LocalModelRuntimeBackend: AnyObject {
  var capabilities: RuntimeCapabilities { get }

  func loadModel(_ model: RuntimeModelRequest) throws
    -> RuntimeModelLoadResult

  func startGeneration(_ generation: RuntimeGenerationRequest) throws
    -> RuntimeGenerationAcknowledgement

  func cancelGeneration(generationId: String) throws
    -> RuntimeCancellationAcknowledgement

  func resetSession(sessionId: String) throws -> RuntimeOperationCompletion

  func unloadModel() throws -> RuntimeOperationCompletion
}

public final class LocalModelRuntimeCoordinator {
  public init(
    supportedSchemaVersion: Int64,
    backend: LocalModelRuntimeBackend
  ) {
    self.supportedSchemaVersion = supportedSchemaVersion
    self.backend = backend
  }

  private let supportedSchemaVersion: Int64
  private let backend: LocalModelRuntimeBackend

  public func handshake(
    request: RuntimeRequestEnvelope
  ) throws -> RuntimeHandshakeResult {
    try validate(request)
    let capabilities = backend.capabilities
    return RuntimeHandshakeResult(
      schemaVersion: supportedSchemaVersion,
      runtimeName: capabilities.runtimeName,
      supportsStreaming: capabilities.supportsStreaming,
      supportsCancellation: capabilities.supportsCancellation
    )
  }

  public func loadModel(
    request: RuntimeRequestEnvelope,
    model: RuntimeModelRequest
  ) throws -> RuntimeModelLoadResult {
    try validate(request)
    return try backend.loadModel(model)
  }

  public func startGeneration(
    request: RuntimeRequestEnvelope,
    generation: RuntimeGenerationRequest
  ) throws -> RuntimeGenerationAcknowledgement {
    try validate(request)
    return try backend.startGeneration(generation)
  }

  public func cancelGeneration(
    request: RuntimeRequestEnvelope,
    generationId: String
  ) throws -> RuntimeCancellationAcknowledgement {
    try validate(request)
    return try backend.cancelGeneration(generationId: generationId)
  }

  public func resetSession(
    request: RuntimeRequestEnvelope,
    sessionId: String
  ) throws -> RuntimeOperationCompletion {
    try validate(request)
    return try backend.resetSession(sessionId: sessionId)
  }

  public func unloadModel(
    request: RuntimeRequestEnvelope
  ) throws -> RuntimeOperationCompletion {
    try validate(request)
    return try backend.unloadModel()
  }

  private func validate(_ request: RuntimeRequestEnvelope) throws {
    guard
      request.schemaVersion == supportedSchemaVersion,
      !request.requestId.isEmpty,
      request.timestampMicros > 0
    else {
      throw RuntimeBoundaryError.protocolMismatch
    }
  }
}

public final class DeterministicLocalModelRuntimeBackend:
  LocalModelRuntimeBackend
{
  public init(eventReceiver: @escaping (RuntimeGenerationEvent) -> Void) {
    self.eventReceiver = eventReceiver
  }

  public let capabilities = RuntimeCapabilities(
    runtimeName: "deterministic",
    supportsStreaming: true,
    supportsCancellation: true
  )

  private let eventReceiver: (RuntimeGenerationEvent) -> Void
  private var loadedModelId: String?

  public func loadModel(
    _ model: RuntimeModelRequest
  ) throws -> RuntimeModelLoadResult {
    loadedModelId = model.modelId
    return RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
  }

  public func startGeneration(
    _ generation: RuntimeGenerationRequest
  ) throws -> RuntimeGenerationAcknowledgement {
    eventReceiver(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 0,
        kind: .started
      )
    )
    eventReceiver(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 1,
        kind: .delta,
        delta: "Deterministic "
      )
    )
    eventReceiver(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 2,
        kind: .delta,
        delta: "response."
      )
    )
    eventReceiver(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 3,
        kind: .completed
      )
    )
    return RuntimeGenerationAcknowledgement(
      generationId: generation.generationId,
      accepted: true
    )
  }

  public func cancelGeneration(
    generationId: String
  ) throws -> RuntimeCancellationAcknowledgement {
    RuntimeCancellationAcknowledgement(
      generationId: generationId,
      acknowledged: true
    )
  }

  public func resetSession(
    sessionId: String
  ) throws -> RuntimeOperationCompletion {
    RuntimeOperationCompletion(completed: true)
  }

  public func unloadModel() throws -> RuntimeOperationCompletion {
    loadedModelId = nil
    return RuntimeOperationCompletion(completed: true)
  }
}
