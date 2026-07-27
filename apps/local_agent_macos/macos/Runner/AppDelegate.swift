import Cocoa
import Carbon
import FlutterMacOS
import InferenceService

@main
class AppDelegate: FlutterAppDelegate {
  private var menuBarController: MenuBarController?
  private var hotKeyController: GlobalHotKeyController?
  private var desktopHostApi: LocalRuntimeDesktopHostApi?
  private var binaryMessenger: FlutterBinaryMessenger?

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

    let binaryMessenger = window.flutterEngine.binaryMessenger
    let eventSink = PigeonGenerationEventSink(
      api: DesktopHostEventApi(binaryMessenger: binaryMessenger)
    )
    let eventBridge = GenerationEventBridge(
      sink: eventSink,
      scheduler: MainQueueRuntimeEventScheduler(),
      coalescingMilliseconds: 10
    )
    let backend = DeterministicLocalModelRuntimeBackend(
      eventReceiver: eventBridge.receive
    )
    let coordinator = LocalModelRuntimeCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      cancellationFence: eventBridge
    )
    let desktopHostApi = LocalRuntimeDesktopHostApi(
      panelController: panelController,
      coordinator: coordinator,
      eventBridge: eventBridge
    )
    DesktopHostApiSetup.setUp(
      binaryMessenger: binaryMessenger,
      api: desktopHostApi
    )
    self.menuBarController = menuBarController
    self.hotKeyController = hotKeyController
    self.desktopHostApi = desktopHostApi
    self.binaryMessenger = binaryMessenger
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
    desktopHostApi?.dispose()
    if let binaryMessenger {
      DesktopHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: nil)
    }
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
