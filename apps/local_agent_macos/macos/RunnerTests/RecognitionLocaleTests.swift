import XCTest

@testable import Lulo

/// Which locale the monolingual transcriber is opened on.
///
/// The choice used to be made here and only here, from
/// `Locale.preferredLanguages`, so the agent heard whatever the Mac was set
/// to and an English agent on a Chinese machine could not be expressed. The
/// app chooses now; this side resolves that choice against what the
/// transcriber can actually do, and keeps the old behaviour as the floor
/// under a choice that has not arrived or cannot be served.
final class RecognitionLocaleTests: XCTestCase {
  private let supported = [
    Locale(identifier: "en-US"), Locale(identifier: "zh-TW"),
    Locale(identifier: "ja-JP"),
  ]

  func testTheAppsChoiceIsUsedWhenTheTranscriberSpeaksIt() {
    let chosen = RecognitionLocale.resolve(
      chosen: "en-US",
      supported: supported,
      preferred: ["zh-Hant-TW"]
    )
    XCTAssertEqual(chosen?.identifier, "en-US")
  }

  func testTheChoiceWinsOverTheMachinesOwnLanguage() {
    // The whole point: this machine is Chinese and the agent is English.
    let chosen = RecognitionLocale.resolve(
      chosen: "en-US",
      supported: supported,
      preferred: ["zh-Hant-TW", "en-US"]
    )
    XCTAssertEqual(chosen?.identifier, "en-US")

    let chinese = RecognitionLocale.resolve(
      chosen: "zh-TW",
      supported: supported,
      preferred: ["en-US"]
    )
    XCTAssertEqual(chinese?.identifier, "zh-TW")
  }

  func testRegionAndScriptDoNotHaveToMatch() {
    // A tag is written a dozen ways — zh-TW, zh-Hant-TW, zh_Hant. What
    // decides which model to load is the language.
    XCTAssertEqual(
      RecognitionLocale.resolve(
        chosen: "zh-Hant-TW", supported: supported, preferred: []
      )?.identifier,
      "zh-TW"
    )
    XCTAssertEqual(
      RecognitionLocale.resolve(
        chosen: "en-GB", supported: supported, preferred: []
      )?.identifier,
      "en-US"
    )
  }

  func testNoChoiceFallsBackToTheMachinesOwnLanguages() {
    // Before the app has said anything — the microphone can be opened by a
    // path that never went through the setting — the old behaviour stands
    // rather than nothing happening.
    let chosen = RecognitionLocale.resolve(
      chosen: nil,
      supported: supported,
      preferred: ["ja-JP", "en-US"]
    )
    XCTAssertEqual(chosen?.identifier, "ja-JP")
  }

  func testAChoiceTheTranscriberCannotSpeakFallsBackRatherThanFailing() {
    // A locale the platform has no model for must not leave the user with a
    // microphone that opens onto nothing. Better the wrong language than no
    // ears at all — and the app can say which it used.
    let chosen = RecognitionLocale.resolve(
      chosen: "cy-GB",
      supported: supported,
      preferred: ["zh-Hant-TW"]
    )
    XCTAssertEqual(chosen?.identifier, "zh-TW")
  }

  func testNothingSupportedIsNothingChosen() {
    XCTAssertNil(
      RecognitionLocale.resolve(
        chosen: "en-US", supported: [], preferred: ["en-US"]
      )
    )
  }
}
