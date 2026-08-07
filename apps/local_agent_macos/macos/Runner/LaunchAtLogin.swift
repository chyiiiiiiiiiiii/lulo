import Foundation
import ServiceManagement

/// Whether the app starts itself when the user logs in.
///
/// The app describes itself as resident — it lives in the menu bar, it keeps
/// a presence on the desktop, it is meant to be there when you turn to it.
/// It was not there after a restart, because nothing ever asked macOS to
/// start it.
///
/// Nothing here is remembered. The registration belongs to macOS: it
/// survives reinstalls, and the user can revoke it in System Settings
/// without this app running to notice. A stored copy would eventually claim
/// something untrue about the machine, so the answer is always read back.
///
/// Five states rather than two, because macOS answers with more than yes and
/// no, and each of the other three needs the user to do something different —
/// or tells them there is nothing to do. Collapsing them into `off` was the
/// first version of this file and it produced a switch that flipped back
/// with no explanation, which is indistinguishable from a broken app.
enum LaunchAtLogin {
  /// What macOS currently does, without changing it.
  static func status() -> HostLoginItemStatus {
    guard #available(macOS 13.0, *) else {
      // `SMAppService` arrived in macOS 13 and the deployment target is 12.
      // The older `SMLoginItemSetEnabled` needs a separate helper bundle,
      // which this app does not ship, so on 12 the honest answer is that no
      // copy of this app can do it rather than that it is switched off.
      return .unavailable
    }
    return reading(SMAppService.mainApp.status)
  }

  /// Asks macOS to start the app at login, or to stop, and reports what
  /// actually resulted.
  ///
  /// Rarely what was asked for. Registering can be denied by the user, can
  /// be refused for the signature, or can find a registration already there;
  /// unregistering can find nothing to remove. All of those are ordinary and
  /// none of them is an error worth throwing at the caller — but they are
  /// four different things to tell the user, so they are four answers.
  static func set(_ enabled: Bool) -> HostLoginItemStatus {
    guard #available(macOS 13.0, *) else {
      return .unavailable
    }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return reading(SMAppService.mainApp.status)
    } catch {
      let failure = error as NSError
      NSLog(
        "Lulo login item: %@ refused (%ld %@)",
        enabled ? "register" : "unregister",
        failure.code,
        failure.domain
      )
      return after(
        failure,
        asking: enabled,
        status: SMAppService.mainApp.status
      )
    }
  }

  /// What macOS reports, as one of the states the app can show.
  ///
  /// Separated from the calls above because this is the part with a decision
  /// in it and the only part a test can reach — `SMAppService` talks to a
  /// system daemon over XPC that a unit test has no business waking up.
  @available(macOS 13.0, *)
  static func reading(_ status: SMAppService.Status) -> HostLoginItemStatus {
    switch status {
    case .enabled:
      return .on
    case .requiresApproval:
      // The registration exists and macOS is waiting for the user to allow
      // it in System Settings — which is also what it reports after the user
      // revokes consent there. Reporting it as `on` would promise a login
      // that will not happen; reporting it as `off` would hide the one place
      // it can be fixed.
      return .needsApproval
    case .notRegistered:
      return .off
    case .notFound:
      // macOS cannot find the bundle it was asked about. Nothing the user
      // does in this window changes that, so it belongs with the refusals.
      return .refused
    @unknown default:
      return .refused
    }
  }

  /// The state a throwing register or unregister leaves things in.
  ///
  /// [status] is what macOS reports afterwards, which for two of these is
  /// the real answer: an unregister that found nothing to remove and a
  /// register that found one already there have both left things where they
  /// were asked to be. The rest are refusals that the status alone reports
  /// as plain `off`, which is the misleading part this exists to stop.
  ///
  /// Pure, and the reason `set` is split in half: these are the paths that
  /// matter and none of them can be reached by calling `SMAppService`.
  @available(macOS 13.0, *)
  static func after(
    _ error: NSError,
    asking enabled: Bool,
    status: SMAppService.Status
  ) -> HostLoginItemStatus {
    switch error.code {
    case Self.alreadyRegistered where enabled,
      Self.jobNotFound where !enabled:
      // Asked for what was already true. Not a failure.
      return reading(status)
    case Self.launchDeniedByUser:
      // macOS has the request and wants the user to allow it in System
      // Settings. The same state as `requiresApproval`, arrived at from the
      // other direction.
      return .needsApproval
    default:
      // Including `invalidSignature`, which is what an app run from a build
      // directory and signed ad-hoc gets. Reading the status here would say
      // `notRegistered`, and showing that as a plain off switch is how the
      // user ends up tapping something that silently does nothing.
      return .refused
    }
  }

  // From `ServiceManagement/SMErrors.h`. Named here rather than used from
  // the header because that enum is anonymous and imports without these
  // names; the numbers are part of the framework's contract.
  private static let jobNotFound = 6
  private static let launchDeniedByUser = 11
  private static let alreadyRegistered = 12
}
