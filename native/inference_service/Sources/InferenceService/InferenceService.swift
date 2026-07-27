import Dispatch
import Foundation

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

public protocol RuntimeEventDispatching: AnyObject {
  func dispatch(_ operation: @escaping () -> Void)
}

public final class MainQueueRuntimeEventDispatcher:
  RuntimeEventDispatching
{
  public convenience init() {
    self.init(
      isMainThread: { Thread.isMainThread },
      enqueueOnMain: { operation in
        let operationBox = RuntimeEventOperationBox(operation)
        DispatchQueue.main.async {
          operationBox.run()
        }
      }
    )
  }

  init(
    isMainThread: @escaping () -> Bool,
    enqueueOnMain: @escaping (@escaping () -> Void) -> Void
  ) {
    self.isMainThread = isMainThread
    self.enqueueOnMain = enqueueOnMain
  }

  private let isMainThread: () -> Bool
  private let enqueueOnMain: (@escaping () -> Void) -> Void

  public func dispatch(_ operation: @escaping () -> Void) {
    if isMainThread() {
      operation()
    } else {
      enqueueOnMain(operation)
    }
  }
}

private final class RuntimeEventOperationBox: @unchecked Sendable {
  init(_ operation: @escaping () -> Void) {
    self.operation = operation
  }

  private let operation: () -> Void

  func run() {
    operation()
  }
}

public protocol RuntimeGenerationCancellationFencing: AnyObject {
  func cancelGeneration(generationId: String)
}

public final class GenerationEventBridge:
  RuntimeGenerationCancellationFencing,
  @unchecked Sendable
{
  public init(
    sink: RuntimeGenerationEventSink,
    scheduler: RuntimeEventScheduling,
    coalescingMilliseconds: Int
  ) {
    precondition((8...16).contains(coalescingMilliseconds))
    self.sink = sink
    self.scheduler = scheduler
    self.coalescingMilliseconds = coalescingMilliseconds
    transitionQueue.setSpecific(
      key: transitionQueueKey,
      value: transitionQueueIdentity
    )
  }

  private let transitionQueue = DispatchQueue(
    label: "com.flutterlocalagent.inference-service.event-bridge"
  )
  private let transitionQueueKey = DispatchSpecificKey<UInt8>()
  private let transitionQueueIdentity: UInt8 = 1
  private var sink: RuntimeGenerationEventSink?
  private let scheduler: RuntimeEventScheduling
  private let coalescingMilliseconds: Int
  private var generationId: String?
  private var lastSequence: Int64?
  private var pendingDelta = ""
  private var pendingDeltaSequence: Int64?
  private var scheduledFlush: RuntimeScheduledTask?
  private var lifecycle = Lifecycle.idle
  private var nextGenerationToken: UInt64 = 0
  private var staleGenerationIds: [String] = []

  public func receive(_ event: RuntimeGenerationEvent) {
    withSerializedTransition {
      receiveSerialized(event)
    }
  }

  public func dispose() {
    withSerializedTransition {
      disposeSerialized()
    }
  }

  public func cancelGeneration(generationId: String) {
    withSerializedTransition {
      cancelGenerationSerialized(generationId: generationId)
    }
  }

  private func receiveSerialized(_ event: RuntimeGenerationEvent) {
    let generationToken: UInt64
    switch lifecycle {
    case .disposed:
      return
    case let .active(activeGenerationId, activeGenerationToken):
      guard
        event.generationId == activeGenerationId,
        event.kind != .started,
        event.sequence > (lastSequence ?? -1)
      else {
        return
      }
      generationToken = activeGenerationToken
    case .idle:
      guard
        event.kind == .started,
        !event.generationId.isEmpty,
        event.sequence >= 0,
        !staleGenerationIds.contains(event.generationId)
      else {
        return
      }
      generationId = event.generationId
      nextGenerationToken &+= 1
      generationToken = nextGenerationToken
      lifecycle = .active(
        generationId: event.generationId,
        token: generationToken
      )
    }

    if event.kind == .delta {
      guard let delta = event.delta else {
        return
      }
      lastSequence = event.sequence
      pendingDelta.append(delta)
      pendingDeltaSequence = event.sequence
      if scheduledFlush == nil {
        let task = scheduler.schedule(
          afterMilliseconds: coalescingMilliseconds
        ) { [weak self] in
          self?.flushScheduledDelta(generationToken: generationToken)
        }
        if
          case let .active(_, activeGenerationToken) = lifecycle,
          activeGenerationToken == generationToken,
          !pendingDelta.isEmpty,
          scheduledFlush == nil
        {
          scheduledFlush = task
        } else {
          task.cancel()
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
    if isTerminalEvent(event.kind) {
      recordStaleGeneration(event.generationId)
      generationId = nil
      lastSequence = nil
      lifecycle = .idle
    }
  }

  private func disposeSerialized() {
    guard lifecycle != .disposed else {
      return
    }
    lifecycle = .disposed
    scheduledFlush?.cancel()
    scheduledFlush = nil
    pendingDelta = ""
    pendingDeltaSequence = nil
    sink = nil
  }

  private func cancelGenerationSerialized(generationId: String) {
    guard lifecycle != .disposed else {
      return
    }
    recordStaleGeneration(generationId)
    guard
      case let .active(activeGenerationId, _) = lifecycle,
      activeGenerationId == generationId
    else {
      return
    }
    scheduledFlush?.cancel()
    scheduledFlush = nil
    pendingDelta = ""
    pendingDeltaSequence = nil
    let cancellationSequence = (lastSequence ?? -1) + 1
    lastSequence = cancellationSequence
    sink?.send(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: cancellationSequence,
        kind: .cancelled,
        failureCode: .cancelled,
        message: "The response was cancelled."
      )
    )
    self.generationId = nil
    lastSequence = nil
    lifecycle = .idle
  }

  private func emitPendingDelta() {
    guard
      lifecycle != .disposed,
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

  private func flushScheduledDelta(generationToken: UInt64) {
    withSerializedTransition {
      guard
        case let .active(_, activeGenerationToken) = lifecycle,
        activeGenerationToken == generationToken
      else {
        return
      }
      scheduledFlush = nil
      emitPendingDelta()
    }
  }

  private func recordStaleGeneration(_ generationId: String) {
    guard !staleGenerationIds.contains(generationId) else {
      return
    }
    staleGenerationIds.append(generationId)
    if staleGenerationIds.count > staleGenerationCapacity {
      staleGenerationIds.removeFirst()
    }
  }

  private func isTerminalEvent(_ kind: RuntimeGenerationEventKind) -> Bool {
    switch kind {
    case .completed, .cancelled, .failed:
      true
    case .started, .delta:
      false
    }
  }

  private enum Lifecycle: Equatable {
    case idle
    case active(generationId: String, token: UInt64)
    case disposed
  }

  private let staleGenerationCapacity = 32

  private func withSerializedTransition<T>(
    _ operation: () throws -> T
  ) rethrows -> T {
    if
      DispatchQueue.getSpecific(key: transitionQueueKey)
        == transitionQueueIdentity
    {
      return try operation()
    }
    return try transitionQueue.sync(execute: operation)
  }
}

public enum RuntimeBoundaryError: Error, Equatable, Sendable {
  case modelNotInstalled
  case modelLoadFailed
  case runtimeUnavailable
  case generationBusy
  case generationFailed
  case cancelled
  case protocolMismatch
}

public struct RuntimeSafeFailure: Equatable, Sendable {
  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }

  public let code: String
  public let message: String
}

public func safeRuntimeFailure(for error: Error) -> RuntimeSafeFailure {
  guard let boundaryError = error as? RuntimeBoundaryError else {
    return RuntimeSafeFailure(
      code: "runtimeUnavailable",
      message: "Local inference is unavailable."
    )
  }
  switch boundaryError {
  case .modelNotInstalled:
    return RuntimeSafeFailure(
      code: "modelNotInstalled",
      message: "The local model is not installed."
    )
  case .modelLoadFailed:
    return RuntimeSafeFailure(
      code: "modelLoadFailed",
      message: "The local model could not be loaded."
    )
  case .runtimeUnavailable:
    return RuntimeSafeFailure(
      code: "runtimeUnavailable",
      message: "Local inference is unavailable."
    )
  case .generationBusy:
    return RuntimeSafeFailure(
      code: "generationBusy",
      message: "Another response is already being generated."
    )
  case .generationFailed:
    return RuntimeSafeFailure(
      code: "generationFailed",
      message: "Local inference failed."
    )
  case .cancelled:
    return RuntimeSafeFailure(
      code: "cancelled",
      message: "The response was cancelled."
    )
  case .protocolMismatch:
    return RuntimeSafeFailure(
      code: "protocolMismatch",
      message: "The desktop host protocol is incompatible."
    )
  }
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

public protocol RuntimeBackend: AnyObject, Sendable {
  var capabilities: RuntimeCapabilities { get async }

  func loadModel(_ model: RuntimeModelRequest) async throws
    -> RuntimeModelLoadResult

  func startGeneration(_ generation: RuntimeGenerationRequest) async throws
    -> RuntimeGenerationAcknowledgement

  func cancelGeneration(generationId: String) async throws
    -> RuntimeCancellationAcknowledgement

  func resetSession(sessionId: String) async throws
    -> RuntimeOperationCompletion

  func unloadModel() async throws -> RuntimeOperationCompletion
}

public actor InferenceCoordinator {
  public init(
    supportedSchemaVersion: Int64,
    backend: any RuntimeBackend,
    eventHandler: @escaping @Sendable (RuntimeGenerationEvent) -> Void = { _ in }
  ) {
    self.supportedSchemaVersion = supportedSchemaVersion
    self.backend = backend
    self.eventHandler = eventHandler
  }

  private enum ModelState {
    case idle
    case loading(
      request: RuntimeModelRequest,
      token: UInt64,
      task: Task<RuntimeModelLoadResult, Error>
    )
    case loaded(
      request: RuntimeModelRequest,
      result: RuntimeModelLoadResult,
      token: UInt64
    )
  }

  private enum GenerationState {
    case idle
    case starting(
      generationId: String,
      token: UInt64,
      task: Task<RuntimeGenerationAcknowledgement, Error>
    )
    case active(generationId: String, token: UInt64)
  }

  private struct CancellationOperation {
    let operationToken: UInt64
    let generationId: String
    let generationToken: UInt64
    let task: Task<RuntimeCancellationAcknowledgement, Error>
  }

  private struct UnloadOperation {
    let token: UInt64
    let task: Task<RuntimeOperationCompletion, Error>
  }

  private let supportedSchemaVersion: Int64
  private let backend: any RuntimeBackend
  private let eventHandler:
    @Sendable (RuntimeGenerationEvent) -> Void
  private var modelState = ModelState.idle
  private var nextModelToken: UInt64 = 0
  private var generationState = GenerationState.idle
  private var nextGenerationToken: UInt64 = 0
  private var nextCancellationToken: UInt64 = 0
  private var cancellationOperation: CancellationOperation?
  private var nextUnloadToken: UInt64 = 0
  private var unloadOperation: UnloadOperation?
  private var lastGenerationSequence: Int64?
  private var cancelledGenerationIds: [String] = []

  public func loadModel(
    request: RuntimeRequestEnvelope,
    model: RuntimeModelRequest
  ) async throws -> RuntimeModelLoadResult {
    try validate(request)
    guard unloadOperation == nil else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }

    switch modelState {
    case .loaded(let loadedRequest, let result, _):
      guard loadedRequest == model else {
        throw RuntimeBoundaryError.modelLoadFailed
      }
      return result
    case .loading(let loadingRequest, _, let task):
      guard loadingRequest == model else {
        throw RuntimeBoundaryError.modelLoadFailed
      }
      return try await task.value
    case .idle:
      let token = nextModelToken
      nextModelToken &+= 1
      let task = Task {
        try await backend.loadModel(model)
      }
      modelState = .loading(request: model, token: token, task: task)
      do {
        let result = try await task.value
        if
          case .loading(_, let activeToken, _) = modelState,
          activeToken == token
        {
          modelState = .loaded(
            request: model,
            result: result,
            token: token
          )
        }
        return result
      } catch {
        if
          case .loading(_, let activeToken, _) = modelState,
          activeToken == token
        {
          modelState = .idle
        }
        throw error
      }
    }
  }

  public func startGeneration(
    request: RuntimeRequestEnvelope,
    generation: RuntimeGenerationRequest
  ) async throws -> RuntimeGenerationAcknowledgement {
    try validate(request)
    guard unloadOperation == nil else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    guard !cancelledGenerationIds.contains(generation.generationId) else {
      throw RuntimeBoundaryError.protocolMismatch
    }
    guard case .idle = generationState else {
      throw RuntimeBoundaryError.generationBusy
    }

    let task = Task {
      try await backend.startGeneration(generation)
    }
    let token = nextGenerationToken
    nextGenerationToken &+= 1
    lastGenerationSequence = nil
    generationState = .starting(
      generationId: generation.generationId,
      token: token,
      task: task
    )
    do {
      let acknowledgement = try await task.value
      if
        case .starting(
          let generationId,
          let activeToken,
          _
        ) = generationState,
        generationId == generation.generationId,
        activeToken == token
      {
        generationState = acknowledgement.accepted
          ? .active(generationId: generation.generationId, token: token)
          : .idle
      }
      return acknowledgement
    } catch {
      if
        case .starting(
          let generationId,
          let activeToken,
          _
        ) = generationState,
        generationId == generation.generationId,
        activeToken == token
      {
        generationState = .idle
      }
      throw error
    }
  }

  public func cancelGeneration(
    request: RuntimeRequestEnvelope,
    generationId: String
  ) async throws -> RuntimeCancellationAcknowledgement {
    try validate(request)
    if cancelledGenerationIds.contains(generationId) {
      return RuntimeCancellationAcknowledgement(
        generationId: generationId,
        acknowledged: true
      )
    }
    if
      let cancellationOperation,
      cancellationOperation.generationId == generationId
    {
      return try await finishCancellation(cancellationOperation)
    }
    guard let generationToken = generationToken(for: generationId) else {
      return try await backend.cancelGeneration(generationId: generationId)
    }

    let operationToken = nextCancellationToken
    nextCancellationToken &+= 1
    let operation = CancellationOperation(
      operationToken: operationToken,
      generationId: generationId,
      generationToken: generationToken,
      task: Task {
        try await backend.cancelGeneration(generationId: generationId)
      }
    )
    cancellationOperation = operation
    return try await finishCancellation(operation)
  }

  private func finishCancellation(
    _ operation: CancellationOperation
  ) async throws -> RuntimeCancellationAcknowledgement {
    do {
      let acknowledgement = try await operation.task.value
      guard acknowledgement.generationId == operation.generationId else {
        if cancellationOperation?.operationToken == operation.operationToken {
          cancellationOperation = nil
        }
        throw RuntimeBoundaryError.protocolMismatch
      }
      guard
        cancellationOperation?.operationToken == operation.operationToken
      else {
        return acknowledgement
      }
      cancellationOperation = nil
      guard
        acknowledgement.acknowledged,
        generationToken(for: operation.generationId)
          == operation.generationToken
      else {
        return acknowledgement
      }

      let sequence = (lastGenerationSequence ?? -1) + 1
      generationState = .idle
      lastGenerationSequence = nil
      recordCancelledGeneration(operation.generationId)
      eventHandler(
        RuntimeGenerationEvent(
          generationId: operation.generationId,
          sequence: sequence,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        )
      )
      return acknowledgement
    } catch {
      if cancellationOperation?.operationToken == operation.operationToken {
        cancellationOperation = nil
      }
      throw error
    }
  }

  public func unloadModel(
    request: RuntimeRequestEnvelope
  ) async throws -> RuntimeOperationCompletion {
    try validate(request)
    if let unloadOperation {
      return try await finishUnload(unloadOperation)
    }

    let token = nextUnloadToken
    nextUnloadToken &+= 1
    let task = Task {
      try await self.performUnload(request: request)
    }
    let operation = UnloadOperation(token: token, task: task)
    unloadOperation = operation
    return try await finishUnload(operation)
  }

  private func performUnload(
    request: RuntimeRequestEnvelope
  ) async throws -> RuntimeOperationCompletion {
    if
      case .loading(let modelRequest, let token, let task) = modelState
    {
      do {
        let result = try await task.value
        if
          case .loading(_, let activeToken, _) = modelState,
          activeToken == token
        {
          modelState = .loaded(
            request: modelRequest,
            result: result,
            token: token
          )
        }
      } catch {
        if
          case .loading(_, let activeToken, _) = modelState,
          activeToken == token
        {
          modelState = .idle
        }
        throw error
      }
    }
    if let generationId = currentGenerationId {
      let acknowledgement = try await cancelGeneration(
        request: request,
        generationId: generationId
      )
      guard acknowledgement.acknowledged else {
        throw RuntimeBoundaryError.generationBusy
      }
    }
    return try await backend.unloadModel()
  }

  private func finishUnload(
    _ operation: UnloadOperation
  ) async throws -> RuntimeOperationCompletion {
    do {
      let completion = try await operation.task.value
      guard unloadOperation?.token == operation.token else {
        return completion
      }
      unloadOperation = nil
      if completion.completed {
        modelState = .idle
        generationState = .idle
        lastGenerationSequence = nil
      }
      return completion
    } catch {
      if unloadOperation?.token == operation.token {
        unloadOperation = nil
      }
      throw error
    }
  }

  public func receiveGenerationEvent(_ event: RuntimeGenerationEvent) async {
    guard generationToken(for: event.generationId) != nil else {
      return
    }
    if
      let lastGenerationSequence,
      event.sequence <= lastGenerationSequence
    {
      return
    }
    lastGenerationSequence = event.sequence
    if isTerminal(event.kind) {
      generationState = .idle
      lastGenerationSequence = nil
    }
    eventHandler(event)
  }

  private func generationToken(for generationId: String) -> UInt64? {
    switch generationState {
    case .starting(let activeGenerationId, let token, _),
      .active(let activeGenerationId, let token):
      activeGenerationId == generationId ? token : nil
    case .idle:
      nil
    }
  }

  private var currentGenerationId: String? {
    switch generationState {
    case .starting(let generationId, _, _),
      .active(let generationId, _):
      generationId
    case .idle:
      nil
    }
  }

  private func recordCancelledGeneration(_ generationId: String) {
    guard !cancelledGenerationIds.contains(generationId) else {
      return
    }
    cancelledGenerationIds.append(generationId)
    if cancelledGenerationIds.count > 32 {
      cancelledGenerationIds.removeFirst()
    }
  }

  private func isTerminal(_ kind: RuntimeGenerationEventKind) -> Bool {
    switch kind {
    case .completed, .cancelled, .failed:
      true
    case .started, .delta:
      false
    }
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

public final class LocalModelRuntimeCoordinator {
  public init(
    supportedSchemaVersion: Int64,
    backend: LocalModelRuntimeBackend,
    cancellationFence: RuntimeGenerationCancellationFencing? = nil
  ) {
    self.supportedSchemaVersion = supportedSchemaVersion
    self.backend = backend
    self.cancellationFence = cancellationFence
  }

  private let supportedSchemaVersion: Int64
  private let backend: LocalModelRuntimeBackend
  private let cancellationFence: RuntimeGenerationCancellationFencing?

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
    let acknowledgement = try backend.cancelGeneration(
      generationId: generationId
    )
    if acknowledgement.acknowledged {
      cancellationFence?.cancelGeneration(generationId: generationId)
    }
    return acknowledgement
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
