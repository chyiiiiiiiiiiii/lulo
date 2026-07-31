import Dispatch
import Foundation
@testable import LiteRTLM
import XCTest

@testable import InferenceService

final class LocalModelRuntimeTests: XCTestCase {
  func testConversationMaxOutputTokensPropagatesValidatedValue() throws {
    var recordedValues: [Int32] = []

    try applyConversationMaxOutputTokens(128) { value in
      recordedValues.append(value)
    }

    XCTAssertEqual(recordedValues, [128])
  }

  func testConversationMaxOutputTokensOmitsUnsetValue() throws {
    var recordedValues: [Int32] = []

    try applyConversationMaxOutputTokens(nil) { value in
      recordedValues.append(value)
    }

    XCTAssertTrue(recordedValues.isEmpty)
  }

  func testConversationMaxOutputTokensRejectsInvalidValues() {
    let invalidValues = [0, -1, Int(Int32.max) + 1]

    for value in invalidValues {
      XCTAssertThrowsError(
        try applyConversationMaxOutputTokens(value) { _ in }
      ) { error in
        XCTAssertEqual(
          error as? LiteRTLMError,
          .conversation(.invalidMaxOutputTokens)
        )
      }
    }
  }

  func testLiteRTLMBackendMapsLoadRequestAndRejectsMissingModel() async throws {
    let modelDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: modelDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: modelDirectory) }
    let modelURL = modelDirectory.appendingPathComponent("model.litertlm")
    XCTAssertTrue(FileManager.default.createFile(atPath: modelURL.path, contents: Data([0])))
    let driver = LiteRTLMRuntimeDriverSpy()
    let backend = LiteRTLMRuntimeBackend(
      configuration: LiteRTLMRuntimeConfiguration(
        primaryBackend: .gpu,
        enableCPUFallback: true,
        cpuFallbackThreadCount: 4,
        cacheDirectory: "/tmp/litert-runtime-tests",
        topK: 32
      ),
      eventRelay: RuntimeGenerationEventRelay(),
      driverFactory: FixedLiteRTLMRuntimeDriverFactory(driver: driver)
    )

    let result = try await backend.loadModel(
      RuntimeModelRequest(
        modelId: "gemma",
        modelPath: modelURL.path,
        contextSize: 4096
      )
    )

    XCTAssertEqual(
      result,
      RuntimeModelLoadResult(modelId: "gemma", loaded: true)
    )
    let loadRequests = await driver.loadRequests
    XCTAssertEqual(
      loadRequests,
      [
        LiteRTLMDriverLoadRequest(
          modelPath: modelURL.path,
          backend: .gpu,
          maxNumTokens: 4096,
          cacheDirectory: "/tmp/litert-runtime-tests"
        )
      ]
    )

    do {
      _ = try await backend.unloadModel()
      _ = try await backend.loadModel(
        RuntimeModelRequest(
          modelId: "missing",
          modelPath: modelDirectory
            .appendingPathComponent("missing.litertlm").path,
          contextSize: 4096
        )
      )
      XCTFail("Expected a missing model to be rejected")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .modelNotInstalled)
    }
    let finalLoadRequestCount = await driver.loadRequests.count
    XCTAssertEqual(finalLoadRequestCount, 1)
  }

  func testLiteRTLMBackendStartsPromptlyAndEmitsOrderedEvents() async throws {
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-7",
      prompt: "Hello",
      context: ["system fact", "prior turn"],
      history: [
        RuntimeConversationTurn(role: .user, text: "asked"),
        RuntimeConversationTurn(role: .assistant, text: "answered"),
      ],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 16,
      seed: 7
    )

    let acknowledgement = try await harness.backend.startGeneration(generation)

    XCTAssertEqual(
      acknowledgement,
      RuntimeGenerationAcknowledgement(
        generationId: "generation-1",
        accepted: true
      )
    )
    await harness.driver.waitForGenerationCall()
    let generationRequests = await harness.driver.generationRequests
    XCTAssertEqual(
      generationRequests,
      [
        LiteRTLMDriverGenerationRequest(
          sessionId: "session-7",
          prompt: "Hello",
          history: [
            RuntimeConversationTurn(role: .user, text: "asked"),
            RuntimeConversationTurn(role: .assistant, text: "answered"),
          ],
          extraContext: ["context": ["system fact", "prior turn"]],
          sampler: LiteRTLMSamplerFingerprint(
            topK: 32,
            topP: 0.9,
            temperature: 0.25,
            seed: 7
          ),
          maxOutputTokens: 16
        )
      ]
    )
    let completedBeforeRelease = await harness.driver.generationCompleted
    XCTAssertFalse(completedBeforeRelease)

    await harness.driver.emitChunk("Hel")
    await harness.driver.emitChunk("lo")
    await harness.driver.finishGeneration()
    await harness.events.waitForCount(4)

    let orderedEvents = await harness.events.events
    XCTAssertEqual(orderedEvents, [
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      ),
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "Hel"
      ),
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .delta,
        delta: "lo"
      ),
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 3,
        kind: .completed
      ),
    ])
  }

  func testLiteRTLMBackendDrainsCancelledGenerationBeforeTheNext()
    async throws {
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    _ = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-1",
        sessionId: "session-1",
        prompt: "Hello",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 16,
        seed: 7
      )
    )
    await harness.driver.waitForGenerationCall()
    await harness.driver.emitChunk("partial")
    await harness.events.waitForCount(2)

    _ = try await harness.backend.cancelGeneration(generationId: "generation-1")
    await harness.events.waitForCount(3)

    // LiteRT-LM v0.14.0 never finishes a cancelled task: CancelProcess leaves
    // one active task in its callback pool forever, which wedges the engine so
    // hard that even unloadModel blocks. The driver cancel must therefore stay
    // unused, and the abandoned decode is drained instead.
    let cancelledSessionIds = await harness.driver.cancelledSessionIds
    XCTAssertEqual(cancelledSessionIds, [])

    let second = Task {
      try await harness.backend.startGeneration(
        RuntimeGenerationRequest(
        generationId: "generation-2",
        sessionId: "session-1",
        prompt: "Hello",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 16,
        seed: 7
      )
      )
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    let startedWhileDraining = await harness.driver.generationRequests.count
    XCTAssertEqual(
      startedWhileDraining,
      1,
      "A new generation must not reach the engine while it is draining."
    )

    await harness.driver.finishGeneration()
    let acknowledgement = try await second.value
    XCTAssertTrue(acknowledgement.accepted)
    // The acknowledgement precedes the driver call, which the generation task
    // makes, so observe the call rather than assuming it already happened.
    var startedAfterDrain = await harness.driver.generationRequests.count
    let deadline = Date().addingTimeInterval(5)
    while startedAfterDrain < 2, Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
      startedAfterDrain = await harness.driver.generationRequests.count
    }
    XCTAssertEqual(startedAfterDrain, 2)
  }

  func testLiteRTLMBackendCancellationEmitsOneTerminalAndFreesTheSlot()
    async throws {
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    _ = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-1",
        sessionId: "session-1",
        prompt: "Hello",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 16,
        seed: 7
      )
    )
    await harness.driver.waitForGenerationCall()
    await harness.driver.emitChunk("kept")
    await harness.events.waitForCount(2)

    _ = try await harness.backend.cancelGeneration(generationId: "generation-1")
    await harness.events.waitForCount(3)

    let kinds = await harness.events.events.map(\.kind)
    XCTAssertEqual(
      kinds,
      [.started, .delta, .cancelled],
      "Cancellation must emit exactly one cancelled terminal event."
    )

    await harness.driver.emitChunk("late")
    await Task.yield()
    let settledKinds = await harness.events.events.map(\.kind)
    XCTAssertEqual(
      settledKinds,
      [.started, .delta, .cancelled],
      "A late chunk must not follow the cancelled terminal."
    )

    // Without a terminal event the coordinator never releases the slot, so a
    // cancelled turn would permanently block every later generation. The
    // abandoned decode still owns the engine, so let it drain first; the
    // ordering itself is pinned by the dedicated drain test.
    await harness.driver.finishGeneration()
    let next = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-2",
        sessionId: "session-1",
        prompt: "Again",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 16,
        seed: 7
      )
    )
    XCTAssertTrue(next.accepted, "The next generation must be accepted.")
  }

  func testLiteRTLMBackendCancellationFencesLateChunks() async throws {
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "Hello",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 16,
      seed: 7
    )
    _ = try await harness.backend.startGeneration(generation)
    await harness.driver.waitForGenerationCall()
    await harness.driver.emitChunk("kept")
    await harness.events.waitForCount(2)

    let acknowledgement = try await harness.backend.cancelGeneration(
      generationId: "generation-1"
    )
    await harness.driver.emitChunk("late")
    await Task.yield()

    XCTAssertEqual(
      acknowledgement,
      RuntimeCancellationAcknowledgement(
        generationId: "generation-1",
        acknowledged: true
      )
    )
    let cancelledSessionIds = await harness.driver.cancelledSessionIds
    let deliveredDeltas = await harness.events.events.compactMap(\.delta)
    // Fencing is what hides the late chunk, not the runtime's own cancel.
    // LiteRT-LM v0.14.0's CancelProcess wedges the engine permanently, so it
    // is deliberately never invoked.
    XCTAssertEqual(cancelledSessionIds, [])
    XCTAssertEqual(
      deliveredDeltas,
      ["kept"]
    )
  }

  private func makeLiteRTLMBackendHarness() async throws
    -> LiteRTLMBackendTestHarness
  {
    let modelDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: modelDirectory,
      withIntermediateDirectories: true
    )
    let modelURL = modelDirectory.appendingPathComponent("model.litertlm")
    XCTAssertTrue(FileManager.default.createFile(atPath: modelURL.path, contents: Data([0])))
    let driver = LiteRTLMRuntimeDriverSpy()
    let relay = RuntimeGenerationEventRelay()
    let events = AsyncRuntimeEventRecorder()
    await relay.attach { event in
      await events.record(event)
    }
    let backend = LiteRTLMRuntimeBackend(
      configuration: LiteRTLMRuntimeConfiguration(
        primaryBackend: .gpu,
        enableCPUFallback: true,
        cpuFallbackThreadCount: 4,
        cacheDirectory: "/tmp/litert-runtime-tests",
        topK: 32
      ),
      eventRelay: relay,
      driverFactory: FixedLiteRTLMRuntimeDriverFactory(driver: driver)
    )
    _ = try await backend.loadModel(
      RuntimeModelRequest(
        modelId: "gemma",
        modelPath: modelURL.path,
        contextSize: 64
      )
    )
    return LiteRTLMBackendTestHarness(
      backend: backend,
      driver: driver,
      events: events,
      modelDirectory: modelDirectory
    )
  }

  func testMainQueueDispatcherQueuesOffMainWorkInOrder() {
    var queued: [() -> Void] = []
    var delivered: [Int] = []
    let dispatcher = MainQueueRuntimeEventDispatcher(
      isMainThread: { false },
      enqueueOnMain: { queued.append($0) }
    )

    dispatcher.dispatch { delivered.append(1) }
    dispatcher.dispatch { delivered.append(2) }

    XCTAssertTrue(delivered.isEmpty)
    XCTAssertEqual(queued.count, 2)
    queued.forEach { $0() }
    XCTAssertEqual(delivered, [1, 2])
  }

  func testMainQueueDispatcherDeliversInlineWhenAlreadyMain() {
    var queued: [() -> Void] = []
    var delivered = false
    let dispatcher = MainQueueRuntimeEventDispatcher(
      isMainThread: { true },
      enqueueOnMain: { queued.append($0) }
    )

    dispatcher.dispatch { delivered = true }

    XCTAssertTrue(delivered)
    XCTAssertTrue(queued.isEmpty)
  }

  func testMapsEveryOperationErrorAndUnknownErrorToSafeFailure() {
    let cases: [(Error, RuntimeSafeFailure)] = [
      (
        RuntimeBoundaryError.modelNotInstalled,
        RuntimeSafeFailure(
          code: "modelNotInstalled",
          message: "The local model is not installed."
        )
      ),
      (
        RuntimeBoundaryError.modelLoadFailed,
        RuntimeSafeFailure(
          code: "modelLoadFailed",
          message: "The local model could not be loaded."
        )
      ),
      (
        RuntimeBoundaryError.runtimeUnavailable,
        RuntimeSafeFailure(
          code: "runtimeUnavailable",
          message: "Local inference is unavailable."
        )
      ),
      (
        RuntimeBoundaryError.generationBusy,
        RuntimeSafeFailure(
          code: "generationBusy",
          message: "Another response is already being generated."
        )
      ),
      (
        RuntimeBoundaryError.generationFailed,
        RuntimeSafeFailure(
          code: "generationFailed",
          message: "Local inference failed."
        )
      ),
      (
        RuntimeBoundaryError.cancelled,
        RuntimeSafeFailure(
          code: "cancelled",
          message: "The response was cancelled."
        )
      ),
      (
        RuntimeBoundaryError.protocolMismatch,
        RuntimeSafeFailure(
          code: "protocolMismatch",
          message: "The desktop host protocol is incompatible."
        )
      ),
      (
        PrivateBackendError(
          diagnostic: "/private/model.bin prompt=private user text"
        ),
        RuntimeSafeFailure(
          code: "runtimeUnavailable",
          message: "Local inference is unavailable."
        )
      ),
    ]

    for (error, expected) in cases {
      XCTAssertEqual(safeRuntimeFailure(for: error), expected)
    }
  }

  func testRejectsSchemaMismatchBeforeBackendInvocation() {
    let backend = RecordingLocalModelRuntimeBackend()
    let coordinator = LocalModelRuntimeCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 3,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "deterministic-model",
      modelPath: "/models/deterministic.bin",
      contextSize: 4096
    )

    XCTAssertThrowsError(
      try coordinator.loadModel(request: request, model: model)
    ) { error in
      XCTAssertEqual(error as? RuntimeBoundaryError, .protocolMismatch)
    }
    XCTAssertEqual(backend.invocationCount, 0)
  }

  func testRejectsInvalidEnvelopeBeforeEveryBackendOperation() {
    typealias Invocation = (
      LocalModelRuntimeCoordinator,
      RuntimeRequestEnvelope
    ) throws -> Void
    let operations: [(name: String, invoke: Invocation)] = [
      (
        "handshake",
        { coordinator, request in
          _ = try coordinator.handshake(request: request)
        }
      ),
      (
        "loadModel",
        { coordinator, request in
          _ = try coordinator.loadModel(
            request: request,
            model: RuntimeModelRequest(
              modelId: "model-1",
              modelPath: "/private/model.bin",
              contextSize: 4096
            )
          )
        }
      ),
      (
        "startGeneration",
        { coordinator, request in
          _ = try coordinator.startGeneration(
            request: request,
            generation: RuntimeGenerationRequest(
              generationId: "generation-1",
              sessionId: "session-1",
              prompt: "private prompt",
              context: ["private context"],
              temperature: 0.25,
              topP: 0.9,
              maxTokens: 128,
              seed: 7
            )
          )
        }
      ),
      (
        "cancelGeneration",
        { coordinator, request in
          _ = try coordinator.cancelGeneration(
            request: request,
            generationId: "generation-1"
          )
        }
      ),
      (
        "resetSession",
        { coordinator, request in
          _ = try coordinator.resetSession(
            request: request,
            sessionId: "session-1"
          )
        }
      ),
      (
        "unloadModel",
        { coordinator, request in
          _ = try coordinator.unloadModel(request: request)
        }
      ),
    ]
    let invalidRequests: [(name: String, request: RuntimeRequestEnvelope)] = [
      (
        "schema mismatch",
        RuntimeRequestEnvelope(
          schemaVersion: 3,
          requestId: "request-1",
          timestampMicros: 1
        )
      ),
      (
        "empty request ID",
        RuntimeRequestEnvelope(
          schemaVersion: 2,
          requestId: "",
          timestampMicros: 1
        )
      ),
      (
        "zero timestamp",
        RuntimeRequestEnvelope(
          schemaVersion: 2,
          requestId: "request-1",
          timestampMicros: 0
        )
      ),
      (
        "negative timestamp",
        RuntimeRequestEnvelope(
          schemaVersion: 2,
          requestId: "request-1",
          timestampMicros: -1
        )
      ),
    ]

    for invalidRequest in invalidRequests {
      for operation in operations {
        let backend = RecordingLocalModelRuntimeBackend()
        let coordinator = LocalModelRuntimeCoordinator(
          supportedSchemaVersion: 2,
          backend: backend
        )
        let context = "\(invalidRequest.name): \(operation.name)"

        XCTAssertThrowsError(
          try operation.invoke(coordinator, invalidRequest.request),
          context
        ) { error in
          XCTAssertEqual(
            error as? RuntimeBoundaryError,
            .protocolMismatch,
            context
          )
        }
        XCTAssertEqual(backend.invocations, [], context)
      }
    }
  }

  func testOverlappingSameModelLoadsShareOneBackendLoadAndResult() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let admissionGate = AsyncAdmissionGate(requiredArrivals: 2)

    async let first: RuntimeModelLoadResult = {
      await admissionGate.arriveAndWait()
      return try await coordinator.loadModel(request: request, model: model)
    }()
    async let second: RuntimeModelLoadResult = {
      await admissionGate.arriveAndWait()
      return try await coordinator.loadModel(request: request, model: model)
    }()

    await admissionGate.waitUntilAllArrive()
    await admissionGate.open()
    await backend.waitForLoadCall()
    let inFlightLoadCount = await backend.loadCallCount
    XCTAssertEqual(inFlightLoadCount, 1)
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )

    let results = try await [first, second]
    XCTAssertEqual(results, [
      RuntimeModelLoadResult(modelId: model.modelId, loaded: true),
      RuntimeModelLoadResult(modelId: model.modelId, loaded: true),
    ])
    let loadCallCount = await backend.loadCallCount
    XCTAssertEqual(loadCallCount, 1)
  }

  func testSecondGenerationIsRejectedWhileFirstStartIsInFlight() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )
    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult

    async let firstAcknowledgement = coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )
    await backend.waitForStartCall(count: 1)

    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: secondGeneration
      )
      XCTFail("Expected the second generation to be rejected")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .generationBusy)
    }

    await backend.completeStart(
      generationId: firstGeneration.generationId,
      with: RuntimeGenerationAcknowledgement(
        generationId: firstGeneration.generationId,
        accepted: true
      )
    )
    let acknowledgement = try await firstAcknowledgement
    XCTAssertEqual(
      acknowledgement,
      RuntimeGenerationAcknowledgement(
        generationId: firstGeneration.generationId,
        accepted: true
      )
    )
    let startCallCount = await backend.startCallCount
    XCTAssertEqual(startCallCount, 1)
  }

  func testTerminalEventReleasesGenerationSlotForNextRequest() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )
    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult

    async let firstAcknowledgement = coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )
    await backend.waitForStartCall(count: 1)
    await backend.completeStart(
      generationId: firstGeneration.generationId,
      with: RuntimeGenerationAcknowledgement(
        generationId: firstGeneration.generationId,
        accepted: true
      )
    )
    _ = try await firstAcknowledgement

    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: firstGeneration.generationId,
        sequence: 1,
        kind: .completed
      )
    )

    async let secondAcknowledgement = coordinator.startGeneration(
      request: request,
      generation: secondGeneration
    )
    await backend.waitForStartCall(count: 2)
    await backend.completeStart(
      generationId: secondGeneration.generationId,
      with: RuntimeGenerationAcknowledgement(
        generationId: secondGeneration.generationId,
        accepted: true
      )
    )
    let acknowledgement = try await secondAcknowledgement
    XCTAssertEqual(
      acknowledgement,
      RuntimeGenerationAcknowledgement(
        generationId: secondGeneration.generationId,
        accepted: true
      )
    )
    let startCallCount = await backend.startCallCount
    XCTAssertEqual(startCallCount, 2)
  }

  func testTerminalBeforeStartAcknowledgementDoesNotResurrectGeneration()
    async throws
  {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )
    let thirdGeneration = RuntimeGenerationRequest(
      generationId: "generation-3",
      sessionId: "session-1",
      prompt: "third",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 3
    )

    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult

    async let firstAcknowledgement = coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )
    await backend.waitForStartCall(count: 1)
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: firstGeneration.generationId,
        sequence: 1,
        kind: .completed
      )
    )

    await backend.automaticallyAcknowledgeStarts()
    let acknowledgement: RuntimeGenerationAcknowledgement?
    do {
      acknowledgement = try await coordinator.startGeneration(
        request: request,
        generation: secondGeneration
      )
    } catch {
      acknowledgement = nil
      XCTFail("Terminal should release ownership before acknowledgement: \(error)")
    }

    await backend.completeStart(
      generationId: firstGeneration.generationId,
      with: RuntimeGenerationAcknowledgement(
        generationId: firstGeneration.generationId,
        accepted: true
      )
    )
    _ = try await firstAcknowledgement

    guard let acknowledgement else {
      return
    }
    XCTAssertEqual(
      acknowledgement,
      RuntimeGenerationAcknowledgement(
        generationId: secondGeneration.generationId,
        accepted: true
      )
    )
    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: thirdGeneration
      )
      XCTFail("Expected the active second generation to retain ownership")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .generationBusy)
    }
    let startCallCount = await backend.startCallCount
    XCTAssertEqual(startCallCount, 2)
  }

  func testLateStartFailureDoesNotReleaseNewGenerationOwnership() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )
    let thirdGeneration = RuntimeGenerationRequest(
      generationId: "generation-3",
      sessionId: "session-1",
      prompt: "third",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 3
    )

    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult

    async let firstAcknowledgement = coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )
    await backend.waitForStartCall(count: 1)
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: firstGeneration.generationId,
        sequence: 1,
        kind: .failed,
        failureCode: .generationFailed,
        message: "Local inference failed."
      )
    )

    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: secondGeneration
    )

    await backend.failStart(
      generationId: firstGeneration.generationId,
      with: RuntimeBoundaryError.generationFailed
    )
    do {
      _ = try await firstAcknowledgement
      XCTFail("Expected the stale first start to fail")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .generationFailed)
    }

    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: thirdGeneration
      )
      XCTFail("Expected the active second generation to retain ownership")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .generationBusy)
    }
    let startCallCount = await backend.startCallCount
    XCTAssertEqual(startCallCount, 2)
  }

  func testCancelBeforeStartAcknowledgementEmitsOneTerminalAndIsIdempotent()
    async throws
  {
    let backend = RuntimeBackendSpy()
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )

    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult

    async let firstAcknowledgement = coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )
    await backend.waitForStartCall(count: 1)

    let firstCancellation = try await coordinator.cancelGeneration(
      request: request,
      generationId: firstGeneration.generationId
    )
    let duplicateCancellation = try await coordinator.cancelGeneration(
      request: request,
      generationId: firstGeneration.generationId
    )

    XCTAssertEqual(
      firstCancellation,
      RuntimeCancellationAcknowledgement(
        generationId: firstGeneration.generationId,
        acknowledged: true
      )
    )
    XCTAssertEqual(duplicateCancellation, firstCancellation)
    let events = recorder.events
    XCTAssertEqual(
      events,
      [
        RuntimeGenerationEvent(
          generationId: firstGeneration.generationId,
          sequence: 0,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
      ]
    )
    let cancelCallCount = await backend.cancelCallCount
    XCTAssertEqual(cancelCallCount, 1)

    await backend.completeStart(
      generationId: firstGeneration.generationId,
      with: RuntimeGenerationAcknowledgement(
        generationId: firstGeneration.generationId,
        accepted: true
      )
    )
    _ = try await firstAcknowledgement

    await backend.automaticallyAcknowledgeStarts()
    let secondAcknowledgement = try await coordinator.startGeneration(
      request: request,
      generation: secondGeneration
    )
    XCTAssertEqual(
      secondAcknowledgement,
      RuntimeGenerationAcknowledgement(
        generationId: secondGeneration.generationId,
        accepted: true
      )
    )
  }

  func testConcurrentCancellationSharesOneBackendOperation() async throws {
    let backend = RuntimeBackendSpy(blockCancellations: true)
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    let admissionGate = AsyncAdmissionGate(requiredArrivals: 2)
    async let firstCancellation: RuntimeCancellationAcknowledgement = {
      await admissionGate.arriveAndWait()
      return try await coordinator.cancelGeneration(
        request: request,
        generationId: generation.generationId
      )
    }()
    async let secondCancellation: RuntimeCancellationAcknowledgement = {
      await admissionGate.arriveAndWait()
      return try await coordinator.cancelGeneration(
        request: request,
        generationId: generation.generationId
      )
    }()

    await admissionGate.waitUntilAllArrive()
    await admissionGate.open()
    await backend.waitForCancelCall()
    for _ in 0..<8 {
      await Task.yield()
    }
    let inFlightCancelCount = await backend.cancelCallCount
    XCTAssertEqual(inFlightCancelCount, 1)

    await backend.completeCancellations(
      with: RuntimeCancellationAcknowledgement(
        generationId: generation.generationId,
        acknowledged: true
      )
    )

    let acknowledgements = try await [firstCancellation, secondCancellation]
    XCTAssertEqual(
      acknowledgements,
      [
        RuntimeCancellationAcknowledgement(
          generationId: generation.generationId,
          acknowledged: true
        ),
        RuntimeCancellationAcknowledgement(
          generationId: generation.generationId,
          acknowledged: true
        ),
      ]
    )
    let events = recorder.events
    XCTAssertEqual(
      events,
      [
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 0,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
      ]
    )
  }

  func testCancelDuringPrefillEmitsOneTerminalAndDropsLateEvents() async throws {
    let backend = RuntimeBackendSpy()
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 0,
        kind: .started
      )
    )
    _ = try await coordinator.cancelGeneration(
      request: request,
      generationId: generation.generationId
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 2,
        kind: .delta,
        delta: "late"
      )
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 3,
        kind: .completed
      )
    )

    let events = recorder.events
    XCTAssertEqual(
      events,
      [
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 1,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
      ]
    )
  }

  func testCancelDuringDecodePreservesPrefixAndDropsLateEvents() async throws {
    let backend = RuntimeBackendSpy()
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 0,
        kind: .started
      )
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 1,
        kind: .delta,
        delta: "before"
      )
    )
    _ = try await coordinator.cancelGeneration(
      request: request,
      generationId: generation.generationId
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 3,
        kind: .delta,
        delta: "late"
      )
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 4,
        kind: .completed
      )
    )

    let events = recorder.events
    XCTAssertEqual(
      events,
      [
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 1,
          kind: .delta,
          delta: "before"
        ),
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 2,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
      ]
    )
  }

  func testStaleSequenceCannotRewindCancellationTerminal() async throws {
    let backend = RuntimeBackendSpy()
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 0,
        kind: .started
      )
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 2,
        kind: .delta,
        delta: "newest"
      )
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 1,
        kind: .delta,
        delta: "stale"
      )
    )
    _ = try await coordinator.cancelGeneration(
      request: request,
      generationId: generation.generationId
    )

    let events = recorder.events
    XCTAssertEqual(
      events,
      [
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 2,
          kind: .delta,
          delta: "newest"
        ),
        RuntimeGenerationEvent(
          generationId: generation.generationId,
          sequence: 3,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
      ]
    )
  }

  func testMismatchedCancellationAcknowledgementCannotClearOwnership()
    async throws
  {
    let backend = RuntimeBackendSpy(
      cancelAcknowledgementGenerationId: "generation-other"
    )
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )

    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )

    do {
      _ = try await coordinator.cancelGeneration(
        request: request,
        generationId: firstGeneration.generationId
      )
      XCTFail("Expected a mismatched acknowledgement to be rejected")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .protocolMismatch)
    }

    let events = recorder.events
    XCTAssertTrue(events.isEmpty)
    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: secondGeneration
      )
      XCTFail("Expected the first generation to retain ownership")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .generationBusy)
    }
  }

  func testRecentlyCancelledGenerationIdCannotBeReused() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )
    _ = try await coordinator.cancelGeneration(
      request: request,
      generationId: generation.generationId
    )

    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: generation
      )
      XCTFail("Expected a recently cancelled generation ID to be rejected")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .protocolMismatch)
    }
    let startCallCount = await backend.startCallCount
    XCTAssertEqual(startCallCount, 1)
  }

  func testSynchronousEventHandlerReceivesEventsInActorOrder() async throws {
    let backend = RuntimeBackendSpy()
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 0,
        kind: .started
      )
    )
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 1,
        kind: .delta,
        delta: "next"
      )
    )

    let sequences = recorder.events.map(\.sequence)
    XCTAssertEqual(sequences, [0, 1])
  }

  func testUnloadWaitsForCancellationThenReleasesModelForReload() async throws {
    let backend = RuntimeBackendSpy(
      blockCancellations: true,
      blockUnloads: true
    )
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    async let initialLoad = coordinator.loadModel(
      request: request,
      model: model
    )
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await initialLoad
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    async let unloadResult = coordinator.unloadModel(request: request)
    await backend.waitForCancelCall()
    let unloadCountBeforeCancellation = await backend.unloadCallCount
    XCTAssertEqual(unloadCountBeforeCancellation, 0)

    await backend.completeCancellations(
      with: RuntimeCancellationAcknowledgement(
        generationId: generation.generationId,
        acknowledged: true
      )
    )
    await backend.waitForUnloadCall()
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )
    let unloadCompletion = try await unloadResult
    XCTAssertEqual(
      unloadCompletion,
      RuntimeOperationCompletion(completed: true)
    )

    async let reload = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall(count: 2)
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    let reloadResult = try await reload
    XCTAssertEqual(
      reloadResult,
      RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 1)
  }

  func testUnloadBlocksNewLoadAndGenerationUntilCompletion() async throws {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    async let initialLoad = coordinator.loadModel(
      request: request,
      model: model
    )
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await initialLoad
    await backend.automaticallyAcknowledgeStarts()

    async let unloadResult = coordinator.unloadModel(request: request)
    await backend.waitForUnloadCall()

    do {
      _ = try await coordinator.loadModel(request: request, model: model)
      XCTFail("Expected model load to be rejected during unload")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: generation
      )
      XCTFail("Expected generation to be rejected during unload")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }

    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )
    _ = try await unloadResult
    let startCallCount = await backend.startCallCount
    XCTAssertEqual(startCallCount, 0)
  }

  func testUnloadWaitsForInFlightModelLoadAndFencesLateCompletion()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )

    async let initialLoad = coordinator.loadModel(
      request: request,
      model: model
    )
    await backend.waitForLoadCall()

    let unloadAdmissionGate = AsyncAdmissionGate(requiredArrivals: 1)
    let unloadTask = Task(priority: .high) {
      await unloadAdmissionGate.arriveAndWait()
      return try await coordinator.unloadModel(request: request)
    }
    await unloadAdmissionGate.waitUntilAllArrive()
    await unloadAdmissionGate.open()
    for _ in 0..<64 {
      await Task.yield()
    }
    let unloadCountBeforeLoadFinishes = await backend.unloadCallCount
    XCTAssertEqual(unloadCountBeforeLoadFinishes, 0)

    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    await backend.waitForUnloadCall()
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )
    _ = try await initialLoad
    _ = try await unloadTask.value

    await backend.automaticallyCompleteLoads()
    _ = try await coordinator.loadModel(request: request, model: model)
    let loadCallCount = await backend.loadCallCount
    XCTAssertEqual(loadCallCount, 2)
  }

  func testShutdownDeadlineDisposesWhenCancellationNeverAcknowledges()
    async throws
  {
    let backend = RuntimeBackendSpy(blockCancellations: true)
    let deadline = ManualShutdownDeadline()
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      },
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )

    async let load = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await load
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    async let shutdown = coordinator.shutdown()
    await backend.waitForCancelCall()
    await deadline.waitUntilArmed()
    await deadline.fire()

    do {
      _ = try await shutdown
      XCTFail("Expected the shutdown deadline to fail closed")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    do {
      _ = try await coordinator.loadModel(request: request, model: model)
      XCTFail("Expected a disposed coordinator to reject model loading")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    await coordinator.receiveGenerationEvent(
      RuntimeGenerationEvent(
        generationId: generation.generationId,
        sequence: 0,
        kind: .delta,
        delta: "late"
      )
    )

    let cancelCallCount = await backend.cancelCallCount
    XCTAssertEqual(cancelCallCount, 1)
    XCTAssertTrue(recorder.events.isEmpty)
  }

  func testConcurrentShutdownCallsShareOneSuccessfulCancellationAndUnload()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    await backend.automaticallyCompleteLoads()
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.loadModel(request: request, model: model)
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    async let firstShutdown = coordinator.shutdown()
    await backend.waitForCancelCall()
    async let secondShutdown = coordinator.shutdown()
    await backend.waitForUnloadCall()
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )

    let firstCompletion = try await firstShutdown
    let secondCompletion = try await secondShutdown
    XCTAssertEqual(firstCompletion, RuntimeOperationCompletion(completed: true))
    XCTAssertEqual(secondCompletion, RuntimeOperationCompletion(completed: true))
    let cancelCallCount = await backend.cancelCallCount
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(cancelCallCount, 1)
    XCTAssertEqual(unloadCallCount, 1)
  }

  func testShutdownDeadlineDisposesWhenUnloadNeverCompletes() async throws {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    await backend.automaticallyCompleteLoads()
    _ = try await coordinator.loadModel(request: request, model: model)

    async let shutdown = coordinator.shutdown()
    await backend.waitForUnloadCall()
    await deadline.waitUntilArmed()
    await deadline.fire()

    do {
      _ = try await shutdown
      XCTFail("Expected the shutdown deadline to fail closed")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )
    do {
      _ = try await coordinator.unloadModel(request: request)
      XCTFail("Expected a disposed coordinator to reject model unloading")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
  }

  func testShutdownDeadlineDoesNotRetainCoordinator() async throws {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    var coordinator: InferenceCoordinator? = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    weak let releasedCoordinator = coordinator

    let shutdownTask = Task { [coordinator] in
      try await coordinator!.shutdown()
    }
    await backend.waitForUnloadCall()
    await deadline.waitUntilArmed()
    await deadline.fire()
    do {
      _ = try await shutdownTask.value
      XCTFail("Expected the shutdown deadline to fail closed")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    coordinator = nil
    for _ in 0..<8 {
      await Task.yield()
    }

    XCTAssertNil(releasedCoordinator)
  }

  func testShutdownDeadlineDiscardsLateModelLoadCompletion() async throws {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )

    async let load = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    await deadline.fire()
    do {
      _ = try await shutdown
      XCTFail("Expected the shutdown deadline to fail closed")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }

    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try? await load
    for _ in 0..<8 {
      await Task.yield()
    }
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 0)
    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: RuntimeGenerationRequest(
          generationId: "generation-1",
          sessionId: "session-1",
          prompt: "late",
          context: [],
          temperature: 0.25,
          topP: 0.9,
          maxTokens: 128,
          seed: 1
        )
      )
      XCTFail("Expected a disposed coordinator to reject late work")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
  }

  func testShutdownImmediatelyRejectsEveryNewModelOperation() async throws {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    await backend.automaticallyCompleteLoads()
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.loadModel(request: request, model: model)
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    async let shutdown = coordinator.shutdown()
    await backend.waitForCancelCall()
    await backend.waitForUnloadCall()
    func assertRuntimeUnavailable<T>(
      _ operation: () async throws -> T
    ) async {
      do {
        _ = try await operation()
        XCTFail("Expected shutdown to reject new work")
      } catch {
        XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
      }
    }
    await assertRuntimeUnavailable {
      try await coordinator.loadModel(request: request, model: model)
    }
    await assertRuntimeUnavailable {
      try await coordinator.startGeneration(request: request, generation: generation)
    }
    await assertRuntimeUnavailable {
      try await coordinator.cancelGeneration(
        request: request,
        generationId: generation.generationId
      )
    }
    await assertRuntimeUnavailable {
      try await coordinator.unloadModel(request: request)
    }

    await deadline.waitUntilArmed()
    await deadline.fire()
    _ = try? await shutdown
  }

  func testShutdownWaitsForInFlightLoadBeforeUnloading() async throws {
    let backend = RuntimeBackendSpy()
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )

    async let load = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    for _ in 0..<8 {
      await Task.yield()
    }
    let unloadCountBeforeLoadSettles = await backend.unloadCallCount
    XCTAssertEqual(unloadCountBeforeLoadSettles, 0)

    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    await backend.waitForUnloadCall()
    _ = try? await load
    let shutdownCompletion = try await shutdown
    XCTAssertEqual(shutdownCompletion, RuntimeOperationCompletion(completed: true))
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 1)
  }

  func testShutdownSkipsCancellationWhenInFlightStartFails() async throws {
    let backend = RuntimeBackendSpy()
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    await backend.automaticallyCompleteLoads()
    _ = try await coordinator.loadModel(request: request, model: model)

    async let start = coordinator.startGeneration(
      request: request,
      generation: generation
    )
    await backend.waitForStartCall(count: 1)
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    await backend.failStart(
      generationId: generation.generationId,
      with: RuntimeBoundaryError.generationFailed
    )
    await backend.waitForUnloadCall()
    _ = try? await start
    _ = try await shutdown
    let cancelCallCount = await backend.cancelCallCount
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(cancelCallCount, 0)
    XCTAssertEqual(unloadCallCount, 1)
  }

  func testShutdownSkipsCancellationWhenInFlightStartIsDeclined()
    async throws
  {
    let backend = RuntimeBackendSpy()
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    await backend.automaticallyCompleteLoads()
    _ = try await coordinator.loadModel(request: request, model: model)

    async let start = coordinator.startGeneration(
      request: request,
      generation: generation
    )
    await backend.waitForStartCall(count: 1)
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    await backend.completeStart(
      generationId: generation.generationId,
      with: RuntimeGenerationAcknowledgement(
        generationId: generation.generationId,
        accepted: false
      )
    )
    await backend.waitForUnloadCall()
    _ = try? await start
    _ = try await shutdown
    let cancelCallCount = await backend.cancelCallCount
    XCTAssertEqual(cancelCallCount, 0)
  }

  func testOrdinaryUnloadPropagatesItsBackendError() async throws {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    async let unload = coordinator.unloadModel(request: request)
    await backend.waitForUnloadCall()
    await backend.failUnloads(with: RuntimeBoundaryError.modelLoadFailed)
    do {
      _ = try await unload
      XCTFail("Expected the backend error to propagate")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .modelLoadFailed)
    }
  }

  func testOrdinaryUnloadPropagatesInFlightLoadError() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )

    async let load = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    async let unload = coordinator.unloadModel(request: request)
    await backend.failLoads(with: RuntimeBoundaryError.modelLoadFailed)
    _ = try? await load
    do {
      _ = try await unload
      XCTFail("Expected the in-flight load error to propagate")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .modelLoadFailed)
    }
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 0)
  }

  func testOrdinaryUnloadFailureKeepsSuccessfulCancellationTerminal()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )
    await backend.automaticallyCompleteLoads()
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.loadModel(request: request, model: model)
    _ = try await coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )

    async let unload = coordinator.unloadModel(request: request)
    await backend.waitForCancelCall()
    await backend.waitForUnloadCall()
    await backend.failUnloads(with: RuntimeBoundaryError.runtimeUnavailable)
    _ = try? await unload

    let secondAcknowledgement = try await coordinator.startGeneration(
      request: request,
      generation: secondGeneration
    )
    XCTAssertTrue(secondAcknowledgement.accepted)
    let cancelCallCount = await backend.cancelCallCount
    XCTAssertEqual(cancelCallCount, 1)
    XCTAssertEqual(recorder.events.map(\.kind), [.cancelled])
  }

  func testOrdinaryIncompleteUnloadKeepsSuccessfulCancellationTerminal()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let firstGeneration = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    let secondGeneration = RuntimeGenerationRequest(
      generationId: "generation-2",
      sessionId: "session-1",
      prompt: "second",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 2
    )
    await backend.automaticallyCompleteLoads()
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.loadModel(request: request, model: model)
    _ = try await coordinator.startGeneration(
      request: request,
      generation: firstGeneration
    )

    async let unload = coordinator.unloadModel(request: request)
    await backend.waitForCancelCall()
    await backend.waitForUnloadCall()
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: false)
    )
    let completion = try await unload
    XCTAssertFalse(completion.completed)

    let secondAcknowledgement = try await coordinator.startGeneration(
      request: request,
      generation: secondGeneration
    )
    XCTAssertTrue(secondAcknowledgement.accepted)
    let cancelCallCount = await backend.cancelCallCount
    XCTAssertEqual(cancelCallCount, 1)
    XCTAssertEqual(recorder.events.map(\.kind), [.cancelled])
  }

  func testShutdownReusesOrdinaryCancellationWithoutLateTerminalEvent()
    async throws
  {
    let backend = RuntimeBackendSpy(blockCancellations: true)
    let deadline = ManualShutdownDeadline()
    let recorder = RuntimeEventRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      },
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    await backend.automaticallyCompleteLoads()
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.loadModel(request: request, model: model)
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    async let cancellation = coordinator.cancelGeneration(
      request: request,
      generationId: generation.generationId
    )
    await backend.waitForCancelCall()
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    let cancelCountBeforeAcknowledgement = await backend.cancelCallCount
    XCTAssertEqual(cancelCountBeforeAcknowledgement, 1)
    let unloadCountBeforeAcknowledgement = await backend.unloadCallCount
    XCTAssertEqual(unloadCountBeforeAcknowledgement, 0)

    await backend.completeCancellations(
      with: RuntimeCancellationAcknowledgement(
        generationId: generation.generationId,
        acknowledged: true
      )
    )
    await backend.waitForUnloadCall()
    _ = try await cancellation
    _ = try await shutdown
    let cancelCallCount = await backend.cancelCallCount
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(cancelCallCount, 1)
    XCTAssertEqual(unloadCallCount, 1)
    XCTAssertTrue(recorder.events.isEmpty)
  }

  func testShutdownRejectsMismatchedReusedCancellationAcknowledgement()
    async throws
  {
    let backend = RuntimeBackendSpy(blockCancellations: true)
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    await backend.automaticallyCompleteLoads()
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.loadModel(request: request, model: model)
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    async let cancellation = coordinator.cancelGeneration(
      request: request,
      generationId: generation.generationId
    )
    await backend.waitForCancelCall()
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    await backend.completeCancellations(
      with: RuntimeCancellationAcknowledgement(
        generationId: "wrong-generation",
        acknowledged: true
      )
    )
    _ = try? await cancellation
    do {
      _ = try await shutdown
      XCTFail("Expected mismatched cancellation identity to fail shutdown")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 0)
  }

  func testShutdownDeadlineReusesExistingUnloadWithoutSecondBackendCall()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    await backend.automaticallyCompleteLoads()
    _ = try await coordinator.loadModel(request: request, model: model)

    async let ordinaryUnload = coordinator.unloadModel(request: request)
    await backend.waitForUnloadCall()
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    await deadline.fire()
    do {
      _ = try await shutdown
      XCTFail("Expected the shutdown deadline to fail closed")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 1)
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )
    _ = try? await ordinaryUnload
  }

  func testShutdownDeadlineStopsReusedUnloadBeforeLateBackendUnload()
    async throws
  {
    let backend = RuntimeBackendSpy(blockCancellations: true)
    let deadline = ManualShutdownDeadline()
    let recorder = RuntimeEventRecorder()
    let unloadAdmissions = ShutdownWaitRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { event in
        recorder.record(event)
      },
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline),
      shutdownWaitObserver: {},
      ordinaryUnloadAdmissionObserver: {
        Task {
          await unloadAdmissions.recordWait()
        }
      }
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    let model = RuntimeModelRequest(
      modelId: "model-1",
      modelPath: "/models/model-1.bin",
      contextSize: 4096
    )
    let generation = RuntimeGenerationRequest(
      generationId: "generation-1",
      sessionId: "session-1",
      prompt: "first",
      context: [],
      temperature: 0.25,
      topP: 0.9,
      maxTokens: 128,
      seed: 1
    )
    await backend.automaticallyCompleteLoads()
    await backend.automaticallyAcknowledgeStarts()
    _ = try await coordinator.loadModel(request: request, model: model)
    _ = try await coordinator.startGeneration(
      request: request,
      generation: generation
    )

    async let ordinaryUnload = coordinator.unloadModel(request: request)
    await backend.waitForCancelCall()
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    await deadline.fire()
    do {
      _ = try await shutdown
      XCTFail("Expected the shutdown deadline to fail closed")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    do {
      _ = try await ordinaryUnload
      XCTFail("Expected the reused unload to fail closed")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }

    await backend.completeCancellations(
      with: RuntimeCancellationAcknowledgement(
        generationId: generation.generationId,
        acknowledged: true
      )
    )
    await unloadAdmissions.waitForWaitCount(1)

    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 0)
    XCTAssertTrue(recorder.events.isEmpty)
    do {
      _ = try await coordinator.shutdown()
      XCTFail("Expected the terminal shutdown outcome to remain unavailable")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
  }

  func testShutdownReusesExistingUnloadCompletion() async throws {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    async let ordinaryUnload = coordinator.unloadModel(request: request)
    await backend.waitForUnloadCall()
    async let shutdown = coordinator.shutdown()
    await deadline.waitUntilArmed()
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )

    let ordinaryCompletion = try await ordinaryUnload
    let shutdownCompletion = try await shutdown
    XCTAssertEqual(ordinaryCompletion, RuntimeOperationCompletion(completed: true))
    XCTAssertEqual(shutdownCompletion, RuntimeOperationCompletion(completed: true))
    let unloadCallCount = await backend.unloadCallCount
    XCTAssertEqual(unloadCallCount, 1)
  }

  func testShutdownDeadlineReleasesCoordinatorWithExistingHungUnload()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    var coordinator: InferenceCoordinator? = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
    )
    weak let releasedCoordinator = coordinator
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    let ordinaryUnload = Task { [weak coordinator] in
      try? await coordinator?.unloadModel(request: request)
    }
    await backend.waitForUnloadCall()
    let shutdown = Task { [weak coordinator] in
      try? await coordinator?.shutdown()
    }
    await deadline.waitUntilArmed()
    await deadline.fire()
    _ = await shutdown.value
    _ = await ordinaryUnload.value
    coordinator = nil
    for _ in 0..<8 {
      await Task.yield()
    }

    XCTAssertNil(releasedCoordinator)
  }

  func testConcurrentShutdownSuccessSharesResultAfterBothCallersWait()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let waits = ShutdownWaitRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { _ in },
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline),
      shutdownWaitObserver: {
        Task {
          await waits.recordWait()
        }
      }
    )

    async let first = coordinator.shutdown()
    await backend.waitForUnloadCall()
    async let second = coordinator.shutdown()
    await waits.waitForWaitCount(2)
    await backend.completeUnloads(
      with: RuntimeOperationCompletion(completed: true)
    )

    let firstCompletion = try await first
    let secondCompletion = try await second
    XCTAssertEqual(firstCompletion, RuntimeOperationCompletion(completed: true))
    XCTAssertEqual(secondCompletion, RuntimeOperationCompletion(completed: true))
  }

  func testConcurrentShutdownDeadlineSharesFailureAfterBothCallersWait()
    async throws
  {
    let backend = RuntimeBackendSpy(blockUnloads: true)
    let deadline = ManualShutdownDeadline()
    let waits = ShutdownWaitRecorder()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { _ in },
      shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline),
      shutdownWaitObserver: {
        Task {
          await waits.recordWait()
        }
      }
    )

    async let first = coordinator.shutdown()
    await backend.waitForUnloadCall()
    async let second = coordinator.shutdown()
    await waits.waitForWaitCount(2)
    await deadline.waitUntilArmed()
    await deadline.fire()

    do {
      _ = try await first
      XCTFail("Expected the shared deadline failure")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
    do {
      _ = try await second
      XCTFail("Expected the shared deadline failure")
    } catch {
      XCTAssertEqual(error as? RuntimeBoundaryError, .runtimeUnavailable)
    }
  }

  func testShutdownCompletionDeadlineRaceSharesOutcomeForEightyIterations()
    async throws
  {
    enum Outcome: Equatable {
      case completed
      case unavailable
    }
    func shutdownOutcome(_ coordinator: InferenceCoordinator) async -> Outcome {
      let completion = try? await coordinator.shutdown()
      return completion == nil ? .unavailable : .completed
    }

    for _ in 0..<80 {
      let backend = RuntimeBackendSpy(blockUnloads: true)
      let deadline = ManualShutdownDeadline()
      let coordinator = InferenceCoordinator(
        supportedSchemaVersion: 2,
        backend: backend,
        shutdownDeadlineFactory: ManualShutdownDeadlineFactory(deadline: deadline)
      )
      async let first = shutdownOutcome(coordinator)
      await backend.waitForUnloadCall()
      async let second = shutdownOutcome(coordinator)
      await deadline.waitUntilArmed()
      async let completion: Void = backend.completeUnloads(
        with: RuntimeOperationCompletion(completed: true)
      )
      async let expiry: Void = deadline.fire()
      _ = await (completion, expiry)
      let firstOutcome = await first
      let secondOutcome = await second
      let lateOutcome = await shutdownOutcome(coordinator)
      XCTAssertEqual(firstOutcome, secondOutcome)
      XCTAssertEqual(secondOutcome, lateOutcome)
    }
  }

  func testEventBridgePreservesIdentitySequenceAndOneTerminal() {
    let sink = RecordingGenerationEventSink()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: ManualRuntimeEventScheduler(),
      coalescingMilliseconds: 10
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "hello"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .failed,
        failureCode: .generationFailed,
        message: "Local inference failed."
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 3,
        kind: .delta,
        delta: "late"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 4,
        kind: .completed
      )
    )

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 1,
          kind: .delta,
          delta: "hello"
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 2,
          kind: .failed,
          failureCode: .generationFailed,
          message: "Local inference failed."
        ),
      ]
    )
  }

  func testEventBridgeAcceptsSequentialGenerationsAndFencesLatePriorEvents() {
    let sink = RecordingGenerationEventSink()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: ManualRuntimeEventScheduler(),
      coalescingMilliseconds: 10
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .completed
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .delta,
        delta: "late"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 3,
        kind: .failed,
        failureCode: .generationFailed,
        message: "late terminal"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 1,
        kind: .delta,
        delta: "next"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 2,
        kind: .cancelled,
        failureCode: .cancelled,
        message: "The response was cancelled."
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 3,
        kind: .completed
      )
    )

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 1,
          kind: .completed
        ),
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 1,
          kind: .delta,
          delta: "next"
        ),
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 2,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
      ]
    )
  }

  func testCancellationAcknowledgementDropsBufferedAndFencesLaterEvents() throws {
    let sink = RecordingGenerationEventSink()
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )
    let coordinator = LocalModelRuntimeCoordinator(
      supportedSchemaVersion: 2,
      backend: RecordingLocalModelRuntimeBackend(),
      cancellationFence: bridge
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "must not escape"
      )
    )

    XCTAssertEqual(
      try coordinator.cancelGeneration(
        request: request,
        generationId: "generation-1"
      ),
      RuntimeCancellationAcknowledgement(
        generationId: "generation-1",
        acknowledged: true
      )
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .delta,
        delta: "late"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 3,
        kind: .completed
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 0,
        kind: .started
      )
    )
    scheduler.runAllIncludingCancelled()

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 2,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 0,
          kind: .started
        ),
      ]
    )
    XCTAssertEqual(scheduler.cancelledTaskCount, 1)
  }

  func testAcknowledgedCancellationBeforeStartFencesThatGeneration() throws {
    let sink = RecordingGenerationEventSink()
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )
    let coordinator = LocalModelRuntimeCoordinator(
      supportedSchemaVersion: 2,
      backend: RecordingLocalModelRuntimeBackend(),
      cancellationFence: bridge
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    XCTAssertEqual(
      try coordinator.cancelGeneration(
        request: request,
        generationId: "generation-1"
      ),
      RuntimeCancellationAcknowledgement(
        generationId: "generation-1",
        acknowledged: true
      )
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "late"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .completed
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 1,
        kind: .delta,
        delta: "next"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 2,
        kind: .completed
      )
    )

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 1,
          kind: .delta,
          delta: "next"
        ),
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 2,
          kind: .completed
        ),
      ]
    )
  }

  func testAcknowledgedDifferentGenerationIsFencedWithoutAffectingActive() throws {
    let sink = RecordingGenerationEventSink()
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )
    let coordinator = LocalModelRuntimeCoordinator(
      supportedSchemaVersion: 2,
      backend: RecordingLocalModelRuntimeBackend(),
      cancellationFence: bridge
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "kept"
      )
    )
    XCTAssertEqual(
      try coordinator.cancelGeneration(
        request: request,
        generationId: "generation-2"
      ),
      RuntimeCancellationAcknowledgement(
        generationId: "generation-2",
        acknowledged: true
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .delta,
        delta: " going"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 3,
        kind: .completed
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 1,
        kind: .delta,
        delta: "late"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 2,
        kind: .completed
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-3",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-3",
        sequence: 1,
        kind: .completed
      )
    )

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 2,
          kind: .delta,
          delta: "kept going"
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 3,
          kind: .completed
        ),
        RuntimeGenerationEvent(
          generationId: "generation-3",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-3",
          sequence: 1,
          kind: .completed
        ),
      ]
    )
  }

  func testUnacknowledgedCancellationLeavesActiveGenerationUnfenced() throws {
    let sink = RecordingGenerationEventSink()
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )
    let backend = RecordingLocalModelRuntimeBackend()
    backend.cancellationAcknowledged = false
    let coordinator = LocalModelRuntimeCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      cancellationFence: bridge
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "preserved"
      )
    )

    XCTAssertEqual(
      try coordinator.cancelGeneration(
        request: request,
        generationId: "generation-1"
      ),
      RuntimeCancellationAcknowledgement(
        generationId: "generation-1",
        acknowledged: false
      )
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .completed
      )
    )
    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 1,
          kind: .delta,
          delta: "preserved"
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 2,
          kind: .completed
        ),
      ]
    )
  }

  func testCancellationDuringSchedulingCancelsReturnedStaleTask() {
    let sink = RecordingGenerationEventSink()
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    scheduler.onSchedule = {
      bridge.cancelGeneration(generationId: "generation-1")
    }
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "must not escape"
      )
    )
    scheduler.runAllIncludingCancelled()
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 0,
        kind: .started
      )
    )

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 2,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
        RuntimeGenerationEvent(
          generationId: "generation-2",
          sequence: 0,
          kind: .started
        ),
      ]
    )
    XCTAssertEqual(scheduler.cancelledTaskCount, 1)
  }

  func testOverlappingTransitionsPreserveSynchronousDeliveryOrder() {
    let sink = BlockingFirstGenerationEventSink()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: ManualRuntimeEventScheduler(),
      coalescingMilliseconds: 10
    )
    let bridgeBox = UncheckedSendableBox(bridge)
    let startFinished = DispatchSemaphore(value: 0)
    let cancellationWillInvoke = DispatchSemaphore(value: 0)
    let cancellationFinished = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
      bridgeBox.value.receive(
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        )
      )
      startFinished.signal()
    }
    XCTAssertEqual(
      sink.firstSendEntered.wait(timeout: .now() + 1),
      .success
    )

    DispatchQueue.global().async {
      cancellationWillInvoke.signal()
      bridgeBox.value.cancelGeneration(generationId: "generation-1")
      cancellationFinished.signal()
    }
    XCTAssertEqual(
      cancellationWillInvoke.wait(timeout: .now() + 1),
      .success
    )
    XCTAssertEqual(
      cancellationFinished.wait(timeout: .now() + 0.25),
      .timedOut
    )

    sink.releaseFirstSend.signal()
    XCTAssertEqual(startFinished.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(
      cancellationFinished.wait(timeout: .now() + 1),
      .success
    )
    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 1,
          kind: .cancelled,
          failureCode: .cancelled,
          message: "The response was cancelled."
        ),
      ]
    )
  }

  func testDisposeWaitsForOverlappingTerminalDeliveryAndRemainsTerminal() {
    let sink = BlockingTerminalGenerationEventSink()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: ManualRuntimeEventScheduler(),
      coalescingMilliseconds: 10
    )
    let bridgeBox = UncheckedSendableBox(bridge)
    let terminalFinished = DispatchSemaphore(value: 0)
    let disposeWillInvoke = DispatchSemaphore(value: 0)
    let disposeFinished = DispatchSemaphore(value: 0)

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    DispatchQueue.global().async {
      bridgeBox.value.receive(
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 1,
          kind: .completed
        )
      )
      terminalFinished.signal()
    }
    XCTAssertEqual(
      sink.terminalSendEntered.wait(timeout: .now() + 1),
      .success
    )

    DispatchQueue.global().async {
      disposeWillInvoke.signal()
      bridgeBox.value.dispose()
      disposeFinished.signal()
    }
    XCTAssertEqual(disposeWillInvoke.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(
      disposeFinished.wait(timeout: .now() + 0.25),
      .timedOut
    )

    sink.releaseTerminalSend.signal()
    XCTAssertEqual(terminalFinished.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(disposeFinished.wait(timeout: .now() + 1), .success)
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-2",
        sequence: 0,
        kind: .started
      )
    )
    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 1,
          kind: .completed
        ),
      ]
    )
  }

  func testCoalescesDeltasWithinPolicyWindowAndFlushesAtTerminal() {
    let sink = RecordingGenerationEventSink()
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "Hel"
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .delta,
        delta: "lo"
      )
    )

    XCTAssertEqual(sink.events.map(\.kind), [.started])
    XCTAssertEqual(scheduler.scheduledDelays, [10])
    XCTAssertTrue((8...16).contains(scheduler.scheduledDelays[0]))

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 3,
        kind: .completed
      )
    )

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 2,
          kind: .delta,
          delta: "Hello"
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 3,
          kind: .completed
        ),
      ]
    )
    XCTAssertEqual(scheduler.cancelledTaskCount, 1)

    scheduler.runAll()
    XCTAssertEqual(sink.events.count, 3)
  }

  func testDeterministicBackendCompletesLifecycleWithoutModelFiles() throws {
    let sink = RecordingGenerationEventSink()
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )
    let backend = DeterministicLocalModelRuntimeBackend(
      eventReceiver: bridge.receive
    )
    let coordinator = LocalModelRuntimeCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )

    XCTAssertEqual(
      try coordinator.handshake(request: request),
      RuntimeHandshakeResult(
        schemaVersion: 2,
        runtimeName: "deterministic",
        supportsStreaming: true,
        supportsCancellation: true
      )
    )
    XCTAssertEqual(
      try coordinator.loadModel(
        request: request,
        model: RuntimeModelRequest(
          modelId: "deterministic-model",
          modelPath: "/path/that/does/not/exist.bin",
          contextSize: 4096
        )
      ),
      RuntimeModelLoadResult(
        modelId: "deterministic-model",
        loaded: true
      )
    )
    XCTAssertEqual(
      try coordinator.startGeneration(
        request: request,
        generation: RuntimeGenerationRequest(
          generationId: "generation-1",
          sessionId: "session-1",
          prompt: "private prompt",
          context: ["private context"],
          temperature: 0.25,
          topP: 0.9,
          maxTokens: 128,
          seed: 7
        )
      ),
      RuntimeGenerationAcknowledgement(
        generationId: "generation-1",
        accepted: true
      )
    )
    XCTAssertEqual(
      try coordinator.cancelGeneration(
        request: request,
        generationId: "generation-1"
      ),
      RuntimeCancellationAcknowledgement(
        generationId: "generation-1",
        acknowledged: true
      )
    )
    XCTAssertEqual(
      try coordinator.resetSession(request: request, sessionId: "session-1"),
      RuntimeOperationCompletion(completed: true)
    )
    XCTAssertEqual(
      try coordinator.unloadModel(request: request),
      RuntimeOperationCompletion(completed: true)
    )

    XCTAssertEqual(
      sink.events,
      [
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 0,
          kind: .started
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 2,
          kind: .delta,
          delta: "Deterministic response."
        ),
        RuntimeGenerationEvent(
          generationId: "generation-1",
          sequence: 3,
          kind: .completed
        ),
      ]
    )
    scheduler.runAll()
    XCTAssertEqual(sink.events.count, 3)
  }

  func testDisposeCancelsBufferedAndFencesDirectCallbacks() {
    let recorder = SharedGenerationEventRecorder()
    var sink: ForwardingGenerationEventSink? = ForwardingGenerationEventSink(
      recorder: recorder
    )
    weak let releasedSink = sink
    let scheduler = ManualRuntimeEventScheduler()
    let bridge = GenerationEventBridge(
      sink: sink!,
      scheduler: scheduler,
      coalescingMilliseconds: 10
    )

    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 0,
        kind: .started
      )
    )
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 1,
        kind: .delta,
        delta: "buffered"
      )
    )
    sink = nil

    bridge.dispose()
    scheduler.runAll()
    bridge.receive(
      RuntimeGenerationEvent(
        generationId: "generation-1",
        sequence: 2,
        kind: .completed
      )
    )

    XCTAssertEqual(recorder.events.map(\.kind), [.started])
    XCTAssertEqual(scheduler.cancelledTaskCount, 1)
    XCTAssertNil(releasedSink)
  }

  func testCoordinatorHandshakeReportsBackendCapabilities() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )

    let result = try await coordinator.handshake(
      request: RuntimeRequestEnvelope(
        schemaVersion: 2,
        requestId: "request-1",
        timestampMicros: 1
      )
    )

    XCTAssertEqual(
      result,
      RuntimeHandshakeResult(
        schemaVersion: 2,
        runtimeName: "spy",
        supportsStreaming: true,
        supportsCancellation: true
      )
    )
  }

  func testCoordinatorHandshakeRejectsProtocolMismatch() async {
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: RuntimeBackendSpy()
    )

    await assertRuntimeBoundaryError(.protocolMismatch) {
      _ = try await coordinator.handshake(
        request: RuntimeRequestEnvelope(
          schemaVersion: 1,
          requestId: "request-1",
          timestampMicros: 1
        )
      )
    }
  }

  func testCoordinatorResetSessionDelegatesExactSessionToBackend() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )

    let completion = try await coordinator.resetSession(
      request: RuntimeRequestEnvelope(
        schemaVersion: 2,
        requestId: "request-1",
        timestampMicros: 1
      ),
      sessionId: "session-1"
    )

    XCTAssertEqual(completion, RuntimeOperationCompletion(completed: true))
    let resetSessionIds = await backend.resetSessionIds
    XCTAssertEqual(resetSessionIds, ["session-1"])
  }

  func testCoordinatorResetSessionRejectsProtocolMismatch() async {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )

    await assertRuntimeBoundaryError(.protocolMismatch) {
      _ = try await coordinator.resetSession(
        request: RuntimeRequestEnvelope(
          schemaVersion: 2,
          requestId: "",
          timestampMicros: 1
        ),
        sessionId: "session-1"
      )
    }
    let resetSessionIds = await backend.resetSessionIds
    XCTAssertEqual(resetSessionIds, [])
  }

  func testCoordinatorRejectsHandshakeAndResetSessionAfterShutdown() async throws {
    let backend = RuntimeBackendSpy()
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend
    )
    let request = RuntimeRequestEnvelope(
      schemaVersion: 2,
      requestId: "request-1",
      timestampMicros: 1
    )
    _ = try await coordinator.shutdown()

    await assertRuntimeBoundaryError(.runtimeUnavailable) {
      _ = try await coordinator.handshake(request: request)
    }
    await assertRuntimeBoundaryError(.runtimeUnavailable) {
      _ = try await coordinator.resetSession(
        request: request,
        sessionId: "session-1"
      )
    }
    let resetSessionIds = await backend.resetSessionIds
    XCTAssertEqual(resetSessionIds, [])
  }

  private func assertRuntimeBoundaryError(
    _ expected: RuntimeBoundaryError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected) but the operation succeeded.", file: file, line: line)
    } catch let error as RuntimeBoundaryError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("Expected \(expected) but got \(error).", file: file, line: line)
    }
  }


  /// Opt-in throughput comparison between the GPU and CPU backends.
  ///
  /// The runtime logs a failure to create an OpenCL context on this machine, so
  /// this measures what the two configurations actually deliver rather than
  /// trusting the requested backend.
  func testRealGemmaBackendThroughput() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the real-model smoke.")
    }

    let cases: [(String, LiteRTLMRuntimeConfiguration)] = [
      (
        "gpu",
        LiteRTLMRuntimeConfiguration(
          primaryBackend: .gpu,
          enableCPUFallback: false
        )
      ),
      (
        "cpu",
        LiteRTLMRuntimeConfiguration(
          primaryBackend: .cpu(threadCount: nil),
          enableCPUFallback: false
        )
      ),
    ]

    for (name, configuration) in cases {
      let collector = RealModelEventCollector()
      let relay = RuntimeGenerationEventRelay()
      await relay.attach { event in await collector.record(event) }
      let backend = LiteRTLMRuntimeBackend(
        configuration: configuration,
        eventRelay: relay
      )
      let loadStarted = Date()
      do {
        _ = try await backend.loadModel(
          RuntimeModelRequest(
            modelId: "gemma-4-E4B-it",
            modelPath: modelPath,
            contextSize: 4096
          )
        )
      } catch {
        print("BENCH backend=\(name) load_failed=\(error)")
        continue
      }
      let loadSeconds = Date().timeIntervalSince(loadStarted)

      let started = Date()
      _ = try await backend.startGeneration(
        RuntimeGenerationRequest(
          generationId: "bench-\(name)",
          sessionId: "bench-\(name)",
          prompt: "Write one paragraph about why local inference matters.",
          context: [],
          temperature: 0.7,
          topP: 0.95,
          maxTokens: 128,
          seed: 7
        )
      )
      let deadline = Date().addingTimeInterval(300)
      while Date() < deadline, await !collector.isTerminal {
        try await Task.sleep(nanoseconds: 20_000_000)
      }
      let elapsed = Date().timeIntervalSince(started)
      let kinds = await collector.kinds
      let text = await collector.text
      let deltas = kinds.filter { $0 == .delta }.count
      let perSecond = elapsed > 0 ? Double(deltas) / elapsed : 0
      print(
        "BENCH backend=\(name) load=\(String(format: "%.2f", loadSeconds))s "
          + "gen=\(String(format: "%.2f", elapsed))s deltas=\(deltas) "
          + "deltas_per_second=\(String(format: "%.2f", perSecond)) "
          + "chars=\(text.count) terminal=\(String(describing: kinds.last))"
      )
      _ = try await backend.unloadModel()
    }
  }

  /// Opt-in: a stopped turn must not prevent the next one.
  ///
  /// LiteRT-LM v0.14.0 cannot actually stop a running decode. CancelProcess
  /// leaves one active task in its callback thread pool forever, which wedges
  /// the engine so completely that a later generation only reports started and
  /// even unloadModel blocks. The backend therefore abandons the decode rather
  /// than cancelling it, discards its output, and drains it before the next
  /// generation touches the engine.
  func testRealGemmaServesTheNextTurnAfterACancellation() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the real-model smoke.")
    }

    let collector = RealModelEventCollector()
    let relay = RuntimeGenerationEventRelay()
    await relay.attach { event in
      await collector.record(event)
    }
    let backend = LiteRTLMRuntimeBackend(eventRelay: relay)
    _ = try await backend.loadModel(
      RuntimeModelRequest(
        modelId: "gemma-4-E4B-it",
        modelPath: modelPath,
        contextSize: 4096
      )
    )

    _ = try await backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-1",
        sessionId: "session-1",
        prompt: "Count slowly from one to two hundred.",
        context: [],
        temperature: 0.7,
        topP: 0.95,
        maxTokens: 512,
        seed: 7
      )
    )
    let deltaDeadline = Date().addingTimeInterval(120)
    while Date() < deltaDeadline, await collector.kinds.count < 2 {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    _ = try await backend.cancelGeneration(generationId: "generation-1")
    print("REAL_SMOKE after_cancel_kinds=\(await collector.kinds)")

    await collector.reset()
    _ = try await backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-2",
        sessionId: "session-1",
        prompt: "Say the single word: ready.",
        context: [],
        temperature: 0.7,
        topP: 0.95,
        maxTokens: 32,
        seed: 7
      )
    )
    let deadline = Date().addingTimeInterval(180)
    while Date() < deadline, await !collector.isTerminal {
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    let kinds = await collector.kinds
    let text = await collector.text
    print("REAL_SMOKE reuse_kinds=\(kinds)")
    print("REAL_SMOKE reuse_text=\(text)")
    XCTAssertEqual(
      kinds.last,
      .completed,
      "The turn after a stop must still complete."
    )
    XCTAssertFalse(
      text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "The turn after a stop must produce real text."
    )
    _ = try await backend.unloadModel()
  }

  /// Opt-in smoke against the real Gemma 4 E4B artifact.
  ///
  /// Set REAL_GEMMA_MODEL_PATH to run it. It is skipped by default so the
  /// ordinary suite stays model-free and fast.
  func testRealGemmaLoadsAndStreamsTokens() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the real-model smoke.")
    }

    let collector = RealModelEventCollector()
    let relay = RuntimeGenerationEventRelay()
    await relay.attach { event in
      await collector.record(event)
    }
    let backend = LiteRTLMRuntimeBackend(eventRelay: relay)

    let loadStarted = Date()
    let load = try await backend.loadModel(
      RuntimeModelRequest(
        modelId: "gemma-4-E4B-it",
        modelPath: modelPath,
        contextSize: 4096
      )
    )
    let loadSeconds = Date().timeIntervalSince(loadStarted)
    XCTAssertTrue(load.loaded, "The real model must load.")
    print("REAL_SMOKE cold_load_seconds=\(loadSeconds)")

    let generationStarted = Date()
    let acknowledgement = try await backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-1",
        sessionId: "session-1",
        prompt: "Reply with exactly one short sentence about local AI.",
        context: [],
        temperature: 0.7,
        topP: 0.95,
        maxTokens: 48,
        seed: 7
      )
    )
    XCTAssertTrue(acknowledgement.accepted, "The generation must be accepted.")

    let deadline = Date().addingTimeInterval(300)
    while Date() < deadline, await !collector.isTerminal {
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    let kinds = await collector.kinds
    let text = await collector.text
    let failure = await collector.failureDescription
    let elapsed = Date().timeIntervalSince(generationStarted)
    print("REAL_SMOKE kinds=\(kinds)")
    print("REAL_SMOKE generation_seconds=\(elapsed)")
    print("REAL_SMOKE text=\(text)")
    if let failure {
      print("REAL_SMOKE failure=\(failure)")
    }

    XCTAssertNil(failure, "The real generation must not fail.")
    XCTAssertEqual(kinds.first, .started)
    XCTAssertEqual(kinds.last, .completed)
    XCTAssertFalse(
      text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "Gemma must emit real token text."
    )

    _ = try await backend.unloadModel()
  }


  func testHistoryIsTrimmedToWhatTheContextCanHold() {
    // A conversation longer than the window must not be seeded whole: it
    // does not degrade, it fails, and the failure reaches the user as an
    // empty answer.
    let long = (1...40).map {
      RuntimeConversationTurn(role: .user, text: String(repeating: "字", count: 100) + "\($0)")
    }
    let kept = LiteRTLMRuntimeBackend.historyFitting(long, contextSize: 4096)

    XCTAssertLessThan(kept.count, long.count)
    XCTAssertLessThanOrEqual(kept.reduce(0) { $0 + $1.text.count }, 4096 / 3)
    // What survives is the end of the conversation, in order.
    XCTAssertEqual(kept.last?.text, long.last?.text)
    XCTAssertEqual(kept.map(\.text), Array(long.suffix(kept.count)).map(\.text))
  }

  func testAShortHistoryIsKeptWhole() {
    let short = [
      RuntimeConversationTurn(role: .user, text: "what was asked"),
      RuntimeConversationTurn(role: .assistant, text: "answered"),
    ]
    XCTAssertEqual(
      LiteRTLMRuntimeBackend.historyFitting(short, contextSize: 4096).map(\.text),
      short.map(\.text)
    )
  }
}

private enum BackendInvocation: Equatable {
  case handshake
  case loadModel
  case startGeneration
  case cancelGeneration
  case resetSession
  case unloadModel
}

private actor AsyncAdmissionGate {
  init(requiredArrivals: Int) {
    self.requiredArrivals = requiredArrivals
  }

  private let requiredArrivals: Int
  private var arrivalCount = 0
  private var opened = false
  private var allArrivedContinuations: [CheckedContinuation<Void, Never>] = []
  private var waitingContinuations: [CheckedContinuation<Void, Never>] = []

  func arriveAndWait() async {
    arrivalCount += 1
    if arrivalCount == requiredArrivals {
      allArrivedContinuations.forEach { $0.resume() }
      allArrivedContinuations.removeAll()
    }
    guard !opened else {
      return
    }
    await withCheckedContinuation { continuation in
      waitingContinuations.append(continuation)
    }
  }

  func waitUntilAllArrive() async {
    guard arrivalCount < requiredArrivals else {
      return
    }
    await withCheckedContinuation { continuation in
      allArrivedContinuations.append(continuation)
    }
  }

  func open() {
    opened = true
    waitingContinuations.forEach { $0.resume() }
    waitingContinuations.removeAll()
  }
}

private actor ManualShutdownDeadline: RuntimeShutdownDeadline {
  private var fired = false
  private var armed = false
  private var armContinuations: [CheckedContinuation<Void, Never>] = []
  private var waitContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]

  func wait() async -> Bool {
    guard !Task.isCancelled else {
      return false
    }
    armed = true
    armContinuations.forEach { $0.resume() }
    armContinuations.removeAll()
    guard !fired else {
      return !Task.isCancelled
    }
    let waitId = UUID()
    await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { continuation in
        if fired || Task.isCancelled {
          continuation.resume()
        } else {
          waitContinuations[waitId] = continuation
        }
      }
    }, onCancel: {
      Task {
        await self.cancelWait(id: waitId)
      }
    })
    return !Task.isCancelled
  }

  func waitUntilArmed() async {
    guard !armed else {
      return
    }
    await withCheckedContinuation { continuation in
      armContinuations.append(continuation)
    }
  }

  func fire() {
    fired = true
    waitContinuations.values.forEach { $0.resume() }
    waitContinuations.removeAll()
  }

  private func cancelWait(id: UUID) {
    waitContinuations.removeValue(forKey: id)?.resume()
  }
}

private actor ShutdownWaitRecorder {
  private var waitCount = 0
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func recordWait() {
    waitCount += 1
    continuations.forEach { $0.resume() }
    continuations.removeAll()
  }

  func waitForWaitCount(_ expectedCount: Int) async {
    while waitCount < expectedCount {
      await withCheckedContinuation { continuation in
        continuations.append(continuation)
      }
    }
  }
}

private struct ManualShutdownDeadlineFactory: RuntimeShutdownDeadlineFactory {
  let deadline: ManualShutdownDeadline

  func makeDeadline() -> any RuntimeShutdownDeadline {
    deadline
  }
}

private actor RuntimeBackendSpy: RuntimeBackend {
  init(
    blockCancellations: Bool = false,
    blockUnloads: Bool = false,
    cancelAcknowledgementGenerationId: String? = nil
  ) {
    self.blockCancellations = blockCancellations
    self.blockUnloads = blockUnloads
    self.cancelAcknowledgementGenerationId =
      cancelAcknowledgementGenerationId
  }

  let capabilities = RuntimeCapabilities(
    runtimeName: "spy",
    supportsStreaming: true,
    supportsCancellation: true
  )

  private(set) var loadCallCount = 0
  private(set) var startCallCount = 0
  private(set) var cancelCallCount = 0
  private(set) var unloadCallCount = 0
  private var loadCallContinuations: [CheckedContinuation<Void, Never>] = []
  private var startCallContinuations: [CheckedContinuation<Void, Never>] = []
  private var loadContinuations:
    [CheckedContinuation<RuntimeModelLoadResult, Error>] = []
  private var startContinuations: [
    String: CheckedContinuation<RuntimeGenerationAcknowledgement, Error>
  ] = [:]
  private var shouldAutomaticallyAcknowledgeStarts = false
  private var shouldAutomaticallyCompleteLoads = false
  private let blockCancellations: Bool
  private let blockUnloads: Bool
  private let cancelAcknowledgementGenerationId: String?
  private var cancelCallContinuations: [CheckedContinuation<Void, Never>] = []
  private var cancelContinuations:
    [CheckedContinuation<RuntimeCancellationAcknowledgement, Error>] = []
  private var unloadCallContinuations: [CheckedContinuation<Void, Never>] = []
  private var unloadContinuations:
    [CheckedContinuation<RuntimeOperationCompletion, Error>] = []

  func loadModel(_ model: RuntimeModelRequest) async throws
    -> RuntimeModelLoadResult {
    loadCallCount += 1
    loadCallContinuations.forEach { $0.resume() }
    loadCallContinuations.removeAll()
    if shouldAutomaticallyCompleteLoads {
      return RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    }
    return try await withCheckedThrowingContinuation { continuation in
      loadContinuations.append(continuation)
    }
  }

  func waitForLoadCall(count: Int = 1) async {
    guard loadCallCount < count else {
      return
    }
    await withCheckedContinuation { continuation in
      loadCallContinuations.append(continuation)
    }
  }

  func completeLoads(with result: RuntimeModelLoadResult) {
    loadContinuations.forEach { $0.resume(returning: result) }
    loadContinuations.removeAll()
  }

  func failLoads(with error: Error) {
    loadContinuations.forEach { $0.resume(throwing: error) }
    loadContinuations.removeAll()
  }

  func automaticallyCompleteLoads() {
    shouldAutomaticallyCompleteLoads = true
  }

  func startGeneration(_ generation: RuntimeGenerationRequest) async throws
    -> RuntimeGenerationAcknowledgement {
    startCallCount += 1
    startCallContinuations.forEach { $0.resume() }
    startCallContinuations.removeAll()
    if shouldAutomaticallyAcknowledgeStarts {
      return RuntimeGenerationAcknowledgement(
        generationId: generation.generationId,
        accepted: true
      )
    }
    return try await withCheckedThrowingContinuation { continuation in
      startContinuations[generation.generationId] = continuation
    }
  }

  func waitForStartCall(count: Int) async {
    guard startCallCount < count else {
      return
    }
    await withCheckedContinuation { continuation in
      startCallContinuations.append(continuation)
    }
  }

  func completeStart(
    generationId: String,
    with result: RuntimeGenerationAcknowledgement
  ) {
    startContinuations.removeValue(forKey: generationId)?.resume(
      returning: result
    )
  }

  func failStart(generationId: String, with error: Error) {
    startContinuations.removeValue(forKey: generationId)?.resume(
      throwing: error
    )
  }

  func automaticallyAcknowledgeStarts() {
    shouldAutomaticallyAcknowledgeStarts = true
  }

  func cancelGeneration(generationId: String) async throws
    -> RuntimeCancellationAcknowledgement {
    cancelCallCount += 1
    cancelCallContinuations.forEach { $0.resume() }
    cancelCallContinuations.removeAll()
    if blockCancellations {
      return try await withCheckedThrowingContinuation { continuation in
        cancelContinuations.append(continuation)
      }
    }
    return RuntimeCancellationAcknowledgement(
      generationId: cancelAcknowledgementGenerationId ?? generationId,
      acknowledged: true
    )
  }

  func waitForCancelCall() async {
    guard cancelCallCount == 0 else {
      return
    }
    await withCheckedContinuation { continuation in
      cancelCallContinuations.append(continuation)
    }
  }

  func completeCancellations(
    with result: RuntimeCancellationAcknowledgement
  ) {
    cancelContinuations.forEach { $0.resume(returning: result) }
    cancelContinuations.removeAll()
  }

  private(set) var resetSessionIds: [String] = []

  func resetSession(sessionId: String) async throws -> RuntimeOperationCompletion {
    resetSessionIds.append(sessionId)
    return RuntimeOperationCompletion(completed: true)
  }

  func unloadModel() async throws -> RuntimeOperationCompletion {
    unloadCallCount += 1
    unloadCallContinuations.forEach { $0.resume() }
    unloadCallContinuations.removeAll()
    if blockUnloads {
      return try await withCheckedThrowingContinuation { continuation in
        unloadContinuations.append(continuation)
      }
    }
    return RuntimeOperationCompletion(completed: true)
  }

  func waitForUnloadCall() async {
    guard unloadCallCount == 0 else {
      return
    }
    await withCheckedContinuation { continuation in
      unloadCallContinuations.append(continuation)
    }
  }

  func completeUnloads(with result: RuntimeOperationCompletion) {
    unloadContinuations.forEach { $0.resume(returning: result) }
    unloadContinuations.removeAll()
  }

  func failUnloads(with error: Error) {
    unloadContinuations.forEach { $0.resume(throwing: error) }
    unloadContinuations.removeAll()
  }
}

private final class RuntimeEventRecorder: @unchecked Sendable {
  var events: [RuntimeGenerationEvent] {
    lock.lock()
    defer { lock.unlock() }
    return storedEvents
  }

  private let lock = NSLock()
  private var storedEvents: [RuntimeGenerationEvent] = []

  func record(_ event: RuntimeGenerationEvent) {
    lock.lock()
    storedEvents.append(event)
    lock.unlock()
  }
}

private final class RecordingLocalModelRuntimeBackend: LocalModelRuntimeBackend {
  private(set) var invocations: [BackendInvocation] = []
  var cancellationAcknowledged = true

  var invocationCount: Int {
    invocations.count
  }

  var capabilities: RuntimeCapabilities {
    invocations.append(.handshake)
    return RuntimeCapabilities(
      runtimeName: "recording",
      supportsStreaming: true,
      supportsCancellation: true
    )
  }

  func loadModel(_ model: RuntimeModelRequest) throws -> RuntimeModelLoadResult {
    invocations.append(.loadModel)
    return RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
  }

  func startGeneration(
    _ generation: RuntimeGenerationRequest
  ) throws -> RuntimeGenerationAcknowledgement {
    invocations.append(.startGeneration)
    return RuntimeGenerationAcknowledgement(
      generationId: generation.generationId,
      accepted: true
    )
  }

  func cancelGeneration(
    generationId: String
  ) throws -> RuntimeCancellationAcknowledgement {
    invocations.append(.cancelGeneration)
    return RuntimeCancellationAcknowledgement(
      generationId: generationId,
      acknowledged: cancellationAcknowledged
    )
  }

  func resetSession(sessionId: String) throws -> RuntimeOperationCompletion {
    invocations.append(.resetSession)
    return RuntimeOperationCompletion(completed: true)
  }

  func unloadModel() throws -> RuntimeOperationCompletion {
    invocations.append(.unloadModel)
    return RuntimeOperationCompletion(completed: true)
  }
}

private struct PrivateBackendError: Error {
  let diagnostic: String
}

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
  init(_ value: Value) {
    self.value = value
  }

  let value: Value
}

private final class RecordingGenerationEventSink: RuntimeGenerationEventSink {
  private(set) var events: [RuntimeGenerationEvent] = []

  func send(_ event: RuntimeGenerationEvent) {
    events.append(event)
  }
}

private final class BlockingFirstGenerationEventSink:
  RuntimeGenerationEventSink,
  @unchecked Sendable
{
  let firstSendEntered = DispatchSemaphore(value: 0)
  let releaseFirstSend = DispatchSemaphore(value: 0)

  var events: [RuntimeGenerationEvent] {
    lock.lock()
    defer { lock.unlock() }
    return recordedEvents
  }

  private let lock = NSLock()
  private var recordedEvents: [RuntimeGenerationEvent] = []
  private var shouldBlockFirstSend = true

  func send(_ event: RuntimeGenerationEvent) {
    lock.lock()
    let shouldBlock = shouldBlockFirstSend
    shouldBlockFirstSend = false
    lock.unlock()

    if shouldBlock {
      firstSendEntered.signal()
      releaseFirstSend.wait()
    }

    lock.lock()
    recordedEvents.append(event)
    lock.unlock()
  }
}

private final class BlockingTerminalGenerationEventSink:
  RuntimeGenerationEventSink,
  @unchecked Sendable
{
  let terminalSendEntered = DispatchSemaphore(value: 0)
  let releaseTerminalSend = DispatchSemaphore(value: 0)

  var events: [RuntimeGenerationEvent] {
    lock.lock()
    defer { lock.unlock() }
    return recordedEvents
  }

  private let lock = NSLock()
  private var recordedEvents: [RuntimeGenerationEvent] = []

  func send(_ event: RuntimeGenerationEvent) {
    if event.kind == .completed {
      terminalSendEntered.signal()
      releaseTerminalSend.wait()
    }
    lock.lock()
    recordedEvents.append(event)
    lock.unlock()
  }
}

private final class SharedGenerationEventRecorder {
  var events: [RuntimeGenerationEvent] = []
}

private final class ForwardingGenerationEventSink: RuntimeGenerationEventSink {
  init(recorder: SharedGenerationEventRecorder) {
    self.recorder = recorder
  }

  private let recorder: SharedGenerationEventRecorder

  func send(_ event: RuntimeGenerationEvent) {
    recorder.events.append(event)
  }
}

private final class ManualRuntimeEventScheduler: RuntimeEventScheduling {
  private var tasks: [ManualRuntimeScheduledTask] = []
  private(set) var cancelledTaskCount = 0
  var onSchedule: (() -> Void)?

  var scheduledDelays: [Int] {
    tasks.map(\.delayMilliseconds)
  }

  func schedule(
    afterMilliseconds delayMilliseconds: Int,
    _ operation: @escaping () -> Void
  ) -> RuntimeScheduledTask {
    let task = ManualRuntimeScheduledTask(
      delayMilliseconds: delayMilliseconds,
      operation: operation,
      onCancel: { [weak self] in
        self?.cancelledTaskCount += 1
      }
    )
    tasks.append(task)
    let callback = onSchedule
    onSchedule = nil
    callback?()
    return task
  }

  func runAll() {
    let pending = tasks
    tasks.removeAll()
    for task in pending where !task.isCancelled {
      task.run()
    }
  }

  func runAllIncludingCancelled() {
    let pending = tasks
    tasks.removeAll()
    for task in pending {
      task.run()
    }
  }
}

private final class ManualRuntimeScheduledTask: RuntimeScheduledTask {
  init(
    delayMilliseconds: Int,
    operation: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.delayMilliseconds = delayMilliseconds
    self.operation = operation
    self.onCancel = onCancel
  }

  let delayMilliseconds: Int
  private let operation: () -> Void
  private let onCancel: () -> Void
  private(set) var isCancelled = false

  func cancel() {
    guard !isCancelled else {
      return
    }
    isCancelled = true
    onCancel()
  }

  func run() {
    operation()
  }
}

private struct LiteRTLMBackendTestHarness {
  let backend: LiteRTLMRuntimeBackend
  let driver: LiteRTLMRuntimeDriverSpy
  let events: AsyncRuntimeEventRecorder
  let modelDirectory: URL

  init(
    backend: LiteRTLMRuntimeBackend,
    driver: LiteRTLMRuntimeDriverSpy,
    events: AsyncRuntimeEventRecorder,
    modelDirectory: URL
  ) {
    self.backend = backend
    self.driver = driver
    self.events = events
    self.modelDirectory = modelDirectory
  }
}

private struct FixedLiteRTLMRuntimeDriverFactory:
  LiteRTLMRuntimeDriverFactory
{
  let driver: LiteRTLMRuntimeDriverSpy

  func makeDriver() -> any LiteRTLMRuntimeDriving {
    driver
  }
}

private actor LiteRTLMRuntimeDriverSpy: LiteRTLMRuntimeDriving {
  private(set) var loadRequests: [LiteRTLMDriverLoadRequest] = []
  private(set) var generationRequests: [LiteRTLMDriverGenerationRequest] = []
  private(set) var cancelledSessionIds: [String] = []
  private(set) var resetSessionIds: [String] = []
  private(set) var unloadCount = 0
  private(set) var generationCompleted = false

  private var generationHandler:
    (@Sendable (String) async -> Void)?
  private var generationContinuation: CheckedContinuation<Void, Error>?
  private var generationCallWaiters: [CheckedContinuation<Void, Never>] = []

  func load(_ request: LiteRTLMDriverLoadRequest) async throws {
    loadRequests.append(request)
  }

  func generate(
    _ request: LiteRTLMDriverGenerationRequest,
    onChunk: @escaping @Sendable (String) async -> Void
  ) async throws {
    generationRequests.append(request)
    generationHandler = onChunk
    generationCallWaiters.forEach { $0.resume() }
    generationCallWaiters.removeAll()
    try await withCheckedThrowingContinuation { continuation in
      generationContinuation = continuation
    }
    generationCompleted = true
  }

  func cancel(sessionId: String) async throws {
    cancelledSessionIds.append(sessionId)
  }

  func resetSession(sessionId: String) async throws {
    resetSessionIds.append(sessionId)
  }

  func unload() async {
    unloadCount += 1
  }

  func waitForGenerationCall() async {
    guard generationRequests.isEmpty else {
      return
    }
    await withCheckedContinuation { continuation in
      generationCallWaiters.append(continuation)
    }
  }

  func emitChunk(_ chunk: String) async {
    await generationHandler?(chunk)
  }

  func finishGeneration() {
    generationContinuation?.resume()
    generationContinuation = nil
  }
}

private actor AsyncRuntimeEventRecorder {
  private(set) var events: [RuntimeGenerationEvent] = []
  private var waiters:
    [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func record(_ event: RuntimeGenerationEvent) {
    events.append(event)
    let ready = waiters.filter { events.count >= $0.count }
    waiters.removeAll { events.count >= $0.count }
    ready.forEach { $0.continuation.resume() }
  }

  func waitForCount(_ count: Int) async {
    guard events.count < count else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append((count, continuation))
    }
  }
}


private actor RealModelEventCollector {
  private(set) var kinds: [RuntimeGenerationEventKind] = []
  private(set) var text = ""
  private(set) var failureDescription: String?

  func reset() {
    kinds.removeAll()
    text = ""
    failureDescription = nil
  }

  var isTerminal: Bool {
    guard let last = kinds.last else {
      return false
    }
    return last == .completed || last == .cancelled || last == .failed
  }

  func record(_ event: RuntimeGenerationEvent) {
    kinds.append(event.kind)
    if let delta = event.delta {
      text += delta
    }
    if event.kind == .failed {
      failureDescription =
        "\(String(describing: event.failureCode)): \(event.message ?? "")"
    }
  }
}