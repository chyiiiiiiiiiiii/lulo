import Dispatch
import AppKit
import Foundation
import UniformTypeIdentifiers
import InferenceService

/// Bridges the generated Pigeon host boundary to the asynchronous
/// `InferenceCoordinator` actor.
///
/// Every lifecycle method returns immediately and resolves its Pigeon
/// completion once the actor answers, so model initialization never runs on
/// the main thread. Panel control stays synchronous because it only touches
/// AppKit.
final class LocalRuntimeDesktopHostApi: DesktopHostApi {
  init(
    panelController: DesktopPanelControlling,
    coordinator: InferenceCoordinator,
    eventBridge: GenerationEventBridge
  ) {
    self.panelController = panelController
    self.coordinator = coordinator
    self.eventBridge = eventBridge
  }

  private let panelController: DesktopPanelControlling
  private let coordinator: InferenceCoordinator
  private let eventBridge: GenerationEventBridge

  func handshake(
    request: HostRequest,
    completion: @escaping (Result<HostHandshakeResult, Error>) -> Void
  ) {
    let coordinator = self.coordinator
    let envelope = request.runtimeEnvelope
    Task {
      await resolve(completion) {
        let result = try await coordinator.handshake(request: envelope)
        return HostHandshakeResult(
          schemaVersion: result.schemaVersion,
          runtimeName: result.runtimeName,
          supportsStreaming: result.supportsStreaming,
          supportsCancellation: result.supportsCancellation
        )
      }
    }
  }

  func loadModel(
    request: HostRequest,
    model: HostModelRequest,
    completion: @escaping (Result<HostModelLoadResult, Error>) -> Void
  ) {
    let coordinator = self.coordinator
    let envelope = request.runtimeEnvelope
    let modelRequest = RuntimeModelRequest(
      modelId: model.modelId,
      modelPath: model.modelPath,
      contextSize: model.contextSize
    )
    Task {
      await resolve(completion) {
        let result = try await coordinator.loadModel(
          request: envelope,
          model: modelRequest
        )
        return HostModelLoadResult(
          modelId: result.modelId,
          loaded: result.loaded
        )
      }
    }
  }

  func startGeneration(
    request: HostRequest,
    generation: HostGenerationRequest,
    completion: @escaping (Result<HostGenerationAcknowledgement, Error>) -> Void
  ) {
    let coordinator = self.coordinator
    let envelope = request.runtimeEnvelope
    let generationRequest = RuntimeGenerationRequest(
      generationId: generation.generationId,
      sessionId: generation.sessionId,
      prompt: generation.prompt,
      context: generation.context,
      temperature: generation.temperature,
      topP: generation.topP,
      maxTokens: generation.maxTokens,
      seed: generation.seed
    )
    Task {
      await resolve(completion) {
        let result = try await coordinator.startGeneration(
          request: envelope,
          generation: generationRequest
        )
        return HostGenerationAcknowledgement(
          generationId: result.generationId,
          accepted: result.accepted
        )
      }
    }
  }

  func cancelGeneration(
    request: HostRequest,
    generationId: String,
    completion: @escaping (Result<HostCancellationAcknowledgement, Error>) -> Void
  ) {
    let coordinator = self.coordinator
    let eventBridge = self.eventBridge
    let envelope = request.runtimeEnvelope
    Task {
      await resolve(completion) {
        let result = try await coordinator.cancelGeneration(
          request: envelope,
          generationId: generationId
        )
        if result.acknowledged {
          // The bridge tracks one active generation at a time. Engaging its
          // fence marks this generation stale, so anything the runtime still
          // emits for it is dropped, and returns the bridge to idle. Skipping
          // this would leave the bridge pinned to the cancelled generation,
          // which then rejects the next turn's started event and leaves that
          // turn producing nothing at all.
          eventBridge.cancelGeneration(generationId: result.generationId)
        }
        return HostCancellationAcknowledgement(
          generationId: result.generationId,
          acknowledged: result.acknowledged
        )
      }
    }
  }

  func resetSession(
    request: HostRequest,
    sessionId: String,
    completion: @escaping (Result<HostOperationCompletion, Error>) -> Void
  ) {
    let coordinator = self.coordinator
    let envelope = request.runtimeEnvelope
    Task {
      await resolve(completion) {
        let result = try await coordinator.resetSession(
          request: envelope,
          sessionId: sessionId
        )
        return HostOperationCompletion(completed: result.completed)
      }
    }
  }

  func unloadModel(
    request: HostRequest,
    completion: @escaping (Result<HostOperationCompletion, Error>) -> Void
  ) {
    let coordinator = self.coordinator
    let envelope = request.runtimeEnvelope
    Task {
      await resolve(completion) {
        let result = try await coordinator.unloadModel(request: envelope)
        return HostOperationCompletion(completed: result.completed)
      }
    }
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

  func setPresentationMode(
    request: HostRequest,
    mode: HostPresentationMode
  ) throws {
    try validatePanelRequest(request)
    let resolved: DesktopPresentationMode =
      mode == .orb ? .orb : .expanded
    onMain { self.panelController.setPresentationMode(resolved) }
  }

  func chooseModelFile(
    request: HostRequest,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    onMain {
      let panel = NSOpenPanel()
      panel.title = "Choose a model"
      panel.message = "Pick the LiteRT-LM file Lulo should think with."
      // The extension is not one the system knows, so it is declared here
      // rather than looked up.
      if let litertlm = UTType(filenameExtension: "litertlm") {
        panel.allowedContentTypes = [litertlm]
      }
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      // Cancelling is an answer, not a failure: it means the user kept what
      // they already had.
      let chosen = panel.runModal() == .OK ? panel.url?.path ?? "" : ""
      completion(.success(chosen))
    }
  }

  func setWindowBehaviour(
    request: HostRequest,
    keepOrbOnTop: Bool,
    followAcrossSpaces: Bool
  ) throws {
    try validatePanelRequest(request)
    onMain {
      self.panelController.setWindowBehaviour(
        keepOrbOnTop: keepOrbOnTop,
        followAcrossSpaces: followAcrossSpaces
      )
    }
  }

  func presentationGeometry(request: HostRequest) throws -> HostTransitionGeometry {
    try validatePanelRequest(request)
    var geometry: DesktopTransitionGeometry?
    onMain { geometry = self.panelController.currentGeometry() }
    return Self.hostGeometry(geometry!)
  }

  /// Restates a stage geometry in the shape the app is handed.
  private static func hostGeometry(
    _ geometry: DesktopTransitionGeometry
  ) -> HostTransitionGeometry {
    HostTransitionGeometry(
      width: Double(geometry.size.width),
      height: Double(geometry.size.height),
      conversationLeft: Double(geometry.conversation.minX),
      conversationTop: Double(geometry.conversation.minY),
      conversationWidth: Double(geometry.conversation.width),
      conversationHeight: Double(geometry.conversation.height),
      orbLeft: Double(geometry.orb.minX),
      orbTop: Double(geometry.orb.minY),
      orbExtent: Double(geometry.orb.width)
    )
  }

  func beginPresentationTransition(
    request: HostRequest,
    target: HostPresentationMode,
    completion: @escaping (Result<HostTransitionGeometry, Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    onMain {
      let geometry = self.panelController.beginTransition()
      completion(.success(Self.hostGeometry(geometry)))
    }
  }

  func endPresentationTransition(
    request: HostRequest,
    mode: HostPresentationMode
  ) throws {
    try validatePanelRequest(request)
    let resolved: DesktopPresentationMode = mode == .orb ? .orb : .expanded
    onMain { self.panelController.endTransition(resolved) }
  }

  func moveWindowBy(
    request: HostRequest,
    deltaX: Double,
    deltaY: Double
  ) throws {
    try validatePanelRequest(request)
    onMain {
      self.panelController.moveBy(
        deltaX: CGFloat(deltaX),
        deltaY: CGFloat(deltaY)
      )
    }
  }

  /// Stops delivering events to Flutter, then drains the coordinator within a
  /// bounded window so termination cannot hang on a running generation.
  ///
  /// The bridge is disposed first: it is the only component that hops to the
  /// main queue, so shutting it down before waiting keeps this bounded wait
  /// from deadlocking against the thread it is called on.
  func dispose() {
    eventBridge.dispose()
    let coordinator = self.coordinator
    let drained = DispatchSemaphore(value: 0)
    Task {
      _ = try? await coordinator.shutdown()
      drained.signal()
    }
    _ = drained.wait(timeout: .now() + .milliseconds(2000))
  }

  private func resolve<T>(
    _ completion: @escaping (Result<T, Error>) -> Void,
    _ operation: () async throws -> T
  ) async {
    do {
      completion(.success(try await operation()))
    } catch {
      completion(.failure(makePigeonError(for: error)))
    }
  }

  private func validatePanelRequest(_ request: HostRequest) throws {
    guard
      request.schemaVersion == 2,
      !request.requestId.isEmpty,
      request.timestampMicros > 0
    else {
      throw makePigeonError(for: RuntimeBoundaryError.protocolMismatch)
    }
  }

  private func onMain(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.sync(execute: operation)
    }
  }
}

/// Maps any runtime error onto the stable, non-leaking Pigeon failure code.
private func makePigeonError(for error: Error) -> PigeonError {
  let failure = safeRuntimeFailure(for: error)
  return PigeonError(
    code: failure.code,
    message: failure.message,
    details: nil
  )
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
