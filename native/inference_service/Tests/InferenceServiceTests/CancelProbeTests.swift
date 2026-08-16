import Foundation
import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether cancelling actually stops the decode on the vendored runtime.
///
/// `LiteRTLMRuntimeBackend.cancelGeneration` abandons rather than stops,
/// and its comment says why — measured on **v0.14.0**, where
/// `CancelProcess` left a task pinned in the callback thread pool so
/// completely that the engine never recovered across four minutes. The
/// abandoned decode is left to burn its whole token budget while the next
/// generation waits for it, which is why stopping an answer and typing the
/// next question can sit for a minute with nothing on screen.
///
/// The runtime is v0.16.0 now, and that constraint has never been re-run
/// against it. This does, and it measures the two things the design turns
/// on: how long the stream takes to end after `cancel()`, and whether the
/// engine is usable immediately afterwards.
///
/// ```sh
/// REAL_GEMMA_MODEL_PATH="…/gemma-4-E4B-it.litertlm" \
///   TOOL_PROBE_BACKEND=gpu TOOL_PROBE_REPORT=/tmp/cancel.txt \
///   swift test --filter CancelProbeTests
/// ```
final class CancelProbeTests: XCTestCase {
  func testWhetherCancelEndsTheDecodeOrOnlyAbandonsIt() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the cancel probe.")
    }
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: ToolCallProbeTests.probeBackend
      )
    )
    try await engine.initialize()

    // A question with a long answer in it, so there is plenty of decode
    // left to cancel.
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: 0.95,
          temperature: 0.7,
          seed: 1
        )
      )
    )
    let started = Date()
    var chunks = 0
    var cancelSent: Date?
    var characters = 0
    var threw: String?
    do {
      for try await chunk in conversation.sendMessageStream(
        Message("請詳細說明馬拉松訓練的十六週課表，每一週都要寫。"),
        maxOutputTokens: 2048
      ) {
        chunks += 1
        characters += chunk.toString.count
        // Cancel once the answer is clearly under way, the way a user hits
        // stop a second or two in.
        if chunks == 12 {
          cancelSent = Date()
          try conversation.cancel()
        }
      }
    } catch {
      // Ending the stream by throwing CANCELLED is what a cancel that
      // actually cancels looks like. On v0.14.0 nothing ended at all.
      threw = String(describing: error)
    }
    let streamEnded = Date()
    guard let cancelSent else {
      throw XCTSkip("The answer ended before there was anything to cancel.")
    }
    let msToEnd = Int(streamEnded.timeIntervalSince(cancelSent) * 1000)
    ToolCallProbeTests.report(
      "CANCEL stream ended \(msToEnd)ms after cancel "
        + "(\(characters) chars over \(chunks) chunks, "
        + "\(Int(streamEnded.timeIntervalSince(started) * 1000))ms total, "
        + "threw: \(threw ?? "nothing"))"
    )

    // The half the old comment says is broken: is the engine usable now,
    // or does the abandoned decode still own it?
    let mark = Date()
    let second = try await engine.createConversation(
      with: ConversationConfig(
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: 0.95,
          temperature: 0.2,
          seed: 2
        )
      )
    )
    var reply = ""
    for try await chunk in second.sendMessageStream(
      Message("用一句話說早安。"),
      maxOutputTokens: 64
    ) {
      reply += chunk.toString
    }
    let afterMs = Int(Date().timeIntervalSince(mark) * 1000)
    ToolCallProbeTests.report(
      "CANCEL next answer took \(afterMs)ms: "
        + reply.replacingOccurrences(of: "\n", with: " ")
    )
    XCTAssertFalse(
      reply.isEmpty,
      "The engine never answered again after a cancel — the v0.14.0 wedge"
    )
  }
}
