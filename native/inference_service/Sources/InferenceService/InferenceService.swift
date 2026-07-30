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

public protocol RuntimeShutdownDeadline: Sendable {
  func wait() async -> Bool
}

public protocol RuntimeShutdownDeadlineFactory: Sendable {
  func makeDeadline() -> any RuntimeShutdownDeadline
}

public struct SystemRuntimeShutdownDeadlineFactory:
  RuntimeShutdownDeadlineFactory
{
  public init(timeoutNanoseconds: UInt64 = 5_000_000_000) {
    self.timeoutNanoseconds = timeoutNanoseconds
  }

  public func makeDeadline() -> any RuntimeShutdownDeadline {
    SystemRuntimeShutdownDeadline(timeoutNanoseconds: timeoutNanoseconds)
  }

  private let timeoutNanoseconds: UInt64
}

private struct SystemRuntimeShutdownDeadline: RuntimeShutdownDeadline {
  let timeoutNanoseconds: UInt64

  func wait() async -> Bool {
    do {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      return !Task.isCancelled
    } catch {
      return false
    }
  }
}

public actor InferenceCoordinator {
  public init(
    supportedSchemaVersion: Int64,
    backend: any RuntimeBackend,
    eventHandler: @escaping @Sendable (RuntimeGenerationEvent) -> Void = { _ in },
    shutdownDeadlineFactory: any RuntimeShutdownDeadlineFactory =
      SystemRuntimeShutdownDeadlineFactory()
  ) {
    self.init(
      supportedSchemaVersion: supportedSchemaVersion,
      backend: backend,
      eventHandler: eventHandler,
      shutdownDeadlineFactory: shutdownDeadlineFactory,
      shutdownWaitObserver: {}
    )
  }

  init(
    supportedSchemaVersion: Int64,
    backend: any RuntimeBackend,
    eventHandler: @escaping @Sendable (RuntimeGenerationEvent) -> Void,
    shutdownDeadlineFactory: any RuntimeShutdownDeadlineFactory,
    shutdownWaitObserver: @escaping @Sendable () -> Void,
    ordinaryUnloadAdmissionObserver: @escaping @Sendable () -> Void = {}
  ) {
    self.supportedSchemaVersion = supportedSchemaVersion
    self.backend = backend
    self.eventHandler = eventHandler
    self.shutdownDeadlineFactory = shutdownDeadlineFactory
    self.shutdownWaitObserver = shutdownWaitObserver
    self.ordinaryUnloadAdmissionObserver = ordinaryUnloadAdmissionObserver
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

  private final class UnloadOperation {
    init(
      token: UInt64,
      task: Task<RuntimeOperationCompletion, Error>,
      result: UnloadResult,
      generationId: String?
    ) {
      self.token = token
      self.task = task
      self.result = result
      self.generationId = generationId
    }

    let token: UInt64
    let task: Task<RuntimeOperationCompletion, Error>
    let result: UnloadResult
    let generationId: String?
    var observerTask: Task<Void, Never>?
    var cancellationTask: Task<RuntimeCancellationAcknowledgement, Error>?
    var backendUnloadTask: Task<RuntimeOperationCompletion, Error>?
  }

  private struct TeardownPlan: Sendable {
    let backend: any RuntimeBackend
    let loadingTask: Task<RuntimeModelLoadResult, Error>?
    let startingTask: Task<RuntimeGenerationAcknowledgement, Error>?
    let cancellationTask: Task<RuntimeCancellationAcknowledgement, Error>?
    let cancellationGenerationId: String?
    let generationId: String?
    let cancellationHandler: @Sendable (String) async -> Void
  }

  private struct ShutdownPlan: Sendable {
    let teardown: TeardownPlan
    let existingUnloadResult: UnloadResult?
  }

  private enum Lifecycle {
    case ready
    case shuttingDown(ShutdownOperation)
    case disposed(ShutdownResult)
  }

  private final class ShutdownOperation {
    init(token: UInt64, result: ShutdownResult) {
      self.token = token
      self.result = result
    }

    let token: UInt64
    let result: ShutdownResult
    var workerTask: Task<Void, Never>?
    var deadlineTask: Task<Void, Never>?
    var cancellationTask: Task<RuntimeCancellationAcknowledgement, Error>?
    var unloadTask: Task<RuntimeOperationCompletion, Error>?
  }

  private enum ShutdownOutcome: Sendable {
    case completed(RuntimeOperationCompletion)
    case unavailable
  }

  private actor ShutdownResult {
    private var outcome: ShutdownOutcome?
    private var continuations: [CheckedContinuation<ShutdownOutcome, Never>] = []

    func wait() async throws -> RuntimeOperationCompletion {
      let outcome = if let outcome {
        outcome
      } else {
        await withCheckedContinuation { continuation in
          continuations.append(continuation)
        }
      }
      switch outcome {
      case .completed(let completion):
        return completion
      case .unavailable:
        throw RuntimeBoundaryError.runtimeUnavailable
      }
    }

    func resolve(_ outcome: ShutdownOutcome) {
      guard self.outcome == nil else {
        return
      }
      self.outcome = outcome
      continuations.forEach { $0.resume(returning: outcome) }
      continuations.removeAll()
    }
  }

  private actor UnloadResult {
    private var outcome: Result<RuntimeOperationCompletion, Error>?
    private var continuations:
      [CheckedContinuation<Result<RuntimeOperationCompletion, Error>, Never>] = []

    func wait() async throws -> RuntimeOperationCompletion {
      let outcome = if let outcome {
        outcome
      } else {
        await withCheckedContinuation { continuation in
          continuations.append(continuation)
        }
      }
      return try outcome.get()
    }

    func resolve(_ outcome: Result<RuntimeOperationCompletion, Error>) {
      guard self.outcome == nil else {
        return
      }
      self.outcome = outcome
      continuations.forEach { $0.resume(returning: outcome) }
      continuations.removeAll()
    }
  }

  private let supportedSchemaVersion: Int64
  private let backend: any RuntimeBackend
  private let eventHandler:
    @Sendable (RuntimeGenerationEvent) -> Void
  private let shutdownDeadlineFactory: any RuntimeShutdownDeadlineFactory
  private let shutdownWaitObserver: @Sendable () -> Void
  private let ordinaryUnloadAdmissionObserver: @Sendable () -> Void
  private var lifecycle = Lifecycle.ready
  private var nextShutdownToken: UInt64 = 0
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
    guard isReadyForRequests, unloadOperation == nil else {
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
      let backend = self.backend
      let task = Task {
        try await backend.loadModel(model)
      }
      modelState = .loading(request: model, token: token, task: task)
      do {
        let result = try await task.value
        guard isReadyForRequests else {
          throw RuntimeBoundaryError.runtimeUnavailable
        }
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
        guard isReadyForRequests else {
          throw RuntimeBoundaryError.runtimeUnavailable
        }
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
    guard isReadyForRequests, unloadOperation == nil else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    guard !cancelledGenerationIds.contains(generation.generationId) else {
      throw RuntimeBoundaryError.protocolMismatch
    }
    guard case .idle = generationState else {
      throw RuntimeBoundaryError.generationBusy
    }

    let backend = self.backend
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
      guard isReadyForRequests else {
        throw RuntimeBoundaryError.runtimeUnavailable
      }
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
      guard isReadyForRequests else {
        throw RuntimeBoundaryError.runtimeUnavailable
      }
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
    guard isReadyForRequests else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
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
    let backend = self.backend
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
      guard isReadyForRequests else {
        return acknowledgement
      }
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
    guard isReadyForRequests else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    if let unloadOperation {
      return try await finishUnload(unloadOperation)
    }

    let token = nextUnloadToken
    nextUnloadToken &+= 1
    let plan = makeTeardownPlan(reportCancellation: true)
    let task = Task { [weak self] in
      if let generationId = try await Self.settleTeardown(plan) {
        guard let cancellationTask =
          await self?.admitOrdinaryUnloadCancellation(
            token: token,
            generationId: generationId
          )
        else {
          throw RuntimeBoundaryError.runtimeUnavailable
        }
        let acknowledgement = try await cancellationTask.value
        guard acknowledgement.generationId == generationId else {
          throw RuntimeBoundaryError.protocolMismatch
        }
        guard acknowledgement.acknowledged else {
          throw RuntimeBoundaryError.generationBusy
        }
        await plan.cancellationHandler(acknowledgement.generationId)
      }
      guard let unloadTask = await self?.admitOrdinaryBackendUnload(token: token)
      else {
        throw RuntimeBoundaryError.runtimeUnavailable
      }
      return try await unloadTask.value
    }
    let operation = UnloadOperation(
      token: token,
      task: task,
      result: UnloadResult(),
      generationId: plan.generationId
    )
    unloadOperation = operation
    operation.observerTask = Task { [weak self, task] in
      do {
        let completion = try await task.value
        await self?.completeUnload(token: token, completion: completion)
      } catch {
        await self?.failUnload(token: token, error: error)
      }
    }
    return try await finishUnload(operation)
  }

  public func shutdown() async throws -> RuntimeOperationCompletion {
    switch lifecycle {
    case .disposed(let result):
      return try await waitForShutdownResult(result)
    case .shuttingDown(let operation):
      return try await waitForShutdownResult(operation.result)
    case .ready:
      let token = nextShutdownToken
      nextShutdownToken &+= 1
      let result = ShutdownResult()
      let operation = ShutdownOperation(token: token, result: result)
      lifecycle = .shuttingDown(operation)

      let deadline = shutdownDeadlineFactory.makeDeadline()
      let plan = ShutdownPlan(
        teardown: makeTeardownPlan(),
        existingUnloadResult: unloadOperation?.result
      )
      operation.deadlineTask = Task { [weak self, deadline] in
        guard await deadline.wait() else {
          return
        }
        await self?.expireShutdown(token: token)
      }
      operation.workerTask = Task { [weak self] in
        do {
          let completion: RuntimeOperationCompletion
          if let existingUnloadResult = plan.existingUnloadResult {
            completion = try await existingUnloadResult.wait()
          } else {
            let generationId = try await Self.settleTeardown(plan.teardown)
            if let generationId {
              guard let cancellationTask =
                await self?.admitShutdownCancellation(
                  token: token,
                  generationId: generationId
                )
              else {
                return
              }
              let acknowledgement = try await cancellationTask.value
              guard acknowledgement.generationId == generationId else {
                throw RuntimeBoundaryError.protocolMismatch
              }
              guard acknowledgement.acknowledged else {
                throw RuntimeBoundaryError.generationBusy
              }
            }
            guard let unloadTask = await self?.admitShutdownUnload(token: token)
            else {
              return
            }
            completion = try await unloadTask.value
          }
          await self?.finishShutdown(token: token, completion: completion)
        } catch {
          await self?.failShutdown(token: token)
        }
      }
      return try await waitForShutdownResult(result)
    }
  }

  private func waitForShutdownResult(
    _ result: ShutdownResult
  ) async throws -> RuntimeOperationCompletion {
    shutdownWaitObserver()
    return try await result.wait()
  }

  private var isReadyForRequests: Bool {
    if case .ready = lifecycle {
      return true
    }
    return false
  }

  private func makeTeardownPlan(
    reportCancellation: Bool = false
  ) -> TeardownPlan {
    let loadingTask: Task<RuntimeModelLoadResult, Error>? = if case .loading(
      _, _, let task
    ) = modelState {
      task
    } else {
      nil
    }
    let startingTask: Task<RuntimeGenerationAcknowledgement, Error>? =
      if case .starting(_, _, let task) = generationState {
        task
      } else {
        nil
      }
    let cancellationHandler:
      @Sendable (String) async -> Void
    if reportCancellation {
      cancellationHandler = { [weak self] generationId in
        await self?.recordTeardownCancellation(generationId)
      }
    } else {
      cancellationHandler = { _ in }
    }
    return TeardownPlan(
      backend: backend,
      loadingTask: loadingTask,
      startingTask: startingTask,
      cancellationTask: cancellationOperation?.task,
      cancellationGenerationId: cancellationOperation?.generationId,
      generationId: currentGenerationId,
      cancellationHandler: cancellationHandler
    )
  }

  private nonisolated static func settleTeardown(
    _ plan: TeardownPlan
  ) async throws -> String? {
    if let loadingTask = plan.loadingTask {
      _ = try await loadingTask.value
      try Task.checkCancellation()
    }
    if let startingTask = plan.startingTask {
      guard let acknowledgement = try? await startingTask.value,
        acknowledgement.accepted
      else {
        try Task.checkCancellation()
        return nil
      }
      try Task.checkCancellation()
    }
    if let cancellationTask = plan.cancellationTask {
      let acknowledgement = try await cancellationTask.value
      try Task.checkCancellation()
      guard acknowledgement.generationId == plan.cancellationGenerationId else {
        throw RuntimeBoundaryError.protocolMismatch
      }
      guard acknowledgement.acknowledged else {
        throw RuntimeBoundaryError.generationBusy
      }
      await plan.cancellationHandler(acknowledgement.generationId)
      return nil
    }
    try Task.checkCancellation()
    return plan.generationId
  }

  private func admitOrdinaryUnloadCancellation(
    token: UInt64,
    generationId: String
  ) -> Task<RuntimeCancellationAcknowledgement, Error>? {
    guard let operation = unloadOperation, operation.token == token else {
      return nil
    }
    guard isReadyForRequests || isShutdownInProgress else {
      return nil
    }
    let backend = self.backend
    let task = Task {
      try Task.checkCancellation()
      return try await backend.cancelGeneration(generationId: generationId)
    }
    operation.cancellationTask = task
    return task
  }

  private func admitOrdinaryBackendUnload(
    token: UInt64
  ) -> Task<RuntimeOperationCompletion, Error>? {
    ordinaryUnloadAdmissionObserver()
    guard let operation = unloadOperation, operation.token == token else {
      return nil
    }
    guard isReadyForRequests || isShutdownInProgress else {
      return nil
    }
    let backend = self.backend
    let task = Task {
      try Task.checkCancellation()
      return try await backend.unloadModel()
    }
    operation.backendUnloadTask = task
    return task
  }

  private var isShutdownInProgress: Bool {
    if case .shuttingDown = lifecycle {
      return true
    }
    return false
  }

  private func admitShutdownCancellation(
    token: UInt64,
    generationId: String
  ) -> Task<RuntimeCancellationAcknowledgement, Error>? {
    guard case .shuttingDown(let operation) = lifecycle,
      operation.token == token
    else {
      return nil
    }
    let backend = self.backend
    let task = Task {
      try Task.checkCancellation()
      return try await backend.cancelGeneration(generationId: generationId)
    }
    operation.cancellationTask = task
    return task
  }

  private func admitShutdownUnload(
    token: UInt64
  ) -> Task<RuntimeOperationCompletion, Error>? {
    guard case .shuttingDown(let operation) = lifecycle,
      operation.token == token
    else {
      return nil
    }
    let backend = self.backend
    let task = Task {
      try Task.checkCancellation()
      return try await backend.unloadModel()
    }
    operation.unloadTask = task
    return task
  }

  private func recordTeardownCancellation(_ generationId: String) {
    guard isReadyForRequests, generationToken(for: generationId) != nil else {
      return
    }
    let sequence = (lastGenerationSequence ?? -1) + 1
    generationState = .idle
    lastGenerationSequence = nil
    recordCancelledGeneration(generationId)
    eventHandler(
      RuntimeGenerationEvent(
        generationId: generationId,
        sequence: sequence,
        kind: .cancelled,
        failureCode: .cancelled,
        message: "The response was cancelled."
      )
    )
  }

  private func finishShutdown(
    token: UInt64,
    completion: RuntimeOperationCompletion
  ) async {
    guard case .shuttingDown(let operation) = lifecycle,
      operation.token == token
    else {
      return
    }
    operation.deadlineTask?.cancel()
    operation.workerTask = nil
    operation.deadlineTask = nil
    operation.cancellationTask = nil
    operation.unloadTask = nil
    resetStateAfterShutdown()
    lifecycle = .disposed(operation.result)
    await operation.result.resolve(.completed(completion))
  }

  private func failShutdown(token: UInt64) async {
    await disposeAfterShutdownDeadline(token: token)
  }

  private func expireShutdown(token: UInt64) async {
    await disposeAfterShutdownDeadline(token: token)
  }

  private func disposeAfterShutdownDeadline(token: UInt64) async {
    guard case .shuttingDown(let operation) = lifecycle,
      operation.token == token
    else {
      return
    }
    operation.workerTask?.cancel()
    operation.deadlineTask?.cancel()
    operation.cancellationTask?.cancel()
    operation.unloadTask?.cancel()
    operation.workerTask = nil
    operation.deadlineTask = nil
    operation.cancellationTask = nil
    operation.unloadTask = nil
    let pendingUnload = unloadOperation
    pendingUnload?.task.cancel()
    pendingUnload?.observerTask?.cancel()
    pendingUnload?.cancellationTask?.cancel()
    pendingUnload?.backendUnloadTask?.cancel()
    pendingUnload?.observerTask = nil
    pendingUnload?.cancellationTask = nil
    pendingUnload?.backendUnloadTask = nil
    resetStateAfterShutdown()
    lifecycle = .disposed(operation.result)
    await pendingUnload?.result.resolve(
      .failure(RuntimeBoundaryError.runtimeUnavailable)
    )
    await operation.result.resolve(.unavailable)
  }

  private func resetStateAfterShutdown() {
    modelState = .idle
    generationState = .idle
    cancellationOperation = nil
    unloadOperation = nil
    lastGenerationSequence = nil
    cancelledGenerationIds.removeAll()
  }

  private func completeUnload(
    token: UInt64,
    completion: RuntimeOperationCompletion
  ) async {
    guard let operation = unloadOperation, operation.token == token else {
      return
    }
    operation.observerTask = nil
    guard isReadyForRequests else {
      await operation.result.resolve(.success(completion))
      return
    }
    unloadOperation = nil
    if completion.completed {
      if
        let generationId = operation.generationId,
        generationToken(for: generationId) != nil
      {
        let sequence = (lastGenerationSequence ?? -1) + 1
        generationState = .idle
        lastGenerationSequence = nil
        recordCancelledGeneration(generationId)
        eventHandler(
          RuntimeGenerationEvent(
            generationId: generationId,
            sequence: sequence,
            kind: .cancelled,
            failureCode: .cancelled,
            message: "The response was cancelled."
          )
        )
      }
      modelState = .idle
      generationState = .idle
      lastGenerationSequence = nil
    }
    await operation.result.resolve(.success(completion))
  }

  private func failUnload(token: UInt64, error: Error) async {
    guard let operation = unloadOperation, operation.token == token else {
      return
    }
    operation.observerTask = nil
    guard isReadyForRequests else {
      await operation.result.resolve(.failure(error))
      return
    }
    unloadOperation = nil
    await operation.result.resolve(.failure(error))
  }

  private func finishUnload(
    _ operation: UnloadOperation
  ) async throws -> RuntimeOperationCompletion {
    try await operation.result.wait()
  }

  public func receiveGenerationEvent(_ event: RuntimeGenerationEvent) async {
    guard isReadyForRequests,
      generationToken(for: event.generationId) != nil
    else {
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

  /// Reports the runtime contract this coordinator speaks together with the
  /// capabilities its backend actually provides.
  public func handshake(
    request: RuntimeRequestEnvelope
  ) async throws -> RuntimeHandshakeResult {
    try validate(request)
    guard isReadyForRequests else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    let capabilities = await backend.capabilities
    return RuntimeHandshakeResult(
      schemaVersion: supportedSchemaVersion,
      runtimeName: capabilities.runtimeName,
      supportsStreaming: capabilities.supportsStreaming,
      supportsCancellation: capabilities.supportsCancellation
    )
  }

  /// Clears the conversation state the backend holds for one session.
  public func resetSession(
    request: RuntimeRequestEnvelope,
    sessionId: String
  ) async throws -> RuntimeOperationCompletion {
    try validate(request)
    guard isReadyForRequests else {
      throw RuntimeBoundaryError.runtimeUnavailable
    }
    return try await backend.resetSession(sessionId: sessionId)
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
