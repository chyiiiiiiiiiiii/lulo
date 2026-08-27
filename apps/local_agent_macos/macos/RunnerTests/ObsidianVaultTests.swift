import AppKit
import XCTest

@testable import Lulo

/// The write into somebody else's notes, actually performed.
///
/// Every other test of this feature stands behind a fake host, which is where
/// "built and never connected to anything" lives. These run the real
/// `FileManager` and `FileHandle` path against a real folder.
final class ObsidianVaultTests: XCTestCase {
  private var folder: URL!
  private var defaults: UserDefaults!

  override func setUpWithError() throws {
    try super.setUpWithError()
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("vault-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true)
    defaults = UserDefaults(suiteName: "obsidian-vault-tests-\(UUID().uuidString)")
    defaults.removePersistentDomain(
      forName: "obsidian-vault-tests-\(UUID().uuidString)")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
    try super.tearDownWithError()
  }

  /// Stores the grant the way choosing a folder would.
  private func vaultRemembering(_ url: URL) throws -> ObsidianVault {
    let bookmark = try url.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil,
      relativeTo: nil)
    defaults.set(bookmark, forKey: ObsidianVault.bookmarkKey)
    return ObsidianVault(defaults: defaults)
  }

  func testTheFirstEntryOfADayCarriesTheHeaderAndTheRestDoNot() throws {
    let vault = try vaultRemembering(folder)

    XCTAssertEqual(
      vault.append(fileName: "2026-08-28.md", header: "HEADER\n", entry: "ONE\n"),
      .written)
    XCTAssertEqual(
      vault.append(fileName: "2026-08-28.md", header: "HEADER\n", entry: "TWO\n"),
      .written)

    let written = try String(
      contentsOf: folder.appendingPathComponent("2026-08-28.md"),
      encoding: .utf8)
    XCTAssertEqual(written, "HEADER\nONE\nTWO\n")
  }

  /// The file is in somebody else's vault. Whatever they wrote in it stays
  /// exactly where it was, and the next entry goes after it.
  func testWhatTheUserWroteThemselvesIsNeverTouched() throws {
    let page = folder.appendingPathComponent("2026-08-28.md")
    try "my own notes, please do not eat\n".write(
      to: page, atomically: true, encoding: .utf8)
    let vault = try vaultRemembering(folder)

    XCTAssertEqual(
      vault.append(fileName: "2026-08-28.md", header: "HEADER\n", entry: "ONE\n"),
      .written)

    XCTAssertEqual(
      try String(contentsOf: page, encoding: .utf8),
      "my own notes, please do not eat\nONE\n")
  }

  func testWithNoFolderChosenThereIsNowhereToWrite() {
    XCTAssertEqual(
      ObsidianVault(defaults: defaults).append(
        fileName: "2026-08-28.md", header: "H", entry: "E"),
      .noVault)
  }

  /// A vault that was chosen and has since been deleted is not the same
  /// answer as one that was never chosen — Settings tells the user different
  /// things about the two.
  func testAFolderThatIsGoneReportsDeniedRatherThanNoVault() throws {
    let vault = try vaultRemembering(folder)
    try FileManager.default.removeItem(at: folder)

    let outcome = vault.append(
      fileName: "2026-08-28.md", header: "H", entry: "E")

    XCTAssertNotEqual(outcome, .noVault)
    XCTAssertNotEqual(outcome, .written)
  }

  /// The only names this is ever asked for are made from a date. One that is
  /// not says something has gone wrong upstream, and is refused rather than
  /// resolved into somewhere else in the user's vault.
  func testANameThatIsAPathIsRefused() throws {
    let vault = try vaultRemembering(folder)

    XCTAssertEqual(
      vault.append(fileName: "../escaped.md", header: "H", entry: "E"), .failed)
    XCTAssertEqual(
      vault.append(fileName: "sub/dir.md", header: "H", entry: "E"), .failed)
    XCTAssertEqual(vault.append(fileName: "", header: "H", entry: "E"), .failed)
  }
}
