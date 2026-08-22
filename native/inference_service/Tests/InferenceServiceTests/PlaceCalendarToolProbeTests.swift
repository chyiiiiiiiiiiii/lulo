import Foundation
import LiteRTLM
import XCTest

@testable import InferenceService

/// Whether the model actually reaches for the place and calendar tools.
///
/// A declaration costs context on every turn, so a tool the model will not
/// call is worth a measured 0/5 — the bar `remember`'s exclusion set and
/// this repository holds new tools to. Declarations here carry the same
/// names and descriptions the Dart toolbox registers, under the same
/// system preface the app composes, so what is measured is what ships.
///
/// ```sh
/// REAL_GEMMA_MODEL_PATH="…/gemma-4-E4B-it.litertlm" \
///   TOOL_PROBE_REPORT=/tmp/new-tools.txt \
///   swift test --filter PlaceCalendarToolProbeTests
/// ```
final class PlaceCalendarToolProbeTests: XCTestCase {
  nonisolated(unsafe) static var placeExecutions = 0
  nonisolated(unsafe) static var calendarExecutions = 0
  nonisolated(unsafe) static var lastPlaceQuery = ""

  struct PlaceProbeTool: Tool {
    static let name = "search_places"
    static let description =
      "Searches Apple Maps for real places: shops, cafes, restaurants, "
      + "landmarks. Returns real names and addresses. Include the city or "
      + "district in the query (for example 大安區 安靜咖啡廳). Use whenever "
      + "the user asks about a place to go; never invent place names or "
      + "addresses yourself."
    var query: String = ""
    init() {}
    func run() async throws -> Any {
      PlaceCalendarToolProbeTests.placeExecutions += 1
      PlaceCalendarToolProbeTests.lastPlaceQuery = query
      return [
        "places": [
          ["name": "貳月咖啡", "address": "台北市大安區溫州街 2 號"],
          ["name": "小驢館", "address": "台北市大安區和平東路二段 96 巷"],
        ],
        "totalFound": 2,
      ]
    }
  }

  struct CalendarProbeTool: Tool {
    static let name = "read_calendar"
    static let description =
      "Reads the user's own calendar. Returns their events between two "
      + "dates: title, time, and which calendar. Use when the user asks "
      + "about their schedule, what they have planned, or whether they are "
      + "free."
    var from: String = ""
    var to: String = ""
    init() {}
    // Lenient on purpose: the model sometimes omits an argument, and in
    // production the Dart tool answers that with a readable error rather
    // than the whole turn dying. Strict decoding here would measure the
    // harness, not the model.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      from = (try? container.decode(String.self, forKey: .from)) ?? ""
      to = (try? container.decode(String.self, forKey: .to)) ?? ""
    }
    enum CodingKeys: String, CodingKey {
      case from
      case to
    }
    func run() async throws -> Any {
      PlaceCalendarToolProbeTests.calendarExecutions += 1
      return [
        "events": [
          [
            "title": "牙醫", "start": "2026-08-23 14:30",
            "end": "2026-08-23 15:00", "calendar": "個人",
          ]
        ],
        "totalEvents": 1,
      ]
    }
  }

  struct ConversationProbeTool: Tool {
    static let name = "search_conversations"
    static let description =
      "Searches the user's past conversations with you. Returns matching "
      + "conversation titles and dates. Use when the user asks what you "
      + "talked about before."
    var query: String = ""
    init() {}
    func run() async throws -> Any {
      ["matches": [], "totalMatches": 0]
    }
  }

  func testTheNewToolsAreCalledWhenAskedForAndOnlyThen() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["REAL_GEMMA_MODEL_PATH"] else {
      throw XCTSkip("Set REAL_GEMMA_MODEL_PATH to probe the new tools.")
    }
    let engine = Engine(
      engineConfig: try EngineConfig(
        modelPath: modelPath,
        backend: ToolCallProbeTests.probeBackend
      )
    )
    try await engine.initialize()

    // The full production toolbox, so a tool is chosen against its
    // neighbours the way it will be in the app.
    func askAll(
      _ question: String,
      seed: Int
    ) async throws -> String {
      let conversation = try await engine.createConversation(
        with: ConversationConfig(
          systemMessage: Message(WrittenPrefaceProbeTests.spokenPrefaceToday),
          tools: [ConversationProbeTool(), PlaceProbeTool(), CalendarProbeTool()],
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
        maxOutputTokens: 256
      ) {
        reply += chunk.toString
      }
      return reply
    }

    var placeCalled = 0
    for seed in 1...5 {
      Self.placeExecutions = 0
      let reply = try await askAll("幫我找大安區附近安靜的咖啡廳", seed: seed)
      if Self.placeExecutions > 0 { placeCalled += 1 }
      ToolCallProbeTests.report(
        "PLACE \(seed): \(Self.placeExecutions > 0 ? "called '\(Self.lastPlaceQuery)'" : "silent") "
          + reply.replacingOccurrences(of: "\n", with: " ")
      )
    }
    ToolCallProbeTests.report("PLACE recall: \(placeCalled)/5")

    var calendarCalled = 0
    for seed in 1...5 {
      Self.calendarExecutions = 0
      let reply = try await askAll(
        "現在是 2026 年 8 月 22 日（星期六）14:00。\n我明天有什麼行程？",
        seed: seed
      )
      if Self.calendarExecutions > 0 { calendarCalled += 1 }
      ToolCallProbeTests.report(
        "CALENDAR \(seed): \(Self.calendarExecutions > 0 ? "called" : "silent") "
          + reply.replacingOccurrences(of: "\n", with: " ")
      )
    }
    ToolCallProbeTests.report("CALENDAR recall: \(calendarCalled)/5")

    var spurious = 0
    for seed in 1...5 {
      Self.placeExecutions = 0
      Self.calendarExecutions = 0
      let reply = try await askAll("早安！", seed: seed)
      spurious += Self.placeExecutions + Self.calendarExecutions
      ToolCallProbeTests.report(
        "UNRELATED \(seed): \(Self.placeExecutions + Self.calendarExecutions) calls "
          + reply.replacingOccurrences(of: "\n", with: " ")
      )
    }
    ToolCallProbeTests.report("UNRELATED spurious calls: \(spurious)")

    XCTAssertGreaterThanOrEqual(
      placeCalled,
      4,
      "A place tool the model will not reach for is context spent on nothing."
    )
    XCTAssertGreaterThanOrEqual(
      calendarCalled,
      4,
      "A calendar tool the model will not reach for is context spent on nothing."
    )
    XCTAssertEqual(
      spurious,
      0,
      "Tools fired for a greeting: the precision half has broken."
    )
  }
}
