import ServiceManagement
import XCTest

@testable import Lulo

/// `SMAppService.Status` is itself macOS 13, so tests that name its cases
/// are too. The app's deployment target is 12, which is exactly why
/// `LaunchAtLogin` has an `unavailable` state to fall back to.
@available(macOS 13.0, *)
final class LaunchAtLoginTests: XCTestCase {
  private func error(_ code: Int) -> NSError {
    NSError(domain: "SMAppServiceErrorDomain", code: code)
  }

  func testAnEnabledRegistrationReadsAsOn() {
    XCTAssertEqual(LaunchAtLogin.reading(.enabled), .on)
  }

  func testARegistrationAwaitingTheUserIsNeitherOnNorOff() {
    // macOS accepted it and is waiting for approval in System Settings, and
    // reports the same after the user revokes consent there. Showing this as
    // `on` promises a login that will not happen; showing it as `off` hides
    // the one place it can be fixed.
    XCTAssertEqual(LaunchAtLogin.reading(.requiresApproval), .needsApproval)
  }

  func testNoRegistrationReadsAsOff() {
    XCTAssertEqual(LaunchAtLogin.reading(.notRegistered), .off)
  }

  func testABundleMacOSCannotFindIsARefusalRatherThanOff() {
    // Nothing the user does in the settings sheet changes this, so it must
    // not be shown as a switch they can simply turn on.
    XCTAssertEqual(LaunchAtLogin.reading(.notFound), .refused)
  }

  func testRegisteringWhatIsAlreadyRegisteredIsNotAFailure() {
    // `register()` throws `kSMErrorAlreadyRegistered` rather than doing
    // nothing. Treating that as a refusal was the first version's trap: the
    // switch sat in `needsApproval`, every tap tried to register again,
    // every attempt threw, and the state never moved in either direction.
    XCTAssertEqual(
      LaunchAtLogin.after(error(12), asking: true, status: .requiresApproval),
      .needsApproval
    )
    XCTAssertEqual(
      LaunchAtLogin.after(error(12), asking: true, status: .enabled),
      .on
    )
  }

  func testUnregisteringWhatWasNeverRegisteredIsNotAFailure() {
    XCTAssertEqual(
      LaunchAtLogin.after(error(6), asking: false, status: .notRegistered),
      .off
    )
  }

  func testAUserWhoDeniedItIsSentToSystemSettingsRatherThanShownOff() {
    // `kSMErrorLaunchDeniedByUser`. The status afterwards is
    // `notRegistered`, so reading it alone would show a plain off switch —
    // the user taps it again and nothing visibly happens, forever.
    XCTAssertEqual(
      LaunchAtLogin.after(error(11), asking: true, status: .notRegistered),
      .needsApproval
    )
  }

  func testASignatureMacOSWillNotAcceptIsSaidOutLoud() {
    // `kSMErrorInvalidSignature` — what an app run from a build directory
    // and signed ad-hoc gets, which is every build this repository makes.
    XCTAssertEqual(
      LaunchAtLogin.after(error(3), asking: true, status: .notRegistered),
      .refused
    )
  }

  func testAnUnrecognisedFailureIsARefusalRatherThanSilence() {
    XCTAssertEqual(
      LaunchAtLogin.after(error(2), asking: true, status: .notRegistered),
      .refused
    )
  }

  func testAlreadyRegisteredWhileAskingToStopIsStillARefusal() {
    // The two forgiving cases are each tied to the direction that makes them
    // harmless. `alreadyRegistered` coming back from an unregister would be
    // macOS contradicting itself, and must not be smoothed over.
    XCTAssertEqual(
      LaunchAtLogin.after(error(12), asking: false, status: .enabled),
      .refused
    )
  }
}
