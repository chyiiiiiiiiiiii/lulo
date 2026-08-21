import Foundation
import XCTest

@testable import InferenceService

/// Whether the conversation a cancel stopped can answer the next question.
///
/// `CancelProbeTests` measured the half the v0.14.0 comment worried about —
/// the engine recovers, a **new** conversation answers 2.7s later — and the
/// design was built on it. But production never opens a new conversation
/// after a cancel: `SystemLiteRTLMRuntimeDriver.cancel` stops the
/// conversation and leaves it in the dictionary, and the next turn of that
/// session reuses it. Measured live (2026-08-21), every generation after a
/// barge-in failed with `generationFailed` for the rest of the session —
/// the exact gap between what the probe proved and what the code does.
///
/// This probe walks the production path at the driver seam: generate,
/// cancel mid-stream, then ask the same session again.
///
/// ```sh
/// REAL_GEMMA_MODEL_PATH="…/gemma-4-E4B-it.litertlm" \
///   TOOL_PROBE_REPORT=/tmp/cancel-same-session.txt \
///   swift test --filter CancelSameSessionProbeTests
/// ```
final class CancelSameSessionProbeTests: XCTestCase {
  private actor Tally {
    private(set) var chunks = 0
    private(set) var reply = ""

    func bump() -> Int {
      chunks += 1
      return chunks
    }

    func append(_ text: String) {
      reply += text
    }
  }

  func testTheSameSessionAnswersAgainAfterACancel() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the cancel probe.")
    }
    let driver = SystemLiteRTLMRuntimeDriver()
    try await driver.load(
      LiteRTLMDriverLoadRequest(
        modelPath: modelPath,
        backend: .gpu,
        maxNumTokens: 4096,
        cacheDirectory: NSTemporaryDirectory()
      )
    )
    let sampler = LiteRTLMSamplerFingerprint(
      topK: 40,
      topP: 0.95,
      temperature: 0.7,
      seed: 1
    )
    func ask(_ prompt: String, maxTokens: Int) -> LiteRTLMDriverGenerationRequest {
      LiteRTLMDriverGenerationRequest(
        sessionId: "probe-session",
        systemInstruction: "",
        prompt: prompt,
        history: [],
        extraContext: [:],
        sampler: sampler,
        maxOutputTokens: maxTokens,
        contextSize: 4096
      )
    }

    // A question with a long answer in it, cancelled the way a barge-in
    // cancels it: mid-stream, through the driver.
    let first = Tally()
    var firstThrew: String?
    do {
      try await driver.generate(
        ask("請詳細說明馬拉松訓練的十六週課表，每一週都要寫。", maxTokens: 2048)
      ) { chunk in
        guard case .text = chunk else { return }
        if await first.bump() == 12 {
          try? await driver.cancel(sessionId: "probe-session")
        }
      }
    } catch {
      firstThrew = String(describing: error)
    }
    let cancelledAfter = await first.chunks
    guard cancelledAfter >= 12 else {
      throw XCTSkip("The answer ended before there was anything to cancel.")
    }

    // The production path: the user's next sentence, same session.
    let second = Tally()
    var secondThrew: String?
    do {
      try await driver.generate(
        ask("用一句話說早安。", maxTokens: 64)
      ) { chunk in
        if case .text(let text) = chunk {
          await second.append(text)
        }
      }
    } catch {
      secondThrew = String(describing: error)
    }
    let reply = await second.reply
    ToolCallProbeTests.report(
      "CANCEL-SAME-SESSION first threw: \(firstThrew ?? "nothing"); "
        + "second threw: \(secondThrew ?? "nothing"); "
        + "reply: \(reply.replacingOccurrences(of: "\n", with: " "))"
    )
    XCTAssertNil(
      secondThrew,
      "The session never answered again after its own cancel."
    )
    XCTAssertFalse(
      reply.isEmpty,
      "The session never answered again after its own cancel."
    )
  }
}
