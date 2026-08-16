import Foundation
import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether the answer *uses* the background it was handed, or *recites* it.
///
/// The clock and the frontmost app ride in the turn instruction because
/// 「現在幾點」 and 「我卡住了」 need them. The model then began opening
/// answers with them — 「Lulo 看到您現在的時間已經是 2026 年 8 月 17 日的
/// 凌晨一點點，而且您正在使用 Warp 終端機」 in front of a question about
/// what to eat. A labelled section in a prompt reads as something to use,
/// and a clock is the easiest thing in one to say.
///
/// The fix is a rule beside the sections, and this is its measurement: the
/// recital has to stop **without** making the facts unreachable, so an
/// unrelated question and two questions that are entirely about the
/// background are scored against each other.
final class BackgroundRecitalProbeTests: XCTestCase {
  /// The turn instruction `composeAgentPrompt` now produces, up to the
  /// question. From `dart run tool/dump_turn.dart` in `agent_core`.
  static let background = """
    [背景：現在]
    現在是 2026 年 8 月 17 日（星期一）01:05。

    [背景：桌面]
    使用者正在使用 Warp。

    以上「背景」只是你知道的事，不是問題的一部分。只有在問題真的需要時才用到它，不要在開頭複述。

    [問題]

    """

  func testBackgroundIsUsedWhenNeededAndNotRecitedWhenNot() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the background probe.")
    }
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: ToolCallProbeTests.probeBackend
      )
    )
    try await engine.initialize()
    let asks: [(label: String, question: String, needed: Bool)] = [
      ("unrelated", "待會要吃雞蛋，你覺得怎麼樣？", false),
      ("about-time", "現在幾點？", true),
      ("about-app", "我現在在用什麼？", true),
    ]
    for ask in asks {
      var recited = 0
      var used = 0
      for seed in 1...3 {
        let conversation = try await engine.createConversation(
          with: ConversationConfig(
            systemMessage: Message(WrittenPrefaceProbeTests.writtenPreface),
            samplerConfig: try SamplerConfig(
              topK: 40,
              topP: 0.95,
              temperature: 0.7,
              seed: seed
            )
          )
        )
        var reply = ""
        for try await chunk in conversation.sendMessageStream(
          Message(Self.background + ask.question),
          maxOutputTokens: 256
        ) {
          reply += chunk.toString
        }
        // Recital is scored on the opening, because that is where it
        // appeared and where it costs the reader — the first forty
        // characters are what the eye lands on.
        let opening = String(reply.prefix(40))
        if Self.mentionsBackground(opening) {
          recited += 1
        }
        if Self.mentionsBackground(reply) {
          used += 1
        }
        ToolCallProbeTests.report(
          "BACKGROUND \(ask.label) \(seed): "
            + String(reply.replacingOccurrences(of: "\n", with: " ").prefix(90))
        )
      }
      ToolCallProbeTests.report(
        "BACKGROUND \(ask.label): opened-with-it \(recited)/3, "
          + "used-anywhere \(used)/3"
      )
      if ask.needed {
        XCTAssertGreaterThanOrEqual(
          used,
          2,
          "\(ask.label): the rule made the background unreachable"
        )
      } else {
        XCTAssertLessThanOrEqual(
          recited,
          1,
          "\(ask.label): the answer still opens by reciting its background"
        )
      }
    }
  }

  /// Whether [text] names anything only the background could have told it.
  static func mentionsBackground(_ text: String) -> Bool {
    let marks = ["01:05", "Warp", "凌晨", "8 月 17", "一點零五", "一點五分"]
    return marks.contains { text.contains($0) }
  }
}
