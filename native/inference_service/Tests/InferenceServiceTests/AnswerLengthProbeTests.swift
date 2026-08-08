import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether the answer's length follows the question, or the instruction.
///
/// Every answer the app gives is the same length. The instruction says 「三句
/// 話以內」 — a ceiling — and the model treats it as a target: four questions
/// of wildly different weight all come back in exactly three sentences, the
/// third of them padding. What is wanted is one sentence where one will do
/// and eight where eight are needed.
///
/// The existing evidence cannot settle this. It compared "a sentence budget"
/// against "the adjective 簡潔 alone" and measured the **mean** length: 172
/// characters against 64. Mean length says nothing about whether the length
/// tracks the question, and a model that answers everything in three
/// sentences and one that answers everything in eight both have a defensible
/// mean.
///
/// So the thing measured here is the **spread**, and the shortest answer.
/// Padding cannot be scored at all and is printed instead — a third sentence
/// that says 「使用前最好還是先了解相關的劑量」 is not something a character
/// count can see.
///
/// The two candidates beside the current instruction come from products that
/// run this in production, not from invention: Deepgram's voice agent guide
/// specifies "1-2 sentences (under 120 characters typically, **max 300 for
/// complex information**)" — a typical value and a raised ceiling, both
/// numbered — and ElevenLabs' is "under 3 sentences **unless the user asks
/// for details**" — a ceiling with an escape. Both were written for frontier
/// models; this one calls a registered tool 0 times out of 5 under this same
/// preface, so the shape may transfer and the wording may not.
///
/// ```sh
/// REAL_GEMMA_MODEL_PATH="…/Lulo/models/gemma-4-E4B-it.litertlm" \
///   swift test --filter AnswerLengthProbeTests
/// ```
final class AnswerLengthProbeTests: XCTestCase {
  /// The app's preface with the length line left as a placeholder.
  ///
  /// Everything else is held identical, including 「回答長度：簡潔」 lower
  /// down — it is what the app really sends, and removing it would measure a
  /// prompt nobody uses. It may well fight the two candidates, which is
  /// itself worth seeing.
  static func preface(length: String) -> String {
    """
    [核心人格]
    你是 Lulo，在使用者電腦上運作的私人助手。
    用臺灣繁體中文回答，親近但不裝熟。
    先回答核心；不確定時坦白說明，不捏造資訊。

    [語音回答方式]
    這是用說的，不是用寫的。
    \(length)
    不要使用 Markdown。
    不要朗讀完整 URL。
    避免冗長條列。
    使用適合自然朗讀的短句。

    [使用者偏好]
    回答長度：簡潔。
    """
  }

  struct Variant {
    let label: String
    let length: String
  }

  static let variants: [Variant] = [
    Variant(
      label: "A ceiling (today)",
      length: "回答控制在三句話以內；講完核心就停，細節等使用者追問再說。"
    ),
    Variant(
      label: "B typical + bounded exception",
      length:
        "多數問題一到三句就夠；需要步驟、比較或說明原因時可以到七八句。"
        + "講完就停，不要為了湊長度補話。"
    ),
    Variant(
      label: "C ceiling + escape",
      length: "回答控制在三句話以內，除非使用者要細節或問題本身需要。"
    ),
  ]

  /// Five questions chosen for a deliberate gradient of weight, from one that
  /// one sentence answers completely to one that cannot be answered well in
  /// fewer than several.
  static let questions: [String] = [
    "你叫什麼名字？",
    "早安",
    "跑步前要暖身嗎？",
    "肌酸怎麼吃？有什麼副作用？",
    "幫我比較跑步和游泳對膝蓋的影響，還有各自適合什麼人。",
  ]

  /// Sentences, counted the way Chinese ends them.
  static func sentences(in text: String) -> Int {
    text.filter { "。！？!?".contains($0) }.count
  }

  /// One question, asked once, on a conversation of its own.
  ///
  /// A fresh engine per question so nothing carries over: an answer that
  /// followed a long one would be shaped by it rather than by the
  /// instruction, and the app starts every conversation clean.
  private func ask(
    _ question: String,
    preface: String,
    seed: Int,
    modelPath: String
  ) async throws -> String {
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: LiteRTLMRuntimeConfiguration.defaultBackend == .gpu
          ? .gpu : .cpu(threadCount: nil),
        cacheDir: LiteRTLMRuntimeConfiguration.defaultCacheDirectory
      )
    )
    try await engine.initialize()
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: Message(preface),
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: 0.95,
          temperature: 0.7,
          // Fixed per question rather than per run, so the three variants
          // answer the same question from the same draw and differ only by
          // the instruction.
          seed: seed
        )
      )
    )
    var reply = ""
    for try await chunk in conversation.sendMessageStream(
      Message("[問題]\n\(question)"),
      maxOutputTokens: 512
    ) {
      reply += chunk.toString
    }
    return reply.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The same five questions down one conversation, which is how the app is
  /// actually used.
  ///
  /// The single-turn probe below shows the current instruction spreading 13
  /// to 89 characters, and the screenshot that started this shows four
  /// answers of exactly three sentences each. Both cannot be the instruction.
  /// The difference is that a real conversation carries the model's own
  /// previous answers in its KV cache, and the suspicion is that it copies
  /// their shape — the second answer is three sentences because the first
  /// one was, not because the question asked for three.
  ///
  /// If that is what is happening, a better instruction fixes less than it
  /// looks like it should, and this is the run that says so.
  /// Whether the first sentence carries the answer.
  ///
  /// Length turned out not to be the thing that hurts a spoken answer. Of the
  /// three long answers the adopted length rule produced, two opened with the
  /// answer — 「跑步前暖身是蠻建議的」, 「肌酸通常是每日服用」 — and the longest
  /// opened with 「跑步和游泳對膝蓋的影響是不同的」, fourteen characters that
  /// say nothing.
  ///
  /// That is what cannot be recovered in speech. Two hundred characters is
  /// thirty seconds, but thirty seconds is fine if the first five gave you
  /// the answer and barge-in works, which here it does. Five seconds of
  /// throat-clearing is not fine, because there is no way to skim past it.
  ///
  /// The pattern is that the model rambles *more* the harder the question —
  /// exactly when leading with the answer matters most. So the question is
  /// whether saying so explicitly moves it.
  ///
  /// Nothing here can be scored automatically. Whether a sentence is the
  /// answer or a preamble is a judgement, and a character count that tried
  /// would be the third scorer this project has been misled by. The first
  /// sentence of every answer is printed on its own line to be read.
  static let openers: [Variant] = [
    Variant(
      label: "core identity as it stands",
      length: "先回答核心；不確定時坦白說明，不捏造資訊。"
    ),
    Variant(
      label: "first sentence must be the answer",
      length:
        "第一句就要是答案本身。不要先說「這個問題很複雜」或「兩者是不同的」這類開場。"
        + "不確定時坦白說明，不捏造資訊。"
    ),
  ]

  /// The preface with the *core identity* line varied instead of the length
  /// one, and the length rule left at what the app now ships.
  static func openerPreface(core: String) -> String {
    """
    [核心人格]
    你是 Lulo，在使用者電腦上運作的私人助手。
    用臺灣繁體中文回答，親近但不裝熟。
    \(core)

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
  }

  /// Questions chosen to provoke a preamble: comparisons, choices and
  /// why-questions, which is where the rambling opener showed up.
  static let openerQuestions: [String] = [
    "幫我比較跑步和游泳對膝蓋的影響，還有各自適合什麼人。",
    "為什麼有些人跑步會膝蓋痛？",
    "我該選跑步機還是戶外跑？",
    "肌酸和乳清蛋白差在哪？",
    "減脂期要怎麼安排訓練？",
  ]

  /// The first sentence, the way Chinese ends one.
  static func firstSentence(of text: String) -> String {
    var out = ""
    for character in text {
      out.append(character)
      if "。！？!?".contains(character) {
        break
      }
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Writes a probe line where it will actually be seen.
  ///
  /// Not `print`. Under a real run the runtime writes hundreds of lines to
  /// stderr and this probe's own stdout did not survive it — the marker
  /// proved the loop ran and the lines were nowhere. stderr is the channel
  /// that demonstrably arrives.
  static func say(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
  }

  func testWhetherTheFirstSentenceCarriesTheAnswer() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the opener probe.")
    }

    for variant in Self.openers {
      Self.say("OPENER === \(variant.label) ===")
      let replies = try await askAll(
        Self.openerQuestions,
        preface: Self.openerPreface(core: variant.length),
        modelPath: modelPath
      )
      for (index, reply) in replies.enumerated() {
        Self.say("OPENER   Q\(index + 1) \(Self.openerQuestions[index])")
        Self.say("OPENER     first: \(Self.firstSentence(of: reply))")
        Self.say(
          "OPENER     whole: "
            + reply.replacingOccurrences(of: "\n", with: " ")
        )
      }
    }
  }

  /// All the questions down one conversation, in order.
  private func askAll(
    _ questions: [String],
    preface: String,
    modelPath: String
  ) async throws -> [String] {
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: LiteRTLMRuntimeConfiguration.defaultBackend == .gpu
          ? .gpu : .cpu(threadCount: nil),
        cacheDir: LiteRTLMRuntimeConfiguration.defaultCacheDirectory
      )
    )
    try await engine.initialize()
    // One conversation for all of them, which is the whole point.
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: Message(preface),
        samplerConfig: try SamplerConfig(
          topK: 40, topP: 0.95, temperature: 0.7, seed: 7)
      )
    )
    var replies: [String] = []
    for question in questions {
      var reply = ""
      for try await chunk in conversation.sendMessageStream(
        Message("[問題]\n\(question)"),
        maxOutputTokens: 512
      ) {
        reply += chunk.toString
      }
      replies.append(reply.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return replies
  }

  /// The same five questions down one conversation, which is how the app is
  /// actually used.
  ///
  /// The single-turn probe shows the current instruction spreading 13 to 89
  /// characters; the screenshot that started this shows four answers of
  /// exactly three sentences each. Both cannot be the instruction. The
  /// difference is that a real conversation carries the model's own previous
  /// answers in its KV cache, and the suspicion is that it copies their shape
  /// — the second answer is three sentences because the first one was, not
  /// because the question asked for three.
  ///
  /// If that is what is happening, a better instruction fixes less than it
  /// looks like it should, and this is the run that says so.
  func testWhetherOneConversationFlattensTheAnswers() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the length probe.")
    }

    for variant in Self.variants {
      Self.say("MULTITURN === \(variant.label) ===")
      let replies = try await askAll(
        Self.questions,
        preface: Self.preface(length: variant.length),
        modelPath: modelPath
      )
      for (index, reply) in replies.enumerated() {
        Self.say(
          "MULTITURN   Q\(index + 1) \(reply.count) chars, "
            + "\(Self.sentences(in: reply)) sentences — \(Self.questions[index])"
        )
        Self.say(
          "MULTITURN     "
            + reply.replacingOccurrences(of: "\n", with: " ")
        )
      }
      let lengths = replies.map(\.count)
      let shortest = lengths.min() ?? 0
      let longest = lengths.max() ?? 0
      Self.say(
        "MULTITURN   spread: shortest \(shortest), longest \(longest), "
          + "ratio \(longest / max(shortest, 1))"
      )
    }
  }

  func testWhetherTheAnswerLengthFollowsTheQuestion() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the length probe.")
    }

    for variant in Self.variants {
      var lengths: [Int] = []
      Self.say("LENGTH === \(variant.label) ===")
      for (index, question) in Self.questions.enumerated() {
        let reply = try await ask(
          question,
          preface: Self.preface(length: variant.length),
          seed: index + 1,
          modelPath: modelPath
        )
        lengths.append(reply.count)
        Self.say(
          "LENGTH   Q\(index + 1) \(reply.count) chars, "
            + "\(Self.sentences(in: reply)) sentences — \(question)"
        )
        Self.say("LENGTH     \(reply.replacingOccurrences(of: "\n", with: " "))")
      }
      let shortest = lengths.min() ?? 0
      let longest = lengths.max() ?? 0
      Self.say(
        "LENGTH   spread: shortest \(shortest), longest \(longest), "
          + "ratio \(longest / max(shortest, 1))"
      )
    }
  }
}
