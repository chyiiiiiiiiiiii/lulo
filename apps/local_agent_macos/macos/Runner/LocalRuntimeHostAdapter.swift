import Dispatch
import Foundation
import InferenceService

final class LocalRuntimeDesktopHostApi: DesktopHostApi {
  init(
    panelController: DesktopPanelControlling,
    coordinator: LocalModelRuntimeCoordinator,
    eventBridge: GenerationEventBridge
  ) {
    self.panelController = panelController
    self.coordinator = coordinator
    self.eventBridge = eventBridge
  }

  private let panelController: DesktopPanelControlling
  private let coordinator: LocalModelRuntimeCoordinator
  private let eventBridge: GenerationEventBridge

  func handshake(request: HostRequest) throws -> HostHandshakeResult {
    let result = try translate {
      try coordinator.handshake(request: request.runtimeEnvelope)
    }
    return HostHandshakeResult(
      schemaVersion: result.schemaVersion,
      runtimeName: result.runtimeName,
      supportsStreaming: result.supportsStreaming,
      supportsCancellation: result.supportsCancellation
    )
  }

  func loadModel(
    request: HostRequest,
    model: HostModelRequest
  ) throws -> HostModelLoadResult {
    let result = try translate {
      try coordinator.loadModel(
        request: request.runtimeEnvelope,
        model: RuntimeModelRequest(
          modelId: model.modelId,
          modelPath: model.modelPath,
          contextSize: model.contextSize
        )
      )
    }
    return HostModelLoadResult(modelId: result.modelId, loaded: result.loaded)
  }

  func startGeneration(
    request: HostRequest,
    generation: HostGenerationRequest
  ) throws -> HostGenerationAcknowledgement {
    let result = try translate {
      try coordinator.startGeneration(
        request: request.runtimeEnvelope,
        generation: RuntimeGenerationRequest(
          generationId: generation.generationId,
          sessionId: generation.sessionId,
          prompt: generation.prompt,
          context: generation.context,
          temperature: generation.temperature,
          topP: generation.topP,
          maxTokens: generation.maxTokens,
          seed: generation.seed
        )
      )
    }
    return HostGenerationAcknowledgement(
      generationId: result.generationId,
      accepted: result.accepted
    )
  }

  func cancelGeneration(
    request: HostRequest,
    generationId: String
  ) throws -> HostCancellationAcknowledgement {
    let result = try translate {
      try coordinator.cancelGeneration(
        request: request.runtimeEnvelope,
        generationId: generationId
      )
    }
    return HostCancellationAcknowledgement(
      generationId: result.generationId,
      acknowledged: result.acknowledged
    )
  }

  func resetSession(
    request: HostRequest,
    sessionId: String
  ) throws -> HostOperationCompletion {
    let result = try translate {
      try coordinator.resetSession(
        request: request.runtimeEnvelope,
        sessionId: sessionId
      )
    }
    return HostOperationCompletion(completed: result.completed)
  }

  func unloadModel(
    request: HostRequest
  ) throws -> HostOperationCompletion {
    let result = try translate {
      try coordinator.unloadModel(request: request.runtimeEnvelope)
    }
    return HostOperationCompletion(completed: result.completed)
  }

  func showPanel(request: HostRequest) throws {
    try validatePanelRequest(request)
    onMain { self.panelController.show() }
  }

  func hidePanel(request: HostRequest) throws {
    try validatePanelRequest(request)
    onMain { self.panelController.hide() }
  }

  func togglePanel(request: HostRequest) throws {
    try validatePanelRequest(request)
    onMain { self.panelController.toggle() }
  }

  func dispose() {
    eventBridge.dispose()
  }

  private func translate<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch {
      throw pigeonError(for: error)
    }
  }

  private func validatePanelRequest(_ request: HostRequest) throws {
    guard
      request.schemaVersion == 2,
      !request.requestId.isEmpty,
      request.timestampMicros > 0
    else {
      throw pigeonError(for: RuntimeBoundaryError.protocolMismatch)
    }
  }

  private func pigeonError(for error: Error) -> PigeonError {
    let failure = safeRuntimeFailure(for: error)
    return PigeonError(
      code: failure.code,
      message: failure.message,
      details: nil
    )
  }

  private func onMain(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.sync(execute: operation)
    }
  }
}

final class PigeonGenerationEventSink: RuntimeGenerationEventSink {
  init(
    api: DesktopHostEventApi,
    dispatcher: RuntimeEventDispatching = MainQueueRuntimeEventDispatcher()
  ) {
    self.api = api
    self.dispatcher = dispatcher
  }

  private let api: DesktopHostEventApi
  private let dispatcher: RuntimeEventDispatching

  func send(_ event: RuntimeGenerationEvent) {
    dispatcher.dispatch { [weak self] in
      self?.sendOnMain(event)
    }
  }

  private func sendOnMain(_ event: RuntimeGenerationEvent) {
    api.onGenerationEvent(
      event: HostGenerationEvent(
        schemaVersion: 2,
        generationId: event.generationId,
        sequence: event.sequence,
        type: event.kind.hostType,
        delta: event.delta,
        failureCode: event.failureCode?.hostCode,
        message: event.message
      ),
      completion: { _ in }
    )
  }
}

final class MainQueueRuntimeEventScheduler: RuntimeEventScheduling {
  func schedule(
    afterMilliseconds delayMilliseconds: Int,
    _ operation: @escaping () -> Void
  ) -> RuntimeScheduledTask {
    let workItem = DispatchWorkItem(block: operation)
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(delayMilliseconds),
      execute: workItem
    )
    return DispatchRuntimeScheduledTask(workItem: workItem)
  }
}

private final class DispatchRuntimeScheduledTask: RuntimeScheduledTask {
  init(workItem: DispatchWorkItem) {
    self.workItem = workItem
  }

  private let workItem: DispatchWorkItem

  func cancel() {
    workItem.cancel()
  }
}

private extension HostRequest {
  var runtimeEnvelope: RuntimeRequestEnvelope {
    RuntimeRequestEnvelope(
      schemaVersion: schemaVersion,
      requestId: requestId,
      timestampMicros: timestampMicros
    )
  }
}

private extension RuntimeGenerationEventKind {
  var hostType: HostGenerationEventType {
    switch self {
    case .started:
      .started
    case .delta:
      .delta
    case .completed:
      .completed
    case .cancelled:
      .cancelled
    case .failed:
      .failed
    }
  }
}

private extension RuntimeFailureCode {
  var hostCode: HostFailureCode {
    switch self {
    case .modelNotInstalled:
      .modelNotInstalled
    case .modelLoadFailed:
      .modelLoadFailed
    case .runtimeUnavailable:
      .runtimeUnavailable
    case .generationBusy:
      .generationBusy
    case .generationFailed:
      .generationFailed
    case .cancelled:
      .cancelled
    case .protocolMismatch:
      .protocolMismatch
    }
  }
}
