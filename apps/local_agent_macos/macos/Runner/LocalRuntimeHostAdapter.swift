import Dispatch
import AppKit
import EventKit
import Foundation
import MapKit
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
    eventBridge: GenerationEventBridge,
    modelAccess: ChosenModelAccess = ChosenModelAccess(),
    menuBar: MenuBarController? = nil,
    screenLook: ScreenLookController? = nil
  ) {
    self.panelController = panelController
    self.coordinator = coordinator
    self.eventBridge = eventBridge
    self.modelAccess = modelAccess
    self.menuBar = menuBar
    self.screenLook = screenLook
  }

  /// Takes the invited look at the screen, absent in the window tests.
  private let screenLook: ScreenLookController?

  /// The status-bar menu, which is told what to show rather than asking.
  ///
  /// Optional because the menu belongs to the running app and the window
  /// tests build this adapter without one.
  private let menuBar: MenuBarController?

  private let panelController: DesktopPanelControlling
  private let coordinator: InferenceCoordinator
  private let eventBridge: GenerationEventBridge
  private let modelAccess: ChosenModelAccess

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
    // The sandbox lets go of a chosen file at the end of the run it was chosen
    // in, so the permission written down then has to be taken up again before
    // anything tries to read gigabytes through it. A model inside the app's
    // own container needs none of this and is simply readable.
    modelAccess.beginReading(model.modelPath)
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
      systemInstruction: generation.systemInstruction,
      prompt: generation.prompt,
      context: generation.context,
      history: generation.history.map {
        RuntimeConversationTurn(
          role: $0.role == .user ? .user : .assistant,
          text: $0.text
        )
      },
      temperature: generation.temperature,
      topP: generation.topP,
      maxTokens: generation.maxTokens,
      seed: generation.seed,
      toolsJson: generation.toolsJson,
      toolResponsesJson: generation.toolResponsesJson,
      imagePath: generation.imagePath
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
        // Nothing is reading the file any more, and a sandboxed app that keeps
        // taking permissions without giving them back runs out of them.
        self.modelAccess.stopReadingEverything()
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
      guard panel.runModal() == .OK, let url = panel.url else {
        completion(.success(""))
        return
      }
      // This is the one moment the sandbox grants access to the file. Writing
      // the grant down here is what lets the model still be readable after a
      // restart, rather than the choice quietly reverting to the preview.
      self.modelAccess.remember(url)
      self.modelAccess.beginReading(url.path)
      completion(.success(url.path))
    }
  }

  func loginItemStatus(
    request: HostRequest,
    completion: @escaping (Result<HostLoginItemStatus, Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    // Off the main thread: these are XPC round trips to `smd`, and this
    // handler arrives on the platform thread, which is the one drawing.
    DispatchQueue.global(qos: .userInitiated).async {
      let status = LaunchAtLogin.status()
      DispatchQueue.main.async { completion(.success(status)) }
    }
  }

  func setLaunchAtLogin(
    request: HostRequest,
    enabled: Bool,
    completion: @escaping (Result<HostLoginItemStatus, Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      // `register` can raise the system's own consent UI, so this one can
      // sit for as long as the user takes to answer it.
      let status = LaunchAtLogin.set(enabled)
      DispatchQueue.main.async { completion(.success(status)) }
    }
  }

  func captureScreenLook(
    request: HostRequest,
    completion: @escaping (Result<HostScreenLookResult, Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    guard let screenLook else {
      completion(
        .success(HostScreenLookResult(status: .unavailable, path: ""))
      )
      return
    }
    Task {
      let outcome = await screenLook.capture()
      let result: HostScreenLookResult = switch outcome {
      case .captured(let path):
        HostScreenLookResult(status: .captured, path: path)
      case .denied:
        HostScreenLookResult(status: .denied, path: "")
      case .unavailable:
        HostScreenLookResult(status: .unavailable, path: "")
      case .failed:
        HostScreenLookResult(status: .failed, path: "")
      }
      completion(.success(result))
    }
  }

  func chooseTextFile(
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
      panel.title = "Choose a file to ask about"
      panel.message = "Pick the text Lulo should answer out of."
      panel.allowedContentTypes = [.plainText, .utf8PlainText, .text]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      // Backing out is an answer, not a failure.
      guard panel.runModal() == .OK, let url = panel.url else {
        completion(.success(""))
        return
      }
      completion(.success(url.path))
    }
  }

  /// One store for the process: EventKit keys the user's grant to it, and
  /// a fresh store per call would re-ask questions the user has answered.
  private static let eventStore = EKEventStore()

  func searchPlaces(
    request: HostRequest,
    query: String,
    completion: @escaping (Result<[HostPlaceHit], Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    let searchRequest = MKLocalSearch.Request()
    searchRequest.naturalLanguageQuery = query
    // No region and no location on purpose: the caller puts the city or
    // district in the query, and the search goes out exactly as typed —
    // the same query the user's own Maps app would send.
    MKLocalSearch(request: searchRequest).start { response, error in
      if let error {
        // Failed and empty read the same to the conversation — no places —
        // but not to whoever is diagnosing why.
        NSLog("Lulo tools: place search failed (%@)", String(describing: error))
        completion(.success([]))
        return
      }
      let hits = (response?.mapItems ?? []).compactMap {
        item -> HostPlaceHit? in
        guard let name = item.name, !name.isEmpty else { return nil }
        let address = item.placemark.title ?? ""
        return HostPlaceHit(name: name, address: address)
      }
      NSLog("Lulo tools: place search heard %d places", hits.count)
      completion(.success(hits))
    }
  }

  func readCalendar(
    request: HostRequest,
    startIso: String,
    endIso: String,
    completion: @escaping (Result<HostCalendarAnswer, Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    guard
      let start = formatter.date(from: String(startIso.prefix(19))),
      let end = formatter.date(from: String(endIso.prefix(19)))
    else {
      completion(.success(HostCalendarAnswer(authorized: true, events: [])))
      return
    }
    let deliver: (Bool) -> Void = { granted in
      guard granted else {
        completion(
          .success(HostCalendarAnswer(authorized: false, events: []))
        )
        return
      }
      let store = Self.eventStore
      let predicate = store.predicateForEvents(
        withStart: start,
        end: end,
        calendars: nil
      )
      let events = store.events(matching: predicate).map { event in
        HostCalendarEvent(
          title: event.title ?? "",
          startIso: formatter.string(from: event.startDate),
          endIso: formatter.string(from: event.endDate),
          calendar: event.calendar?.title ?? "",
          allDay: event.isAllDay
        )
      }
      NSLog("Lulo tools: calendar read %d events", events.count)
      completion(.success(HostCalendarAnswer(authorized: true, events: events)))
    }
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess, .authorized:
      deliver(true)
    case .denied, .restricted, .writeOnly:
      deliver(false)
    case .notDetermined:
      // The system's own dialog, asked at the moment the capability is
      // first wanted rather than at launch.
      if #available(macOS 14.0, *) {
        Self.eventStore.requestFullAccessToEvents { granted, _ in
          DispatchQueue.main.async { deliver(granted) }
        }
      } else {
        Self.eventStore.requestAccess(to: .event) { granted, _ in
          DispatchQueue.main.async { deliver(granted) }
        }
      }
    @unknown default:
      deliver(false)
    }
  }

  func setMenuBarState(request: HostRequest, state: HostMenuBarState) throws {
    try validatePanelRequest(request)
    guard let menuBar else {
      return
    }
    onMain {
      menuBar.apply(
        MenuBarController.State(
          conversations: state.conversations.map {
            (id: $0.conversationId, title: $0.title)
          },
          modelName: state.modelName,
          activity: state.labels.activity,
          canStartVoice: state.canStartVoice,
          labels: MenuBarController.Labels(
            show: state.labels.show,
            hide: state.labels.hide,
            talk: state.labels.talk,
            recent: state.labels.recent,
            quit: state.labels.quit
          )
        )
      )
    }
  }

  func saveTextFile(
    request: HostRequest,
    suggestedName: String,
    contents: String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    do {
      try validatePanelRequest(request)
    } catch {
      completion(.failure(error))
      return
    }
    onMain {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = suggestedName
      // Taken from what the caller asked to be called, not pinned to
      // markdown. This was written for the conversation export and a second
      // caller arrived wanting `.txt`; a panel restricted to `md` appends
      // the type it allows, so a transcript was saved as `名字.txt.md`.
      let suggestedType = UTType(
        filenameExtension: (suggestedName as NSString).pathExtension
      )
      if let suggestedType {
        panel.allowedContentTypes = [suggestedType]
      }
      // Cancelling is an answer, not a failure: the user decided not to.
      guard panel.runModal() == .OK, let url = panel.url else {
        completion(.success(""))
        return
      }
      // Written here rather than by handing the path back to Dart. The panel
      // grants access to this URL and to nothing else, and that grant belongs
      // to this process at this moment — a write attempted from the other
      // side of the channel lands outside it.
      do {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        completion(.success(url.path))
      } catch {
        completion(.failure(error))
      }
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
  ///
  /// Shared with the delegate, which reports the same geometry as an event
  /// whenever the user changes the window's frame.
  static func hostGeometry(
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
      orbExtent: Double(geometry.orb.width),
      fullScreen: geometry.fullScreen
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
      let geometry = self.panelController.beginTransition(
        to: target == .orb ? .orb : .expanded
      )
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
    modelAccess.stopReadingEverything()
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
        message: event.message,
        toolCallsJson: event.toolCallsJson
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
    case .toolCall:
      .toolCall
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
