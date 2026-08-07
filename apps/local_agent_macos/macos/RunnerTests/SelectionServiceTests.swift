import AppKit
import XCTest

@testable import Lulo

final class SelectionServiceTests: XCTestCase {
  private func pasteboard(_ contents: String?) -> NSPasteboard {
    // A named pasteboard rather than .general, so a test never disturbs what
    // the person running it had copied.
    let board = NSPasteboard(name: NSPasteboard.Name("lulo-selection-test"))
    board.clearContents()
    if let contents {
      board.setString(contents, forType: .string)
    }
    return board
  }

  func testSelectedTextIsWhatGetsSent() {
    XCTAssertEqual(
      SelectionService.text(from: pasteboard("幫我把這段改得客氣一點")),
      "幫我把這段改得客氣一點"
    )
  }

  func testSurroundingWhitespaceIsNotPartOfTheQuestion() {
    XCTAssertEqual(
      SelectionService.text(from: pasteboard("  hello there\n\n")),
      "hello there"
    )
  }

  func testASelectionOfNothingIsNotAQuestion() {
    // The system offers the menu item whenever a string is on the
    // pasteboard, so a user who selected a stray newline would otherwise
    // open Lulo onto an empty question.
    XCTAssertNil(SelectionService.text(from: pasteboard("   \n\t ")))
    XCTAssertNil(SelectionService.text(from: pasteboard("")))
  }

  func testAPasteboardWithNoTextAtAllIsRefused() {
    XCTAssertNil(SelectionService.text(from: pasteboard(nil)))
  }
}
