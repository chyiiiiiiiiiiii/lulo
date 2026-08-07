import Carbon
import Foundation

struct GlobalHotKey: Equatable {
  let keyCode: UInt32
  let modifiers: UInt32
}

struct HotKeyRegistration {
  let id: UInt32
  let token: AnyObject
}

@MainActor
protocol HotKeyBackend: AnyObject {
  func register(
    _ key: GlobalHotKey,
    id: UInt32,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws -> HotKeyRegistration
  func unregister(_ registration: HotKeyRegistration)
}

@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
  func register(
    _ key: GlobalHotKey,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws
  func replace(
    with key: GlobalHotKey,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws
  func unregister()
}

extension GlobalHotKeyRegistering {
  func register(_ key: GlobalHotKey, handler: @escaping () -> Void) throws {
    try register(key, handler: handler, releaseHandler: nil)
  }

  func replace(with key: GlobalHotKey, handler: @escaping () -> Void) throws {
    try replace(with: key, handler: handler, releaseHandler: nil)
  }
}

enum GlobalHotKeyError: Error, Equatable {
  case registrationFailed(status: OSStatus)
  case eventHandlerInstallationFailed(status: OSStatus)
}

/// Splits one hotkey into a tap and a hold by time.
///
/// A press starts the threshold clock; a release that beats it is a tap,
/// and one that does not ends the hold the clock began. One key, two
/// meanings: tap toggles the window, hold is push-to-talk — no second
/// binding to learn, and no way to do both at once.
@MainActor
final class HotKeyHoldSplitter {
  /// Schedules [work] after the hold threshold; returns its cancellation.
  typealias Schedule = (@escaping () -> Void) -> () -> Void

  private let onTap: () -> Void
  private let onHoldBegan: () -> Void
  private let onHoldEnded: () -> Void
  private let schedule: Schedule
  private var cancelPending: (() -> Void)?
  private var holding = false

  init(
    onTap: @escaping () -> Void,
    onHoldBegan: @escaping () -> Void,
    onHoldEnded: @escaping () -> Void,
    schedule: @escaping Schedule
  ) {
    self.onTap = onTap
    self.onHoldBegan = onHoldBegan
    self.onHoldEnded = onHoldEnded
    self.schedule = schedule
  }

  func pressed() {
    guard cancelPending == nil, !holding else {
      // Key-repeat delivers extra presses for one physical hold.
      return
    }
    cancelPending = schedule { [weak self] in
      guard let self else { return }
      self.cancelPending = nil
      self.holding = true
      self.onHoldBegan()
    }
  }

  func released() {
    if holding {
      holding = false
      onHoldEnded()
    } else if let cancel = cancelPending {
      cancel()
      cancelPending = nil
      onTap()
    }
  }
}

@MainActor
final class GlobalHotKeyController: GlobalHotKeyRegistering {
  private let backend: HotKeyBackend
  private var registration: HotKeyRegistration?

  /// The next hot key id, shared by every controller in the process.
  ///
  /// Carbon's id space is global: a registration is addressed by
  /// `(signature, id)`, every controller here uses the same signature, and
  /// `CarbonHotKeyCallback.route` accepts on exactly that pair. A per-
  /// instance counter meant a second controller minted id 1 again and its
  /// handler answered for the first controller's key — which is how adding
  /// a dictation key silently took over ⌘⇧Space.
  private static var nextID: UInt32 = 1

  init(backend: HotKeyBackend) {
    self.backend = backend
  }

  convenience init() {
    self.init(backend: CarbonHotKeyBackend())
  }

  func register(
    _ key: GlobalHotKey,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws {
    guard registration == nil else {
      try replace(with: key, handler: handler, releaseHandler: releaseHandler)
      return
    }
    registration = try makeRegistration(
      for: key,
      handler: handler,
      releaseHandler: releaseHandler
    )
  }

  func replace(
    with key: GlobalHotKey,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws {
    let replacement = try makeRegistration(
      for: key,
      handler: handler,
      releaseHandler: releaseHandler
    )
    if let previous = registration {
      backend.unregister(previous)
    }
    registration = replacement
  }

  func unregister() {
    guard let registration else {
      return
    }
    backend.unregister(registration)
    self.registration = nil
  }

  private func makeRegistration(
    for key: GlobalHotKey,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws -> HotKeyRegistration {
    let id = Self.nextID
    defer { Self.nextID &+= 1 }
    return try backend.register(
      key,
      id: id,
      handler: handler,
      releaseHandler: releaseHandler
    )
  }
}

@MainActor
final class CarbonHotKeyBackend: HotKeyBackend {
  func register(
    _ key: GlobalHotKey,
    id: UInt32,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) throws -> HotKeyRegistration {
    let signature = OSType(0x4C_41_47_54)
    let mainQueueHandler = MainQueueHotKeyHandler(handler: handler)
    let mainQueueRelease = releaseHandler.map(MainQueueHotKeyHandler.init)
    let callback = CarbonHotKeyCallback(
      signature: signature,
      id: id,
      handler: mainQueueHandler.enqueue,
      releaseHandler: mainQueueRelease?.enqueue
    )
    var eventSpecs = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      ),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyReleased)
      ),
    ]
    var eventHandlerRef: EventHandlerRef?
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData -> OSStatus in
        guard let event, let userData else {
          return OSStatus(eventNotHandledErr)
        }
        let callback = Unmanaged<CarbonHotKeyCallback>
          .fromOpaque(userData)
          .takeUnretainedValue()
        var eventID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &eventID
        )
        guard status == noErr,
          callback.route(eventID, kind: GetEventKind(event))
        else {
          return OSStatus(eventNotHandledErr)
        }
        return noErr
      },
      2,
      &eventSpecs,
      Unmanaged.passUnretained(callback).toOpaque(),
      &eventHandlerRef
    )
    guard handlerStatus == noErr, let eventHandlerRef else {
      throw GlobalHotKeyError.eventHandlerInstallationFailed(
        status: handlerStatus
      )
    }

    var hotKeyRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(
      signature: signature,
      id: id
    )
    let registrationStatus = RegisterEventHotKey(
      key.keyCode,
      key.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    guard registrationStatus == noErr, let hotKeyRef else {
      RemoveEventHandler(eventHandlerRef)
      throw GlobalHotKeyError.registrationFailed(status: registrationStatus)
    }

    return HotKeyRegistration(
      id: id,
      token: CarbonHotKeyToken(
        hotKeyRef: hotKeyRef,
        eventHandlerRef: eventHandlerRef,
        callback: callback
      )
    )
  }

  func unregister(_ registration: HotKeyRegistration) {
    guard let token = registration.token as? CarbonHotKeyToken else {
      return
    }
    UnregisterEventHotKey(token.hotKeyRef)
    RemoveEventHandler(token.eventHandlerRef)
  }
}

private final class MainQueueHotKeyHandler {
  private let handler: () -> Void

  init(handler: @escaping () -> Void) {
    self.handler = handler
  }

  func enqueue() {
    DispatchQueue.main.async(execute: handler)
  }
}

final class CarbonHotKeyCallback {
  private let signature: OSType
  private let id: UInt32
  private let handler: () -> Void
  private let releaseHandler: (() -> Void)?

  init(
    signature: OSType,
    id: UInt32,
    handler: @escaping () -> Void,
    releaseHandler: (() -> Void)?
  ) {
    self.signature = signature
    self.id = id
    self.handler = handler
    self.releaseHandler = releaseHandler
  }

  func route(_ eventID: EventHotKeyID, kind: UInt32) -> Bool {
    guard eventID.signature == signature, eventID.id == id else {
      return false
    }
    if kind == UInt32(kEventHotKeyReleased) {
      guard let releaseHandler else {
        return false
      }
      releaseHandler()
    } else {
      handler()
    }
    return true
  }
}

private final class CarbonHotKeyToken {
  let hotKeyRef: EventHotKeyRef
  let eventHandlerRef: EventHandlerRef
  let callback: CarbonHotKeyCallback

  init(
    hotKeyRef: EventHotKeyRef,
    eventHandlerRef: EventHandlerRef,
    callback: CarbonHotKeyCallback
  ) {
    self.hotKeyRef = hotKeyRef
    self.eventHandlerRef = eventHandlerRef
    self.callback = callback
  }
}
