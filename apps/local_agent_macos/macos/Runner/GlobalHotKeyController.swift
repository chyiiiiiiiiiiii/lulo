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
    let callback = CarbonHotKeyCallback(id: id, handler: handler)
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
        guard status == noErr, eventID.id == callback.id else {
          return OSStatus(eventNotHandledErr)
        }
        DispatchQueue.main.async(execute: callback.handler)
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
      signature: OSType(0x4C_41_47_54),
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

private final class CarbonHotKeyCallback {
  let id: UInt32
  let handler: () -> Void

  init(id: UInt32, handler: @escaping () -> Void) {
    self.id = id
    self.handler = handler
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
