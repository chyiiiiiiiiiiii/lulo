import Foundation
import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether the typed-channel preface behaves, measured before it ships.
///
/// `answer-length-should-follow-the-question.md` earned a rule the hard
/// way: a 4B model's preface is measured as a whole, never edited a line
/// at a time — variant C added an escape clause to the length line and the
/// model three sections up stopped saying its own name. The written
/// preface is a new block, so the three things it could break are checked
/// against the real model:
///
/// 1. **Persona** — asked its name, it must still be Lulo.
/// 2. **Spread** — the five-question gradient, in one conversation, the
///    way the app is used. Wanted: short stays short, heavy expands.
/// 3. **Tool calling** — the clock must still be called under the new
///    block, because `tool-calling-readiness.md`'s whole table was taken
///    under the spoken one.
///
/// Skipped unless `REAL_GEMMA_MODEL_PATH` is set. Report lines also append
/// to `TOOL_PROBE_REPORT` when set, because the runner eats buffered
/// stdout.
final class WrittenPrefaceProbeTests: XCTestCase {
  /// From `dart run tool/dump_preface.dart --written`, pasted whole.
  static let writtenPreface = """
    [核心人格]
    你是 Lulo，在使用者電腦上運作的私人助手。被問到名字或身分時，你就是 Lulo。
    用臺灣繁體中文回答，親近但不裝熟。
    先回答核心；不要用「這個問題很複雜」、「兩者不一樣」、「明白了」這類開場。
    不確定時坦白說明，不捏造資訊。

    [文字回答方式]
    這是打字的對話，回答是用眼睛讀的。
    多數問題一到三句就夠；需要步驟、比較或說明原因時可以到七八句。講完就停，不要為了湊長度補話。
    需要列點時用「-」開頭的短行；不要用其他 Markdown 語法。

    [使用者偏好]
    回答長度：簡潔。
    """

  /// Today's real spoken preface, from `dart run tool/dump_preface.dart` —
  /// the control. The tool-call table's paste still carries the older
  /// opening line, so whether the current composer output keeps persona
  /// and tools has to be its own measurement, not an assumption.
  static let spokenPrefaceToday = """
    [核心人格]
    你是 Lulo，在使用者電腦上運作的私人助手。被問到名字或身分時，你就是 Lulo。
    用臺灣繁體中文回答，親近但不裝熟。
    先回答核心；不要用「這個問題很複雜」、「兩者不一樣」、「明白了」這類開場。
    不確定時坦白說明，不捏造資訊。

    [語音回答方式]
    這是用說的，不是用寫的。
    多數問題一到三句就夠；需要步驟、比較或說明原因時可以到七八句。講完就停，不要為了湊長度補話。
    不要使用 Markdown。
    不要朗讀完整 URL。
    避免冗長條列。
    使用適合自然朗讀的短句。

    [使用者偏好]
    回答長度：簡潔。
    """

  /// The same five-question gradient the length decision was made on.
  static let gradient: [String] = [
    "你叫什麼名字？",
    "早安！",
    "跑步前要暖身嗎？",
    "肌酸是什麼？該怎麼吃？",
    "幫我比較跑步和游泳對膝蓋的影響，還有各自適合什麼人",
  ]

  func testWhichLineStopsTheToolCalls() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the ablation.")
    }
    // Today's preface with exactly one line reverted per condition, so the
    // 5/5→0/5 regression names its own cause.
    let answerFirst = "先回答核心；不要用「這個問題很複雜」、「兩者不一樣」、「明白了」這類開場。"
    let oldOpening = "先回答核心；不確定時坦白說明，不捏造資訊。"
    let bLength = "多數問題一到三句就夠；需要步驟、比較或說明原因時可以到七八句。講完就停，不要為了湊長度補話。"
    let oldLength = "回答控制在三句話以內；講完就停，細節等使用者追問再說。"
    let conditions: [(String, String)] = [
      (
        "ablate opening→old",
        Self.spokenPrefaceToday.replacingOccurrences(
          of: answerFirst + "\n不確定時坦白說明，不捏造資訊。",
          with: oldOpening
        )
      ),
      (
        "ablate length→old",
        Self.spokenPrefaceToday.replacingOccurrences(
          of: bLength,
          with: oldLength
        )
      ),
    ]
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: ToolCallProbeTests.probeBackend
      )
    )
    try await engine.initialize()
    for (label, preface) in conditions {
      XCTAssertNotEqual(
        preface,
        Self.spokenPrefaceToday,
        "\(label): the replacement did not take, so this row would " +
          "silently re-measure the unablated preface"
      )
      var called = 0
      for seed in 1...5 {
        ToolCallProbeTests.clockExecutions = 0
        let conversation = try await engine.createConversation(
          with: ConversationConfig(
            systemMessage: Message(preface),
            tools: [ToolCallProbeTests.ClockTool()],
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
          Message("現在幾點？")
        ) {
          reply += chunk.toString
        }
        if ToolCallProbeTests.clockExecutions > 0 { called += 1 }
        _ = reply
      }
      ToolCallProbeTests.report("ABLATE \(label): called \(called)/5")
    }
  }

  func testTheNameSurvivesSamplingOnBothChannels() async throws {
    // Identity at temperature 0.7 is sampled, and one draw saying Gemma is
    // a different fact from three in five saying it. Five seeds per
    // channel; the bar is at least four answering as Lulo.
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the persona check.")
    }
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: ToolCallProbeTests.probeBackend
      )
    )
    try await engine.initialize()
    let shippedYesterday = Self.spokenPrefaceToday.replacingOccurrences(
      of: "先回答核心；不要用「這個問題很複雜」、「兩者不一樣」、「明白了」這類開場。",
      with: "第一句就要是答案本身，不要先說「這個問題很複雜」或「兩者不一樣」這類開場。"
    )
    for (label, preface) in [
      ("SPOKEN-TODAY", Self.spokenPrefaceToday),
      ("WRITTEN", Self.writtenPreface),
      ("BASELINE-ANSWERFIRST", shippedYesterday),
    ] {
      var lulo = 0
      for seed in 1...5 {
        let conversation = try await engine.createConversation(
          with: ConversationConfig(
            systemMessage: Message(preface),
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
          Message("你叫什麼名字？"),
          maxOutputTokens: 64
        ) {
          reply += chunk.toString
        }
        if reply.contains("Lulo") { lulo += 1 }
        ToolCallProbeTests.report(
          "PERSONA \(label) \(seed): "
            + reply.replacingOccurrences(of: "\n", with: " ")
        )
      }
      ToolCallProbeTests.report("PERSONA \(label): Lulo \(lulo)/5")
      if label != "BASELINE-ANSWERFIRST" {
        XCTAssertGreaterThanOrEqual(lulo, 4, "\(label) is losing its name")
      }
    }
  }

  func testTheWrittenPrefaceHoldsPersonaSpreadAndTools() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to probe the written preface.")
    }
    try await probe(
      label: "SPOKEN-TODAY",
      preface: Self.spokenPrefaceToday,
      modelPath: modelPath
    )
    try await probe(
      label: "WRITTEN",
      preface: Self.writtenPreface,
      modelPath: modelPath
    )
  }

  private func probe(
    label: String,
    preface: String,
    modelPath: String
  ) async throws {
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: ToolCallProbeTests.probeBackend
      )
    )
    try await engine.initialize()

    // 1 + 2: persona and spread, down one conversation like the app.
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: Message(preface),
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: 0.95,
          temperature: 0.7,
          seed: 1
        )
      )
    )
    var lengths: [Int] = []
    for (index, question) in Self.gradient.enumerated() {
      var reply = ""
      for try await chunk in conversation.sendMessageStream(
        Message(question),
        maxOutputTokens: 512
      ) {
        reply += chunk.toString
      }
      lengths.append(reply.count)
      ToolCallProbeTests.report(
        "\(label) q\(index + 1) (\(reply.count)): "
          + reply.replacingOccurrences(of: "\n", with: " ⏎ ")
      )
      if index == 0 {
        XCTAssertTrue(
          reply.contains("Lulo"),
          "The written block loosened the identity the way variant C did: "
            + reply
        )
      }
    }
    let spread =
      Double(lengths.max() ?? 1) / Double(max(lengths.min() ?? 1, 1))
    ToolCallProbeTests.report(
      "\(label) lengths=\(lengths) spread=\(String(format: "%.1f", spread))×"
    )
    XCTAssertGreaterThan(
      spread,
      2,
      "Every answer the same length is the flattening the length decision "
        + "exists to prevent."
    )

    // 3: the clock is still called under the written block.
    var called = 0
    for seed in 1...5 {
      ToolCallProbeTests.clockExecutions = 0
      let toolConversation = try await engine.createConversation(
        with: ConversationConfig(
          systemMessage: Message(preface),
          tools: [ToolCallProbeTests.ClockTool()],
          samplerConfig: try SamplerConfig(
            topK: 40,
            topP: 0.95,
            temperature: 0.7,
            seed: Int(seed)
          )
        )
      )
      var reply = ""
      for try await chunk in toolConversation.sendMessageStream(
        Message("現在幾點？")
      ) {
        reply += chunk.toString
      }
      if ToolCallProbeTests.clockExecutions > 0 {
        called += 1
      }
      ToolCallProbeTests.report(
        "\(label) tool \(seed): "
          + "\(ToolCallProbeTests.clockExecutions > 0 ? "called" : "silent") "
          + reply.replacingOccurrences(of: "\n", with: " ")
      )
    }
    ToolCallProbeTests.report("\(label) tool zh/app-preface: called \(called)/5")
    XCTAssertGreaterThanOrEqual(
      called,
      4,
      "The spoken preface calls 5/5; a written block that stops the calls "
        + "would be variant C all over again."
    )
  }
}
