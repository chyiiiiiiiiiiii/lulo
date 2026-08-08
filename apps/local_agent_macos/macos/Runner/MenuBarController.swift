import AppKit

/// The status-bar menu, which is half of what a resident app is for.
///
/// It used to hold show/hide and quit and nothing else, which is a menu with
/// no reason to be opened. What it shows now — what the agent is doing, what
/// it is thinking with, and the conversations it has been having — is pushed
/// from Dart rather than pulled: AppKit builds the menu at the moment it
/// opens, and asking across the channel then would mean opening an empty menu
/// that fills in a frame later.
final class MenuBarController: NSObject, NSMenuDelegate {
  /// What the menu is currently showing.
  struct State {
    /// The most recent conversations, in the order they should be listed.
    var conversations: [(id: String, title: String)] = []
    /// What the agent is thinking with, empty while it is the preview.
    var modelName: String = ""
    /// What it is doing right now, already in the user's language.
    var activity: String = ""
    /// Whether voice can be started at all.
    var canStartVoice: Bool = false
    /// The menu's own words, already in the user's language.
    var labels: Labels = Labels()
  }

  /// Every word the menu shows that is not a conversation title.
  ///
  /// Handed over rather than written here. The rest of the interface follows
  /// the system language through `AppLocalizations`, and there is none of
  /// that on this side — a menu that composed its own titles would be the one
  /// part of the app that stayed English on a Chinese Mac.
  struct Labels {
    var show: String = "Show Lulo"
    var hide: String = "Hide Lulo"
    var talk: String = "Talk to Lulo"
    var recent: String = "Recent"
    var quit: String = "Quit Lulo"
  }

  /// How many conversations the menu lists.
  ///
  /// A menu is a shortcut, not a browser: the list already exists inside the
  /// app and anything past the last few is quicker to find there.
  static let listedConversations = 3

  private let panelController: DesktopPanelControlling
  private let statusItem: NSStatusItem
  private let visibilityItem = NSMenuItem()
  private let hotKeyStatusItem = NSMenuItem()
  private let dictationItem = NSMenuItem()
  private var dictationClearsAt: Date?
  private let activityItem = NSMenuItem()
  private let modelItem = NSMenuItem()
  private let voiceItem = NSMenuItem()
  private let conversationsHeading = NSMenuItem()
  private var conversationItems: [NSMenuItem] = []
  private let menu = NSMenu()

  private var state = State()

  /// Called with the conversation the user chose from the menu.
  var onConversationChosen: ((String) -> Void)?

  /// Called when the user asked for voice from the menu.
  var onVoiceRequested: (() -> Void)?

  init(
    panelController: DesktopPanelControlling,
    statusBar: NSStatusBar = .system
  ) {
    self.panelController = panelController
    statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    if #available(macOS 11.0, *) {
      statusItem.button?.image = NSImage(
        systemSymbolName: "sparkles",
        accessibilityDescription: "Local Agent"
      )
    } else {
      statusItem.button?.title = "AI"
    }

    dictationItem.isHidden = true
    menu.delegate = self
    statusItem.menu = menu
    rebuild()
  }

  /// Replaces what the menu shows.
  func apply(_ state: State) {
    self.state = state
    rebuild()
  }

  /// Says how the last dictation went, where the user can actually see it.
  ///
  /// The menu bar and not the app's own window: a dictation happens while the
  /// user is working in somebody else's app, so anything drawn inside Lulo is
  /// drawn where nobody is looking. A failure that is only logged is
  /// discovered by pasting the previous clipboard contents into someone
  /// else's document.
  ///
  /// The icon carries it too, because a menu nobody opens says nothing: it
  /// goes to a filled dot on success and an exclamation on any failure, and
  /// back to the resting glyph after [dictationNoticeSeconds].
  func reportDictation(_ outcome: DictationOutcome) {
    let symbol: String
    switch outcome {
    case .copied(let characters):
      dictationItem.title = "Copied \(characters) characters"
      symbol = "checkmark.circle.fill"
      NSSound(named: "Tink")?.play()
    case .heardNothing:
      dictationItem.title = "Heard nothing — say it again"
      symbol = "exclamationmark.circle"
      NSSound(named: "Funk")?.play()
    case .microphoneUnavailable:
      dictationItem.title = "The microphone would not open"
      symbol = "exclamationmark.circle"
      NSSound(named: "Funk")?.play()
    case .recogniserUnreachable:
      dictationItem.title = "The recogniser is not running"
      symbol = "exclamationmark.circle"
      NSSound(named: "Funk")?.play()
    }
    dictationItem.isHidden = false
    setStatusSymbol(symbol)
    // Back to resting after a while, so a success from ten minutes ago is not
    // still being reported as though it just happened.
    let clearsAt = Date().addingTimeInterval(Self.dictationNoticeSeconds)
    dictationClearsAt = clearsAt
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.dictationNoticeSeconds
    ) { [weak self] in
      guard let self, self.dictationClearsAt == clearsAt else { return }
      self.dictationClearsAt = nil
      self.dictationItem.isHidden = true
      self.setStatusSymbol("sparkles")
    }
    rebuild()
  }

  /// How long the icon carries the outcome of a dictation.
  static let dictationNoticeSeconds: TimeInterval = 4

  private func setStatusSymbol(_ name: String) {
    if #available(macOS 11.0, *) {
      statusItem.button?.image = NSImage(
        systemSymbolName: name,
        accessibilityDescription: "Local Agent"
      )
    }
  }

  /// The last dictation's line, for tests.
  var dictationNoticeForTesting: String? {
    dictationItem.isHidden ? nil : dictationItem.title
  }

  func setHotKeyAvailable(_ available: Bool) {
    hotKeyStatusItem.isHidden = available
    hotKeyStatusItem.title = available
      ? ""
      : "Global shortcut unavailable — use Show"
  }

  func menuWillOpen(_ menu: NSMenu) {
    refreshVisibilityTitle()
  }

  /// Rebuilds the whole menu from `state`.
  ///
  /// Rebuilt rather than patched: the conversation list changes length, and
  /// a menu assembled by index is the kind of thing that survives every test
  /// and then puts the wrong title on the wrong item in front of a user.
  private func rebuild() {
    menu.removeAllItems()
    conversationItems.removeAll()

    // What it is doing, first, because that is the question the menu is most
    // often opened to answer.
    if !state.activity.isEmpty {
      activityItem.title = state.activity
      activityItem.isEnabled = false
      menu.addItem(activityItem)
    }
    if !state.modelName.isEmpty {
      modelItem.title = state.modelName
      modelItem.isEnabled = false
      menu.addItem(modelItem)
    }
    if menu.numberOfItems > 0 {
      menu.addItem(.separator())
    }

    visibilityItem.target = self
    visibilityItem.action = #selector(togglePanel)
    menu.addItem(visibilityItem)
    refreshVisibilityTitle()

    if state.canStartVoice {
      voiceItem.title = state.labels.talk
      voiceItem.target = self
      voiceItem.action = #selector(startVoice)
      menu.addItem(voiceItem)
    }

    if !state.conversations.isEmpty {
      menu.addItem(.separator())
      conversationsHeading.title = state.labels.recent
      conversationsHeading.isEnabled = false
      menu.addItem(conversationsHeading)
      for conversation in state.conversations.prefix(Self.listedConversations) {
        let item = NSMenuItem(
          title: conversation.title,
          action: #selector(openConversation(_:)),
          keyEquivalent: ""
        )
        item.target = self
        // The identifier carries the conversation, so the handler never has
        // to find it again by title or by position.
        item.representedObject = conversation.id
        menu.addItem(item)
        conversationItems.append(item)
      }
    }

    if !dictationItem.isHidden {
      menu.addItem(.separator())
      dictationItem.isEnabled = false
      menu.addItem(dictationItem)
    }

    menu.addItem(.separator())
    hotKeyStatusItem.isEnabled = false
    menu.addItem(hotKeyStatusItem)
    let quitItem = NSMenuItem(
      title: state.labels.quit,
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    menu.addItem(quitItem)
  }

  @objc private func togglePanel() {
    panelController.toggle()
    refreshVisibilityTitle()
  }

  @objc private func startVoice() {
    onVoiceRequested?()
  }

  @objc private func openConversation(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else {
      return
    }
    onConversationChosen?(id)
  }

  private func refreshVisibilityTitle() {
    visibilityItem.title = panelController.isVisible
      ? state.labels.hide
      : state.labels.show
  }

  /// The menu as it stands, for tests.
  var itemsForTesting: [NSMenuItem] { menu.items }
}
