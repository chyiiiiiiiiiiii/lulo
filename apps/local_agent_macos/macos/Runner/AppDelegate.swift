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

  /// Held for the app's life: a menu item's target is not retained by the
  /// item, so a local one is deallocated and the shortcut stops working.
  private var newConversationMenuTarget: MenuActionTarget?
  private var conversationsMenuTarget: MenuActionTarget?

  /// Gives the app the File menu a Mac user expects to find.
  ///
  /// One item, because there is one thing to put in it. Closing puts the
  /// conversation away rather than closing the agent, which has no closed
  /// state to go to.
  private func installFileMenu(
    onNewConversation: @escaping () -> Void,
    onConversations: @escaping () -> Void
  ) {
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
    // What every assistant on this desktop answers. Both actions already
    // existed on the Dart side and had no way in but the history sheet.
    let newTarget = MenuActionTarget(action: onNewConversation)
    newConversationMenuTarget = newTarget
    let new = NSMenuItem(
      title: "New Conversation",
      action: #selector(MenuActionTarget.run),
      keyEquivalent: "n"
    )
    new.target = newTarget
    fileMenu.addItem(new)
    let listTarget = MenuActionTarget(action: onConversations)
    conversationsMenuTarget = listTarget
    let list = NSMenuItem(
      title: "Conversations…",
      action: #selector(MenuActionTarget.run),
      keyEquivalent: "O"
    )
    list.keyEquivalentModifierMask = [.command, .shift]
    list.target = listTarget
    fileMenu.addItem(list)
    fileMenu.addItem(.separator())
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

  /// Held so the Services handler can reach them; the system calls it long
  /// after `applicationDidFinishLaunching` has returned.
  private var servicePanel: DesktopPanelControlling?
  private var serviceEvents: DesktopHostEventApi?

  /// Keeps the frontmost-app observation alive for the app's lifetime.
  private var frontmostAppObserver: NSObjectProtocol?

  /// Takes the invited look at the screen; owned here beside the observer
  /// that tells it which app the user was last in.
  private var screenLook: ScreenLookController?
  private var hotKeyController: GlobalHotKeyController?
  private var hotKeySplitter: HotKeyHoldSplitter?
  private var dictationHotKey: GlobalHotKeyController?
  private var dictation: DictationController?
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

    // Hold ⌃⇧Space anywhere in macOS, speak, release, and the words are on
    // the clipboard. Its own key, its own controller, its own audio engine:
    // `docs/decisions/dictation-cannot-share-the-tap.md` is a whole document
    // about what carving this out of the conversation's tap costs.
    //
    // Not ⌘⇧D — Finder, Mail and most editors use it, and a Carbon hot key
    // beats the frontmost app's menu, so registering it would break those
    // apps for as long as Lulo runs. ⌃⇧Space is the least-claimed of the
    // combinations left beside the ⌘⇧Space this app already takes. Neither
    // key being user-configurable is the real problem underneath that and is
    // still not solved.
    let dictationController = DictationController(
      source: DictationAudioEngine(),
      transcribe: { clip in
        guard let url = await HeldSpeech.writeHeldClip(clip) else {
          return nil
        }
        return await HeldSpeech.transcribeHeld(
          url,
          terms: [],
          // A whole held utterance, not one sentence of a conversation.
          timeout: 30
        )
      },
      deliver: { copyToPasteboard($0) },
      report: { [weak menuBarController] outcome in
        menuBarController?.reportDictation(outcome)
      }
    )
    let dictationHotKey = GlobalHotKeyController()
    do {
      try dictationHotKey.register(
        GlobalHotKey(
          keyCode: UInt32(kVK_Space),
          modifiers: UInt32(controlKey | shiftKey)
        ),
        handler: { [weak dictationController] in
          MainActor.assumeIsolated { dictationController?.pressed() }
        },
        releaseHandler: { [weak dictationController] in
          Task { @MainActor in
            await dictationController?.released()
          }
        }
      )
    } catch {
      // The conversation's own hotkey is reported in the menu; a dictation
      // key that will not register leaves dictation simply absent, which is
      // what it was until now.
      NSLog(
        "Lulo dictation: the hotkey would not register (%@)",
        String(describing: error)
      )
    }
    self.dictation = dictationController
    self.dictationHotKey = dictationHotKey


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
    // The Services menu calls into this object directly, from any app, at
    // any time — so what it needs is kept rather than captured.
    self.servicePanel = panelController
    self.serviceEvents = eventApi
    NSApp.servicesProvider = self
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
    // The buttons under the resting orb are drawn by AppKit, because there is
    // no room inside the stage's frame beneath the orb and the window may
    // never be resized to make room. What each one *means* is decided in
    // Dart, so only the identifier crosses.
    panelController.onOrbActionInvoked = { id in
      eventApi.onOrbActionInvoked(actionId: id, completion: { _ in })
    }
    installSettingsMenuItem { eventApi.onSettingsRequested(completion: { _ in }) }
    installFileMenu(
      onNewConversation: {
        eventApi.onNewConversationRequested(completion: { _ in })
      },
      onConversations: {
        eventApi.onConversationsRequested(completion: { _ in })
      }
    )
    // Which app the user is in, told on every switch. Activating Lulo is
    // deliberately not reported: summoning the agent makes it frontmost,
    // and a question about "this" means the place the user came from.
    // Needs no permission — the name of the frontmost app is the one fact
    // macOS gives away freely, and it is all that crosses here. Whether a
    // question ever carries it is a setting applied on the other side.
    let ownBundleId = Bundle.main.bundleIdentifier
    let screenLookController = ScreenLookController()
    self.screenLook = screenLookController
    frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { notification in
      guard
        let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication,
        activated.bundleIdentifier != ownBundleId,
        let name = activated.localizedName,
        !name.isEmpty
      else {
        return
      }
      eventApi.onFrontmostAppChanged(name: name, completion: { _ in })
    }
    // The app the user was in when Lulo launched, so the first question is
    // not blind just because no switch has happened yet.
    if let current = NSWorkspace.shared.frontmostApplication,
      current.bundleIdentifier != ownBundleId,
      let name = current.localizedName,
      !name.isEmpty
    {
      eventApi.onFrontmostAppChanged(name: name, completion: { _ in })
    }
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
      menuBar: menuBarController,
      screenLook: screenLookController
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

  /// The Services menu handing over what the user had selected elsewhere.
  ///
  /// Named in `Info.plist` under `NSServices`; the selector is what the
  /// system calls. It shows the window as well as sending the text, because
  /// an answer arriving in a window the user cannot see is the same as no
  /// answer.
  @objc func askLuloAboutSelection(
    _ pasteboard: NSPasteboard,
    userData: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString>?
  ) {
    guard let text = SelectionService.text(from: pasteboard) else {
      error?.pointee = "There was no text to send." as NSString
      return
    }
    servicePanel?.show()
    servicePanel?.setPresentationMode(.expanded)
    serviceEvents?.onServiceTextReceived(text: text, completion: { _ in })
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
    dictationHotKey?.unregister()
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
