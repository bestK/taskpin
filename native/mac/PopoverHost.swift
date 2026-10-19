//
//  PopoverHost.swift — the Flutter-hosted popover behind a menu-bar click.
//
//  Phase 8's deliverable: "原生 StatusItemView 在菜单栏渲染完整 span 列表；点击开
//  Flutter 承载的 popover" (docs/FLUTTER_REWRITE_PLAN.md). The plan's mapping for
//  the dialog window effects is
//
//    borderless    styleMask without .titled (+ .fullSizeContentView)
//    always-on-top level = .floating
//    clickthrough  ignoresMouseEvents = true
//    opacity       alphaValue = alpha / 255
//    transparent   isOpaque = false, backgroundColor = .clear
//
//  and for the popover specifically it says "NSPopover + FlutterViewController".
//  That is what this is. The `NSPopover` supplies the "click outside closes"
//  behaviour for free (`.transient`), which the plan lists as an acceptance
//  item, and it positions itself against the status item the way every other
//  menu-bar app's popover does.
//
//  WHY THE DIALOG SPEC GOES OVER A CHANNEL RATHER THAN BEING A PROPERTY:
//  a `FlutterViewController` is a separate engine with its own isolate. There is
//  no in-process object graph to hand a Swift value to. The spec therefore
//  crosses on the SAME channel name and method that
//  `lib/app/windows/dialog_window.dart` already uses for the Windows dialog
//  window — `taskpin/dialog_spec` / `setSpec` — so the Dart side reuses
//  `_DialogWindowBridge` verbatim instead of growing a second decoder. That is
//  the same "one contract, two native painters" rule the bar follows.
//
//  NOT COMPILED — no macOS host on this machine. See `native/mac/README.md`.
//

import AppKit
import FlutterMacOS

/// The popover's default content size.
///
/// VISUAL_SPEC §11.1: "默认宽 360；最小 240，最大 720". The height is the
/// plan's dialog default (`kDialogDefaultHeight` on the Dart side); the popover
/// then sizes to the spec once it arrives.
private let kDefaultPopoverWidth: CGFloat = 360
private let kDefaultPopoverHeight: CGFloat = 300
private let kMinPopoverWidth: CGFloat = 240
private let kMaxPopoverWidth: CGFloat = 720

/// Hosts one lazily-created Flutter engine behind one `NSPopover` per bar.
///
/// ONE ENGINE, MANY POPOVERS. A popover is transient and shows one item at a
/// time in practice, so a per-bar engine would be several hundred MB of RSS for
/// no benefit — the same reasoning the plan applies to the Windows side when it
/// refuses one Flutter engine per taskbar strip.
///
/// NOT the same thing as `desktop_multi_window`'s child windows: those are
/// top-level `NSWindow`s with their own window id and a cross-engine method
/// channel. A popover is anchored to a view and must be presented by the main
/// thread with a real `NSView` anchor, which the plugin cannot supply — hence a
/// native host rather than `WindowController.create`.
final class PopoverHost: NSObject, NSPopoverDelegate {

    /// barId -> the popover currently open for it.
    private var popovers: [Int: NSPopover] = [:]

    /// The shared Flutter engine, created on the first click.
    ///
    /// `FlutterDartProject` + `dartEntrypointArguments` mirrors how
    /// `desktop_multi_window` starts its child engines: the same Dart `main` runs
    /// and branches on the argument, so no `@pragma('vm:entry-point')` second
    /// entry point is needed.
    private var flutterViewController: FlutterViewController?

    /// The spec most recently sent, replayed to a freshly created engine.
    private var lastSpec: [String: Any]?

    /// The spec channel on the popover engine, created with the engine.
    ///
    /// Cached rather than rebuilt per send: `FlutterMethodChannel` is cheap but
    /// not free, and a `refresh`ing dialog re-sends on every tick.
    private var specChannel: FlutterMethodChannel?

    /// Which bar the open popover belongs to.
    private var openBarId: Int?

    /// Called when a popover closes itself (an outside click, Escape, or the
    /// app deactivating). The plugin uses it to notify Dart, so a script that
    /// wants to stop a refresh loop when its popover goes away can.
    var onClosed: ((Int) -> Void)?

    // MARK: - Presentation

    /// Open the popover for `barId`, or close it if it is already open.
    func toggle(for barId: Int, relativeTo anchor: NSView) {
        if let existing = popovers[barId], existing.isShown {
            existing.performClose(nil)
            return
        }
        show(for: barId, relativeTo: anchor)
    }

    /// Show (or re-show) the popover for `barId`.
    func show(for barId: Int, relativeTo anchor: NSView) {
        // One popover at a time: two anchored popovers would fight over the
        // status bar's anchor rect.
        if let open = openBarId, open != barId {
            popovers[open]?.performClose(nil)
        }

        let popover = popovers[barId] ?? makePopover()
        popovers[barId] = popover

        // `.transient`: closes when the user clicks anywhere else, and when the
        // app deactivates. That is the plan's "点击外部关闭".
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true

        let size = contentSize(from: lastSpec)
        popover.contentSize = size
        popover.contentViewController = makeContentViewController(size: size)

        openBarId = barId
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .minY // below the menu bar
        )
        // A menu-bar popover should take focus so keyboard input works.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether a popover for `barId` is on screen.
    func isOpen(for barId: Int) -> Bool {
        popovers[barId]?.isShown ?? false
    }

    /// Close the popover for one bar, if open.
    func close(for barId: Int) {
        popovers[barId]?.performClose(nil)
        popovers.removeValue(forKey: barId)
        if openBarId == barId { openBarId = nil }
    }

    /// Close everything (bar removed, engine shutting down).
    func closeAll() {
        for popover in popovers.values where popover.isShown {
            popover.performClose(nil)
        }
        popovers.removeAll()
        openBarId = nil
    }

    // MARK: - Content

    /// Send a dialog spec to the popover engine.
    ///
    /// Called by `StatusItemPlugin` when the Dart side has a spec for the
    /// clicked bar. If the engine does not exist yet the spec is remembered and
    /// replayed on creation, so the common order — click, then the Dart side
    /// answers asynchronously with the spec — works without a second click.
    func send(spec: [String: Any]) {
        lastSpec = spec
        guard let channel = specChannel else { return }
        // The popover may already be up showing an older spec: an auto-refreshing
        // dialog (`refresh` in the dialog spec) works this way — the window
        // stays, the items are swapped. A new size moves the popover too.
        channel.invokeMethod("setSpec", arguments: spec)
        if let barId = openBarId, let popover = popovers[barId] {
            popover.contentSize = contentSize(from: spec)
        }
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = CGSize(width: kDefaultPopoverWidth, height: kDefaultPopoverHeight)
        popover.delegate = self
        return popover
    }

    /// Build (once) and return the Flutter view controller.
    ///
    /// The engine is created lazily so an app with no clickable items never pays
    /// for it, and reused so a second click does not spin up a second engine.
    private func makeContentViewController(size: CGSize) -> NSViewController {
        if let existing = flutterViewController {
            return existing
        }

        let project = FlutterDartProject()
        // The same Dart `main` as the manager window; `dialog_window.dart`
        // branches on this argument to run `dialogWindowMain` instead of the
        // shell.
        project.dartEntrypointArguments = ["popover"]

        // `FlutterViewController(project:)` — the single-argument initializer,
        // which is the form `desktop_multi_window` itself uses
        // (`FlutterMultiWindowPlugin.CreateWindow`). Not the
        // `(project:nibName:bundle:)` variant: that one is declared nullable in
        // some SDK versions and would need an unwrap whose failure mode is
        // unclear.
        let controller = FlutterViewController(project: project)
        controller.view.frame = NSRect(origin: .zero, size: size)
        flutterViewController = controller

        // Built once and kept, so a refreshing dialog's repeated `setSpec` does
        // not allocate a channel each tick.
        let channel = FlutterMethodChannel(
            name: kPopoverSpecChannel,
            binaryMessenger: controller.engine.binaryMessenger
        )
        specChannel = channel

        // The child engine registers its `taskpin/dialog_spec` handler at
        // startup (`_DialogWindowBridge.listen` in
        // `lib/app/windows/dialog_window.dart`), so nothing has to be pushed
        // there — but a spec that arrived BEFORE the engine existed is replayed
        // now that there is somewhere to send it.
        if let spec = lastSpec {
            channel.invokeMethod("setSpec", arguments: spec)
        }

        return controller
    }

    /// The size a spec asks for, clamped to the popover's usable range.
    ///
    /// A popover taller than the screen is useless, so the height is also capped
    /// at 80 % of the visible frame — the same rule VISUAL_SPEC §11.1 gives the
    /// dialog window ("最大高 屏幕工作区 80%").
    private func contentSize(from spec: [String: Any]?) -> CGSize {
        let width = CGFloat((spec?["width"] as? NSNumber)?.doubleValue ?? Double(kDefaultPopoverWidth))
        let height = CGFloat((spec?["height"] as? NSNumber)?.doubleValue ?? Double(kDefaultPopoverHeight))
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return CGSize(
            width: min(kMaxPopoverWidth, max(kMinPopoverWidth, width)),
            height: min(visible * 0.8, max(80, height))
        )
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        guard let barId = openBarId else { return }
        openBarId = nil
        onClosed?(barId)
    }
}
