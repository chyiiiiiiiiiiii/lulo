import AppKit

protocol DesktopPanelControlling: AnyObject {
  var isVisible: Bool { get }
  func show()
  func hide()
  func toggle()
}

struct FlutterPanelContent {
  let engine: AnyObject
  let viewController: NSViewController
}

final class DesktopPanelController: DesktopPanelControlling {
  private(set) var retainedPanel: NSPanel
  private(set) var retainedEngine: AnyObject
  private let screenProvider: () -> NSScreen?

  init(
    panel: NSPanel,
    screenProvider: @escaping () -> NSScreen? = DesktopPanelController.screenAtPointer,
    contentFactory: () -> FlutterPanelContent
  ) {
    precondition(Thread.isMainThread)
    let content = contentFactory()
    retainedPanel = panel
    retainedEngine = content.engine
    self.screenProvider = screenProvider

    panel.contentViewController = content.viewController
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.styleMask.insert(.nonactivatingPanel)
    panel.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
  }

  var isVisible: Bool {
    retainedPanel.isVisible
  }

  func show() {
    precondition(Thread.isMainThread)
    if !retainedPanel.isVisible {
      moveToActiveDisplay()
    }
    NSApp.activate(ignoringOtherApps: true)
    retainedPanel.orderFrontRegardless()
    retainedPanel.makeKey()
  }

  func hide() {
    precondition(Thread.isMainThread)
    retainedPanel.orderOut(nil)
  }

  func toggle() {
    precondition(Thread.isMainThread)
    isVisible ? hide() : show()
  }

  private func moveToActiveDisplay() {
    guard let screen = screenProvider() else {
      return
    }
    let visibleFrame = screen.visibleFrame
    let origin = NSPoint(
      x: visibleFrame.midX - retainedPanel.frame.width / 2,
      y: visibleFrame.midY - retainedPanel.frame.height / 2
    )
    retainedPanel.setFrameOrigin(origin)
  }

  private static func screenAtPointer() -> NSScreen? {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
      ?? NSScreen.main
  }
}
