import Dispatch
import XCTest

@testable import InferenceService

final class LocalModelRuntimeTests: XCTestCase {
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
    await backend.completeLoad(
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

private actor RuntimeBackendSpy: RuntimeBackend {
  let capabilities = RuntimeCapabilities(
    runtimeName: "spy",
    supportsStreaming: true,
    supportsCancellation: true
  )

  private(set) var loadCallCount = 0
  private var loadCallContinuations: [CheckedContinuation<Void, Never>] = []
  private var loadContinuation: CheckedContinuation<RuntimeModelLoadResult, Error>?

  func loadModel(_ model: RuntimeModelRequest) async throws
    -> RuntimeModelLoadResult {
    loadCallCount += 1
    loadCallContinuations.forEach { $0.resume() }
    loadCallContinuations.removeAll()
    return try await withCheckedThrowingContinuation { continuation in
      loadContinuation = continuation
    }
  }

  func waitForLoadCall() async {
    guard loadCallCount == 0 else {
      return
    }
    await withCheckedContinuation { continuation in
      loadCallContinuations.append(continuation)
    }
  }

  func completeLoad(with result: RuntimeModelLoadResult) {
    loadContinuation?.resume(returning: result)
    loadContinuation = nil
  }

  func startGeneration(_ generation: RuntimeGenerationRequest) async throws
    -> RuntimeGenerationAcknowledgement {
    RuntimeGenerationAcknowledgement(
      generationId: generation.generationId,
      accepted: true
    )
  }

  func cancelGeneration(generationId: String) async throws
    -> RuntimeCancellationAcknowledgement {
    RuntimeCancellationAcknowledgement(
      generationId: generationId,
      acknowledged: true
    )
  }

  func resetSession(sessionId: String) async throws -> RuntimeOperationCompletion {
    RuntimeOperationCompletion(completed: true)
  }

  func unloadModel() async throws -> RuntimeOperationCompletion {
    RuntimeOperationCompletion(completed: true)
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
