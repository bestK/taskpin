import Cocoa
import FlutterMacOS
// TaskPin's own native macOS module, compiled in by the `taskpin_bar` pod
// (see macos/Podfile and native/mac/taskpin_bar.podspec).
import taskpin_bar

class MainFlutterWindow: NSWindow {
  /// The manager window. There is exactly one; the AppDelegate's Dock reopen
  /// and the `taskpin/main_window` channel reach it through this.
  private(set) static weak var shared: MainFlutterWindow?

  private var mainWindowChannel: FlutterMethodChannel?

  /// The red traffic light and ⌘W hide the manager rather than closing it,
  /// matching Windows (`WM_CLOSE` -> `SW_HIDE`): the Flutter engine keeps
  /// running, so the menu-bar strips keep refreshing.
  override func performClose(_ sender: Any?) {
    orderOut(sender)
  }

  /// Un-hide, de-miniaturise and raise the manager.
  func showManager() {
    if isMiniaturized { deminiaturize(nil) }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  override func awakeFromNib() {
    MainFlutterWindow.shared = self

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
    // `taskpin/main_window` below answers `isMaximized()` with
    // NotImplemented, so it reads as null and TitleBar hides the
    // Windows-style button row.
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

    // The macOS half of `taskpin/main_window`
    // (lib/core/window/main_window_channel.dart). Only what macOS needs:
    //   show()   un-hide and raise (the strip menu's "Manage items...")
    //   close()  hide; the process and the strips stay
    //   quit()   terminate through AppKit, so the app quits the normal way
    //            (status items removed, engines shut down) instead of exit(0)
    // minimize / toggleMaximize / isMaximized stay NotImplemented: the traffic
    // lights own those, and a null isMaximized keeps TitleBar's Windows buttons
    // hidden.
    let channel = FlutterMethodChannel(
      name: "taskpin/main_window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "show":
        self?.showManager()
        result(nil)
      case "close":
        self?.orderOut(nil)
        result(nil)
      case "quit":
        result(nil)
        NSApp.terminate(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    mainWindowChannel = channel

    super.awakeFromNib()
  }
}
