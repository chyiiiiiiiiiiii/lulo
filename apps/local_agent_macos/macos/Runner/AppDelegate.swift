import Cocoa
import Carbon
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var menuBarController: MenuBarController?
  private var hotKeyController: GlobalHotKeyController?
  private var desktopHostApi: PanelDesktopHostApi?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    guard let window = resolveMainFlutterWindow(
      outletWindow: mainFlutterWindow,
      applicationWindows: NSApp.windows
    ), let panelController = window.panelController else {
      assertionFailure("The retained desktop panel was not loaded.")
      super.applicationDidFinishLaunching(notification)
      return
    }

    let menuBarController = MenuBarController(panelController: panelController)
    let hotKeyController = GlobalHotKeyController()
    do {
      try hotKeyController.register(
        GlobalHotKey(
          keyCode: UInt32(kVK_Space),
          modifiers: UInt32(cmdKey | shiftKey)
        ),
        handler: { [weak panelController] in
          panelController?.toggle()
        }
      )
      menuBarController.setHotKeyAvailable(true)
    } catch {
      menuBarController.setHotKeyAvailable(false)
    }

    let desktopHostApi = PanelDesktopHostApi(
      panelController: panelController
    )
    DesktopHostApiSetup.setUp(
      binaryMessenger: window.flutterEngine.binaryMessenger,
      api: desktopHostApi
    )
    self.menuBarController = menuBarController
    self.hotKeyController = hotKeyController
    self.desktopHostApi = desktopHostApi
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag,
      let panelController = NSApp.windows
        .compactMap({ $0 as? MainFlutterWindow })
        .first?
        .panelController
    {
      panelController.show()
    }
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    hotKeyController?.unregister()
    super.applicationWillTerminate(notification)
  }
}

func resolveMainFlutterWindow(
  outletWindow: NSWindow?,
  applicationWindows: [NSWindow]
) -> MainFlutterWindow? {
  if let window = outletWindow as? MainFlutterWindow {
    return window
  }
  return applicationWindows.compactMap { $0 as? MainFlutterWindow }.first
}

private final class PanelDesktopHostApi: DesktopHostApi {
  private let panelController: DesktopPanelControlling

  init(panelController: DesktopPanelControlling) {
    self.panelController = panelController
  }

  func showPanel(request: HostRequest) throws {
    try validate(request)
    onMain { self.panelController.show() }
  }

  func hidePanel(request: HostRequest) throws {
    try validate(request)
    onMain { self.panelController.hide() }
  }

  func togglePanel(request: HostRequest) throws {
    try validate(request)
    onMain { self.panelController.toggle() }
  }

  private func validate(_ request: HostRequest) throws {
    guard
      request.schemaVersion == 1,
      !request.requestId.isEmpty,
      request.timestampMicros > 0
    else {
      throw PigeonError(
        code: "protocolMismatch",
        message: "The desktop host request schema is incompatible.",
        details: nil
      )
    }
  }

  private func onMain(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.sync(execute: operation)
    }
  }
}
