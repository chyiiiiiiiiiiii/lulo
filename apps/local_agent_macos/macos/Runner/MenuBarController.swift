import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
  private let panelController: DesktopPanelControlling
  private let statusItem: NSStatusItem
  private let visibilityItem = NSMenuItem()
  private let hotKeyStatusItem = NSMenuItem()

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

    let menu = NSMenu()
    menu.delegate = self
    visibilityItem.target = self
    visibilityItem.action = #selector(togglePanel)
    menu.addItem(visibilityItem)
    hotKeyStatusItem.isEnabled = false
    hotKeyStatusItem.isHidden = true
    menu.addItem(hotKeyStatusItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "Quit Local Agent",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    menu.addItem(quitItem)
    statusItem.menu = menu
    refreshVisibilityTitle()
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

  @objc private func togglePanel() {
    panelController.toggle()
    refreshVisibilityTitle()
  }

  private func refreshVisibilityTitle() {
    visibilityItem.title = panelController.isVisible
      ? "Hide Local Agent"
      : "Show Local Agent"
  }
}
