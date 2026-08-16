import Foundation
import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether this app's own stack can look at a screenshot, and what looking
/// costs.
///
/// The feasibility of 「看一下我的螢幕」 was first measured through the pip
/// runtime's Python binding — 7.6 s to describe a real screenshot. That
/// proved the model and the C core; it did not prove the vendored Swift
/// wrapper, the GPU backend, or the engine-load cost of carrying a vision
/// executor the user may never use. This does. Skipped unless
/// `REAL_GEMMA_MODEL_PATH` is set; `VISION_PROBE_IMAGE` names the image,
/// or the probe writes a small synthetic one.
final class VisionProbeTests: XCTestCase {
  func testTheEngineDescribesAnImageAndSaysWhatItCost() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the vision probe.")
    }
    guard let imagePath = environment["VISION_PROBE_IMAGE"] else {
      throw XCTSkip("Set VISION_PROBE_IMAGE to a PNG to describe.")
    }

    // What the engine costs to open with no vision executor, as the app
    // loads today, so the number beside it means something.
    var mark = Date()
    let plain = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: .gpu
      )
    )
    try await plain.initialize()
    ToolCallProbeTests.report(
      "VISION init without vision: \(Self.ms(since: mark))ms"
    )

    mark = Date()
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: .gpu,
        visionBackend: .gpu
      )
    )
    try await engine.initialize()
    ToolCallProbeTests.report(
      "VISION init with vision: \(Self.ms(since: mark))ms"
    )

    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: Message(WrittenPrefaceProbeTests.writtenPreface),
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: 0.95,
          temperature: 0.7,
          seed: 1
        )
      )
    )
    mark = Date()
    var reply = ""
    for try await chunk in conversation.sendMessageStream(
      Message(
        contents: [
          .imageFile(imagePath),
          .text("用繁體中文描述這張截圖裡看得到什麼。兩三句就好。"),
        ],
        role: .user
      ),
      maxOutputTokens: 256
    ) {
      reply += chunk.toString
    }
    ToolCallProbeTests.report(
      "VISION look took \(Self.ms(since: mark))ms: "
        + reply.replacingOccurrences(of: "\n", with: " ")
    )
    XCTAssertFalse(reply.isEmpty, "The look came back with nothing at all")
  }

  private static func ms(since mark: Date) -> Int {
    Int(Date().timeIntervalSince(mark) * 1000)
  }
}
