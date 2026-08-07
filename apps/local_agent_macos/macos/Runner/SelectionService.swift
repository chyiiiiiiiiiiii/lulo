import AppKit
import Foundation

/// Text handed over from another app's Services menu.
///
/// Selecting a paragraph in Mail and asking Lulo about it used to be six
/// steps: copy, switch, paste, type the request, wait, copy the answer back.
/// The Services menu is the system's own way to do that in one, it works in
/// every app that handles text, it needs no Accessibility permission, and it
/// is available on the deployment target — which is more than can be said
/// for reading the screen.
///
/// Send-only. Writing the answer back over the selection needs
/// `NSReturnTypes` and a handler that blocks until the Dart isolate answers,
/// which is a different shape and a riskier one.
enum SelectionService {
  /// The text of [pasteboard], or nil when there is nothing worth sending.
  ///
  /// Separated from the handler because this is the part with a decision in
  /// it and the only part a test can reach: a real `NSServices` invocation
  /// needs the app registered with Launch Services and a user picking a menu
  /// item.
  ///
  /// Whitespace-only is nothing. The system offers the item whenever a
  /// string type is on the pasteboard, so a user who selected a stray
  /// newline would otherwise open Lulo onto an empty question.
  static func text(from pasteboard: NSPasteboard) -> String? {
    guard let raw = pasteboard.string(forType: .string) else {
      return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
