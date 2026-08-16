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

  func testAChangedSamplerRebuildsTheConversationInsteadOfRefusing()
    async throws
  {
    // The sampler is not part of a message — LiteRT-LM takes it once, in
    // ConversationConfig, and `sendMessageStream` has no argument for it. So
    // a session that has already answered cannot be handed a new one, and
    // until the answer style became a setting nothing ever tried: the app
    // sent the same three numbers forever, and the guard below never fired.
    //
    // Refusing is the wrong answer to that. It fails the turn the user just
    // asked, and every turn after it in that conversation. Rebuilding the
    // conversation is right, and costs one prefill of the history rather
    // than a model load — the same trade the system instruction already
    // makes two branches above.
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    func ask(
      _ id: String,
      temperature: Double
    ) -> RuntimeGenerationRequest {
      RuntimeGenerationRequest(
        generationId: id,
        sessionId: "session-7",
        prompt: "Hello",
        context: [],
        history: [],
        temperature: temperature,
        topP: 0.9,
        maxTokens: 16,
        seed: 7
      )
    }

    _ = try await harness.backend.startGeneration(ask("g1", temperature: 0.2))
    await harness.driver.waitForGenerationCall()
    await harness.driver.finishGeneration()
    await harness.events.waitForCount(2)

    // The user picks a different answer style and asks again.
    let second = try await harness.backend.startGeneration(
      ask("g2", temperature: 1)
    )

    XCTAssertTrue(
      second.accepted,
      "A style the user changed failed the next question instead of applying"
    )
    // waitForGenerationCall returns at once when any call has been recorded,
    // so this waits for the second one specifically.
    var requests = await harness.driver.generationRequests
    for _ in 0..<200 where requests.count < 2 {
      try await Task.sleep(nanoseconds: 2_000_000)
      requests = await harness.driver.generationRequests
    }
    XCTAssertEqual(requests.count, 2, "The second question never ran")
    XCTAssertEqual(
      requests.last?.sampler.temperature,
      1,
      "The new sampler never reached the driver"
    )
    let loads = await harness.driver.loadRequests.count
    XCTAssertEqual(
      loads,
      1,
      "Changing how an answer sounds reloaded the model"
    )
  }

  func testToolDeclarationsReachTheDriverAndResponsesReplaceThePrompt()
    async throws
  {
    // Tools are declared in Dart and executed in Dart; the runtime's part
    // is rendering the declarations into the template and carrying the
    // results back in. Both travel as opaque JSON — the backend must hand
    // them through without an opinion.
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    let declarations = #"[{"type":"function","function":{"name":"echo"}}]"#
    let first = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "g1",
        sessionId: "session-9",
        prompt: "Hello",
        context: [],
        history: [],
        temperature: 0.2,
        topP: 0.9,
        maxTokens: 16,
        seed: 7,
        toolsJson: declarations
      )
    )
    XCTAssertTrue(first.accepted)
    await harness.driver.waitForGenerationCall()
    await harness.driver.finishGeneration()
    await harness.events.waitForCount(2)

    // The model asked for a tool; the caller ran it and continues the same
    // session with the results and no prompt — the user's words for this
    // turn were already sent by g1.
    let responses = #"[{"name":"echo","id":"c1","response":{"ok":true}}]"#
    let second = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "g2",
        sessionId: "session-9",
        prompt: "",
        context: [],
        history: [],
        temperature: 0.2,
        topP: 0.9,
        maxTokens: 16,
        seed: 7,
        toolsJson: declarations,
        toolResponsesJson: responses
      )
    )
    XCTAssertTrue(
      second.accepted,
      "A continuation with an empty prompt is the tool loop's normal step"
    )
    var requests = await harness.driver.generationRequests
    for _ in 0..<200 where requests.count < 2 {
      try await Task.sleep(nanoseconds: 2_000_000)
      requests = await harness.driver.generationRequests
    }
    XCTAssertEqual(requests.first?.toolsJson, declarations)
    XCTAssertEqual(requests.last?.toolResponsesJson, responses)
  }

  func testTheLooksPictureRidesTheRequestToTheDriver() async throws {
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    _ = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "g1",
        sessionId: "session-9",
        prompt: "我在看什麼？",
        context: [],
        history: [],
        temperature: 0.2,
        topP: 0.9,
        maxTokens: 16,
        seed: 7,
        imagePath: "/tmp/look.png"
      )
    )
    await harness.driver.waitForGenerationCall()
    let request = await harness.driver.generationRequests.first
    XCTAssertEqual(request?.imagePath, "/tmp/look.png")
  }

  func testAnEmptyPromptWithoutToolResponsesIsStillRefused() async throws {
    // The empty-prompt allowance exists for tool continuations and for
    // nothing else; an ordinary request with nothing to say stays a
    // protocol error rather than becoming a blank generation.
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    do {
      _ = try await harness.backend.startGeneration(
        RuntimeGenerationRequest(
          generationId: "g1",
          sessionId: "session-9",
          prompt: "",
          context: [],
          history: [],
          temperature: 0.2,
          topP: 0.9,
          maxTokens: 16,
          seed: 7
        )
      )
      XCTFail("An empty prompt with no tool responses was accepted")
    } catch {
      // Expected: the request never reaches the driver.
      let requests = await harness.driver.generationRequests
      XCTAssertTrue(requests.isEmpty)
    }
  }

  func testAToolCallChunkIsTerminalAndCarriesTheCalls() async throws {
    // When the model stops to ask for tools, that is the end of this
    // generation — the loop's next step is a new generation on the same
    // session. The event must carry the calls, and nothing after it may
    // dress the same generation up as completed: a completed event behind
    // the toolCall would tell the caller the turn is over when the model
    // is still waiting for its results.
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    _ = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "g1",
        sessionId: "session-9",
        prompt: "Hello",
        context: [],
        history: [],
        temperature: 0.2,
        topP: 0.9,
        maxTokens: 16,
        seed: 7,
        toolsJson: #"[{"type":"function","function":{"name":"echo"}}]"#
      )
    )
    await harness.driver.waitForGenerationCall()
    let calls = #"[{"name":"echo","id":"c1","arguments":{}}]"#
    await harness.driver.emitToolCalls(calls)
    await harness.driver.finishGeneration()
    await harness.events.waitForCount(2)
    // Give any wrongly-emitted completion a chance to arrive before the
    // absence below is believed.
    try await Task.sleep(nanoseconds: 20_000_000)
    let events = await harness.events.events
    XCTAssertEqual(events.map(\.kind), [.started, .toolCall])
    XCTAssertEqual(events.last?.toolCallsJson, calls)
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
          systemInstruction: "",
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
          maxOutputTokens: 16,
          contextSize: 64
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

  func testLiteRTLMBackendCarriesTheSystemInstructionToTheDriver()
    async throws {
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }

    _ = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-1",
        sessionId: "session-7",
        systemInstruction: "You are Lulo.",
        prompt: "Hello",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 16,
        seed: 7
      )
    )
    await harness.driver.waitForGenerationCall()

    let requests = await harness.driver.generationRequests
    XCTAssertEqual(requests.first?.systemInstruction, "You are Lulo.")
  }

  func testLiteRTLMBackendCarriesTheWindowSizeToTheDriver() async throws {
    // The driver holds the live conversations, so it is the only place that
    // can notice one outgrowing the window — and it cannot notice without
    // being told how big the window is. The backend knows, from the model it
    // loaded; before this the driver never heard.
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }

    _ = try await harness.backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "generation-1",
        sessionId: "session-7",
        systemInstruction: "",
        prompt: "Hello",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 16,
        seed: 7
      )
    )
    await harness.driver.waitForGenerationCall()

    let requests = await harness.driver.generationRequests
    XCTAssertEqual(requests.first?.contextSize, 64)
  }

  func testSystemInstructionTakesRoomFromTheHistoryBudget() {
    let history = [
      RuntimeConversationTurn(role: .user, text: "0123456789"),
      RuntimeConversationTurn(role: .assistant, text: "0123456789"),
    ]
    // Ten ASCII characters cost four tokens plus six turn markers, so two
    // turns need twenty. A window with exactly that much free keeps both.
    let roomForBoth = LiteRTLMRuntimeBackend.historyFitting(
      history,
      systemInstruction: "",
      prompt: "",
      maxOutputTokens: 0,
      contextSize: 26
    )
    XCTAssertEqual(roomForBoth.count, 2)

    // The system instruction is prefilled into the same window, so it has to
    // be charged for; thirty bytes is ten tokens and one turn's worth of
    // history has to go.
    let roomForOne = LiteRTLMRuntimeBackend.historyFitting(
      history,
      systemInstruction: String(repeating: "a", count: 30),
      prompt: "",
      maxOutputTokens: 0,
      contextSize: 26
    )
    XCTAssertEqual(roomForOne.count, 1)
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

    // Since v0.16.0 the runtime's own cancel ends the decode — measured at
    // 27 ms in `CancelProbeTests`, against v0.14.0 where it wedged the
    // engine and the decode had to be left to burn its token budget while
    // the next question waited for it. The driver cancel is what makes
    // stopping actually stop, so it must be invoked.
    let cancelledSessionIds = await harness.driver.cancelledSessionIds
    XCTAssertEqual(cancelledSessionIds, ["session-1"])

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
    // Fencing is what hides the late chunk; the runtime's own cancel is
    // what stops the decode producing more of them, and since v0.16.0 it
    // does that in milliseconds rather than wedging the engine.
    XCTAssertFalse(cancelledSessionIds.isEmpty)
    XCTAssertEqual(
      deliveredDeltas,
      ["kept"]
    )
  }

  func testAStartCancelledWhileDrainingNeverClaimsTheEngine() async throws {
    // The cancel for a start still waiting out a drain finds nothing
    // active and answers unacknowledged — which must also mean the start
    // aborts when its turn comes. Claiming anyway makes a zombie: a
    // decode nobody wants, burning its whole budget while every real
    // turn is refused as instantly busy.
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    func generation(_ id: String) -> RuntimeGenerationRequest {
      RuntimeGenerationRequest(
        generationId: id,
        sessionId: "session-1",
        prompt: "hi",
        context: [],
        temperature: 0.3,
        topP: 0.9,
        maxTokens: 16,
        seed: 1
      )
    }
    _ = try await harness.backend.startGeneration(generation("generation-a"))
    await harness.driver.waitForGenerationCall()
    _ = try await harness.backend.cancelGeneration(
      generationId: "generation-a"
    )

    async let startB = harness.backend.startGeneration(
      generation("generation-b")
    )
    try await Task.sleep(nanoseconds: 150_000_000)
    let ack = try await harness.backend.cancelGeneration(
      generationId: "generation-b"
    )
    XCTAssertFalse(ack.acknowledged)

    await harness.driver.finishGeneration()
    var startBError: Error?
    do {
      _ = try await startB
    } catch {
      startBError = error
    }

    XCTAssertEqual(
      startBError as? RuntimeBoundaryError,
      .cancelled,
      "A start whose generation was cancelled while draining must abort."
    )
    let requests = await harness.driver.generationRequests.count
    XCTAssertEqual(
      requests,
      1,
      "The cancelled start claimed the engine anyway — a zombie."
    )
    await harness.driver.finishGeneration()
  }

  func testOneEngineAdmitsOneWaiterWhenTheDrainReleases() async throws {
    // Every waiter sleeps in the same drain loop, and the loop never
    // re-checks the claim after waking: when the abandoned decode ends,
    // all of them proceed and the engine gets two concurrent decodes —
    // the exact overlap the wait exists to prevent, and by the code's
    // own account an unrecoverable wedge.
    let harness = try await makeLiteRTLMBackendHarness()
    defer { try? FileManager.default.removeItem(at: harness.modelDirectory) }
    func generation(_ id: String) -> RuntimeGenerationRequest {
      RuntimeGenerationRequest(
        generationId: id,
        sessionId: "session-1",
        prompt: "hi",
        context: [],
        temperature: 0.3,
        topP: 0.9,
        maxTokens: 16,
        seed: 1
      )
    }
    _ = try await harness.backend.startGeneration(generation("generation-a"))
    await harness.driver.waitForGenerationCall()
    _ = try await harness.backend.cancelGeneration(
      generationId: "generation-a"
    )

    async let startB = harness.backend.startGeneration(
      generation("generation-b")
    )
    async let startC = harness.backend.startGeneration(
      generation("generation-c")
    )
    try await Task.sleep(nanoseconds: 150_000_000)
    await harness.driver.finishGeneration()

    var refusals: [RuntimeBoundaryError] = []
    do {
      _ = try await startB
    } catch {
      if let error = error as? RuntimeBoundaryError {
        refusals.append(error)
      }
    }
    do {
      _ = try await startC
    } catch {
      if let error = error as? RuntimeBoundaryError {
        refusals.append(error)
      }
    }

    XCTAssertEqual(
      refusals,
      [.generationBusy],
      "Exactly one waiter may claim the engine; the other is refused."
    )
    let requests = await harness.driver.generationRequests.count
    XCTAssertEqual(
      requests,
      2,
      "Two waiters were admitted onto one engine at once."
    )
    await harness.driver.finishGeneration()
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

  func testUnacknowledgedCancellationOfAStartingGenerationReleasesTheSlot()
    async throws
  {
    // The slot is claimed before the backend is awaited, and the backend's
    // start can block for minutes: LiteRT-LM abandons a cancelled decode
    // rather than stopping it, and the next start waits for it to burn its
    // whole token budget. Cancel while that is happening and the backend has
    // never seen the generation, so it answers acknowledged: false — which
    // means "I am not running it", the state the caller asked for. Reading
    // that as a failure and returning left the coordinator claimed forever,
    // and every later turn came back as an instant zero-character
    // "Response failed".
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
    func generation(_ id: String) -> RuntimeGenerationRequest {
      RuntimeGenerationRequest(
        generationId: id,
        sessionId: "session-1",
        prompt: "prompt",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 128,
        seed: 1
      )
    }
    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult

    // The first start is in flight and never answers — the drain wait.
    async let firstStart = coordinator.startGeneration(
      request: request,
      generation: generation("generation-1")
    )
    await backend.waitForStartCall(count: 1)

    // The user barges in. The backend has no such generation.
    await backend.acknowledgeCancellations(false)
    let cancellation = try await coordinator.cancelGeneration(
      request: request,
      generationId: "generation-1"
    )
    XCTAssertFalse(cancellation.acknowledged)

    // The next turn must be accepted, not refused as busy. Captured rather
    // than thrown: the first start is still suspended on a continuation, and
    // leaving this scope without resuming it deadlocks the test instead of
    // failing it.
    await backend.automaticallyAcknowledgeStarts()
    var secondStartError: Error?
    do {
      _ = try await coordinator.startGeneration(
        request: request,
        generation: generation("generation-2")
      )
    } catch {
      secondStartError = error
    }

    await backend.failStart(
      generationId: "generation-1",
      with: RuntimeBoundaryError.cancelled
    )
    _ = try? await firstStart

    XCTAssertNil(
      secondStartError,
      "The slot was never released, so the next turn was refused as busy."
    )
  }

  func testCancelOfAFencedGenerationStillReachesTheBackend() async throws {
    // The fence records that the slot let this generation go — it does not
    // mean the backend will never run it. A start waiting out a drain can
    // claim the engine after the fence was written, and the compensating
    // cancel arriving here is the only thing that stops that decode from
    // burning its whole budget as a zombie, failing every turn in between
    // as instantly busy. The backend's cancel is idempotent, so forwarding
    // costs nothing when the fence was right.
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
    async let loadResult = coordinator.loadModel(request: request, model: model)
    await backend.waitForLoadCall()
    await backend.completeLoads(
      with: RuntimeModelLoadResult(modelId: model.modelId, loaded: true)
    )
    _ = try await loadResult

    async let firstStart = coordinator.startGeneration(
      request: request,
      generation: RuntimeGenerationRequest(
        generationId: "generation-1",
        sessionId: "session-1",
        prompt: "prompt",
        context: [],
        temperature: 0.25,
        topP: 0.9,
        maxTokens: 128,
        seed: 1
      )
    )
    await backend.waitForStartCall(count: 1)

    // The backend has never seen the generation: the cancel is
    // unacknowledged and the id lands on the fence.
    await backend.acknowledgeCancellations(false)
    _ = try await coordinator.cancelGeneration(
      request: request,
      generationId: "generation-1"
    )
    let firstCancelCount = await backend.cancelCallCount
    XCTAssertEqual(firstCancelCount, 1)

    // The compensating cancel for the same id must still be forwarded.
    _ = try await coordinator.cancelGeneration(
      request: request,
      generationId: "generation-1"
    )
    let secondCancelCount = await backend.cancelCallCount
    XCTAssertEqual(
      secondCancelCount,
      2,
      "A cancel swallowed by the fence leaves the backend decode a zombie."
    )

    await backend.failStart(
      generationId: "generation-1",
      with: RuntimeBoundaryError.cancelled
    )
    _ = try? await firstStart
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
    // Two, deliberately: the duplicate is forwarded to the backend even
    // though the slot already let the generation go, because a start
    // waiting out a drain can claim the engine after the fence was
    // written — the forwarded cancel is what stops that zombie. The
    // backend's cancel is idempotent, so the duplicate costs nothing;
    // what stays single is the terminal event above.
    let cancelCallCount = await backend.cancelCallCount
    XCTAssertEqual(cancelCallCount, 2)

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

  /// Opt-in: what the budget says fits must actually fit.
  ///
  /// The estimate this budget rests on cannot be checked against a
  /// tokenizer, because LiteRT-LM does not expose one. It can be checked
  /// against the model: seed a conversation with exactly as much history as
  /// `historyFitting` allows and require a real answer back. Overflow does
  /// not degrade here, it fails, and the failure arrives as an empty
  /// terminal turn — so an answer with text in it is the evidence.
  ///
  /// Run in Latin script deliberately. Han was priced about right before
  /// and is priced about right now; English is where the budget became four
  /// times more generous, so English is where a new overflow would appear.
  ///
  /// Set REAL_GEMMA_MODEL_PATH to run it.
  func testRealGemmaAnswersWithAHistoryFilledToTheBudget() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the real-model smoke.")
    }

    let contextSize: Int64 = 4096
    let maxOutputTokens = 64
    let passphrase = "thimble-ferret"
    let prompt = "What was the passphrase I gave you? Reply with just the word."

    // Far more history than can fit, so the budget is what decides, not the
    // supply.
    //
    // One turn near the end carries a passphrase nothing else could supply.
    // Without it this test passes whether or not the history reached the
    // model at all — a short prompt on its own completes perfectly well, so
    // "it answered" would have proved only that nothing crashed. Recalling
    // the passphrase is what distinguishes a history that was seeded from
    // one that was silently dropped.
    var history = (1...400).map { index in
      RuntimeConversationTurn(
        role: index.isMultiple(of: 2) ? .assistant : .user,
        text: "Turn number \(index) of a long and ordinary English conversation."
      )
    }
    let passphraseTurn = 390
    history[passphraseTurn - 1] = RuntimeConversationTurn(
      role: .user,
      text: "Remember this for later: the passphrase is \(passphrase)."
    )
    let seeded = LiteRTLMRuntimeBackend.historyFitting(
      history,
      systemInstruction: "",
      prompt: prompt,
      maxOutputTokens: maxOutputTokens,
      contextSize: contextSize
    )
    let estimate = seeded.reduce(0) {
      $0 + LiteRTLMRuntimeBackend.estimatedTokenCount($1.text)
        + LiteRTLMRuntimeBackend.turnMarkerTokens
    }
    print(
      "BUDGET seeded_turns=\(seeded.count) of \(history.count) "
        + "estimated_history_tokens=\(estimate) "
        + "context=\(contextSize) reserved_output=\(maxOutputTokens)"
    )
    XCTAssertGreaterThan(
      seeded.count,
      0,
      "A budget that seeds nothing would make this prove nothing."
    )
    XCTAssertLessThan(seeded.count, history.count, "The supply must not be the limit.")
    XCTAssertTrue(
      seeded.contains { $0.text.contains(passphrase) },
      "The trimming must keep the tail, and the passphrase lives in it."
    )

    let collector = RealModelEventCollector()
    let relay = RuntimeGenerationEventRelay()
    await relay.attach { event in await collector.record(event) }
    let backend = LiteRTLMRuntimeBackend(eventRelay: relay)
    _ = try await backend.loadModel(
      RuntimeModelRequest(
        modelId: "gemma-4-E4B-it",
        modelPath: modelPath,
        contextSize: contextSize
      )
    )

    _ = try await backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "budget-1",
        sessionId: "budget-1",
        prompt: prompt,
        context: [],
        history: history,
        temperature: 0.7,
        topP: 0.95,
        maxTokens: Int64(maxOutputTokens),
        seed: 7
      )
    )
    let deadline = Date().addingTimeInterval(600)
    while Date() < deadline, await !collector.isTerminal {
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    let kinds = await collector.kinds
    let text = await collector.text
    let failure = await collector.failureDescription
    print("BUDGET kinds=\(kinds.last.map(String.init(describing:)) ?? "none")")
    print("BUDGET answer=\(text)")
    if let failure {
      print("BUDGET failure=\(failure)")
    }

    XCTAssertNil(failure, "A history sized to the budget must not overflow.")
    XCTAssertEqual(kinds.last, .completed)
    XCTAssertFalse(
      text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "An empty terminal turn is what overflow looks like from here."
    )
    XCTAssertTrue(
      text.lowercased().contains(passphrase),
      "The model must recall a passphrase from turn \(passphraseTurn), which "
        + "proves the seeded history reached it rather than being dropped. "
        + "It answered: \(text)"
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
    let kept = LiteRTLMRuntimeBackend.historyFitting(
      long,
      systemInstruction: "",
      prompt: "接下來呢",
      maxOutputTokens: 512,
      contextSize: 4096
    )

    XCTAssertLessThan(kept.count, long.count)
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
      LiteRTLMRuntimeBackend.historyFitting(
        short,
        systemInstruction: "",
        prompt: "and then?",
        maxOutputTokens: 512,
        contextSize: 4096
      ).map(\.text),
      short.map(\.text)
    )
  }

  // MARK: - The context budget

  func testTheTokenEstimateNeverFallsBelowOneTokenPerThreeUTF8Bytes() {
    // The estimate exists to stop an overflow, so it may sit above the
    // tokenizer but never below it. Han is three UTF-8 bytes per character
    // and Gemma holds the common characters whole, so one token per three
    // bytes is what Han actually costs — anything looser prices Chinese
    // below the truth and lets the window overflow again.
    for sample in [
      "hello world",
      "字字字字字",
      "混合 mixed 文字 text 123",
      "😀🚀",
      "",
    ] {
      let estimate = LiteRTLMRuntimeBackend.estimatedTokenCount(sample)
      XCTAssertGreaterThanOrEqual(
        estimate * 3,
        sample.utf8.count,
        "\(sample.debugDescription) was estimated below the byte floor."
      )
    }
  }

  func testTheTokenEstimateChargesHanAtLeastOneTokenPerCharacter() {
    // The specific regression a byte divisor invites: dividing by four
    // prices a Chinese character at 0.75 tokens, and a window's worth of
    // Chinese then looks like three quarters of a window.
    let han = String(repeating: "字", count: 4096)
    XCTAssertGreaterThanOrEqual(
      LiteRTLMRuntimeBackend.estimatedTokenCount(han),
      4096,
      "Han must never be estimated below one token per character."
    )
  }

  func testLatinHistoryIsNotTruncatedAsThoughEveryCharacterWereAToken() {
    // The old budget charged one token per character, which is close enough
    // for Han and roughly four times too expensive for English: a history
    // that fits the window comfortably was thrown away to fit a limit that
    // did not exist. Sixty turns of this are about 2,600 UTF-8 bytes, well
    // inside a 4,096-token window once the answer has its room.
    let english = (1...60).map { index in
      RuntimeConversationTurn(
        role: index.isMultiple(of: 2) ? .assistant : .user,
        text: "This is turn number \(index) of an ordinary English conversation."
      )
    }
    let kept = LiteRTLMRuntimeBackend.historyFitting(
      english,
      systemInstruction: "",
      prompt: "What did we say at the start?",
      maxOutputTokens: 512,
      contextSize: 4096
    )

    XCTAssertEqual(
      kept.count,
      english.count,
      "An English history this short must survive a 4,096-token window whole."
    )
  }

  func testTheHistoryBudgetReservesRoomForTheAnswerAndThePrompt() {
    // A third of the window was a stand-in for arithmetic nobody did: the
    // answer the model is about to write, and the prompt that provokes it,
    // both occupy the same window as the history. Reserving nearly all of
    // it for output must leave the history nothing.
    let history = (1...40).map {
      RuntimeConversationTurn(role: .user, text: String(repeating: "字", count: 100) + "\($0)")
    }
    let starved = LiteRTLMRuntimeBackend.historyFitting(
      history,
      systemInstruction: "",
      prompt: "接下來呢",
      maxOutputTokens: 4000,
      contextSize: 4096
    )
    XCTAssertTrue(
      starved.isEmpty,
      "An answer reserving almost the whole window leaves no room to seed."
    )

    // And the same history, with the answer asking for little, keeps more
    // than the fixed third ever allowed.
    let roomy = LiteRTLMRuntimeBackend.historyFitting(
      history,
      systemInstruction: "",
      prompt: "接下來呢",
      maxOutputTokens: 128,
      contextSize: 4096
    )
    XCTAssertGreaterThan(roomy.count, starved.count)
  }

  func testAPromptThatFillsTheWindowLeavesNoRoomForHistory() {
    // The prompt is not free either. One that alone exceeds the window must
    // not be handed a history on top of it.
    let history = [
      RuntimeConversationTurn(role: .user, text: "what was asked"),
      RuntimeConversationTurn(role: .assistant, text: "answered"),
    ]
    XCTAssertTrue(
      LiteRTLMRuntimeBackend.historyFitting(
        history,
        systemInstruction: "",
        prompt: String(repeating: "字", count: 4096),
        maxOutputTokens: 128,
        contextSize: 4096
      ).isEmpty
    )
  }

  func testTheSeededHistoryAndPromptStayInsideTheWindowTheyWereGiven() {
    // The property the whole budget exists for: whatever survives, plus the
    // prompt, plus the reserved answer, must fit what the model was loaded
    // with. Checked against the estimator rather than a magic fraction.
    let history = (1...80).map { index in
      RuntimeConversationTurn(
        role: index.isMultiple(of: 2) ? .assistant : .user,
        text: index.isMultiple(of: 3)
          ? String(repeating: "字", count: 60)
          : "An ordinary English turn, number \(index), of moderate length."
      )
    }
    let prompt = "So what did we conclude?"
    let maxOutputTokens = 512
    let contextSize: Int64 = 4096
    let kept = LiteRTLMRuntimeBackend.historyFitting(
      history,
      systemInstruction: "",
      prompt: prompt,
      maxOutputTokens: maxOutputTokens,
      contextSize: contextSize
    )

    let seeded = kept.reduce(0) {
      $0 + LiteRTLMRuntimeBackend.estimatedTokenCount($1.text)
    }
    XCTAssertLessThanOrEqual(
      seeded + LiteRTLMRuntimeBackend.estimatedTokenCount(prompt) + maxOutputTokens,
      Int(contextSize)
    )
  }

  func testALiveConversationWithRoomLeftTakesTheNextTurn() {
    // The ordinary case: a conversation a few turns old has most of the
    // window left, and rebuilding it would throw away a prefilled cache for
    // nothing.
    XCTAssertTrue(
      LiteRTLMRuntimeBackend.liveConversationHasRoomForTurn(
        heldTokens: 300,
        prompt: "接下來呢",
        maxOutputTokens: 2048,
        contextSize: 4096
      )
    )
  }

  func testALiveConversationThatOutgrewTheWindowIsRebuiltInstead() {
    // `historyFitting` bounds the window only where a conversation is
    // created. Every turn after the first goes to a conversation the runtime
    // already holds, and its KV cache grows with the whole turn instruction —
    // memories, the clock, and up to `maxDocumentCharacters` of document —
    // plus the answer. Nothing measured that, so a long conversation walked
    // past the window and the overflow arrived as an empty answer.
    XCTAssertFalse(
      LiteRTLMRuntimeBackend.liveConversationHasRoomForTurn(
        heldTokens: 3000,
        prompt: "接下來呢",
        maxOutputTokens: 2048,
        contextSize: 4096
      )
    )
  }

  func testTheLiveCheckReservesTheSameRoomAsTheSeedingBudget() {
    // The two paths have to agree, or a conversation is refused room it
    // would have been seeded with — or worse, kept past what seeding would
    // have allowed. Held exactly to the boundary fits; one token more does
    // not.
    let prompt = "接下來呢"
    let maxOutputTokens = 512
    let contextSize: Int64 = 4096
    let boundary =
      Int(contextSize) - maxOutputTokens
      - LiteRTLMRuntimeBackend.estimatedTokenCount(prompt)
      - LiteRTLMRuntimeBackend.turnMarkerTokens

    XCTAssertTrue(
      LiteRTLMRuntimeBackend.liveConversationHasRoomForTurn(
        heldTokens: boundary,
        prompt: prompt,
        maxOutputTokens: maxOutputTokens,
        contextSize: contextSize
      )
    )
    XCTAssertFalse(
      LiteRTLMRuntimeBackend.liveConversationHasRoomForTurn(
        heldTokens: boundary + 1,
        prompt: prompt,
        maxOutputTokens: maxOutputTokens,
        contextSize: contextSize
      )
    )
  }

  func testAConversationHoldingNothingYetIsNeverRebuilt() {
    // A token count the runtime could not produce reads as zero, and zero
    // must not be the thing that throws away a live conversation on every
    // turn. Refusing to rebuild is the safe reading: the seeding budget
    // still bounds whatever gets rebuilt later.
    XCTAssertTrue(
      LiteRTLMRuntimeBackend.liveConversationHasRoomForTurn(
        heldTokens: 0,
        prompt: "接下來呢",
        maxOutputTokens: 2048,
        contextSize: 4096
      )
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
      acknowledged: cancellationAcknowledged
    )
  }

  /// Set false to model a backend that never registered the generation —
  /// which is what it answers when the start is still in flight.
  var cancellationAcknowledged = true

  func acknowledgeCancellations(_ acknowledged: Bool) {
    cancellationAcknowledged = acknowledged
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
    (@Sendable (LiteRTLMDriverChunk) async -> Void)?
  private var generationContinuation: CheckedContinuation<Void, Error>?
  private var generationCallWaiters: [CheckedContinuation<Void, Never>] = []

  func load(_ request: LiteRTLMDriverLoadRequest) async throws {
    loadRequests.append(request)
  }

  func generate(
    _ request: LiteRTLMDriverGenerationRequest,
    onChunk: @escaping @Sendable (LiteRTLMDriverChunk) async -> Void
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
    await generationHandler?(.text(chunk))
  }

  func emitToolCalls(_ callsJson: String) async {
    await generationHandler?(.toolCalls(callsJson))
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