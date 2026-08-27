import AppKit
import Foundation

/// The folder in the user's own notes that the agent writes into.
///
/// Two things make this different from every other file the app touches. It
/// is **outside the container** — an Obsidian vault lives wherever the user
/// keeps it — so the sandbox only reaches it through a grant a panel issued,
/// and that grant has to be kept as a security-scoped bookmark or it is gone
/// at the next launch. And it is **somebody else's**: the files there may be
/// edited, linked and written under by the person who owns them, so nothing
/// already on disk is ever rewritten.
final class ObsidianVault {
  /// Where the lasting grant is kept.
  ///
  /// The bookmark rather than the path, because a path is not permission. A
  /// remembered string would show a folder in Settings that the app cannot
  /// actually open, which is the failure this is meant to make visible.
  static let bookmarkKey = "obsidianVaultBookmark"

  /// Creates a vault reached through [defaults].
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  private let defaults: UserDefaults

  /// How writing into the vault ended.
  enum Outcome {
    case written
    case noVault
    case denied
    case failed
  }

  /// Asks the user for the folder to write into, and keeps the grant.
  ///
  /// Returns its path, or nil if they backed out.
  func choose() -> String? {
    precondition(Thread.isMainThread)
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = NSLocalizedString("Choose", comment: "")
    guard panel.runModal() == .OK, let url = panel.url else {
      return nil
    }
    guard remember(url) else {
      return nil
    }
    return url.path
  }

  /// Stores the lasting grant for [url]; false when macOS would not issue one.
  private func remember(_ url: URL) -> Bool {
    do {
      let bookmark = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      defaults.set(bookmark, forKey: Self.bookmarkKey)
      return true
    } catch {
      return false
    }
  }

  /// Whether a folder has ever been chosen, whether or not it still resolves.
  ///
  /// Kept apart from [folder] so that "nobody asked for this" and "the folder
  /// they asked for is gone" stay different answers. Reported as the same
  /// thing, Settings would tell a user whose vault had been deleted that they
  /// had never chosen one.
  var hasFolder: Bool { defaults.data(forKey: Self.bookmarkKey) != nil }

  /// The folder being written into, or nil if there is none to reach.
  func folder() -> URL? {
    guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else {
      return nil
    }
    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    else {
      return nil
    }
    if stale {
      // The folder moved or was renamed. macOS resolved it anyway and hands
      // back a bookmark that will not resolve again; re-issuing it here is
      // what stops the grant expiring behind the user.
      _ = remember(url)
    }
    return url
  }

  /// Forgets the folder and the grant that reached it.
  func forget() {
    defaults.removeObject(forKey: Self.bookmarkKey)
  }

  /// Appends [entry] to [fileName], writing [header] first if it is new.
  ///
  /// Never rewrites: the file may have been edited by the person whose vault
  /// it is. A name carrying a path separator is refused rather than resolved
  /// — the only names this is asked for are derived from a date, and one that
  /// is not says something has gone wrong upstream.
  func append(fileName: String, header: String, entry: String) -> Outcome {
    guard !fileName.isEmpty, !fileName.contains("/"), fileName != ".."
    else {
      return .failed
    }
    guard let folder = folder() else {
      return hasFolder ? .denied : .noVault
    }
    // A false answer here is not a refusal. `startAccessingSecurityScopedResource`
    // also returns false for a URL that needs no scope at all — anything
    // inside the app's own container — and treating that as denial would
    // report a write that was about to succeed as a permission failure. The
    // answer decides only whether the scope has to be handed back.
    let scoped = folder.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        folder.stopAccessingSecurityScopedResource()
      }
    }
    let file = folder.appendingPathComponent(fileName)
    do {
      if !FileManager.default.fileExists(atPath: file.path) {
        try (header + entry).write(to: file, atomically: true, encoding: .utf8)
        return .written
      }
      guard let handle = try? FileHandle(forWritingTo: file) else {
        return .failed
      }
      defer { try? handle.close() }
      try handle.seekToEnd()
      guard let data = entry.data(using: .utf8) else {
        return .failed
      }
      try handle.write(contentsOf: data)
      return .written
    } catch {
      return .failed
    }
  }
}
