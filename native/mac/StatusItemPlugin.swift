//
//  StatusItemPlugin.swift — the macOS half of the `taskpin/bar` channel.
//
//  The Dart side is `lib/core/bar/bar_controller.dart`; the method names,
//  argument keys and event names are the same as the Windows half
//  (`native/win/taskpin_bar_plugin.cpp`) so `BarController` is
//  platform-agnostic and only the native painter differs. This is the plan's
//  explicit requirement (docs/FLUTTER_REWRITE_PLAN.md, "macOS 菜单栏条" and
//  Phase 8's acceptance line "bar.setSpans 与 Windows 用同一个 channel 契约").
//
//  Channel:  taskpin/bar
//  Methods (Dart -> native):
//    setSpans(barId, spans, state?, tabular?)
//    setGeometry(barId, width, x?)
//    setStyle(barId, bg?, bgHover?, label?, value?, icon?, fontSize?, state?,
//             scrollEnabled?, showSeparators?)
//    showPopover(barId, spec)      -- open/update the Flutter popover
//    hidePopover(barId)
//    showContextMenu(barId, items) -- items: [{title, tag}]
//    remove(barId)
//    removeAll()
//  Events (native -> Dart, `invokeMethod`):
//    onClick(barId, button)
//    onWheel(barId, delta, shift, width)
//    onContextMenu(barId)
//    onHoverChange(barId, hovered)
//    onContextMenuSelection(tag)
//    onPopoverClosed(barId)
//
//  NOT COMPILED — there is no macOS host on this machine. See
//  `native/mac/README.md` for the risk list and the Dart-side contract.
//

import AppKit
import FlutterMacOS

/// The channel name. Must match `kBarChannel` on the Dart side and the Windows
/// plugin's `kTaskpinBarChannel`.
let kBarChannel = "taskpin/bar"

/// The popover's channel. Deliberately the SAME name and method as
/// `kDialogSpecChannel` / `_DialogWindowBridge` in
/// `lib/app/windows/dialog_window.dart`, so the Dart side can reuse that
/// bridge verbatim rather than growing a second spec-decoding path.
///
/// Popover isolate -> native: `ready()` (reply: current spec or nil),
/// `resize({width, height})` (content's natural size, logical points) and
/// `close()` (the dialog's X / Escape; closes the open popover).
/// Native -> isolate: `setSpec(spec)`. See `PopoverHost`.
let kPopoverSpecChannel = "taskpin/dialog_spec"

/// One live bar: the status item, its custom view, and the item's own state.
private final class BarEntry {
    let barId: Int
    /// Recreated by `rebuildStatusItems` when the set of bars changes, so that
    /// the menu-bar order can be made deterministic. The view is reused.
    var statusItem: NSStatusItem
    let view: StatusItemView
    var width: Int
    /// Whether a hover notification is currently "open" on the Dart side, so
    /// only real transitions are emitted.
    var hoverReported = false

    init(barId: Int, statusItem: NSStatusItem, view: StatusItemView, width: Int) {
        self.barId = barId
        self.statusItem = statusItem
        self.view = view
        self.width = width
    }
}

/// Registers the `taskpin/bar` handler for one engine.
///
/// Mirrors `TaskpinBarPluginRegisterWithRegistrar` on the Windows side. The
/// registrar is the manager window's engine: the bars are driven from there and
/// the popover gets its own engine (see `PopoverHost`).
public final class StatusItemPlugin: NSObject, FlutterPlugin {

    /// Every bar this engine owns, keyed by the Dart-side `barId`.
    private var bars: [Int: BarEntry] = [:]
    private let channel: FlutterMethodChannel
    private lazy var popoverHost = PopoverHost()

    /// Whether the popover engine's pre-warm has been queued (once per plugin).
    private var prewarmScheduled = false

    /// When each bar last accepted a click (`systemUptime`).
    private var lastClickAt: [Int: TimeInterval] = [:]

    /// Bars whose `onClick` is still waiting on Dart, mapped to a token so a
    /// stale timeout cannot clear a newer click's pending state.
    private var pendingClicks: [Int: Int] = [:]
    private var nextClickToken = 0

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        // Tell Dart when a popover dismissed itself, so a script that refreshes
        // into its dialog can stop.
        popoverHost.onClosed = { [weak self] barId in
            self?.channel.invokeMethod("onPopoverClosed", arguments: ["barId": barId])
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: kBarChannel,
            binaryMessenger: registrar.messenger
        )
        let instance = StatusItemPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    deinit {
        for entry in bars.values {
            NSStatusBar.system.removeStatusItem(entry.statusItem)
        }
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        // NSStatusItem and every AppKit object below must be touched on the main
        // thread. The registrar already delivers method calls on the platform
        // (main) thread, but a call arriving from another engine's isolate or a
        // test harness would not be, so this is made explicit rather than
        // assumed — the Windows side has the same requirement (it marshals
        // through the platform thread).
        let work: () -> Void = { [weak self] in
            guard let self = self else {
                result(nil)
                return
            }
            switch call.method {
            case "setSpans":
                self.setSpans(args)
            case "setGeometry":
                self.setGeometry(args)
            case "setStyle":
                self.setStyle(args)
            case "showPopover":
                self.showPopover(args)
            case "hidePopover":
                self.hidePopover(args)
            case "showContextMenu":
                self.showContextMenuFromDart(args)
            case "remove":
                self.remove(args)
            case "removeAll":
                self.removeAll()
            default:
                result(FlutterMethodNotImplemented)
                return
            }
            result(nil)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - Methods

    /// `setSpans(barId, spans, state?, tabular?)`
    ///
    /// Creates the status item on first use and updates the span list after.
    /// The status item's length is recomputed every time, because
    /// `NSStatusItem` has no intrinsic sizing of its own — nothing
    /// auto-lays-out a custom subview in the menu bar. A positive `width` is
    /// the configured width; `<= 0` sizes to the content.
    private func setSpans(_ args: [String: Any]) {
        guard let barId = intValue(args["barId"]) else { return }
        let entry = bars[barId] ?? createBar(barId: barId)

        let rawSpans = (args["spans"] as? [Any]) ?? []
        // The ABI caps a display at 32 spans (`kMaxSpans` / `TpBarContent.maxSpans`);
        // the renderer drops the overflow rather than overflowing a buffer.
        // NOTE: `prefix` then `map` over a Collection, not over a Sequence — a
        // lazy `.prefix(32)` chain does not support `map` on a bare Sequence, so
        // the slice is materialised first.
        let spanMaps: [[String: Any]] = rawSpans
            .compactMap { $0 as? [String: Any] }
        entry.view.spans = spanMaps.prefix(32).map { BarSpan.from($0) }

        // The state may arrive per call (it changes far more often than the
        // style) or on setStyle.
        if let state = args["state"] {
            entry.view.style.state = BarState.from(state)
        }

        // The configured width (`bar_width`, else the global `width`) rides on
        // every setSpans, not only on setGeometry, because a newly created bar
        // has never had a geometry call. `<= 0` means "size to content" and
        // leaves the current mode alone — the same sentinel `setGeometry` uses.
        let requestedWidth = intValue(args["width"]) ?? 0
        if requestedWidth > 0 {
            entry.view.explicitWidth = BarGeometryMath.clampWidth(requestedWidth)
        }
        applyWidth(entry, width: entry.view.settledWidth())
    }

    /// `setGeometry(barId, width, x?)`
    ///
    /// `x` is accepted for contract parity with the Windows half but ignored:
    /// the menu bar places its own items, so there is no X to set. A caller
    /// that sends one is not wrong, it is just asking for something the platform
    /// does not offer.
    ///
    /// `width` semantics match `bar_width` in config.json: `> 0` is an explicit
    /// width (clamped), `<= 0` means "size to content", which is the same
    /// sentinel the Windows side uses for an unset `bar_width`.
    private func setGeometry(_ args: [String: Any]) {
        guard let barId = intValue(args["barId"]),
              let entry = bars[barId] else { return }

        let requested = intValue(args["width"]) ?? 0
        entry.view.explicitWidth = requested > 0
            ? BarGeometryMath.clampWidth(requested)
            : 0
        applyWidth(entry, width: entry.view.heldWidth)
    }

    /// `setStyle(barId, ...)`
    ///
    /// Every field is optional; an absent key leaves the current value alone,
    /// so a caller can change just the state.
    private func setStyle(_ args: [String: Any]) {
        guard let barId = intValue(args["barId"]),
              let entry = bars[barId] else { return }

        var style = entry.view.style
        if let v = args["bg"] { style.bg = parseHexColor(v) }
        if let v = args["bgHover"] { style.bgHover = parseHexColor(v) }
        if let v = args["label"] { style.label = parseHexColor(v) }
        if let v = args["value"] { style.value = parseHexColor(v) }
        if let v = args["icon"] { style.icon = parseHexColor(v) }
        if let v = intValue(args["fontSize"]) { style.fontSize = v }
        if let v = args["state"] { style.state = BarState.from(v) }
        if let v = args["scrollEnabled"] as? NSNumber { style.scrollEnabled = v.boolValue }
        if let v = args["showSeparators"] as? NSNumber { style.showSeparators = v.boolValue }
        entry.view.style = style
    }

    /// `showPopover(barId, spec)`
    ///
    /// Open (or update) the Flutter popover for a bar and hand it the dialog
    /// spec. The Dart side calls this in response to `onClick` once it has a
    /// spec to show; the native click handler opens the popover immediately so
    /// the click feels instant, and this call then fills it in.
    ///
    /// `spec` uses the same JSON shape as `DialogSpec.toJson()`, which is also
    /// what the popover engine's `taskpin/dialog_spec` bridge decodes.
    private func showPopover(_ args: [String: Any]) {
        guard let barId = intValue(args["barId"]),
              let entry = bars[barId] else { return }
        // Dart has answered this bar's click.
        pendingClicks[barId] = nil

        if let spec = args["spec"] as? [String: Any] {
            popoverHost.send(spec: spec)
        }
        // `show` is idempotent for an already-open popover only in the sense
        // that AppKit ignores a second presentation; guard so an update to an
        // open popover does not reposition it.
        if !popoverHost.isOpen(for: barId) {
            popoverHost.show(for: barId, relativeTo: entry.view)
        }
    }

    /// `hidePopover(barId)`
    private func hidePopover(_ args: [String: Any]) {
        guard let barId = intValue(args["barId"]) else { return }
        pendingClicks[barId] = nil
        popoverHost.close(for: barId)
    }

    /// `showContextMenu(barId, items)`
    ///
    /// The menu's items and their localised titles are the Dart side's business
    /// (it owns the l10n bundle and the config), but only the main thread can
    /// present an `NSMenu`, so the list crosses the channel and the presentation
    /// happens here.
    private func showContextMenuFromDart(_ args: [String: Any]) {
        let rawItems = (args["items"] as? [Any]) ?? []
        let items: [(title: String, tag: Int)] = rawItems.compactMap { entry in
            guard let map = entry as? [String: Any],
                  let title = map["title"] as? String else { return nil }
            let tag = (map["tag"] as? NSNumber)?.intValue ?? 0
            return (title: title, tag: tag)
        }
        guard !items.isEmpty else { return }
        showContextMenu(items: items)
    }

    /// `remove(barId)` — destroy one status item.
    private func remove(_ args: [String: Any]) {
        guard let barId = intValue(args["barId"]),
              let entry = bars.removeValue(forKey: barId) else { return }
        lastClickAt[barId] = nil
        pendingClicks[barId] = nil
        // The popover belongs to the bar, so it goes with it.
        popoverHost.close(for: barId)
        NSStatusBar.system.removeStatusItem(entry.statusItem)
    }

    /// `removeAll()` — destroy every status item (shutdown, or an engine
    /// restart).
    private func removeAll() {
        for entry in bars.values {
            NSStatusBar.system.removeStatusItem(entry.statusItem)
        }
        bars.removeAll()
        lastClickAt.removeAll()
        pendingClicks.removeAll()
        popoverHost.closeAll()
    }

    // MARK: - Status item lifecycle

    private func createBar(barId: Int) -> BarEntry {
        let view = StatusItemView(frame: NSRect(x: 0, y: 0, width: 100, height: BarMetrics.shared.height))
        let entry = BarEntry(
            barId: barId,
            statusItem: makeStatusItem(for: view),
            view: view,
            width: 100
        )

        // All four native -> Dart events.
        view.onHoverChange = { [weak self] hovered in
            guard let self = self, let entry = self.bars[barId] else { return }
            guard entry.hoverReported != hovered else { return }
            entry.hoverReported = hovered
            self.channel.invokeMethod("onHoverChange", arguments: [
                "barId": barId,
                "hovered": hovered,
            ])
        }

        view.onClick = { [weak self] in
            // The entry is looked up rather than captured: `BarEntry` owns this
            // view, so a closure holding the entry would be a retain cycle
            // (entry -> view -> closure -> entry) and leak a status item per bar
            // removed.
            guard let self = self, self.bars[barId] != nil else { return }
            // Debounce: rapid clicks on one bar otherwise queue several
            // open/close round-trips that land out of order and fight each
            // other. Only ACCEPTED clicks restart the window, so a fast series
            // still lets one click through every 350 ms instead of being
            // swallowed whole.
            let now = ProcessInfo.processInfo.systemUptime
            if let last = self.lastClickAt[barId], now - last < 0.35 { return }
            // A click on a bar whose popover is up only closes it. Anything else
            // is Dart's call: it opens the popover with `showPopover` when the
            // script's click action is a dialog, opens a URL, or does nothing.
            // Opening natively on every click showed an empty popover for items
            // that have no dialog at all. Closing is checked before the pending
            // guard so it is never blocked.
            if self.popoverHost.clickShouldClose(for: barId) {
                self.lastClickAt[barId] = now
                self.popoverHost.close(for: barId)
                return
            }
            // One Dart round-trip per bar at a time.
            guard self.pendingClicks[barId] == nil else { return }
            self.lastClickAt[barId] = now
            self.nextClickToken += 1
            let token = self.nextClickToken
            self.pendingClicks[barId] = token
            self.channel.invokeMethod("onClick", arguments: [
                "barId": barId,
                "button": "left",
            ])
            // Dart answers a dialog click with `showPopover`, which clears the
            // flag; a click it acts on otherwise (a URL) or ignores (an item
            // with no action) sends nothing back, so the flag also expires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, self.pendingClicks[barId] == token else { return }
                self.pendingClicks[barId] = nil
            }
        }

        view.onContextMenu = { [weak self] point in
            guard let self = self else { return }
            // Only the point is remembered natively; the menu itself comes back
            // over the channel (`showContextMenu`) so the item titles stay in
            // the Dart l10n bundle. A caller that never answers simply gets no
            // menu, which is the same degradation as a missing plugin.
            self.pendingMenuPoint = point
            self.channel.invokeMethod("onContextMenu", arguments: ["barId": barId])
        }

        view.onWheel = { [weak self] delta, shift in
            guard let self = self, let entry = self.bars[barId] else { return }
            let next = BarGeometryMath.applyWheel(width: entry.width, delta: delta, shift: shift)
            // Latch the new width so a later content change does not snap the
            // strip back to its natural size — the same thing `BarWindow` gets
            // from keeping `m_width` across `SetContent`.
            entry.view.explicitWidth = next.width
            self.applyWidth(entry, width: CGFloat(next.width))
            self.channel.invokeMethod("onWheel", arguments: [
                "barId": barId,
                "delta": delta,
                "shift": shift,
                // The width AFTER the clamp, so the Dart side persists exactly
                // what is on screen rather than re-deriving it (and risking a
                // second, divergent clamp).
                "width": entry.width,
            ])
        }

        bars[barId] = entry
        // The system put this item to the LEFT of the existing ones; queue a
        // pass that puts the whole set back into config order.
        scheduleOrderingRebuild()
        schedulePopoverPrewarm()
        return entry
    }

    /// Boot the popover engine shortly after the first bar exists.
    ///
    /// A cold Flutter engine on the first click is what made opening slow. The
    /// delay keeps the boot out of the startup burst (manager engine, bar
    /// creation, the ordering rebuild) so it does not compete with it; nothing
    /// is shown, the popover is only built.
    private func schedulePopoverPrewarm() {
        guard !prewarmScheduled else { return }
        prewarmScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, !self.bars.isEmpty else { return }
            self.popoverHost.prewarm()
        }
    }

    /// Create the system status item and attach the custom view to its button.
    ///
    /// Extracted from `createBar` because the ordering pass has to recreate
    /// status items while keeping the view: the system object's position is
    /// fixed at creation, the view carries all the state.
    private func makeStatusItem(for view: StatusItemView) -> NSStatusItem {
        // Variable length: the width is driven from `measuredWidth` after every
        // content change, and a fixed length would clip the content instead.
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // The custom view is a subview of the button rather than `statusItem.view`:
        // `NSStatusItem.view` is deprecated, and the button is what modern macOS
        // gives the status item. The view is the mouse target for clicks, wheel
        // and right-clicks; it is transparent, so the button's native highlight
        // still shows through (the view drives it from mouseDown/mouseUp).
        if let button = statusItem.button {
            button.addSubview(view)
            // Track the button's bounds: `applyWidth` sets `statusItem.length`,
            // which AppKit applies to the button, and the view has to follow.
            // Without this the view would keep its creation-time frame and the
            // strip would draw at the wrong size.
            view.autoresizingMask = [.width, .height]
            // No target/action: clicks are handled by the view, which forwards
            // them to the plugin. The button is only used for its chrome.
            button.target = nil
            button.action = nil
        }
        return statusItem
    }

    // MARK: - Menu-bar ordering

    /// Coalesces the ordering pass onto the next run-loop turn.
    ///
    /// The Dart controller creates its bars one `setSpans` at a time, so a
    /// rebuild per call would tear the strip down three times on startup. The
    /// flag makes a burst of creations one rebuild.
    private func scheduleOrderingRebuild() {
        guard !reorderScheduled else { return }
        reorderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.reorderScheduled = false
            self.rebuildStatusItems()
        }
    }

    /// Recreate every status item so the menu bar reads left-to-right in
    /// ascending bar id (= config index) order.
    ///
    /// WHY THIS IS NEEDED: `NSStatusBar` inserts every newly created item to
    /// the LEFT of the existing ones, so creating bars in config order displays
    /// them reversed. There is no public reorder API, so the system objects are
    /// removed and re-added from the highest id down; the last one added (the
    /// lowest id) ends up leftmost.
    ///
    /// TRADE-OFF: the custom views are reused, so content, callbacks and the
    /// hover/pressed state survive — but a user's ⌘-drag repositioning does
    /// not. `autosaveName` is deliberately NOT set: a saved per-item position
    /// would fight this deterministic config order on the next pin/unpin, and
    /// there is no API to reorder the other items around it. Config order wins.
    private func rebuildStatusItems() {
        guard !bars.isEmpty else { return }
        // A popover is anchored to a view that is about to move to a different
        // button, so close it rather than leave the anchor stale.
        popoverHost.closeAll()
        for entry in bars.values {
            entry.view.removeFromSuperview()
            NSStatusBar.system.removeStatusItem(entry.statusItem)
        }
        // Descending creation order => ascending left-to-right display order.
        for entry in bars.values.sorted(by: { $0.barId > $1.barId }) {
            entry.statusItem = makeStatusItem(for: entry.view)
            applyWidth(entry, width: CGFloat(entry.width))
        }
    }

    /// Whether an ordering pass is already queued.
    private var reorderScheduled = false

    /// Resize the status item and the view together.
    ///
    /// `NSStatusItem.length` positions every item to the right of this one, so
    /// the two must not drift: the view is always pinned to the item's bounds.
    ///
    /// A width of 0 means "no content" and collapses the item to 0 pt. Clamping it
    /// to the 28 pt minimum would leave an empty box in the menu bar. The minimum
    /// only applies to a strip that has something to draw.
    private func applyWidth(_ entry: BarEntry, width: CGFloat) {
        let rounded = Int(width.rounded(.up))
        let clamped: CGFloat = rounded <= 0
            ? 0
            : CGFloat(BarGeometryMath.clampWidth(rounded))
        if entry.statusItem.length != clamped {
            entry.statusItem.length = clamped
        }
        entry.width = Int(clamped)
        entry.view.frame = NSRect(x: 0, y: 0, width: clamped, height: BarMetrics.shared.height)
        entry.view.needsDisplay = true
    }

    // MARK: - Helpers

    /// The screen point remembered from the last right-click, used when the
    /// Dart side asks for a menu to be shown.
    private var pendingMenuPoint: NSPoint?

    /// Show a native menu at the last right-click point.
    ///
    /// Called from the Dart side (`onContextMenu` handler) so the menu's items
    /// and their localised titles stay in Dart while the presentation stays on
    /// the main thread. Public so `PopoverHost` and a test can reach it.
    func showContextMenu(items: [(title: String, tag: Int)]) {
        let point = pendingMenuPoint ?? NSEvent.mouseLocation
        let menu = NSMenu()
        for item in items {
            let entry = NSMenuItem(
                title: item.title,
                action: #selector(menuItemSelected(_:)),
                keyEquivalent: ""
            )
            entry.tag = item.tag
            entry.target = self
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        channel.invokeMethod("onContextMenuSelection", arguments: ["tag": sender.tag])
    }

    private func intValue(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }
}

/// Register the `taskpin/bar` handler for an engine that is not going through
/// the generated registrant.
///
/// `MainFlutterWindow.awakeFromNib` calls this directly so the manager window's
/// engine has the channel without depending on `GeneratedPluginRegistrant`
/// (which is a generated file and must not be hand-edited).
public enum TaskpinBarPluginRegistrar {
    public static func register(with registrar: FlutterPluginRegistrar) {
        StatusItemPlugin.register(with: registrar)
    }
}
