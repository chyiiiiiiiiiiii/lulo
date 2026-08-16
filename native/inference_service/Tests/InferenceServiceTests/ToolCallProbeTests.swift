import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether gemma-4-E4B decides to call a tool when it needs one, and whether
/// being told the answer instead beats asking it to fetch one.
///
/// The tool is registered through the vendored `ConversationConfig(tools:)`
/// and **calling is counted by the tool body running**, never by reading
/// the final text. An earlier version of this probe searched the reply for
/// a sentinel the tool returned, which proves a call when found and proves
/// nothing when absent — and under this app's persona the model calls,
/// then paraphrases the unpronounceable sentinel away, so a year of
/// numbers read "declined" where the truth was "called and answered in
/// character". See the scoring section of
/// `docs/decisions/tool-calling-readiness.md`.
///
/// Every condition in one run, from one artifact, at the sampler settings
/// the app actually uses — an earlier version of this file was edited
/// between runs and left a table in
/// `docs/decisions/tool-calling-readiness.md` that it could no longer
/// reproduce. If you change the conditions, re-run everything and rewrite
/// the whole table, not the row you were looking at.
///
/// Skipped unless `REAL_GEMMA_MODEL_PATH` names an installed model, because
/// it is several minutes of real inference:
///
/// ```sh
/// REAL_GEMMA_MODEL_PATH="…/Lulo/models/gemma-4-E4B-it.litertlm" \
///   swift test --filter ToolCallProbeTests
/// ```
final class ToolCallProbeTests: XCTestCase {
  /// The clock the tool answers with. Chosen so the *minute* doubles as the
  /// sentinel: an invented time has sixty minutes to land on, so a reply
  /// carrying fifty-three is one the tool's answer actually reached.
  ///
  /// This used to be `TOOL-RAN-4718`, a string no model produces by
  /// accident — and that is exactly what broke a year of conclusions. The
  /// old scorer looked for the sentinel in the final text, which proves the
  /// tool ran when it is there and proves **nothing** when it is not. Under
  /// this app's instruction the model called the tool, was handed a string
  /// that is not a time, and answered like the spoken-Chinese assistant it
  /// was told to be — with a plausible clock and no sentinel. Without the
  /// instruction it parroted the sentinel back. The scorer turned that
  /// difference in *quoting* into a table about *calling*: 5/5 bare, 0/5
  /// under the preface, and a decision doc concluded the instruction
  /// suppresses the decision to call. Executions are counted directly now,
  /// and the tool answers with something a persona can actually say.
  static let toolClock = "02:53"

  /// Which compute backend the probe runs on.
  ///
  /// CPU by default, because every row already in
  /// `docs/decisions/tool-calling-readiness.md` was measured that way and a
  /// backend is a condition like any other. That default is itself worth
  /// noticing: `LiteRTLMRuntimeConfiguration.defaultBackend` is `.gpu` on
  /// arm64, so the whole table was taken on a backend the app does not use.
  /// It was left alone rather than quietly switched — the finding it supports
  /// is that a system instruction stops the model calling tools, which is not
  /// a thing a matrix-multiply kernel decides.
  ///
  /// `TOOL_PROBE_BACKEND=gpu` selects the app's, which is not optional for a
  /// model too large to decode on CPU in a sitting.
  static var probeBackend: Backend {
    ProcessInfo.processInfo.environment["TOOL_PROBE_BACKEND"] == "gpu"
      ? .gpu : .cpu(threadCount: nil)
  }

  /// Which conditions to run, when only some of them are wanted.
  ///
  /// Empty runs all of them, which is what the checked-in table needs. A
  /// comma-separated `TOOL_PROBE_ONLY` keeps the labels equal to one of its
  /// entries — a 12B model reloaded sixty times is an hour of a machine, and
  /// the question asked of a new model is usually two rows wide.
  ///
  /// Equality rather than a substring, because the labels nest: every one of
  /// them is a prefix of another (`tool zh/app-preface` of `… @steady` and
  /// `… +constrained`, and of `told zh/app-preface` had it matched loosely).
  /// Asking for two rows and being handed five is an extra hour, and worse,
  /// a table that says it ran what was asked for.
  static var probeFilter: [String] {
    (ProcessInfo.processInfo.environment["TOOL_PROBE_ONLY"] ?? "")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// How many times the tool body ran in the current attempt.
  ///
  /// Static because `ToolManager` instantiates a fresh tool per execution,
  /// so an instance property never survives to be read. Unsafe-nonisolated
  /// because the probe runs attempts strictly one at a time; nothing else
  /// touches it.
  nonisolated(unsafe) static var clockExecutions = 0

  /// The clock the model is offered. Running it is recorded, which is the
  /// fact the table is about; what it returns is a time the model can quote.
  struct ClockTool: Tool {
    static let name = "get_current_time"
    static let description = "Returns the current time on this computer."
    init() {}
    func run() async throws -> Any {
      ToolCallProbeTests.clockExecutions += 1
      return ["time": ToolCallProbeTests.toolClock]
    }
  }

  /// How many times each condition is asked.
  ///
  /// Sampling is stochastic, so one call and one refusal are the same
  /// observation until they are repeated. Every condition gets the same
  /// number, so the denominators in the table are comparable.
  static let attempts = 5

  /// How many times a generation the driver aborted is asked again.
  ///
  /// Only for `ABORTED: The timeout was reached while reading back data`,
  /// which is a GPU readback deadline rather than an answer: measured on
  /// this M1 Pro it ends roughly half of gemma-4-12B's generations, and it
  /// ended the shortest condition in the table as readily as the longest.
  /// Retrying it is what keeps a machine's limit out of a column about what
  /// a model decides — and the retries are printed, because a silent one
  /// turns an unreliable model into a clean-looking row.
  static let abortRetries = 3

  /// Whether an error is that readback deadline rather than a real failure.
  ///
  /// Matched on the message because the vendored runtime surfaces it as
  /// `invalidResponse(String)`, with no case of its own to switch on.
  static func isReadbackAbort(_ error: Error) -> Bool {
    String(describing: error).contains("timeout was reached while reading back")
  }

  /// Where the report lines go.
  ///
  /// Printed, and also appended to `TOOL_PROBE_REPORT` when set — a run of
  /// the full table buffers its stdout past whatever the test runner is
  /// willing to deliver, and a five-minute measurement whose numbers cannot
  /// be read afterwards was run for nothing.
  static func report(_ line: String) {
    print(line)
    guard let path = ProcessInfo.processInfo.environment["TOOL_PROBE_REPORT"]
    else {
      return
    }
    let url = URL(fileURLWithPath: path)
    let data = Data((line + "\n").utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: url)
    }
  }

  /// What the app really sends in Chinese, from `composeAgentPrompt` with
  /// the built-in profile. Pasted rather than abbreviated: the first version
  /// of this probe used the opening block alone, about half of it, while the
  /// decision doc drew conclusions about preface *length*.
  ///
  /// Regenerate with `dart run tool/dump_preface.dart` in `agent_core`.
  static let chinesePreface = """
    [核心人格]
    你是 Lulo，在使用者電腦上運作的私人助手。
    被問到名字或身分時，你就是 Lulo。
    用臺灣繁體中文回答，親近但不裝熟。
    先回答核心；不要用「這個問題很複雜」或「兩者不一樣」這類開場。
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

  /// The same, for a question asked in English.
  static let englishPreface = """
    [Core identity]
    You are Lulo, a private assistant running on the user’s computer.
    When asked your name or what you are, you are Lulo.
    Answer in natural spoken English. Be warm without pretending familiarity.
    Lead with the core of the answer; never open with how complex the question is, or that the two things differ.
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

  /// The Chinese preface with one paragraph added about tools, to separate
  /// "the model will not call tools" from "nobody told it to".
  static let toolAwarePreface =
    chinesePreface + """


    [工具]
    你有工具可以用。需要目前時間、日期這類你無法知道的資訊時，
    一定要呼叫工具取得，不要自己猜。
    """

  /// The turn instruction `composeAgentPrompt` now produces, with the clock
  /// in it. This is the alternative being measured against the tool.
  static let toldChinese = """
    [現在]
    現在是 2026 年 8 月 7 日（星期五）02:53。

    [問題]
    現在幾點？
    """

  static let toldEnglish = """
    [Now]
    It is Friday, 7 August 2026, 02:53.

    [Question]
    What time is it?
    """

  /// The app's own sampler settings, from `AnswerStyle` and
  /// `LiteRTLMRuntimeBackend`. Temperature alone is not the app's style —
  /// nucleus probability moves with it, and top-k is the backend's.
  struct Style {
    let name: String
    let temperature: Float
    let topP: Float
    static let balanced = Style(name: "balanced", temperature: 0.7, topP: 0.95)
    static let steady = Style(name: "steady", temperature: 0.2, topP: 0.9)
  }

  /// One thing asked of the model, one way.
  struct Condition {
    let label: String
    let systemMessage: String?
    let prompt: String
    let style: Style
    /// Whether the clock is in the prompt. A told turn is right when it
    /// reads the clock back; a tool turn is expected to *call*, and both
    /// are scored on both columns — a told turn that calls anyway and a
    /// tool turn that quotes without calling are each worth seeing.
    let told: Bool
    /// Whether the conversation forces the tool-call token shape.
    ///
    /// The first version of this probe never set it, and
    /// `docs/decisions/tool-calling-readiness.md` then reported constrained
    /// decoding as missing from the vendored runtime. It is not:
    /// `ExperimentalFlags.enableConversationConstrainedDecoding` is wired
    /// through `Engine.createConversation`, and the binary exports
    /// `LiteRtLmGemmaModelConstraintProvider_CreateConstraintFromTools`
    /// alongside a whole llguidance engine. Every row above it was measured
    /// with this off, which is what makes the off/on pair the measurement
    /// rather than either column alone.
    var constrained: Bool = false
    /// Whether the system text travels as `initialMessages[0]` with
    /// `role: .system` instead of `ConversationConfig(systemMessage:)`.
    ///
    /// The two reach different C calls — `set_messages` against
    /// `set_system_message` — and the official CLI's OpenAI server, which
    /// feeds the same core the message-list way, measured **5/5 under this
    /// app's instruction** where the `systemMessage:` path measures 0/5 on
    /// the same runtime, model, and prompt. This flag is what separates
    /// "the instruction suppresses the decision" from "one of the two C
    /// paths drops or mis-renders the tools".
    var systemAsInitialMessage: Bool = false
  }

  private func ask(
    _ condition: Condition,
    modelPath: String,
    seed: Int
  ) async throws -> String {
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: Self.probeBackend
      )
    )
    try await engine.initialize()
    // Set for every condition rather than only the ones that want it: the
    // flag is process-global and read when a conversation is created, so
    // leaving it wherever the previous condition put it would let one row
    // silently describe another row's settings.
    ExperimentalFlags.optIntoExperimentalAPIs()
    ExperimentalFlags.enableConversationConstrainedDecoding = condition.constrained
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: condition.systemAsInitialMessage
          ? nil
          : condition.systemMessage.map { Message($0) },
        initialMessages: condition.systemAsInitialMessage
          ? condition.systemMessage.map { [Message($0, role: .system)] } ?? []
          : [],
        tools: [ClockTool()],
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: condition.style.topP,
          temperature: condition.style.temperature,
          seed: seed
        )
      )
    )
    var reply = ""
    for try await chunk in conversation.sendMessageStream(
      Message(condition.prompt)
    ) {
      reply += chunk.toString
    }
    return reply
  }

  /// Whether [reply] answered rather than invented.
  ///
  /// Scored on the minute rather than on a spelling of the clock. The model
  /// writes the same answer as `02:53`, `2:53`, 「凌晨兩點五十三分」 and
  /// 「兩點多一點」-with-the-digits, and an exact-string check marks most of
  /// those wrong. Two earlier versions of this probe did exactly that and
  /// understated the told column both times — the second time after the
  /// decision doc had already written the lesson down.
  ///
  /// Fifty-three minutes past is not something an invented time lands on
  /// often: a hallucinated clock has sixty minutes to choose from, so across
  /// five attempts this admits a false positive at a rate worth accepting
  /// for a check that no longer misses the real answers.
  ///
  /// The spellings have to be even between the two languages, and for a
  /// third version of this scorer they were not: the list held 「五十三」 and
  /// no English word form, so a Chinese answer spelled out scored right and
  /// the identical English one scored wrong. That is a scorer flattering
  /// whichever column it was asked about, and the English column it
  /// understated — 3/5 against 5/5 — was the one being investigated. Even,
  /// the English column re-runs at 5/5 and the gap is gone.
  static func answered(_ reply: String) -> Bool {
    // 「五三」 is the fifth spelling this scorer has been caught missing:
    // 「凌晨兩點五三分」 is how the model reads a digital clock aloud when
    // it drops the 十, the way English drops the "and". Every widening
    // here can only raise a quoted column, never a called one.
    let minute = ["53", "五十三", "五三", "fifty-three", "fifty three"]
    let lowered = reply.lowercased()
    return minute.contains { lowered.contains($0) }
  }

  func testTheScorerReadsAClockSpelledOutInEitherLanguage() {
    // The minute list held 「五十三」 and not "fifty-three", so a Chinese
    // answer spelled out scored right and the identical English one scored
    // wrong. The English column read 3/5 against Chinese 5/5, and with the
    // spellings even it re-runs at 5/5 — the whole gap was the instrument
    // being harsher in one language than the other.
    XCTAssertTrue(
      Self.answered("現在是凌晨兩點五十三分。"),
      "A Chinese clock spelled out has always been read."
    )
    XCTAssertTrue(
      Self.answered("It's two fifty-three in the morning."),
      "The same answer in English has to be read the same way."
    )
    XCTAssertTrue(
      Self.answered("It is 02:53."),
      "Digits were the one English form the scorer already accepted."
    )
    XCTAssertTrue(
      Self.answered("現在是凌晨兩點五三分。"),
      "Reading a digital clock aloud drops the 十, and that is still the "
        + "handed clock — the fifth spelling this scorer missed."
    )
  }

  func testTheScorerStillRefusesAnInventedTime() {
    // Widening the spellings must not widen what counts as answering. A
    // clock the model made up names a different minute.
    XCTAssertFalse(Self.answered("It's about 4:17 in the morning."))
    XCTAssertFalse(Self.answered("It is twenty past three."))
    XCTAssertFalse(Self.answered("現在是凌晨四點十七分。"))
  }

  func testCallingIsCountedByExecutionAndNotByQuotation() async throws {
    // The probe's worst bug, pinned so it cannot come back: whether the
    // model *called* is read off the tool body running, never off the final
    // text. A persona that paraphrases the clock instead of quoting it must
    // still count as having called — a year of this file scoring "called"
    // by searching the reply is how a working capability got written up as
    // an absent one.
    Self.clockExecutions = 0
    _ = try await ClockTool().run()
    XCTAssertEqual(
      Self.clockExecutions,
      1,
      "Running the tool body is the one fact the called column reads."
    )
  }

  func testWhetherGemmaCallsAToolOrShouldJustBeTold() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the tool-call probe.")
    }

    let conditions: [Condition] = [
      // Asking the model to fetch it.
      Condition(
        label: "tool zh/no-system-message",
        systemMessage: nil,
        prompt: "現在幾點？",
        style: .balanced,
        told: false
      ),
      Condition(
        label: "tool zh/app-preface",
        systemMessage: Self.chinesePreface,
        prompt: "現在幾點？",
        style: .balanced,
        told: false
      ),
      Condition(
        label: "tool zh/app-preface @steady",
        systemMessage: Self.chinesePreface,
        prompt: "現在幾點？",
        style: .steady,
        told: false
      ),
      Condition(
        label: "tool zh/preface names the tool",
        systemMessage: Self.toolAwarePreface,
        prompt: "現在幾點？",
        style: .balanced,
        told: false
      ),
      Condition(
        label: "tool en/no-system-message",
        systemMessage: nil,
        prompt: "What time is it right now?",
        style: .balanced,
        told: false
      ),
      Condition(
        label: "tool en/app-preface",
        systemMessage: Self.englishPreface,
        prompt: "What time is it right now?",
        style: .balanced,
        told: false
      ),
      // The same three asks with the tool-call token shape forced. Paired
      // with the rows above them rather than run alone: the question is not
      // whether a constrained model calls the clock, it is whether
      // constraining it is what changes a refusal into a call under the
      // instruction this app really sends.
      Condition(
        label: "tool zh/no-system-message +constrained",
        systemMessage: nil,
        prompt: "現在幾點？",
        style: .balanced,
        told: false,
        constrained: true
      ),
      Condition(
        label: "tool zh/app-preface +constrained",
        systemMessage: Self.chinesePreface,
        prompt: "現在幾點？",
        style: .balanced,
        told: false,
        constrained: true
      ),
      Condition(
        label: "tool en/app-preface +constrained",
        systemMessage: Self.englishPreface,
        prompt: "What time is it right now?",
        style: .balanced,
        told: false,
        constrained: true
      ),
      // The same preface fed the way the official OpenAI server feeds it —
      // as the first message rather than through `systemMessage:`.
      Condition(
        label: "tool zh/app-preface @initial-message",
        systemMessage: Self.chinesePreface,
        prompt: "現在幾點？",
        style: .balanced,
        told: false,
        systemAsInitialMessage: true
      ),
      // A question the clock has nothing to do with, with the tool still
      // registered. This is the precision half: registering a tool on the
      // app's main conversation is only safe if an ordinary turn does not
      // reach for it. The recall rows above cannot answer that.
      Condition(
        label: "tool zh/app-preface unrelated-question",
        systemMessage: Self.chinesePreface,
        prompt: "幫我想一句生日祝福的話。",
        style: .balanced,
        told: false
      ),
      Condition(
        label: "tool en/app-preface unrelated-question",
        systemMessage: Self.englishPreface,
        prompt: "Help me write a short birthday wish.",
        style: .balanced,
        told: false
      ),
      // Telling it instead.
      Condition(
        label: "told zh/app-preface",
        systemMessage: Self.chinesePreface,
        prompt: Self.toldChinese,
        style: .balanced,
        told: true
      ),
      Condition(
        label: "told zh/app-preface @steady",
        systemMessage: Self.chinesePreface,
        prompt: Self.toldChinese,
        style: .steady,
        told: true
      ),
      Condition(
        label: "told en/app-preface",
        systemMessage: Self.englishPreface,
        prompt: Self.toldEnglish,
        style: .balanced,
        told: true
      ),
    ]

    let filter = Self.probeFilter
    let selected =
      filter.isEmpty
      ? conditions
      : conditions.filter { filter.contains($0.label) }
    Self.report(
      "PROBE backend=\(Self.probeBackend) conditions=\(selected.count)"
        + "/\(conditions.count) model=\((modelPath as NSString).lastPathComponent)"
    )
    // A misspelled label would otherwise run nothing and pass, and an hour
    // later the absence of rows reads as a model that answered nothing.
    XCTAssertFalse(
      selected.isEmpty,
      "TOOL_PROBE_ONLY=\(filter) matched no condition"
    )

    for condition in selected {
      var called = 0
      var quoted = 0
      // Every reply and how it scored, not the last one seen. This file's
      // own lesson is to check the scorer against the actual replies before
      // believing a column, and it has been broken three times by a version
      // that printed a single reply chosen by nothing but arrival order. A
      // column reading 3/5 is a number until all five can be read: a time
      // the model invented and a real one the scorer could not parse are
      // the same number and completely different problems.
      var transcript: [(called: Bool, quoted: Bool, reply: String)] = []
      var aborted = 0
      for attempt in 0..<Self.attempts {
        // A fixed seed would repeat one sample rather than draw five.
        var reply: String?
        for _ in 0...Self.abortRetries {
          Self.clockExecutions = 0
          do {
            reply = try await ask(
              condition,
              modelPath: modelPath,
              seed: attempt + 1
            )
            break
          } catch let error where Self.isReadbackAbort(error) {
            aborted += 1
            Self.report("PROBE   aborted \(attempt + 1): \(error)")
          }
        }
        guard let last = reply else { continue }
        // Two separate facts, never inferred from each other. Whether the
        // model *called* is read off the tool body having run — the final
        // text is no witness, because a persona paraphrases a clock instead
        // of quoting it, and the version of this probe that searched the
        // reply for a sentinel wrote a working capability up as an absent
        // one. Whether the answer *carried* the clock is the text's to say.
        let ranTool = Self.clockExecutions > 0
        let quotedClock = Self.answered(last)
        if ranTool {
          called += 1
        }
        if quotedClock {
          quoted += 1
        }
        transcript.append(
          (ranTool, quotedClock, last.replacingOccurrences(of: "\n", with: " "))
        )
      }
      // The denominator is what came back, not what was asked for. A
      // generation the driver aborted is not the model declining to call
      // the tool, and folding the two together would report a machine's
      // limit as a model's decision.
      Self.report(
        "PROBE \(condition.label): "
          + "called \(called)/\(transcript.count), "
          + "quoted \(quoted)/\(transcript.count)"
          + (aborted == 0 ? "" : " (\(aborted) aborted, \(Self.attempts) asked)")
      )
      for (index, attempt) in transcript.enumerated() {
        Self.report(
          "PROBE   \(attempt.called ? "called" : "silent")"
            + "+\(attempt.quoted ? "quoted" : "unquoted") "
            + "\(index + 1): \(attempt.reply)"
        )
      }
    }
  }
}
