import XCTest

@testable import InferenceService

final class LocalModelRuntimeTests: XCTestCase {
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

private final class RecordingLocalModelRuntimeBackend: LocalModelRuntimeBackend {
  private(set) var invocationCount = 0

  var capabilities: RuntimeCapabilities {
    RuntimeCapabilities(
      runtimeName: "recording",
      supportsStreaming: true,
      supportsCancellation: true
    )
  }

  func loadModel(_ model: RuntimeModelRequest) throws -> RuntimeModelLoadResult {
    invocationCount += 1
    return RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
  }

  func startGeneration(
    _ generation: RuntimeGenerationRequest
  ) throws -> RuntimeGenerationAcknowledgement {
    invocationCount += 1
    return RuntimeGenerationAcknowledgement(
      generationId: generation.generationId,
      accepted: true
    )
  }

  func cancelGeneration(
    generationId: String
  ) throws -> RuntimeCancellationAcknowledgement {
    invocationCount += 1
    return RuntimeCancellationAcknowledgement(
      generationId: generationId,
      acknowledged: true
    )
  }

  func resetSession(sessionId: String) throws -> RuntimeOperationCompletion {
    invocationCount += 1
    return RuntimeOperationCompletion(completed: true)
  }

  func unloadModel() throws -> RuntimeOperationCompletion {
    invocationCount += 1
    return RuntimeOperationCompletion(completed: true)
  }
}

private final class RecordingGenerationEventSink: RuntimeGenerationEventSink {
  private(set) var events: [RuntimeGenerationEvent] = []

  func send(_ event: RuntimeGenerationEvent) {
    events.append(event)
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
    return task
  }

  func runAll() {
    let pending = tasks
    tasks.removeAll()
    for task in pending where !task.isCancelled {
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
