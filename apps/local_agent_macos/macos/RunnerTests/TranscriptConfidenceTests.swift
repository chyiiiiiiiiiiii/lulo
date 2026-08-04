import Foundation
import Speech
import XCTest

@testable import Runner

/// The recogniser scores every span it settles, and measured over the private
/// corpus the score separates cleanly: the words it got right sit at 0.88 and
/// above, and the ones it got wrong sit below — `Flater` for "Flutter" at
/// 0.48, and the middle of a misheard Mandarin clause at 0.31. Nothing in the
/// app looked at it, so the one signal that says "this sentence is probably
/// not what was said" was thrown away with the attributes.
@available(macOS 26.0, *)
final class TranscriptConfidenceTests: XCTestCase {
  private func attributed(
    _ spans: [(String, Double?)]
  ) -> AttributedString {
    var result = AttributedString()
    for (text, confidence) in spans {
      var run = AttributedString(text)
      if let confidence {
        run.transcriptionConfidence = confidence
      }
      result.append(run)
    }
    return result
  }

  func testTheWeakestSpanIsWhatTheSentenceIsWorth() {
    // One bad word is enough to make the sentence wrong, so the sentence is
    // worth its weakest span rather than its average — averaging buries a
    // 0.31 under a dozen 1.00s, which is exactly the case worth catching.
    let text = attributed([
      ("我剛剛把 ", 1.0), ("Flater", 0.48), (" 的版本都更新了", 1.0),
    ])
    XCTAssertEqual(lowestTranscriptionConfidence(in: text), 0.48)
  }

  func testATranscriptWithoutScoresReportsNone() {
    // The attribute is requested, not guaranteed. A transcript that came back
    // unscored must not read as a confident one, and must not read as a
    // hopeless one either.
    XCTAssertNil(
      lowestTranscriptionConfidence(in: attributed([("好，可以開始了", nil)]))
    )
  }

  func testAnEmptyTranscriptReportsNone() {
    XCTAssertNil(lowestTranscriptionConfidence(in: AttributedString()))
  }

  func testAPartlyScoredTranscriptIsWorthItsScoredSpans() {
    let text = attributed([("先用 ", nil), ("codex", 0.79), (" 檢查", 1.0)])
    XCTAssertEqual(lowestTranscriptionConfidence(in: text), 0.79)
  }
}
