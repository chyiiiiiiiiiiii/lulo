import Cocoa
import Carbon
import FlutterMacOS
import InferenceService

/// Carries a menu item's action to a closure.
final class MenuActionTarget: NSObject {
  init(action: @escaping () -> Void) {
    self.action = action
  }

  private let action: () -> Void

  @objc func run() {
    action()
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  /// Kept so the menu item has something to send its action to.
  private var settingsMenuTarget: MenuActionTarget?

  /// Puts Settings where every Mac app keeps it, under its own menu.
  ///
  /// Built in code rather than in the nib because the app menu is assembled
  /// from the bundle name at load, and this has to attach to whatever it ends
  /// up being called.
  private func installSettingsMenuItem(_ action: @escaping () -> Void) {
    guard let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu else {
      return
    }
    let target = MenuActionTarget(action: action)
    settingsMenuTarget = target
    // The template menu already carries the standard settings item, which
    // macOS renames and places for us. Adding another leaves the user with two
    // of them, so this takes over the one that is already there and only
    // builds one when the template has none.
    if let existing = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
      existing.target = target
      existing.action = #selector(MenuActionTarget.run)
      existing.isEnabled = true
      return
    }
    let item = NSMenuItem(
      title: "Settings…",
      action: #selector(MenuActionTarget.run),
      keyEquivalent: ","
    )
    item.target = target
    // Directly under About, which is where a Mac user reaches for it.
    appMenu.insertItem(item, at: min(1, appMenu.numberOfItems))
    appMenu.insertItem(.separator(), at: min(2, appMenu.numberOfItems))
  }

  /// Kept so the close item has something to send its action to.
  private var closeMenuTarget: MenuActionTarget?

  /// Gives the app the File menu a Mac user expects to find.
  ///
  /// One item, because there is one thing to put in it. Closing puts the
  /// conversation away rather than closing the agent, which has no closed
  /// state to go to.
  private func installFileMenu() {
    guard let mainMenu = NSApp.mainMenu,
      !mainMenu.items.contains(where: { $0.title == "File" })
    else {
      return
    }
    let target = MenuActionTarget { [weak self] in
      self?.collapseConversation()
    }
    closeMenuTarget = target
    let fileMenu = NSMenu(title: "File")
    let close = NSMenuItem(
      title: "Close",
      action: #selector(MenuActionTarget.run),
      keyEquivalent: "w"
    )
    close.target = target
    fileMenu.addItem(close)
    let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileItem.submenu = fileMenu
    // Right after the app's own menu, where File always sits.
    mainMenu.insertItem(fileItem, at: min(1, mainMenu.numberOfItems))
  }

  private func collapseConversation() {
    guard
      let controller = NSApp.windows
        .compactMap({ $0 as? MainFlutterWindow })
        .first?
        .panelController
    else {
      return
    }
    _ = controller.windowShouldClose(controller.retainedPanel)
  }

  private var menuBarController: MenuBarController?
  private var hotKeyController: GlobalHotKeyController?
  private var hotKeySplitter: HotKeyHoldSplitter?
  private var desktopHostApi: LocalRuntimeDesktopHostApi?
  private var binaryMessenger: FlutterBinaryMessenger?
  // Held as Any: the adapter's type only exists on macOS 26, and the voice
  // feature simply is not offered below it.
  private var voiceHostApi: Any?

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
    // One key, two meanings: a tap of ⌘⇧Space toggles the window as it
    // always has; holding it is push-to-talk from anywhere — the agent
    // falls silent and listens for as long as the key is down.
    let holdSplitter = HotKeyHoldSplitter(
      onTap: { [weak panelController] in
        panelController?.toggle()
      },
      onHoldBegan: { [weak self] in
        self?.voiceHold(began: true)
      },
      onHoldEnded: { [weak self] in
        self?.voiceHold(began: false)
      },
      schedule: { work in
        let pending = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(
          deadline: .now() + .milliseconds(300),
          execute: pending
        )
        return { pending.cancel() }
      }
    )
    do {
      try hotKeyController.register(
        GlobalHotKey(
          keyCode: UInt32(kVK_Space),
          modifiers: UInt32(cmdKey | shiftKey)
        ),
        handler: { holdSplitter.pressed() },
        releaseHandler: { holdSplitter.released() }
      )
      menuBarController.setHotKeyAvailable(true)
    } catch {
      menuBarController.setHotKeyAvailable(false)
    }
    self.hotKeySplitter = holdSplitter


    let binaryMessenger = window.flutterEngine.binaryMessenger
    let eventApi = DesktopHostEventApi(binaryMessenger: binaryMessenger)
    // The menu's items are the only place outside the window where the user
    // can ask for something, so they travel the same way every other request
    // from this side does.
    menuBarController.onConversationChosen = { conversationId in
      eventApi.onMenuBarConversationChosen(
        conversationId: conversationId,
        completion: { _ in }
      )
    }
    menuBarController.onVoiceRequested = {
      eventApi.onMenuBarVoiceRequested(completion: { _ in })
    }
    // The hotkey and the menu bar can both change the form, so the Flutter
    // surface is told about every change rather than only the ones it asked
    // for. Otherwise the orb and the conversation can disagree about which is
    // on screen.
    panelController.onPresentationModeChanged = { mode in
      eventApi.onPresentationModeChanged(
        mode: mode == .orb ? .orb : .expanded,
        completion: { _ in }
      )
    }
    // The hotkey and the menu bar ask rather than act, so the app can draw the
    // presence travelling between the two forms instead of finding out the
    // window has already moved.
    panelController.onPresentationChangeRequested = { target in
      eventApi.onPresentationChangeRequested(
        target: target == .orb ? .orb : .expanded,
        completion: { _ in }
      )
    }
    // The frame belongs to the user — resized, zoomed, or taken full screen —
    // and the forms are laid out against it, so every change is reported.
    panelController.onGeometryChanged = { geometry in
      eventApi.onPresentationGeometryChanged(
        geometry: LocalRuntimeDesktopHostApi.hostGeometry(geometry),
        completion: { _ in }
      )
    }
    installSettingsMenuItem { eventApi.onSettingsRequested(completion: { _ in }) }
    installFileMenu()
    let eventSink = PigeonGenerationEventSink(api: eventApi)
    let eventBridge = GenerationEventBridge(
      sink: eventSink,
      scheduler: MainQueueRuntimeEventScheduler(),
      coalescingMilliseconds: 10
    )
    // The relay buffers backend events until the coordinator attaches, so a
    // generation that finishes before wiring completes is not lost. The
    // coordinator is the single arbiter: it sequences and fences events, then
    // forwards them to the Flutter bridge through its event handler.
    let eventRelay = RuntimeGenerationEventRelay()
    let backend = LiteRTLMRuntimeBackend(eventRelay: eventRelay)
    let coordinator = InferenceCoordinator(
      supportedSchemaVersion: 2,
      backend: backend,
      eventHandler: { [eventBridge] event in
        eventBridge.receive(event)
      }
    )
    Task {
      await eventRelay.attach { [coordinator] event in
        await coordinator.receiveGenerationEvent(event)
      }
    }
    let desktopHostApi = LocalRuntimeDesktopHostApi(
      panelController: panelController,
      coordinator: coordinator,
      eventBridge: eventBridge,
      menuBar: menuBarController
    )
    DesktopHostApiSetup.setUp(
      binaryMessenger: binaryMessenger,
      api: desktopHostApi
    )
    // The ears and the mouth: SpeechAnalyzer transcription in, synthesized
    // speech out, everything reported back as events. Below macOS 26 the
    // transcriber does not exist and voice is simply not offered.
    if #available(macOS 26.0, *) {
      let voiceHostApi = VoiceHostAdapter(
        events: VoiceHostEvents(binaryMessenger: binaryMessenger)
      )
      VoiceHostApiSetup.setUp(
        binaryMessenger: binaryMessenger,
        api: voiceHostApi
      )
      self.voiceHostApi = voiceHostApi
    }
    self.menuBarController = menuBarController
    self.hotKeyController = hotKeyController
    self.desktopHostApi = desktopHostApi
    self.binaryMessenger = binaryMessenger
    // The agent rests on the desktop as the orb. Launching straight into the
    // conversation would put a panel in front of whatever the user is doing.
    panelController.setPresentationMode(.orb)
    super.applicationDidFinishLaunching(notification)
  }

  /// The held hotkey, handed to the voice pipeline as push-to-talk.
  private func voiceHold(began: Bool) {
    if #available(macOS 26.0, *) {
      guard let adapter = voiceHostApi as? VoiceHostAdapter else {
        return
      }
      // The splitter's callbacks arrive on the main queue already.
      MainActor.assumeIsolated {
        adapter.hotKeyHold(began: began)
      }
    }
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
      VoiceHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: nil)
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
