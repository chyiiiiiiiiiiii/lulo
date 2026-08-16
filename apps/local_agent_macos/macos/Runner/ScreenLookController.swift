import AppKit
import Foundation
import ScreenCaptureKit

/// Takes one screenshot of the window the user was last working in.
///
/// The invited look, and deliberately nothing more: capture happens only
/// inside `capture()`, which runs because the user pressed the button — the
/// tap is the consent, the scope, and the timing. The first call is where
/// macOS raises its Screen Recording prompt, so the heaviest permission on
/// the platform is asked for at the feature it serves, in the moment the
/// user invokes it, and never at install.
///
/// Not a recorder. Each capture deletes whatever the previous one wrote
/// before writing anything, so at most one look exists on disk at a time —
/// and it lives in the app's own temporary directory, which the system
/// clears on its own schedule.
final class ScreenLookController {
  /// The window this capture aims for: the app the user was last in.
  ///
  /// Kept by the caller (the AppDelegate already watches activations for
  /// the frontmost-app context) and read at capture time, because the act
  /// of summoning Lulo makes Lulo frontmost — the look is at where the
  /// user came from.
  var lastFrontmostBundleId: String?

  /// Where looks are written; one file at most lives here.
  private let directory: URL

  /// Creates a controller writing into the app's temporary directory.
  init() {
    directory = URL(
      fileURLWithPath: NSTemporaryDirectory(),
      isDirectory: true
    ).appendingPathComponent("screen-looks", isDirectory: true)
  }

  /// One attempted look, as the Pigeon boundary reports it.
  enum Outcome {
    case captured(path: String)
    case denied
    case unavailable
    case failed
  }

  /// Captures the front window of the last non-Lulo app, or the whole
  /// display when that window cannot be found.
  func capture() async -> Outcome {
    guard #available(macOS 14.0, *) else {
      return .unavailable
    }
    // Preflight distinguishes "never asked" from "asked and refused":
    // request raises the system prompt on first use and simply returns
    // false thereafter, which is the denied state the caller can name.
    if !CGPreflightScreenCaptureAccess() {
      guard CGRequestScreenCaptureAccess() else {
        return .denied
      }
    }
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
      )
      guard let display = content.displays.first else {
        return .failed
      }
      let target = content.windows.first { window in
        window.owningApplication?.bundleIdentifier == lastFrontmostBundleId
          && window.isOnScreen
          && window.frame.width > 200
          && window.frame.height > 200
      }
      let filter: SCContentFilter
      let size: CGSize
      if let target {
        filter = SCContentFilter(desktopIndependentWindow: target)
        size = target.frame.size
      } else {
        // No window worth aiming at — the whole display, which is what
        // the user sees and therefore what "my screen" means.
        filter = SCContentFilter(
          display: display,
          excludingWindows: []
        )
        size = CGSize(width: display.width, height: display.height)
      }
      let configuration = SCStreamConfiguration()
      // Downscaled at capture: the vision encoder resizes anyway, and the
      // probe that measured 5.7 s a look did it at this scale. Full-res
      // pixels would spend disk and copy time buying nothing.
      let scale = min(1, 1024 / max(size.width, 1))
      configuration.width = Int(size.width * scale)
      configuration.height = Int(size.height * scale)
      configuration.showsCursor = false
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: configuration
      )
      return write(image)
    } catch {
      NSLog(
        "Lulo look: capture failed (%@)",
        String(describing: error)
      )
      return .failed
    }
  }

  private func write(_ image: CGImage) -> Outcome {
    do {
      try? FileManager.default.removeItem(at: directory)
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let destination = directory.appendingPathComponent("look.png")
      let representation = NSBitmapImageRep(cgImage: image)
      guard
        let data = representation.representation(
          using: .png,
          properties: [:]
        )
      else {
        return .failed
      }
      try data.write(to: destination)
      return .captured(path: destination.path)
    } catch {
      NSLog("Lulo look: write failed (%@)", String(describing: error))
      return .failed
    }
  }
}
