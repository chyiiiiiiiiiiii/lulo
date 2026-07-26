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
    handler: @escaping () -> Void
  ) throws -> HotKeyRegistration
  func unregister(_ registration: HotKeyRegistration)
}

@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
  func register(_ key: GlobalHotKey, handler: @escaping () -> Void) throws
  func replace(with key: GlobalHotKey, handler: @escaping () -> Void) throws
  func unregister()
}

enum GlobalHotKeyError: Error, Equatable {
  case registrationFailed(status: OSStatus)
  case eventHandlerInstallationFailed(status: OSStatus)
}

@MainActor
final class GlobalHotKeyController: GlobalHotKeyRegistering {
  private let backend: HotKeyBackend
  private var registration: HotKeyRegistration?
  private var nextID: UInt32 = 1

  init(backend: HotKeyBackend) {
    self.backend = backend
  }

  convenience init() {
    self.init(backend: CarbonHotKeyBackend())
  }

  func register(_ key: GlobalHotKey, handler: @escaping () -> Void) throws {
    guard registration == nil else {
      try replace(with: key, handler: handler)
      return
    }
    registration = try makeRegistration(for: key, handler: handler)
  }

  func replace(
    with key: GlobalHotKey,
    handler: @escaping () -> Void
  ) throws {
    let replacement = try makeRegistration(for: key, handler: handler)
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
    handler: @escaping () -> Void
  ) throws -> HotKeyRegistration {
    defer { nextID &+= 1 }
    return try backend.register(key, id: nextID, handler: handler)
  }
}

@MainActor
final class CarbonHotKeyBackend: HotKeyBackend {
  func register(
    _ key: GlobalHotKey,
    id: UInt32,
    handler: @escaping () -> Void
  ) throws -> HotKeyRegistration {
    let signature = OSType(0x4C_41_47_54)
    let mainQueueHandler = MainQueueHotKeyHandler(handler: handler)
    let callback = CarbonHotKeyCallback(
      signature: signature,
      id: id,
      handler: mainQueueHandler.enqueue
    )
    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
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
        guard status == noErr, callback.route(eventID) else {
          return OSStatus(eventNotHandledErr)
        }
        return noErr
      },
      1,
      &eventSpec,
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

  init(
    signature: OSType,
    id: UInt32,
    handler: @escaping () -> Void
  ) {
    self.signature = signature
    self.id = id
    self.handler = handler
  }

  func route(_ eventID: EventHotKeyID) -> Bool {
    guard eventID.signature == signature, eventID.id == id else {
      return false
    }
    handler()
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
