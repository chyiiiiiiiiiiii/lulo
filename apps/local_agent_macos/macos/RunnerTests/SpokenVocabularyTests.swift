import XCTest

@testable import Lulo

final class SpokenVocabularyTests: XCTestCase {
  func testLatinPhrasesInAnAnswerAreLearned() {
    // The agent's own answers are clean text carrying the exact terms the
    // user is about to say back — "剛剛說的 hot reload 是什麼" only
    // transcribes if "hot reload" is already a bias by then.
    var book = SpokenVocabularyBook(seeds: ["Flutter"])
    XCTAssertTrue(book.learn(from: "Flutter 的 hot reload 讓修改即時生效。"))
    XCTAssertTrue(book.all.contains("hot reload"))
  }

  func testASeedIsNotLearnedAgain() {
    var book = SpokenVocabularyBook(seeds: ["Flutter"])
    XCTAssertFalse(book.learn(from: "Flutter，就是 flutter。"))
    XCTAssertEqual(book.all, ["Flutter"])
  }

  func testNoiseIsNotVocabulary() {
    // Single letters and bare numbers bias nothing worth having.
    var book = SpokenVocabularyBook(seeds: [])
    XCTAssertFalse(book.learn(from: "第 3 點，選 A 就好。"))
    XCTAssertEqual(book.all, [])
  }

  func testSentencePunctuationIsNotPartOfATerm() {
    var book = SpokenVocabularyBook(seeds: [])
    XCTAssertTrue(book.learn(from: "這就是 Riverpod. 它管理狀態。"))
    XCTAssertTrue(book.all.contains("Riverpod"))
    XCTAssertFalse(book.all.contains("Riverpod."))
  }

  func testTheBookIsBoundedAndForgetsTheOldestFirst() {
    var book = SpokenVocabularyBook(seeds: ["Flutter"])
    for i in 0..<(SpokenVocabularyBook.capacity + 5) {
      _ = book.learn(from: "term\(i) 是新的。")
    }
    XCTAssertEqual(book.all.count, 1 + SpokenVocabularyBook.capacity)
    XCTAssertTrue(book.all.contains("Flutter"), "seeds are permanent")
    XCTAssertFalse(book.all.contains("term0"), "the oldest learned term goes")
    XCTAssertTrue(book.all.contains("term\(SpokenVocabularyBook.capacity + 4)"))
  }
}
