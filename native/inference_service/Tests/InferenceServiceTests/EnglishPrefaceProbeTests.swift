import Foundation
import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether the English preface behaves, now that it is the one that ships.
///
/// `agent_prompt_composer.dart` carries a comment on its English branch
/// saying, in as many words, *"Mirrors the Chinese, which is what was probed;
/// this side has not been."* That was defensible while Chinese was the
/// default and English was the fallback for a question that happened to
/// arrive in it. It stopped being defensible the day the agent started
/// opening in English.
///
/// The Chinese side earned three findings the hard way, recorded in
/// `written-preface` and `tool-calling-readiness`: reworking the opening line
/// cost the model its own name at one seed in five; the capability line had
/// to exist because without it the model invented three café names and
/// promised to go and search a map it does not have; and the length rules had
/// to be measured as spread rather than as an average, because a small model
/// reads a ceiling as a target. This asks the same three questions of the
/// English text, which is a different text and not a translation of the one
/// that was measured.
///
/// Skipped unless `REAL_GEMMA_MODEL_PATH` is set: it loads a real model and
/// spends minutes. Report lines also append to `TOOL_PROBE_REPORT`, because
/// the runner eats buffered stdout.
///
/// ```sh
/// REAL_GEMMA_MODEL_PATH=…/gemma-4-E4B-it.litertlm \
/// TOOL_PROBE_REPORT=/tmp/english-preface.txt \
///   swift test --filter EnglishPrefaceProbeTests
/// ```
final class EnglishPrefaceProbeTests: XCTestCase {
  /// From `dart run tool/dump_preface.dart --english`, pasted whole.
  ///
  /// Whole rather than abbreviated, for the reason `ToolCallProbeTests`
  /// records: a probe of half the instruction measures a prompt the app does
  /// not send.
  static let englishPreface = """
    [Core identity]
    You are Lulo, a private assistant running on the user’s computer.
    When a tool can do the job, use the tool before answering. Beyond your tools you have no web, no maps, no location: say plainly when something is out of reach, never promise to look things up, and never invent shop names, addresses, or URLs.
    When asked your name or what you are, you are Lulo.
    Answer in natural spoken English. Be warm without pretending familiarity.
    Lead with the core of the answer; never open with how complex the question is, that the two things differ, or an acknowledgement like "Understood".
    State uncertainty honestly and never invent facts.

    [Spoken response]
    This is being spoken aloud, not written.
    One to three sentences answer most questions; go to seven or eight when the question needs steps, a comparison, or a reason. Stop when you are done, and never pad to fill the room.
    Do not use Markdown.
    Do not read full URLs aloud.
    Avoid long lists.
    Use short sentences that sound natural when spoken.

    [User preferences]
    Answer length: concise.
    """

  /// The Chinese gradient's five questions, asked in English.
  ///
  /// The same shape deliberately: a greeting, a yes-or-no, a definition with
  /// a how, and a comparison. What is being compared is the spread between
  /// them, so the questions have to span the same ground.
  static let gradient: [String] = [
    "What's your name?",
    "Morning!",
    "Should I warm up before a run?",
    "What is creatine, and how should I take it?",
    "Compare running and swimming for my knees, and say who each one suits",
  ]

  private func engine(_ modelPath: String) async throws -> Engine {
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: ToolCallProbeTests.probeBackend
      )
    )
    try await engine.initialize()
    return engine
  }

  private func ask(
    _ engine: Engine,
    _ question: String,
    seed: Int = 1,
    maxOutputTokens: Int = 256
  ) async throws -> String {
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: Message(Self.englishPreface),
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
      Message(question),
      maxOutputTokens: maxOutputTokens
    ) {
      reply += chunk.toString
    }
    return reply.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func testTheNameSurvivesSamplingInEnglish() async throws {
    // Identity at temperature 0.7 is sampled. The Chinese preface lost its
    // name three times in five when its opening line was reworked, and the
    // repair was one specific sentence in one specific slot. The English
    // text has that sentence in that slot; whether it holds is a different
    // question from whether the Chinese one does.
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the English persona check.")
    }
    let engine = try await engine(modelPath)

    var lulo = 0
    for seed in 1...5 {
      let reply = try await ask(engine, "What's your name?", seed: seed, maxOutputTokens: 64)
      if reply.contains("Lulo") { lulo += 1 }
      ToolCallProbeTests.report(
        "EN-PERSONA \(seed): " + reply.replacingOccurrences(of: "\n", with: " ")
      )
    }
    ToolCallProbeTests.report("EN-PERSONA: Lulo \(lulo)/5")
    XCTAssertGreaterThanOrEqual(lulo, 4, "The English preface is losing its name")
  }

  func testTheCapabilityBoundaryHoldsInEnglish() async throws {
    // The line this checks exists because of what happened without it: asked
    // for quiet cafés, the model invented three shops and promised to go and
    // search a map, in an app with no web, no maps and no location. Only the
    // hard half is asserted — no invented address, no promise to look it up —
    // because "said it plainly" is a judgement and the report carries the
    // text for a human to make it.
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the English boundary check.")
    }
    let engine = try await engine(modelPath)

    let promises = [
      "i'll look", "i will look", "let me search", "i'll search",
      "i'll check google", "searching now", "i'll find", "let me google",
    ]
    var clean = 0
    for seed in 1...3 {
      let reply = try await ask(
        engine,
        "Find me a quiet café near here that's open now.",
        seed: seed
      )
      let lowered = reply.lowercased()
      let promised = promises.first(where: { lowered.contains($0) })
      let linked = lowered.contains("http") || lowered.contains("www.")
      if promised == nil && !linked { clean += 1 }
      ToolCallProbeTests.report(
        "EN-BOUNDARY \(seed) promised=\(promised ?? "-") linked=\(linked): "
          + reply.replacingOccurrences(of: "\n", with: " ")
      )
    }
    ToolCallProbeTests.report("EN-BOUNDARY: clean \(clean)/3")
    XCTAssertEqual(clean, 3, "The English preface promised what it cannot do")
  }

  func testTheEnglishAnswersKeepTheirSpread() async throws {
    // Measured as spread, never as an average: a small model reads a ceiling
    // as a target, and a preface that makes every answer the same length has
    // failed even when that length is the right one. Asked in one
    // conversation, the way the app is used, so each answer is written in
    // sight of the last.
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the English spread check.")
    }
    let engine = try await engine(modelPath)
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: Message(Self.englishPreface),
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: 0.95,
          temperature: 0.7,
          seed: 1
        )
      )
    )

    // Room for the longest answer the preface permits, and then some. The
    // first run of this probe capped output at 320 tokens, and the two
    // heaviest answers came back cut mid-word — "twenty grams s", "the water
    // supports your". Their sentence counts were the cap's, not the model's,
    // and the assertion below passed on a number the instrument had made up.
    // A truncated answer is now reported and excluded rather than counted.
    var sentences: [Int] = []
    for question in Self.gradient {
      var reply = ""
      for try await chunk in conversation.sendMessageStream(
        Message(question),
        maxOutputTokens: 768
      ) {
        reply += chunk.toString
      }
      let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
      let finished = trimmed.last.map { ".!?\"'”)".contains($0) } ?? false
      let counted = trimmed.split(whereSeparator: { ".!?".contains($0) })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .count
      sentences.append(finished ? counted : -1)
      ToolCallProbeTests.report(
        "EN-SPREAD \(finished ? String(counted) : "TRUNCATED") sentences | "
          + "\(question) -> " + trimmed.replacingOccurrences(of: "\n", with: " ")
      )
    }
    XCTAssertFalse(
      sentences.contains(-1),
      "An answer was cut off, so its length is the cap's and not the model's"
    )
    ToolCallProbeTests.report("EN-SPREAD: \(sentences)")

    // The greeting must not be answered at the length of the comparison.
    // Deliberately loose: the claim is that the gradient survives, not that
    // any one answer hits a number.
    XCTAssertLessThanOrEqual(
      sentences[1], 3, "A greeting was answered like an essay"
    )
    XCTAssertGreaterThan(
      sentences[4], sentences[1],
      "The heaviest question got no more room than the greeting"
    )
  }

  func testHowTheSpreadComparesWithTheChinesePreface() async throws {
    // The English run came back [1, 2, 3, 3, 3] sentences and [16, 39, 185,
    // 367, 428] characters: the model expands, but never past three
    // sentences — it lengthens the sentences instead, in a preface whose
    // last line asks for short ones because they are being spoken aloud.
    //
    // Whether that is an English defect or the model's own habit cannot be
    // read off one column. Same model, same seed, same five questions in
    // both languages, reported side by side. Nothing is asserted beyond both
    // sides finishing their sentences: this is a comparison for a person to
    // read, and a threshold invented here would be a threshold invented.
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to compare the two prefaces.")
    }
    let engine = try await engine(modelPath)

    let chineseGradient = WrittenPrefaceProbeTests.gradient
    for (label, preface, questions) in [
      ("EN", Self.englishPreface, Self.gradient),
      ("ZH", WrittenPrefaceProbeTests.spokenPrefaceToday, chineseGradient),
    ] {
      let conversation = try await engine.createConversation(
        with: ConversationConfig(
          systemMessage: Message(preface),
          samplerConfig: try SamplerConfig(
            topK: 40, topP: 0.95, temperature: 0.7, seed: 1
          )
        )
      )
      var sentences: [Int] = []
      var characters: [Int] = []
      for question in questions {
        var reply = ""
        for try await chunk in conversation.sendMessageStream(
          Message(question),
          maxOutputTokens: 768
        ) {
          reply += chunk.toString
        }
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let counted = trimmed.split(whereSeparator: { ".!?。！？".contains($0) })
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .count
        sentences.append(counted)
        characters.append(trimmed.count)
        XCTAssertTrue(
          trimmed.last.map { ".!?。！？\"'”)".contains($0) } ?? false,
          "\(label) answer was cut off, so its length is the cap's"
        )
        ToolCallProbeTests.report(
          "COMPARE-\(label) \(counted) sentences \(trimmed.count) chars | "
            + trimmed.replacingOccurrences(of: "\n", with: " ")
        )
      }
      ToolCallProbeTests.report(
        "COMPARE-\(label): sentences \(sentences) chars \(characters)"
      )
    }
  }

  /// The shipped English spoken block, with one line replaced.
  ///
  /// The measured defect is not length, it is granularity: English answers
  /// the heaviest question in three sentences of 140 characters where
  /// Chinese uses five of 40, under a block whose last line asks for short
  /// sentences because they are being spoken aloud. The hypothesis is that
  /// "one to three sentences" reads as the rule and "seven or eight" as
  /// decoration, so the candidate says what expanding means: more sentences,
  /// not longer ones.
  static let candidateSpokenBlock =
    "One to three sentences answer most questions. When a question needs "
    + "steps, a comparison, or a reason, use more sentences rather than "
    + "longer ones — seven or eight short ones beat three long ones. Stop "
    + "when you are done, and never pad to fill the room."

  static var candidatePreface: String {
    englishPreface.replacingOccurrences(
      of:
        "One to three sentences answer most questions; go to seven or eight "
        + "when the question needs steps, a comparison, or a reason. Stop "
        + "when you are done, and never pad to fill the room.",
      with: candidateSpokenBlock
    )
  }

  func testWhetherEnglishCanBeAskedForMoreSentences() async throws {
    // Both conditions, three seeds each, because one draw is not a finding —
    // and the persona question rides along in every conversation, since the
    // last time a length line was edited on the Chinese side the model three
    // sections up stopped saying its own name.
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to compare the length lines.")
    }
    XCTAssertNotEqual(
      Self.candidatePreface, Self.englishPreface,
      "The candidate is the shipped text: the replacement did not match"
    )
    let engine = try await engine(modelPath)

    for (label, preface) in [
      ("SHIPPED", Self.englishPreface), ("CANDIDATE", Self.candidatePreface),
    ] {
      var heaviest: [Int] = []
      var named = 0
      for seed in 1...3 {
        let conversation = try await engine.createConversation(
          with: ConversationConfig(
            systemMessage: Message(preface),
            samplerConfig: try SamplerConfig(
              topK: 40, topP: 0.95, temperature: 0.7, seed: seed
            )
          )
        )
        for question in Self.gradient {
          var reply = ""
          for try await chunk in conversation.sendMessageStream(
            Message(question),
            maxOutputTokens: 768
          ) {
            reply += chunk.toString
          }
          let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
          if question == Self.gradient[0], trimmed.contains("Lulo") {
            named += 1
          }
          guard question == Self.gradient[4] else { continue }
          let counted = trimmed.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
          heaviest.append(counted)
          ToolCallProbeTests.report(
            "LENGTH-\(label) seed \(seed): \(counted) sentences "
              + "\(trimmed.count) chars | "
              + trimmed.replacingOccurrences(of: "\n", with: " ")
          )
        }
      }
      ToolCallProbeTests.report(
        "LENGTH-\(label): heaviest \(heaviest) named \(named)/3"
      )
    }
  }
}
