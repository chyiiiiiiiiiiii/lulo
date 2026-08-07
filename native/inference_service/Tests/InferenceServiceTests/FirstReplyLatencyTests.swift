import LiteRTLM
import XCTest

@testable import InferenceService

/// Why the first answer of a conversation takes longer than the rest.
///
/// The app already loads the model at launch — `bootstrap.dart` calls
/// `warmUp()` so a multi-gigabyte load is not on the critical path of the
/// first answer. What is left is everything between "the model is in memory"
/// and "the first token arrives", and nothing had ever measured which part of
/// that is the wait: creating the conversation, prefilling the system
/// instruction into its KV cache, or the decode itself.
///
/// Every phase is timed separately, twice, so the first turn's cost can be
/// told apart from the steady-state one.
///
/// Skipped unless `REAL_GEMMA_MODEL_PATH` names an installed model, because
/// it is minutes of real inference:
///
/// ```sh
/// REAL_GEMMA_MODEL_PATH="…/Lulo/models/gemma-4-E4B-it.litertlm" \
///   swift test --filter FirstReplyLatencyTests
/// ```
final class FirstReplyLatencyTests: XCTestCase {
  /// What the app really sends as its stable half, from `composeAgentPrompt`
  /// with the built-in profile. Regenerate with
  /// `dart run tool/dump_preface.dart` in `agent_core`.
  static let preface = """
    [核心人格]
    你是 Lulo，在使用者電腦上運作的私人助手。
    用臺灣繁體中文回答，親近但不裝熟。
    先回答核心；不確定時坦白說明，不捏造資訊。

    [語音回答方式]
    這是用說的，不是用寫的。
    回答控制在三句話以內；講完核心就停，細節等使用者追問再說。
    不要使用 Markdown。
    不要朗讀完整 URL。
    避免冗長條列。
    使用適合自然朗讀的短句。

    [使用者偏好]
    回答長度：簡潔。
    """

  private func ms(since start: TimeInterval) -> Double {
    (ProcessInfo.processInfo.systemUptime - start) * 1000
  }

  private func report(_ label: String, _ milliseconds: Double) {
    print(String(format: "FIRSTREPLY %8.0f ms  %@", milliseconds, label))
  }

  func testWhereTheFirstAnswerSpendsItsTime() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the latency probe.")
    }

    // The app pays this at launch, off the critical path. Measured anyway,
    // because "the model is already loaded" is an assumption the rest of
    // this rests on.
    var mark = ProcessInfo.processInfo.systemUptime
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: LiteRTLMRuntimeConfiguration.defaultBackend == .gpu
          ? .gpu : .cpu(threadCount: nil),
        cacheDir: LiteRTLMRuntimeConfiguration.defaultCacheDirectory
      )
    )
    report("Engine(engineConfig:)", ms(since: mark))

    mark = ProcessInfo.processInfo.systemUptime
    try await engine.initialize()
    report("engine.initialize() — paid at launch by warmUp()", ms(since: mark))

    // Everything below is what a user waits through after typing.
    mark = ProcessInfo.processInfo.systemUptime
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        systemMessage: Message(Self.preface),
        samplerConfig: try SamplerConfig(
          topK: 40,
          topP: 0.95,
          temperature: 0.7,
          seed: 7
        )
      )
    )
    report("createConversation(systemMessage:)", ms(since: mark))

    for (index, question) in ["今天星期幾？", "那明天呢？"].enumerated() {
      mark = ProcessInfo.processInfo.systemUptime
      var firstChunkAt: Double?
      var reply = ""
      for try await chunk in conversation.sendMessageStream(
        Message("[問題]\n\(question)"),
        maxOutputTokens: 96
      ) {
        if firstChunkAt == nil {
          firstChunkAt = ms(since: mark)
        }
        reply += chunk.toString
      }
      report("turn \(index + 1): first token", firstChunkAt ?? -1)
      report("turn \(index + 1): whole answer", ms(since: mark))
      print("FIRSTREPLY   turn \(index + 1) said: \(reply.prefix(60))")
    }

    // What the conversation is holding once the preface has been prefilled,
    // so the prefill can be priced in tokens as well as milliseconds.
    if let held = try? conversation.getTokenCount() {
      print("FIRSTREPLY   conversation holds \(held) tokens")
    }
  }

  /// Whether a throwaway generation at launch buys back the first answer.
  ///
  /// It does not. Measured on the GPU backend the app really runs, both
  /// variants inside one process so they share a page-cache state:
  ///
  ///     no warm-up generation     first question, first token   1505 ms
  ///     one warm-up generation    first question, first token   1523 ms
  ///
  /// The idea came from an earlier run that showed 13027 ms against 6825,
  /// which looked like the warm-up halving it. Both numbers were taken on
  /// `.cpu`, which is not what this app runs — `defaultBackend` is `.gpu` on
  /// arm64 — and the two runs were separate processes with different page
  /// caches, so the comparison was between two things that differed in three
  /// ways. Measuring the app's own backend, in one process, leaves nothing
  /// for the warm-up to do.
  ///
  /// What the first turn actually pays extra is the preface prefill, which
  /// `voice-turn-latency.md` already priced at 1648 ms against 362 for a
  /// settled turn — and this reproduces: 1505 ms against 254. It cannot be
  /// paid ahead of time, because the vendored `Conversation` exposes no way
  /// to prefill: `sendMessage` and `sendMessageStream` are the only ways in,
  /// and both leave a turn in the conversation that nobody said.
  ///
  /// Kept as a probe rather than an assertion. There is no threshold here
  /// that means anything — what is worth having is the two numbers next to
  /// each other, taken the same way, the next time somebody has this idea.
  func testWhetherAWarmUpGenerationHelpsTheFirstAnswer() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to run the latency probe.")
    }

    func firstToken(afterWarmUpGeneration warmUpFirst: Bool) async throws -> Double {
      let engine = Engine(
        engineConfig: try EngineConfig(
          modelPath: modelPath,
          backend: LiteRTLMRuntimeConfiguration.defaultBackend == .gpu
            ? .gpu : .cpu(threadCount: nil),
          cacheDir: LiteRTLMRuntimeConfiguration.defaultCacheDirectory
        )
      )
      try await engine.initialize()
      let sampler = try SamplerConfig(
        topK: 40, topP: 0.95, temperature: 0.7, seed: 7)
      if warmUpFirst {
        let warmUp = try await engine.createConversation(
          with: ConversationConfig(samplerConfig: sampler))
        for try await _ in warmUp.sendMessageStream(
          Message("hi"), maxOutputTokens: 1) {}
      }
      let conversation = try await engine.createConversation(
        with: ConversationConfig(
          systemMessage: Message(Self.preface),
          samplerConfig: sampler
        )
      )
      let mark = ProcessInfo.processInfo.systemUptime
      var firstChunkAt: Double?
      for try await _ in conversation.sendMessageStream(
        Message("[問題]\n今天星期幾？"),
        maxOutputTokens: 96
      ) where firstChunkAt == nil {
        firstChunkAt = ms(since: mark)
      }
      return firstChunkAt ?? -1
    }

    // Cold first, so the warm variant cannot be flattered by the cold one
    // having paged everything in for it.
    let cold = try await firstToken(afterWarmUpGeneration: false)
    report("first token, no warm-up generation", cold)
    let warmed = try await firstToken(afterWarmUpGeneration: true)
    report("first token, after a warm-up generation", warmed)
  }
}
