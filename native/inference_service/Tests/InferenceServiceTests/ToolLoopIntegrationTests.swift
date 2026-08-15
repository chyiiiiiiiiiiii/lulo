import Foundation
import XCTest

@testable import InferenceService

/// The whole native half of the tool loop, against the real model: the
/// declarations go in as JSON, the model stops with a `toolCall` event, the
/// caller's results go back in as a continuation, and the final answer
/// quotes what the tool said.
///
/// This is the seam the Dart loop stands on, exercised end to end once so
/// the pieces the unit tests pin separately are known to meet. Skipped
/// unless `REAL_GEMMA_MODEL_PATH` is set, like every probe that costs real
/// inference.
final class ToolLoopIntegrationTests: XCTestCase {
  /// Collects every event the relay delivers.
  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RuntimeGenerationEvent] = []

    func record(_ event: RuntimeGenerationEvent) {
      lock.lock()
      storage.append(event)
      lock.unlock()
    }

    var events: [RuntimeGenerationEvent] {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }
  }

  func testTheModelAsksRunsAndReadsTheClockBack() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the tool-loop test.")
    }
    let recorder = Recorder()
    let relay = RuntimeGenerationEventRelay()
    await relay.attach { event in
      recorder.record(event)
    }
    let backend = LiteRTLMRuntimeBackend(eventRelay: relay)
    _ = try await backend.loadModel(
      RuntimeModelRequest(
        modelId: "gemma-4-E4B-it",
        modelPath: modelPath,
        contextSize: 4096
      )
    )
    let declarations = """
      [{"type":"function","function":{"name":"get_current_time",\
      "description":"Returns the current time on this computer.",\
      "parameters":{"type":"object","properties":{}}}}]
      """
    _ = try await backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "loop-1",
        sessionId: "loop-session",
        systemInstruction: ToolCallProbeTests.chinesePreface,
        prompt: "現在幾點？",
        context: [],
        history: [],
        temperature: 0.7,
        topP: 0.95,
        maxTokens: 128,
        seed: 1,
        toolsJson: declarations
      )
    )
    try await waitUntil("the model asks for the tool") {
      recorder.events.contains { $0.kind == .toolCall }
    }
    let request = recorder.events.first { $0.kind == .toolCall }
    let callsJson = try XCTUnwrap(request?.toolCallsJson)
    XCTAssertTrue(
      callsJson.contains("get_current_time"),
      "The model asked for something else: \(callsJson)"
    )

    _ = try await backend.startGeneration(
      RuntimeGenerationRequest(
        generationId: "loop-2",
        sessionId: "loop-session",
        systemInstruction: ToolCallProbeTests.chinesePreface,
        prompt: "",
        context: [],
        history: [],
        temperature: 0.7,
        topP: 0.95,
        maxTokens: 128,
        seed: 1,
        toolsJson: declarations,
        toolResponsesJson: """
          [{"name":"get_current_time","id":"","response":{"time":"02:53"}}]
          """
      )
    )
    try await waitUntil("the continuation completes") {
      recorder.events.contains {
        $0.kind == .completed && $0.generationId == "loop-2"
      }
    }
    let answer = recorder.events
      .filter { $0.generationId == "loop-2" && $0.kind == .delta }
      .compactMap(\.delta)
      .joined()
    print("TOOLLOOP answer: \(answer)")
    XCTAssertTrue(
      ToolCallProbeTests.answered(answer),
      "The answer does not quote the tool's clock: \(answer)"
    )
  }

  private func waitUntil(
    _ what: String,
    _ condition: () -> Bool
  ) async throws {
    for _ in 0..<600 where !condition() {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertTrue(condition(), "Timed out waiting until \(what)")
  }
}
