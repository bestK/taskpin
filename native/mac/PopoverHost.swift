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

/// Hosts one lazily-created Flutter engine behind one shared `NSPopover`.
///
/// ONE ENGINE, ONE POPOVER. Only one popover is ever on screen, so a per-bar
/// engine would be several hundred MB of RSS for no benefit — the same
/// reasoning the plan applies to the Windows side when it refuses one Flutter
/// engine per taskbar strip. The popover itself is shared too and re-anchored
/// per click: handing the one `FlutterViewController` to a fresh `NSPopover`
/// on every open moved its view between popover windows, and the reopened
/// popover came up as an empty grey panel.
///
/// NOT the same thing as `desktop_multi_window`'s child windows: those are
/// top-level `NSWindow`s with their own window id and a cross-engine method
/// channel. A popover is anchored to a view and must be presented by the main
/// thread with a real `NSView` anchor, which the plugin cannot supply — hence a
/// native host rather than `WindowController.create`.
final class PopoverHost: NSObject, NSPopoverDelegate {

    /// The popover, created with the engine on the first click.
    private var popover: NSPopover?

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

    /// Set once the popover isolate has registered its handler and called
    /// `ready`. Before that, specs are only remembered.
    private var engineReady = false

    /// Which bar the open popover belongs to.
    private var openBarId: Int?

    /// Called when a popover closes itself (an outside click, Escape, or the
    /// app deactivating). The plugin uses it to notify Dart, so a script that
    /// wants to stop a refresh loop when its popover goes away can.
    var onClosed: ((Int) -> Void)?

    /// The bar whose popover closed most recently, and when.
    ///
    /// A `.transient` popover closes on the mouse-DOWN of a click on its own
    /// status item, so by the time that click's mouse-up reaches
    /// `StatusItemPlugin` the popover is already gone and a plain "is it open?"
    /// check would reopen it. Remembering the close lets the second click on a
    /// bar mean "close" instead of "close and reopen".
    private var lastClosed: (barId: Int, at: TimeInterval)?

    /// The content's natural size as last reported by the popover isolate
    /// (`resize`), and the bar it was measured for.
    ///
    /// Remembered so that neither a reopen nor a refreshing dialog's `setSpec`
    /// snaps the popover back to the spec's nominal size before the isolate
    /// re-measures — that snap-then-grow would show as a visible bounce on
    /// every refresh tick.
    private var measured: (barId: Int, size: CGSize)?

    // MARK: - Lifecycle

    /// Create the engine and the shared popover ahead of the first click,
    /// without showing anything.
    ///
    /// A cold Flutter engine takes a noticeable moment to boot, and doing it on
    /// the first click is what made opening feel slow. The `ready` handshake
    /// does not depend on a spec existing: an isolate that boots before any
    /// click gets `nil` in the reply and waits for `setSpec`.
    func prewarm() {
        guard popover == nil else { return }
        // `makeContentViewController` touches `controller.view`, which is what
        // actually launches the engine; a controller whose view was never
        // loaded would leave the isolate unstarted until the first show.
        popover = makePopover(size: contentSize(from: lastSpec))
    }

    // MARK: - Presentation

    /// Whether a click on `barId` right now should only close its popover:
    /// it is open, or it was dismissed by this same click's mouse-down.
    func clickShouldClose(for barId: Int) -> Bool {
        if isOpen(for: barId) { return true }
        guard let closed = lastClosed, closed.barId == barId else { return false }
        return ProcessInfo.processInfo.systemUptime - closed.at < 0.3
    }

    /// Show the popover under `barId`'s status item.
    func show(for barId: Int, relativeTo anchor: NSView) {
        // Reopening the same bar starts at its measured size; another bar's
        // measurement says nothing about this content, so the spec's size is
        // used until the isolate reports a fresh one.
        if let m = measured, m.barId != barId { measured = nil }
        let size = measured?.size ?? contentSize(from: lastSpec)
        let popover = self.popover ?? makePopover(size: size)
        self.popover = popover

        // One popover at a time: a click on another bar re-anchors it. The
        // close is immediate (no animation) so it cannot finish after the
        // reopen below, and the previous bar is told here rather than through
        // `popoverDidClose`, which would also mark the engine hidden.
        if popover.isShown {
            let previous = openBarId
            openBarId = nil
            let animates = popover.animates
            popover.animates = false
            popover.close()
            popover.animates = animates
            if let previous = previous { onClosed?(previous) }
        }

        popover.contentSize = size
        openBarId = barId
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .minY // below the menu bar
        )
        // A menu-bar popover should take focus so keyboard input works.
        NSApp.activate(ignoringOtherApps: true)
        setEngineVisible(true)
    }

    /// Whether `barId`'s popover is on screen.
    func isOpen(for barId: Int) -> Bool {
        openBarId == barId && (popover?.isShown ?? false)
    }

    /// Close the popover if it belongs to `barId`.
    func close(for barId: Int) {
        guard openBarId == barId else { return }
        popover?.performClose(nil)
    }

    /// Close the popover whichever bar it belongs to (bar removed, shutdown).
    func closeAll() {
        popover?.performClose(nil)
    }

    /// Tell the popover engine whether its view is on screen.
    ///
    /// The engine derives its lifecycle from the APP (active, occluded), not
    /// from this popover. After a close the app is often hidden or inactive,
    /// the engine is told `hidden`, Flutter stops producing frames, and the
    /// next open shows nothing — the setSpec arrives, the widgets rebuild, but
    /// no frame is drawn. The popover's own visibility is what matters here,
    /// so it is reported on the engine's lifecycle channel directly, using the
    /// same message `FlutterEngine.setApplicationState` sends.
    private func setEngineVisible(_ visible: Bool) {
        guard let engine = flutterViewController?.engine else { return }
        let state = visible ? "AppLifecycleState.resumed" : "AppLifecycleState.hidden"
        engine.binaryMessenger.send(onChannel: "flutter/lifecycle", message: state.data(using: .utf8))
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
        // Until the popover isolate has said `ready`, a push can land on an
        // engine that is not running yet ("Invalid engine handle") and is lost.
        // The spec is kept in `lastSpec` and handed over in the `ready` reply.
        guard engineReady, let channel = specChannel else { return }
        // The popover may already be up showing an older spec: an auto-refreshing
        // dialog (`refresh` in the dialog spec) works this way — the window
        // stays, the items are swapped. A new size moves the popover too —
        // unless the isolate has already measured this bar's content, in which
        // case it re-reports via `resize` and the spec's nominal size would
        // only make the popover bounce.
        channel.invokeMethod("setSpec", arguments: spec)
        if let barId = openBarId, measured?.barId != barId,
           let popover = popover, popover.isShown {
            popover.contentSize = contentSize(from: spec)
        }
    }

    private func makePopover(size: CGSize) -> NSPopover {
        let popover = NSPopover()
        // `.transient`: closes when the user clicks anywhere else, and when the
        // app deactivates. That is the plan's "点击外部关闭".
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = size
        popover.delegate = self
        // Assigned once and never again; see the type comment.
        popover.contentViewController = makeContentViewController(size: size)
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
        // The same Dart `main` as the manager window; `lib/main.dart`
        // branches on this argument to run `popoverMain` instead of the
        // shell.
        project.dartEntrypointArguments = ["popover"]

        // `FlutterViewController(project:)` — the single-argument initializer,
        // which is the form `desktop_multi_window` itself uses
        // (`FlutterMultiWindowPlugin.CreateWindow`). Not the
        // `(project:nibName:bundle:)` variant: that one is declared nullable in
        // some SDK versions and would need an unwrap whose failure mode is
        // unclear.
        let controller = FlutterViewController(project: project)
        // Clear, not Flutter's default. A `FlutterViewController` paints its view
        // black until the first frame, and that black showed through the
        // popover's rounded frame as a black border and corners. The popover's
        // own material is what should show, so the Flutter view must be see-
        // through. Set on the controller, not only on the view's layer, because
        // the controller's value is the one Flutter applies to its surface.
        controller.backgroundColor = .clear
        controller.view.frame = NSRect(origin: .zero, size: size)
        flutterViewController = controller

        // Built once and kept, so a refreshing dialog's repeated `setSpec` does
        // not allocate a channel each tick.
        let channel = FlutterMethodChannel(
            name: kPopoverSpecChannel,
            binaryMessenger: controller.engine.binaryMessenger
        )
        specChannel = channel

        // A spec cannot be pushed now: the engine is not running until the
        // view loads, and the isolate has no handler until `popoverMain` runs.
        // Instead the isolate PULLS: once its handler is registered it calls
        // `ready` (`_PopoverSpecSource.listen` in
        // `lib/app/windows/popover_window.dart`) and gets the current spec as
        // the reply — `nil` when the engine was pre-warmed before any click.
        // Later specs are pushed with `setSpec`.
        //
        // `resize({width, height})` is the isolate reporting its content's
        // natural size in logical points. The spec's width/height is only a
        // guess made before layout; without this the popover clips any dialog
        // whose items do not fit the nominal 360 x 300.
        //
        // `close()` is the dialog's X (or Escape). It goes through
        // `performClose` like a click outside, so `popoverDidClose` still does
        // the bookkeeping: engine hidden, Dart told `onPopoverClosed`.
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "ready":
                self?.engineReady = true
                result(self?.lastSpec)
            case "resize":
                self?.applyMeasuredSize(call.arguments as? [String: Any] ?? [:])
                result(nil)
            case "close":
                self?.popover?.performClose(nil)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return controller
    }

    /// Apply a `resize` from the popover isolate.
    private func applyMeasuredSize(_ args: [String: Any]) {
        guard let width = (args["width"] as? NSNumber)?.doubleValue,
              let height = (args["height"] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite else { return }
        // The cap is the screen the popover is actually on: on a multi-monitor
        // setup `NSScreen.main` is the key window's screen, which need not be
        // the one under this status item.
        let screen = popover?.contentViewController?.view.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame.height ?? 800
        let size = CGSize(
            width: min(kMaxPopoverWidth, max(kMinPopoverWidth, CGFloat(width))),
            height: min(visible * 0.8, max(80, CGFloat(height)))
        )
        // Only an open popover's measurement is worth remembering; one taken
        // while hidden (a pre-warmed engine laying out an empty spec) belongs
        // to no bar.
        if let barId = openBarId {
            measured = (barId, size)
        }
        guard let popover = popover, popover.contentSize != size else { return }
        popover.contentSize = size
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
        // A re-anchor (`show`) has already done this bookkeeping; a close that
        // lands while the popover is up again belongs to it and is ignored.
        guard let barId = openBarId, !(popover?.isShown ?? false) else { return }
        openBarId = nil
        lastClosed = (barId, ProcessInfo.processInfo.systemUptime)
        setEngineVisible(false)
        onClosed?(barId)
    }
}
