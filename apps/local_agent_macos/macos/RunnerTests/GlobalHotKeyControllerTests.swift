import Carbon
import XCTest

@testable import local_agent_macos

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
      handler: { invocationCount += 1 }
    )

    XCTAssertFalse(
      callback.route(
        EventHotKeyID(signature: OSType(0x4F_54_48_52), id: 7)
      )
    )
    XCTAssertEqual(invocationCount, 0)

    XCTAssertTrue(
      callback.route(
        EventHotKeyID(signature: expectedSignature, id: 7)
      )
    )
    XCTAssertEqual(invocationCount, 1)
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

  func register(
    _ key: GlobalHotKey,
    id: UInt32,
    handler: @escaping () -> Void
  ) throws -> HotKeyRegistration {
    if key == keyToReject {
      throw GlobalHotKeyError.registrationFailed(
        status: OSStatus(eventHotKeyExistsErr)
      )
    }
    keysByID[id] = key
    return HotKeyRegistration(id: id, token: NSObject())
  }

  func unregister(_ registration: HotKeyRegistration) {
    keysByID[registration.id] = nil
    unregisterCount += 1
  }
}
