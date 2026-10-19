import Cocoa
import FlutterMacOS
// TaskPin's own native macOS module, compiled in by the `taskpin_bar` pod
// (see macos/Podfile and native/mac/taskpin_bar.podspec).
import taskpin_bar

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // ── Self-drawn title bar (docs/UI_REFACTOR_PLAN.md §5.2) ──────────────
    //
    // The manager window paints its own 36 px title bar in Flutter
    // (lib/ui/widgets/title_bar.dart), so AppKit's title and title bar are
    // hidden:
    //
    //   titleVisibility = .hidden        no "TaskPin" text in the bar
    //   titlebarAppearsTransparent       the Flutter surface shows through
    //   .fullSizeContentView             content starts at the window's top
    //                                    edge, under the traffic lights
    //
    // The traffic lights stay where they are — that is the point of
    // fullSizeContentView — and the Dart side reserves 72 pt on the left for
    // them. There are no right-side buttons on macOS: the native half of
    // `taskpin/main_window` does not exist, so `isMaximized()` returns null and
    // TitleBar hides the Windows-style button row.
    //
    // This must be set before `super.awakeFromNib()` so the first layout pass
    // already sees the full-size content view; doing it afterwards causes a
    // visible jump of the whole window content on launch.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The generated registrant only knows about pubspec plugins
    // (desktop_multi_window); it cannot know about our own native module, and
    // macos/Flutter/GeneratedPluginRegistrant.swift is generated so it must not
    // be hand-edited. This is the one line that replaces that edit: it gives
    // this engine the `taskpin/bar` channel, which is what drives the menu-bar
    // items (native/mac/StatusItemPlugin.swift).
    //
    // `flutterViewController.registrar(forPlugin:)` rather than the view
    // controller itself: the registrar is the object that owns a plugin's
    // messenger and lifecycle, and `FlutterPlugin.register(with:)` takes one.
    TaskpinBarPluginRegistrar.register(
      with: flutterViewController.registrar(forPlugin: "TaskpinBarPlugin")
    )

    super.awakeFromNib()
  }
}
