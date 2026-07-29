import Foundation

/// Keeps the permission to read a model the user chose from outside the app.
///
/// Lulo runs in the sandbox, so a file anywhere else on the disk is readable
/// only because the open panel handed the permission over, and that hand-over
/// lasts for one run. Left at that, the model chosen today is a path in
/// settings pointing at a file the app is no longer allowed to open, which
/// looks exactly like having chosen no model at all.
///
/// A bookmark is that permission written down. This writes one at the moment
/// the panel grants it and takes it up again before every load.
final class ChosenModelAccess {
  /// Creates the store, with every step of the sandbox dance replaceable so
  /// the remembering can be tested without one.
  init(
    defaults: UserDefaults = .standard,
    makeBookmark: @escaping (URL) throws -> Data = {
      try $0.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    },
    resolveBookmark: @escaping (Data) throws -> URL = { data in
      var stale = false
      return try URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    },
    beginAccess: @escaping (URL) -> Bool = {
      $0.startAccessingSecurityScopedResource()
    },
    endAccess: @escaping (URL) -> Void = {
      $0.stopAccessingSecurityScopedResource()
    }
  ) {
    self.defaults = defaults
    self.makeBookmark = makeBookmark
    self.resolveBookmark = resolveBookmark
    self.beginAccess = beginAccess
    self.endAccess = endAccess
  }

  private let defaults: UserDefaults
  private let makeBookmark: (URL) throws -> Data
  private let resolveBookmark: (Data) throws -> URL
  private let beginAccess: (URL) -> Bool
  private let endAccess: (URL) -> Void
  private var held: [String: URL] = [:]

  /// Where the written-down permissions live between runs.
  static let storageKey = "chosenModelBookmarks"

  /// Writes down the permission the open panel has just granted for [url].
  ///
  /// A failure here is not worth refusing the choice over: the model is
  /// readable for this run either way, and the user finds out at the next
  /// launch rather than being stopped now.
  func remember(_ url: URL) {
    guard let data = try? makeBookmark(url) else {
      return
    }
    var stored = defaults.dictionary(forKey: Self.storageKey) ?? [:]
    stored[url.path] = data
    defaults.set(stored, forKey: Self.storageKey)
  }

  /// Takes the permission for [path] up again, as at the start of a later run.
  ///
  /// Answers whether the app may now read it, so a model whose permission was
  /// never written down is refused rather than tried and failed inside the
  /// runtime, where it would surface as an unreadable file.
  @discardableResult
  func beginReading(_ path: String) -> Bool {
    if held[path] != nil {
      return true
    }
    guard
      let stored = defaults.dictionary(forKey: Self.storageKey),
      let data = stored[path] as? Data,
      let url = try? resolveBookmark(data),
      beginAccess(url)
    else {
      return false
    }
    held[path] = url
    return true
  }

  /// Gives the permission back, when the model is unloaded.
  func stopReading(_ path: String) {
    guard let url = held.removeValue(forKey: path) else {
      return
    }
    endAccess(url)
  }

  /// Gives every held permission back.
  func stopReadingEverything() {
    for url in held.values {
      endAccess(url)
    }
    held.removeAll()
  }
}
