import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSPanel {
  private(set) var flutterEngine: FlutterEngine!
  private(set) var flutterViewController: FlutterViewController!
  private(set) var panelController: DesktopPanelController!

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  override func awakeFromNib() {
    let windowFrame = self.frame
    let engine = FlutterEngine(
      name: "retained_local_agent_engine",
      project: nil
    )
    precondition(
      engine.run(withEntrypoint: nil),
      "The retained Flutter engine failed to start."
    )
    let viewController = FlutterViewController(
      engine: engine,
      nibName: nil,
      bundle: nil
    )

    // The desktop orb sits on a transparent window, and a Flutter view paints
    // an opaque background of its own unless it is cleared here. Without this
    // the vapour is composited onto a black square.
    viewController.backgroundColor = .clear

    RegisterGeneratedPlugins(registry: engine)
    flutterEngine = engine
    flutterViewController = viewController
    panelController = DesktopPanelController(panel: self) {
      FlutterPanelContent(engine: engine, viewController: viewController)
    }
    setFrame(windowFrame, display: true)

    super.awakeFromNib()
  }
}
