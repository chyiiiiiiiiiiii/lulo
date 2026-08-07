import Carbon
import XCTest

@testable import Lulo

@MainActor
final class GlobalHotKeyControllerTests: XCTestCase {
  func testRegisterReplaceAndUnregisterOwnExactlyOneRegistration() throws {
    let backend = RecordingHotKeyBackend()
    let controller = GlobalHotKeyController(backend: backend)
    let first = GlobalHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    let second = GlobalHotKey(
      keyCode: UInt32(kVK_ANSI_K),
      modifiers: UInt32(cmdKey | shiftKey)
    )

    try controller.register(first, handler: {})
    XCTAssertEqual(backend.activeKeys, [first])

    try controller.replace(with: second, handler: {})
    XCTAssertEqual(backend.activeKeys, [second])
    XCTAssertEqual(backend.unregisterCount, 1)

    controller.unregister()
    XCTAssertTrue(backend.activeKeys.isEmpty)
    XCTAssertEqual(backend.unregisterCount, 2)
  }

  func testFailedReplacementKeepsPreviousRegistrationRecoverable() throws {
    let backend = RecordingHotKeyBackend()
    let controller = GlobalHotKeyController(backend: backend)
    let first = GlobalHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    let conflicting = GlobalHotKey(
      keyCode: UInt32(kVK_Space),
      modifiers: UInt32(cmdKey | shiftKey)
    )

    try controller.register(first, handler: {})
    backend.keyToReject = conflicting

    XCTAssertThrowsError(try controller.replace(with: conflicting, handler: {}))
    XCTAssertEqual(backend.activeKeys, [first])
  }

  func testCarbonCallbackRoutesOnlyTheExactSignatureAndIDPair() {
    let expectedSignature = OSType(0x4C_41_47_54)
    var invocationCount = 0
    let callback = CarbonHotKeyCallback(
      signature: expectedSignature,
      id: 7,
      handler: { invocationCount += 1 },
      releaseHandler: nil
    )

    XCTAssertFalse(
      callback.route(
        EventHotKeyID(signature: OSType(0x4F_54_48_52), id: 7),
        kind: UInt32(kEventHotKeyPressed)
      )
    )
    XCTAssertEqual(invocationCount, 0)

    XCTAssertTrue(
      callback.route(
        EventHotKeyID(signature: expectedSignature, id: 7),
        kind: UInt32(kEventHotKeyPressed)
      )
    )
    XCTAssertEqual(invocationCount, 1)

    // A release with no release handler is not this callback's event.
    XCTAssertFalse(
      callback.route(
        EventHotKeyID(signature: expectedSignature, id: 7),
        kind: UInt32(kEventHotKeyReleased)
      )
    )
    XCTAssertEqual(invocationCount, 1)
  }

  @MainActor
  func testTwoControllersNeverMintTheSameIdentifier() {
    // Carbon addresses a registration by (signature, id), and every
    // controller here shares one signature — so an id minted twice is two
    // keys the router cannot tell apart, each answering for the other. The
    // counter used to be per-instance, so a second controller was latent
    // breakage of the first one's key. Only uniqueness is a contract here,
    // not the particular numbers.
    let first = RecordingHotKeyBackend()
    let second = RecordingHotKeyBackend()
    let one = GlobalHotKeyController(backend: first)
    let two = GlobalHotKeyController(backend: second)

    try? one.register(
      GlobalHotKey(keyCode: 49, modifiers: 0),
      handler: {},
      releaseHandler: nil
    )
    try? two.register(
      GlobalHotKey(keyCode: 2, modifiers: 0),
      handler: {},
      releaseHandler: nil
    )

    XCTAssertNotEqual(first.mintedIDs.first, second.mintedIDs.first)
  }
}

@MainActor
private final class RecordingHotKeyBackend: HotKeyBackend {
  private var keysByID: [UInt32: GlobalHotKey] = [:]
  var keyToReject: GlobalHotKey?
  var unregisterCount = 0
  var activeKeys: [GlobalHotKey] {
    keysByID.keys.sorted().compactMap { keysByID[$0] }
  }

  /// The identifiers this backend was handed, in the order they arrived.
  var mintedIDs: [UInt32] = []

  func register(
    _ key: GlobalHotKey,
    id: UInt32,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws -> HotKeyRegistration {
    if key == keyToReject {
      throw GlobalHotKeyError.registrationFailed(
        status: OSStatus(eventHotKeyExistsErr)
      )
    }
    keysByID[id] = key
    mintedIDs.append(id)
    return HotKeyRegistration(id: id, token: NSObject())
  }

  func unregister(_ registration: HotKeyRegistration) {
    keysByID[registration.id] = nil
    unregisterCount += 1
  }

}
