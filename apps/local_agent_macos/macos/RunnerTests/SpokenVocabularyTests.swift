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

  func testTheUsersOwnWordsComeFirst() {
    // The user typed these into the profile; the seeds are a guess made by
    // whoever wrote the app. Contextual biasing trades general accuracy for
    // the list, so when the two disagree the person doing the talking wins.
    var book = SpokenVocabularyBook(seeds: ["Flutter", "Dart"])
    book.adopt(["Lulo", "Breeze-ASR"])
    XCTAssertEqual(book.all, ["Lulo", "Breeze-ASR", "Flutter", "Dart"])
  }

  func testAdoptingReplacesRatherThanAccumulates() {
    // The profile is a watched file: what it says now is the whole answer,
    // and a word the user deleted must stop being listened for.
    var book = SpokenVocabularyBook(seeds: [])
    book.adopt(["Lulo", "Gemma"])
    book.adopt(["Lulo"])
    XCTAssertEqual(book.all, ["Lulo"])
  }

  func testAUserTermIsNotThenLearnedAgainFromAnAnswer() {
    var book = SpokenVocabularyBook(seeds: [])
    book.adopt(["Riverpod"])
    XCTAssertFalse(book.learn(from: "這就是 Riverpod。"))
    XCTAssertEqual(book.all, ["Riverpod"])
  }

  func testAWordDroppedFromTheProfileCanBeLearnedAgain() {
    // Adopting rebuilds what is known, so dropping a term must not leave it
    // permanently unlearnable — the book would then be quietly wrong about
    // its own contents.
    var book = SpokenVocabularyBook(seeds: [])
    book.adopt(["Riverpod"])
    book.adopt([])
    XCTAssertTrue(book.learn(from: "這就是 Riverpod。"))
    XCTAssertEqual(book.all, ["Riverpod"])
  }

  func testAWordThatIsBothTheUsersAndASeedIsListedOnce() {
    // `builtInVocabulary` and the seed list here were written separately and
    // overlap on nine terms, so this is the shape of a fresh install with
    // nobody having touched Settings — not an edge case. Biasing trades
    // general accuracy for the length of the list, and a fifth of it saying
    // the same words twice buys nothing with that trade.
    var book = SpokenVocabularyBook(seeds: ["Flutter", "Dart"])
    book.adopt(["Lulo", "Flutter"])
    XCTAssertEqual(book.all, ["Lulo", "Flutter", "Dart"])
  }

  func testAWordAlreadyLearnedIsNotListedTwiceWhenTheUserAddsIt() {
    var book = SpokenVocabularyBook(seeds: [])
    XCTAssertTrue(book.learn(from: "這就是 Riverpod。"))
    book.adopt(["Riverpod"])
    XCTAssertEqual(book.all, ["Riverpod"])
  }

  func testAdoptingAWordKeepsItAfterTheLearnedListTurnsOver() {
    // Learning it, then adopting it, then filling the learned list past its
    // capacity: eviction must not take away a word the user typed. It used
    // to, because eviction dropped the key that adoption also depended on.
    var book = SpokenVocabularyBook(seeds: [])
    XCTAssertTrue(book.learn(from: "這就是 Riverpod。"))
    book.adopt(["Riverpod"])
    for index in 0..<(SpokenVocabularyBook.capacity + 5) {
      _ = book.learn(from: "term\(index) here")
    }
    XCTAssertEqual(book.all.filter { $0 == "Riverpod" }.count, 1)
    XCTAssertTrue(book.all.contains("Riverpod"))
  }

  func testTheUsersListIsBoundedLikeTheLearnedOne() {
    // `learned` has always been capped. `adopted` comes from a file the user
    // can hand-edit, and an unbounded bias is the one thing this struct's own
    // doc says not to build.
    var book = SpokenVocabularyBook(seeds: [])
    book.adopt((0..<(SpokenVocabularyBook.capacity + 10)).map { "term\($0)" })
    XCTAssertEqual(book.all.count, SpokenVocabularyBook.capacity)
    XCTAssertEqual(book.all.first, "term0")
  }

  func testBlankAndRepeatedEntriesInTheProfileAreNotVocabulary() {
    var book = SpokenVocabularyBook(seeds: [])
    book.adopt(["Lulo", "  ", "lulo", "", "Gemma"])
    XCTAssertEqual(book.all, ["Lulo", "Gemma"])
  }
}
