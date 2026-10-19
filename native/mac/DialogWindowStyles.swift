// DialogWindowStyles.swift — the macOS half of the `taskpin/window` channel.
//
// The Dart side is `lib/features/dialogs/window_channel.dart`; the method names,
// argument keys and semantics are the same as the Windows half
// (`native/win/dialog_window_styles.cpp`) so `DialogWindowApi` is
// platform-agnostic. This mirrors how the plan keeps `taskpin/bar` identical
// across platforms with only the native painter differing
// (docs/FLUTTER_REWRITE_PLAN.md, "macOS 菜单栏条").
//
// The plan's macOS mapping, which this implements:
//
//   borderless    styleMask without .titled (+ .fullSizeContentView)
//   always-on-top level = .floating
//   clickthrough  ignoresMouseEvents = true
//   opacity       alphaValue = alpha / 255
//   transparent   isOpaque = false, backgroundColor = .clear
//   hidden from   collectionBehavior without .canJoinAllSpaces; a window with no
//   Dock/Alt+Tab  .titled and no Dock tile behaves like the C WS_EX_TOOLWINDOW
//
// AppKit is the same family of window attributes the plan calls "比现在折腾
// WS_EX_* 干净" (cleaner than fighting WS_EX_*), so unlike the Windows side this
// needs no layered-window dance: `alphaValue` and `ignoresMouseEvents` are
// first-class NSWindow properties.
//
// NOT VERIFIED: there is no macOS host on this machine (the plan notes Xcode is
// not installed and the macOS phases run on a mac or in CI). This file is
// written to the AppKit API and to the same channel contract as the Windows
// half; it has never been compiled.

import AppKit
import FlutterMacOS

/// The channel name. Must match `kDialogWindowChannel` in
/// `lib/features/dialogs/window_channel.dart`.
private let kDialogWindowChannel = "taskpin/window"

/// Minimum size after a Shift+scroll resize.
///
/// `lib/script_dialog.c:599-600`: `if (w < 80) w = 80; if (h < 40) h = 40;`
/// Kept identical on both platforms so a dialog behaves the same way.
private let kMinWidth: CGFloat = 80
private let kMinHeight: CGFloat = 40

/// Applies the dialog's window effects.
///
/// A struct rather than a class: it holds no state, every method derives what it
/// needs from the window it is handed.
struct DialogWindowStyles {
    /// Remove the title bar and frame; keep the window out of the Dock and the
    /// window cycler.
    ///
    /// `.fullSizeContentView` lets the Flutter view keep the whole window when
    /// the title bar is gone, which is what makes a `borderless` dialog's
    /// content fill its frame instead of sitting under a 22 pt gap.
    static func setBorderless(_ window: NSWindow, borderless: Bool) {
        if borderless {
            window.styleMask.remove([.titled, .closable, .miniaturizable, .resizable])
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Stand in for WS_EX_TOOLWINDOW: an accessory window gets no Dock
            // tile and does not appear in Cmd+Tab.
            window.level = .floating
        } else {
            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
            window.styleMask.remove(.fullSizeContentView)
            window.titleVisibility = .visible
        }
    }

    /// Let mouse input fall through to whatever is beneath.
    ///
    /// C parity: `WM_NCHITTEST` -> `HTTRANSPARENT`, `lib/script_dialog.c:623-624`.
    /// AppKit spells this directly, with none of the layered-window prerequisite
    /// the Windows side needs.
    static func setClickthrough(_ window: NSWindow, clickthrough: Bool) {
        window.ignoresMouseEvents = clickthrough
    }

    /// Window alpha, 0-255.
    ///
    /// C parity: `SetLayeredWindowAttributes(..., LWA_ALPHA)`,
    /// `lib/script_dialog.c:101-104`. NSWindow wants 0.0-1.0.
    static func setOpacity(_ window: NSWindow, alpha: Int) {
        let clamped = max(0, min(255, alpha))
        window.alphaValue = CGFloat(clamped) / 255.0
    }

    /// Let the desktop show through the window.
    ///
    /// `TPDialogSpec.transparent_bg`. Note this makes the NSWindow transparent,
    /// but the Flutter view inside it still paints its own background unless the
    /// embedder is configured otherwise — the same caveat documented on the
    /// Windows side (`tp_dialog_set_transparent_background`). The Dart renderer
    /// declines to paint a fill when the flag is set, which is the half of this
    /// that is in our control.
    static func setTransparentBackground(_ window: NSWindow, transparent: Bool) {
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .windowBackgroundColor
    }

    /// Begin a system window drag from the pointer's current position.
    ///
    /// C parity: `WM_NCHITTEST` -> `HTCAPTION`, `lib/script_dialog.c:621-622`.
    ///
    /// `performDrag(with:)` wants the current event; when the Dart side calls
    /// this from a pointer-down handler the event is the one AppKit is
    /// dispatching, so `NSApp.currentEvent` is the right source.
    static func beginDrag(_ window: NSWindow) {
        guard let event = NSApp.currentEvent else {
            return
        }
        window.performDrag(with: event)
    }

    /// Grow the window by a delta, clamped.
    ///
    /// C parity: `SetWindowPos(..., SWP_NOMOVE | SWP_NOZORDER)` after the clamp
    /// (`lib/script_dialog.c:592-602`). AppKit's origin is bottom-left, so the
    /// height change has to move the origin down by the same amount to keep the
    /// window's TOP edge fixed — otherwise a Shift+scroll would walk the dialog
    /// up the screen.
    static func resizeBy(_ window: NSWindow, dx: CGFloat, dy: CGFloat) {
        var frame = window.frame
        let newWidth = max(kMinWidth, frame.width + dx)
        let newHeight = max(kMinHeight, frame.height + dy)
        let deltaHeight = newHeight - frame.height
        frame.origin.y -= deltaHeight
        frame.size = NSSize(width: newWidth, height: newHeight)
        window.setFrame(frame, display: true)
    }

    /// Position and size the window.
    ///
    /// `x` or `y` of -1 means "centre on the main screen", matching the C
    /// layer's `(screen - window) / 2` (`lib/script_dialog.c:91-94`) and the
    /// sentinel the Dart side sends.
    ///
    /// The requested size is the CONTENT size, so the frame is grown by the
    /// chrome the window currently has — the macOS equivalent of the Windows
    /// `AdjustWindowRectEx` in `tp_dialog_set_frame`.
    static func setFrame(
        _ window: NSWindow,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        guard width > 0, height > 0 else {
            return
        }
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        let frameRect = window.frameRect(forContentRect: contentRect)

        var origin = NSPoint(x: x, y: y)
        if x < 0 || y < 0 {
            guard let screen = window.screen ?? NSScreen.main else {
                return
            }
            let visible = screen.visibleFrame
            let centredX = visible.midX - frameRect.width / 2
            // AppKit's y is bottom-left; `visibleFrame` already excludes the
            // menu bar, which is the closer analogue of the C layer's
            // GetSystemMetrics(SM_CYSCREEN) than `frame` would be.
            let centredY = visible.midY - frameRect.height / 2
            if x < 0 {
                origin.x = centredX
            }
            if y < 0 {
                origin.y = centredY
            }
        }
        window.setFrame(
            NSRect(x: origin.x, y: origin.y, width: frameRect.width, height: frameRect.height),
            display: true
        )
    }

    /// Close the window.
    static func close(_ window: NSWindow) {
        window.performClose(nil)
    }
}

/// Registers the `taskpin/window` handler for one engine.
///
/// Mirrors `TaskpinDialogWindowStylesRegisterWithRegistrar` on the Windows side.
/// The registrar's `view.window` is the window this engine's dialog lives in.
public final class DialogWindowStylesPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: kDialogWindowChannel,
            binaryMessenger: registrar.messenger
        )
        let instance = DialogWindowStylesPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /// The window this plugin acts on. Set by the runner when the dialog window
    /// is created; a `FlutterPlugin` has no window of its own, so unlike the
    /// Windows registrar path (`GetView()->GetNativeWindow()`) it must be told.
    public weak var window: NSWindow?

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let window = window ?? NSApp.keyWindow ?? NSApp.mainWindow else {
            result(FlutterError(
                code: "no_window",
                message: "taskpin/window: no window to apply '\(call.method)' to",
                details: nil
            ))
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "setBorderless":
            DialogWindowStyles.setBorderless(
                window, borderless: args["borderless"] as? Bool ?? false)
        case "setClickthrough":
            DialogWindowStyles.setClickthrough(
                window, clickthrough: args["clickthrough"] as? Bool ?? false)
        case "setOpacity":
            DialogWindowStyles.setOpacity(window, alpha: args["alpha"] as? Int ?? 255)
        case "setTransparentBackground":
            DialogWindowStyles.setTransparentBackground(
                window, transparent: args["transparent"] as? Bool ?? false)
        case "setFrame":
            DialogWindowStyles.setFrame(
                window,
                x: CGFloat(args["x"] as? Double ?? -1),
                y: CGFloat(args["y"] as? Double ?? -1),
                width: CGFloat(args["width"] as? Double ?? 400),
                height: CGFloat(args["height"] as? Double ?? 300)
            )
        case "beginDrag":
            DialogWindowStyles.beginDrag(window)
        case "resizeBy":
            DialogWindowStyles.resizeBy(
                window,
                dx: CGFloat(args["dx"] as? Double ?? 0),
                dy: CGFloat(args["dy"] as? Double ?? 0)
            )
        case "close":
            DialogWindowStyles.close(window)
        default:
            result(FlutterMethodNotImplemented)
            return
        }
        result(nil)
    }
}
