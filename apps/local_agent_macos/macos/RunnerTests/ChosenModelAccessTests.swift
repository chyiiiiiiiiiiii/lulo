import XCTest

@testable import Lulo

final class ChosenModelAccessTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "ChosenModelAccessTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testAModelChosenTodayIsStillReadableOnTheNextLaunch() {
    // The sandbox hands the permission over for one run. Written down at the
    // moment the panel grants it, a later run can take it up again; left
    // unwritten, the path in settings points at a file the app is no longer
    // allowed to open and the agent silently falls back to its preview.
    let url = URL(fileURLWithPath: "/Volumes/Models/gemma-4-E4B-it.litertlm")
    let choosing = Self.make(defaults: defaults)
    choosing.remember(url)

    var accessed: [URL] = []
    let laterRun = Self.make(
      defaults: defaults,
      beginAccess: { url in
        accessed.append(url)
        return true
      }
    )

    XCTAssertTrue(
      laterRun.beginReading(url.path),
      "The model chosen in an earlier run could not be read in this one"
    )
    XCTAssertEqual(accessed, [url])
  }

  func testAModelWithNoWrittenPermissionIsRefusedRatherThanAttempted() {
    let access = Self.make(defaults: defaults)

    // Saying no here is what lets the app report that it cannot read the file.
    // Attempting the load anyway fails several gigabytes deep inside the
    // runtime, where the reason is no longer legible.
    XCTAssertFalse(access.beginReading("/Volumes/Models/never-chosen.litertlm"))
  }

  func testChoosingAnotherModelDoesNotForgetTheFirst() {
    let first = URL(fileURLWithPath: "/Volumes/Models/first.litertlm")
    let second = URL(fileURLWithPath: "/Volumes/Models/second.litertlm")
    let access = Self.make(defaults: defaults)
    access.remember(first)
    access.remember(second)

    let laterRun = Self.make(defaults: defaults)
    XCTAssertTrue(laterRun.beginReading(first.path))
    XCTAssertTrue(laterRun.beginReading(second.path))
  }

  func testThePermissionIsGivenBackWhenTheModelIsUnloaded() {
    let url = URL(fileURLWithPath: "/Volumes/Models/gemma-4-E4B-it.litertlm")
    var released: [URL] = []
    let access = Self.make(
      defaults: defaults,
      endAccess: { released.append($0) }
    )
    access.remember(url)
    XCTAssertTrue(access.beginReading(url.path))

    access.stopReading(url.path)

    // Holding permissions the app is no longer using is how a sandboxed app
    // runs out of them.
    XCTAssertEqual(released, [url])
  }

  /// A store with the sandbox replaced by something a test can run.
  ///
  /// The bookmark itself cannot be exercised here: only a file the open panel
  /// actually granted can be bookmarked with a security scope, and a test has
  /// no panel. What is under test is the remembering — that the permission
  /// written down when the model is chosen is the one taken up later.
  private static func make(
    defaults: UserDefaults,
    beginAccess: @escaping (URL) -> Bool = { _ in true },
    endAccess: @escaping (URL) -> Void = { _ in }
  ) -> ChosenModelAccess {
    return ChosenModelAccess(
      defaults: defaults,
      makeBookmark: { Data("bookmark for \($0.path)".utf8) },
      resolveBookmark: { data in
        let text = String(decoding: data, as: UTF8.self)
        return URL(fileURLWithPath: String(text.dropFirst("bookmark for ".count)))
      },
      beginAccess: beginAccess,
      endAccess: endAccess
    )
  }
}
