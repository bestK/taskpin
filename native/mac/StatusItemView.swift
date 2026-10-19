//
//  StatusItemView.swift — the macOS menu-bar bar.
//
//  The macOS half of the plan's "macOS 菜单栏条：原生 NSStatusItem + 自定义 NSView"
//  (docs/FLUTTER_REWRITE_PLAN.md). Flutter cannot render into an NSStatusItem —
//  the status-bar button is a system-owned layer-backed NSView, and Flutter
//  needs its own NSWindow/NSView + Metal layer + FlutterViewController. So this
//  mirrors the Windows side (`native/win/bar_render_d2d.cpp`): the same span
//  model, the same frozen tokens, the same layout pass — only the painter
//  differs (Core Text instead of Direct2D + DirectWrite).
//
//  What this fixes (the plan calls it out explicitly):
//
//    The old implementation (`src/macos/Services/StatusBarManager.swift`,
//    `updateStatusItem`) set ONE `attributedTitle` and ONE `button.image`. A
//    script returning `font("A", red) .. font("B", green)` therefore lost every
//    colour but the first. Drawing the full span list is a strict improvement.
//
//  macOS-specific rules from the plan / VISUAL_SPEC §9:
//    - the menu bar is 24 pt tall: ONE line only. A `newline` span and
//      everything after it is dropped, and overlong content is
//      ellipsis-truncated — never clipped mid-glyph.
//    - icons are 16 pt; a monochrome source is template-tinted with `bar/icon`.
//    - the bar uses the SYSTEM font (SF Pro), never Inter.
//    - tabular figures always: `CPU: 9%` -> `CPU: 100%` must not shift
//      everything to its right. This is the bar's most important typographic
//      rule (VISUAL_SPEC §4.3).
//
//  NOT COMPILED. There is no macOS host on this machine (no Xcode, no Swift
//  compiler), so this file has never been through a compiler. It is written to
//  the AppKit/Core Text API and cross-checked against the frozen token values.
//  The uncompiled/risk list and the full `taskpin/bar` contract live in
//  `native/mac/README.md`.
//

import AppKit
import CoreText

// MARK: - Frozen tokens

/// The frozen `bar/*` token list.
///
/// PARITY: this is the third copy. The other two are
///   - `native/win/bar_tokens.h`                       (C++, Direct2D)
///   - `packages/taskpin_design/lib/src/tokens/bar_tokens.dart` (Dart)
/// and `packages/taskpin_design/test/tokens/bar_tokens_parity_test.dart`
/// currently enforces Dart <-> C++ only. The trailing `// bar/<name>` comments
/// below deliberately use the same shape as the C++ header so that a Swift leg
/// can be added to that test with the same regex.
///
/// Do NOT add a token here without changing all three copies and the plan.
enum BarTokens {
    /// `lib/config.c` / `TPSpan` sentinel: "use the default colour".
    static let useDefault: UInt32 = 0xFFFF_FFFF

    static let bg: UInt32 = 0xFF0E1015           // bar/bg
    static let bgHover: UInt32 = 0xFF1F242E      // bar/bgHover
    static let hairline: UInt32 = 0x1FFFFFFF     // bar/hairline
    static let separator: UInt32 = 0x33FFFFFF    // bar/separator
    static let stateRunning: UInt32 = 0x00000000 // bar/state.running
    static let stateError: UInt32 = 0xFFF85149   // bar/state.error
    static let stateStale: UInt32 = 0xFFD29922   // bar/state.stale
    static let icon: UInt32 = 0xFFA2ACBA         // bar/icon
    static let label: UInt32 = 0xFFA2ACBA        // bar/label
    static let value: UInt32 = 0xFFE6EAF0        // bar/value

    /// `kColorTextDefault` in `bar_tokens.h`: the fallback for a span whose
    /// colour is the "use default" sentinel. Same VALUE as `value`, but its own
    /// name so a Swift-side parity check can look for both, and so a future
    /// change to one is not silently a change to the other.
    static let textDefault: UInt32 = 0xFFE6EAF0  // bar/value (kColorTextDefault)
}

// MARK: - Span model

/// Horizontal alignment. Integer values equal `SPAN_ALIGN_*` in
/// `lib/scripting.h`, `taskpin::bar::Align` in `native/win/bar_types.h` and
/// `TpSpanAlign.abiValue` in Dart. Do not reorder.
enum BarAlign: Int {
    case left = 0
    case right = 1
    case center = 2

    static func from(_ any: Any?) -> BarAlign {
        guard let n = (any as? NSNumber)?.intValue,
              let v = BarAlign(rawValue: n) else { return .left }
        return v
    }
}

/// Drives the 2 pt left state stripe.
///
/// PARITY: the raw values are `taskpin::bar::ItemState` in
/// `native/win/bar_types.h` (None=0, Running=1, Error=2, Stale=3).
///
/// NOTE — a genuine divergence worth reconciling: the Dart side models this as
/// `TpBarState { running, error, stale, loading }` (`components/bar.dart`),
/// whose implicit ordinals are running=0 / error=1 / stale=2 / loading=3. The
/// two 4-member sets disagree on every value, so the wire form must not be a
/// bare int unless both sides agree on which enum it is. `from(_:)` therefore
/// accepts the C++ ints AND the Dart names as strings.
enum BarState: Int {
    /// `ItemState::StateNone` — no stripe at all.
    ///
    /// Deliberately NOT named `none`: a case called `none` in a non-optional
    /// enum shadows `Optional.none` in pattern position, which makes
    /// `case .none:` ambiguous to read and warns in some Swift versions.
    case noState = 0
    case running = 1
    case error = 2
    case stale = 3

    /// Parse the wire value: a Dart enum name, or a C++ `ItemState` int.
    static func from(_ any: Any?) -> BarState {
        if let s = any as? String {
            switch s.lowercased() {
            case "running": return .running
            case "error": return .error
            case "stale": return .stale
            default: return .noState // "none", "loading", unknown
            }
        }
        if let n = (any as? NSNumber)?.intValue, let v = BarState(rawValue: n) {
            return v
        }
        return .noState
    }
}

/// One span of rich content: either text or an image.
///
/// PARITY: `taskpin::bar::Span` (`native/win/bar_types.h`) and `TpBarSpan`
/// (`packages/taskpin_design/lib/src/models/bar_span.dart`).
struct BarSpan {
    /// Text, or the image source when `isImage`.
    var text: String = ""

    /// 0xAARRGGBB, or `BarTokens.useDefault`.
    var color: UInt32 = BarTokens.useDefault

    /// Point size. 0 = use the style default.
    var fontSize: Int = 0

    var align: BarAlign = .left

    /// This span starts a new line. macOS renders ONE line, so a `newline` span
    /// and everything after it is dropped (see `buildItems`).
    var newline: Bool = false

    var isImage: Bool = false

    /// Requested display size. 0 = the icon metric (16 pt).
    var imageWidth: Int = 0
    var imageHeight: Int = 0

    /// Render numerals with tabular figures.
    ///
    /// Defaults to TRUE here, unlike `taskpin::bar::Span` where it defaults to
    /// false. Reason: the Dart preview strip — the WYSIWYP reference the plan
    /// says must match the real bar — applies `FontFeature.tabularFigures()` to
    /// EVERY span unconditionally (`components/bar.dart`), and VISUAL_SPEC §4.3
    /// makes it an absolute rule ("永远 tabular"). A wire payload may still set
    /// it false explicitly.
    var tabular: Bool = true

    /// Parse one span from the MethodChannel payload.
    static func from(_ json: [String: Any]) -> BarSpan {
        var s = BarSpan()
        s.text = (json["text"] as? String) ?? ""
        s.color = parseHexColor(json["color"])
        s.fontSize = (json["fontSize"] as? NSNumber)?.intValue ?? 0
        s.align = BarAlign.from(json["align"])
        s.newline = (json["newline"] as? NSNumber)?.boolValue ?? false
        s.isImage = (json["isImage"] as? NSNumber)?.boolValue ?? false
        s.imageWidth = (json["imageWidth"] as? NSNumber)?.intValue ?? 0
        s.imageHeight = (json["imageHeight"] as? NSNumber)?.intValue ?? 0
        s.tabular = (json["tabular"] as? NSNumber)?.boolValue ?? true
        return s
    }
}

/// Per-item visual configuration.
///
/// PARITY: `taskpin::bar::BarStyle`. `fontSize` defaults to 11 to match
/// `TpBarTypography.labelSize`, NOT the C++ `BarStyle::font_size = 9` — the two
/// disagree, and 11 is what the Dart preview strip draws, so 11 is what keeps
/// the WYSIWYP promise. Flagged for reconciliation in native/mac/README.md.
///
/// `BarMetrics().labelSize` is a construction-time constant (every field of
/// `BarMetrics` is a `let` with an initialiser), so this default is a compile
/// time constant, not a shared-instance lookup at init.
struct BarStyle {
    var bg: UInt32 = BarTokens.bg
    var bgHover: UInt32 = BarTokens.bgHover
    var label: UInt32 = BarTokens.label
    var value: UInt32 = BarTokens.value
    var icon: UInt32 = BarTokens.icon
    var fontSize: Int = BarMetrics().labelSize
    var state: BarState = .running
    var scrollEnabled: Bool = true
    var showSeparators: Bool = true

    /// Alpha of `bg`. A value < 255 means the item asked for a translucent
    /// strip; the macOS menu bar composites over the desktop, so unlike the
    /// Windows child-window path this needs no layered-window dance — the
    /// rounded fill is simply drawn with its own alpha.
    var bgAlpha: Int { Int((bg >> 24) & 0xFF) }
}

// MARK: - Metrics

/// macOS bar metrics.
///
/// PARITY: `TpBarMetrics.macOS` in `bar_tokens.dart` and VISUAL_SPEC §9.2.
/// These are the macOS column of that table; the Windows column lives in
/// `native/win/bar_tokens.h` (`kMetric*`) and is different on purpose
/// (separator 1x14 gap 6, padding 8/6, radius 0, two lines).
struct BarMetrics {
    /// The menu bar is 24 pt.
    let height: CGFloat = 24
    let padHorizontal: CGFloat = 6
    let padVertical: CGFloat = 0
    let iconSize: CGFloat = 16
    let radius: CGFloat = 6
    /// ONE line. A `newline` span is dropped rather than wrapped.
    let maxLines: Int = 1
    let separatorWidth: CGFloat = 1
    let separatorHeight: CGFloat = 12
    let separatorGap: CGFloat = 4
    let stateStripWidth: CGFloat = 2

    /// Scroll-wheel width clamping, mirroring the Windows clamp
    /// (`kWidthMin` / `kWidthMax` / `kWheelWidthStep`).
    let minWidth: Int = 40
    let maxWidth: Int = 600
    let widthStep: Int = 5

    /// Default label / value size, from `TpBarTypography.labelSize`.
    let labelSize: Int = 11

    /// Font size clamp. The plan says "字号钳制": at 24 pt with no vertical
    /// padding, 18 pt (line height ~22.5) is the largest that still leaves the
    /// descenders inside the strip.
    let minFontSize: Int = 8
    let maxFontSize: Int = 18

    /// Gap between an icon and the text that follows it (VISUAL_SPEC §9.2).
    let iconTextGap: CGFloat = 4

    static let shared = BarMetrics()
}

// MARK: - Colour helpers

/// 0xAARRGGBB -> CGColor.
///
/// `CGColor(srgbRed:...)` rather than a colour-space + components pair: the
/// frozen tokens are sRGB values and the menu bar is sRGB, so no conversion is
/// wanted.
@inline(__always)
func barCGColor(_ argb: UInt32) -> CGColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

@inline(__always)
func barAlpha(_ argb: UInt32) -> CGFloat {
    CGFloat((argb >> 24) & 0xFF) / 255.0
}

/// Parse a colour off the wire.
///
/// Accepts `"#RRGGBB"` (the `TPSpan.color` / `TpBarSpan.colorWire` form),
/// `"RRGGBB"`, and the 8-digit `"AARRGGBB"` form that `lib/config.c` and
/// `taskpin::bar::ParseHexColor` use. Empty or malformed yields the
/// "use default" sentinel, exactly like `ParseHexColor`.
func parseHexColor(_ any: Any?) -> UInt32 {
    guard let raw = any as? String else { return BarTokens.useDefault }
    var digits = raw
    if digits.hasPrefix("#") { digits.removeFirst() }
    if digits.isEmpty { return BarTokens.useDefault }

    func hexValue(_ c: Character) -> UInt32? {
        switch c {
        case "0"..."9": return c.wholeNumberValue.map { UInt32($0) }
        case "a"..."f":
            guard let v = c.unicodeScalars.first.map({ $0.value }) else { return nil }
            return v - 0x61 + 10
        case "A"..."F":
            guard let v = c.unicodeScalars.first.map({ $0.value }) else { return nil }
            return v - 0x41 + 10
        default: return nil
        }
    }

    var value: UInt32 = 0
    for c in digits {
        guard let nibble = hexValue(c) else { return BarTokens.useDefault }
        value = (value << 4) | nibble
    }
    switch digits.count {
    case 6: return 0xFF00_0000 | value // RRGGBB -> opaque
    case 8: return value               // AARRGGBB (TaskPin convention)
    default: return BarTokens.useDefault
    }
}

// MARK: - Icon cache

/// Posted when a background icon load finishes. Each `StatusItemView` observes
/// it and redraws, so several bars all pick the image up. A single stored
/// closure would let only the last-created view see the load, which is why this
/// is a notification rather than a callback property.
extension Notification.Name {
    static let barIconDidLoad = Notification.Name("TaskPinBarIconDidLoad")
}

/// Loads and caches span icons, and answers the "is this source monochrome?"
/// question the template-tint decision needs.
///
/// Sources follow the span ABI: a file path, a `file://` URL, an `http(s)` URL,
/// or a `data:` URI.
///
/// DEVIATION FROM WINDOWS (deliberate): `native/win/bar_image.cpp` fetches
/// `http(s)` sources synchronously inside the paint pass. On macOS the paint
/// pass runs on the main thread and the main thread also draws the menu bar, so
/// a blocking fetch would beachball the whole system UI. Network sources are
/// therefore loaded on a background queue and `.barIconDidLoad` is posted when
/// the image lands. `data:` URIs and local files stay synchronous — they are
/// cheap and by far the common case.
///
/// Animated GIFs are NOT animated here: this draws a single frame. The Windows
/// renderer drives an 80 ms invalidation timer (`kAnimInterval`). Known gap,
/// see native/mac/README.md.
final class BarIconCache {
    static let shared = BarIconCache()

    private var images: [String: NSImage] = [:]
    private var monochrome: [String: Bool] = [:]
    private var failed: Set<String> = []
    private var inFlight: Set<String> = []
    private let lock = NSLock()

    private init() {}

    /// A cached image, or nil. Kicks off a background load for a network
    /// source that is not cached yet (`.barIconDidLoad` is posted when it
    /// arrives).
    func image(for source: String) -> NSImage? {
        lock.lock()
        if let hit = images[source] {
            lock.unlock()
            return hit
        }
        if failed.contains(source) || inFlight.contains(source) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        if let data = Self.dataURIPayload(source) {
            // Cheap and synchronous: a base64 blob already in memory.
            return store(Self.decode(data: data), for: source)
        }
        if let path = Self.localPath(source) {
            return store(NSImage(contentsOfFile: path), for: source)
        }
        if source.lowercased().hasPrefix("http://") || source.lowercased().hasPrefix("https://") {
            lock.lock()
            inFlight.insert(source)
            lock.unlock()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let data = URL(string: source).flatMap { try? Data(contentsOf: $0) }
                let decoded = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.lock.lock()
                    self.inFlight.remove(source)
                    if let decoded = decoded { self.images[source] = decoded }
                    else { self.failed.insert(source) }
                    self.lock.unlock()
                    NotificationCenter.default.post(name: .barIconDidLoad, object: source)
                }
            }
            return nil
        }

        lock.lock()
        failed.insert(source)
        lock.unlock()
        return nil
    }

    /// True when the source has no chromatic content — i.e. every pixel is a
    /// grey (R == G == B) and only the alpha channel carries shape. Those are
    /// the icons the plan says to template-tint with `bar/icon`.
    ///
    /// Unknown / not-yet-loaded sources answer false, so an icon is drawn in
    /// its own colours until it is known to be monochrome. Erring toward "do
    /// not tint" is the safe direction: tinting a colour icon destroys it.
    func isMonochrome(_ source: String) -> Bool {
        lock.lock()
        if let hit = monochrome[source] {
            lock.unlock()
            return hit
        }
        let image = images[source]
        lock.unlock()
        guard let image = image else { return false }

        let verdict = Self.scanMonochrome(image)
        lock.lock()
        monochrome[source] = verdict
        lock.unlock()
        return verdict
    }

    // MARK: private

    @discardableResult
    private func store(_ image: NSImage?, for source: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let image = image else {
            failed.insert(source)
            return nil
        }
        images[source] = image
        return image
    }

    /// `data:[<mediatype>][;base64],<payload>` -> the payload bytes.
    private static func dataURIPayload(_ source: String) -> Data? {
        guard source.lowercased().hasPrefix("data:") else { return nil }
        guard let comma = source.firstIndex(of: ",") else { return nil }
        let meta = source[source.index(source.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(source[source.index(after: comma)...])
        if meta.contains(";base64") {
            return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        }
        return payload.data(using: .utf8)
    }

    private static func decode(data: Data?) -> NSImage? {
        guard let data = data else { return nil }
        return NSImage(data: data)
    }

    /// A local filesystem path, from a bare path or a `file://` URL.
    ///
    /// Returns nil for anything that is not a local file, so the caller falls
    /// through to the network branch.
    private static func localPath(_ source: String) -> String? {
        if source.lowercased().hasPrefix("file://") {
            return URL(string: source)?.path
        }
        if source.contains("://") { return nil } // some other scheme
        return source
    }

    /// Redraw the image into a known 8-bit RGBA buffer and look for chroma.
    ///
    /// The redraw is needed because an NSImage's representations can be any
    /// bit depth, planar, indexed or lazily decoded; scanning `bitmapData`
    /// directly would mean handling every one of those. Drawing into a
    /// canonical rep also forces the decode, which `NSImage(contentsOfFile:)`
    /// otherwise defers until first draw.
    ///
    /// Sampled with a stride: a 512x512 icon has no more "monochrome-ness" than
    /// a 64x64 one, and the status item is redrawn often.
    private static func scanMonochrome(_ image: NSImage) -> Bool {
        let size = image.size
        guard size.width >= 1, size.height >= 1 else { return false }

        // Cap the probe at 64x64: enough to see any real icon's colours.
        let probeW = 64
        let probeH = 64
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: probeW,
            pixelsHigh: probeH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: probeW * 4,
            bitsPerPixel: 32
        ) else { return false }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(x: 0, y: 0, width: CGFloat(probeW), height: CGFloat(probeH)),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return false }
        let bytesPerRow = rep.bytesPerRow
        // Tolerance in 8-bit units. Anti-aliased edges of a grey glyph can pick
        // up a little colour from the compositing space, so an exact R==G==B
        // test would report colour icons everywhere.
        let tolerance = 12

        for y in 0..<probeH {
            let row = data + y * bytesPerRow
            for x in 0..<probeW {
                let p = row + x * 4
                // The buffer is deviceRGB, so byte order is R,G,B,A.
                let r = Int(p[0]), g = Int(p[1]), b = Int(p[2])
                let a = Int(p[3])
                if a < 8 { continue } // fully transparent: carries no colour
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                if maxC - minC > tolerance { return false }
            }
        }
        return true
    }
}

// MARK: - The view

/// The custom view that draws one pinned item into the menu bar.
///
/// Lives as a subview of the `NSStatusItem`'s button (see `StatusItemPlugin`),
/// which is how a status item gets a custom renderer on modern macOS:
/// `NSStatusItem.view` is deprecated in favour of the button. The view is made
/// the hit target for every mouse event so the button's own highlight never
/// shows; hover, click, right-click and wheel are all handled here and
/// forwarded to the plugin through the closures below.
final class StatusItemView: NSView {

    // MARK: model

    /// The spans to render. Setting this repaints.
    var spans: [BarSpan] = [] {
        didSet { needsDisplay = true }
    }

    var style: BarStyle = BarStyle() {
        didSet { needsDisplay = true }
    }

    /// Hover state. Set by the tracking area; also settable by the plugin.
    var hovered: Bool = false {
        didSet {
            guard hovered != oldValue else { return }
            needsDisplay = true
            onHoverChange?(hovered)
        }
    }

    /// A width the item explicitly asked for, from `bar_width` in config.json
    /// (or a wheel resize). 0 means "size to content", which is what
    /// `measuredWidth` then does.
    ///
    /// SURVIVES a content change, matching `BarWindow`: `SetContent` there does
    /// not touch `m_width`, so a wheel-resized bar stays resized when the script
    /// returns new text.
    var explicitWidth: Int = 0

    // MARK: callbacks (all fired on the main thread)

    var onHoverChange: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    /// Screen point of the right-click, for positioning a menu.
    var onContextMenu: ((NSPoint) -> Void)?
    /// (notches, shift) — one notch is +120 / -120, the same unit the Windows
    /// `WM_MOUSEWHEEL` path sees, so the Dart side needs no per-platform branch.
    var onWheel: ((Int, Bool) -> Void)?

    private let metrics = BarMetrics.shared
    private var trackingArea: NSTrackingArea?

    /// Cached fonts, keyed by "size|tabular".
    private var fonts: [String: CTFont] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A background icon load landed; redraw so it appears. Delivered to
        // every view, so several bars all pick the image up.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(barIconDidLoad),
            name: .barIconDidLoad,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(barIconDidLoad),
            name: .barIconDidLoad,
            object: nil
        )
    }

    @objc private func barIconDidLoad(_ note: Notification) {
        needsDisplay = true
    }

    /// `NotificationCenter` holds a zeroing weak reference to a selector-based
    /// observer on macOS 10.11+, so this is not strictly required — but it is
    /// explicit, and it is what keeps the intent obvious if the observer ever
    /// becomes a block-based one.
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Accept the first click even when the app is not frontmost, the way every
    /// other menu-bar item does. Without this a click on an inactive app's
    /// status item is swallowed by the activation.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: geometry

    /// The width the status item should take for the current spans.
    ///
    /// `statusItem.length` is a plain CGFloat, so unlike an auto-sizing AppKit
    /// control there is nothing to hand this to: `StatusItemPlugin` reads this
    /// after every `setSpans` and assigns it.
    ///
    /// Two modes, matching how `bar_width` works in config.json (0 = "size to
    /// content"):
    ///   - [explicitWidth] > 0: honour it, clamped. The user asked for this
    ///     width, so the content truncates into it rather than the strip
    ///     resizing around the content.
    ///   - otherwise: size to the content, so a `CPU 12%` item is not padded
    ///     out to a fixed 200 pt.
    var measuredWidth: CGFloat {
        if explicitWidth > 0 {
            return CGFloat(BarGeometryMath.clampWidth(explicitWidth))
        }
        let natural = naturalContentWidth()
        return min(CGFloat(metrics.maxWidth), max(CGFloat(metrics.minWidth), natural.rounded(.up)))
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        guard b.width > 1, b.height > 1 else { return }

        // Clip everything to the strip's rounded rect so the state stripe and
        // the hover fill cannot bleed into the corners.
        ctx.saveGState()
        ctx.addPath(CGPath(
            roundedRect: b,
            cornerWidth: metrics.radius,
            cornerHeight: metrics.radius,
            transform: nil
        ))
        ctx.clip()

        // ---- background: bar/bg, or the item's bar_bg_color override ----
        let bg = style.bg == BarTokens.useDefault ? BarTokens.bg : style.bg
        ctx.setFillColor(barCGColor(bg))
        ctx.fill(b)

        // ---- hover: bar/bgHover + 1pt hairlines top and bottom ----
        if hovered {
            ctx.setFillColor(barCGColor(style.bgHover))
            ctx.fill(b)
            ctx.setFillColor(barCGColor(BarTokens.hairline))
            ctx.fill(CGRect(x: 0, y: b.height - 1, width: b.width, height: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: b.width, height: 1))
        }

        // ---- 2pt full-height left state stripe ----
        // bar/state.running is fully transparent on purpose: a healthy item
        // shows nothing, so the eye is drawn only to problems.
        let stripe = stripeColor(style.state)
        if barAlpha(stripe) > 0 {
            ctx.setFillColor(barCGColor(stripe))
            ctx.fill(CGRect(x: 0, y: 0, width: metrics.stateStripWidth, height: b.height))
        }

        var items = buildItems()
        guard !items.isEmpty else {
            ctx.restoreGState()
            return
        }

        // ---- truncation pass ----
        // macOS gets ONE line and the plan is explicit: ellipsis-truncate, do
        // not clip. Truncate from the last text span backwards.
        //
        // Measured against `measuredWidth`, not `bounds.width`: the two agree
        // once the plugin has applied the width, but on the frame where content
        // changed they do not yet, and truncating against the stale width would
        // make the strip lag one edit behind.
        truncateToFit(&items, width: measuredWidth)

        // ---- position pass (mirrors bar_render_d2d.cpp's DrawFrame) ----
        let result = layout(items, in: b)

        // ---- separators ----
        // Painted before the content so an icon's own pixels can never sit on
        // top of a rule. 1 x 12pt, bar/separator (white 20%).
        if !result.separators.isEmpty {
            ctx.setFillColor(barCGColor(BarTokens.separator))
            for rect in result.separators { ctx.fill(rect) }
        }

        // ---- draw ----
        for p in result.placed {
            if let image = p.item.image {
                drawIcon(image, source: p.item.span.text, in: p.rect, ctx: ctx)
            } else if let line = p.line {
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: p.rect.minX, y: p.baseline)
                CTLineDraw(line, ctx)
            }
        }

        ctx.restoreGState()
    }

    /// The colour of the left state stripe for a state.
    private func stripeColor(_ state: BarState) -> UInt32 {
        switch state {
        case .noState, .running: return BarTokens.stateRunning
        case .error: return BarTokens.stateError
        case .stale: return BarTokens.stateStale
        }
    }

    // MARK: layout

    /// One laid-out span: its measured size, and its Core Text line once built.
    private struct Item {
        var span: BarSpan
        var line: CTLine?
        var image: NSImage?
        /// Width the span wants with no truncation.
        var naturalWidth: CGFloat
        /// Width it is allowed to occupy; == naturalWidth unless truncated.
        var maxWidth: CGFloat
        /// Height of the drawn content (text block, or the icon box).
        var height: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        /// Space inserted before this span, replacing the separator.
        ///
        /// Set to `metrics.iconTextGap` for a text span that immediately follows
        /// an icon: VISUAL_SPEC §9.2 gives macOS a 4 pt icon-to-text gap, and
        /// §9.5 rule 1 says the text an icon introduces belongs to the SAME
        /// segment, so a 1 pt rule between them would be wrong.
        var gapBefore: CGFloat = 0
        /// Dropped by the truncation pass: contributes nothing, draws nothing.
        var dropped: Bool = false

        var isText: Bool { line != nil && !span.text.isEmpty }
        var effectiveWidth: CGFloat { dropped ? 0 : min(naturalWidth, maxWidth) }
    }

    /// A placed item: where it goes, and the baseline for text.
    private struct Placed {
        var item: Item
        var rect: CGRect
        var baseline: CGFloat
        var line: CTLine?
    }

    /// The result of a layout pass.
    ///
    /// Returned rather than stored: `layout` runs while measuring as well as
    /// while drawing, and a version that accumulated separators in a field would
    /// append duplicates every pass.
    private struct LayoutResult {
        var placed: [Placed] = []
        var separators: [CGRect] = []
    }

    /// The x the first span starts at. The state stripe sits at 0, so the
    /// content is inset past it and then by the horizontal padding. This
    /// matches `TpBarPreviewStrip`'s `stripWidth + m.padHorizontal` (the Dart
    /// reference), NOT the Windows renderer's bare `kMetricPadH`.
    private var contentOriginX: CGFloat { metrics.stateStripWidth + metrics.padHorizontal }

    /// How much horizontal room the spans have.
    private func contentWidthLimit(_ total: CGFloat) -> CGFloat {
        max(0, total - contentOriginX - metrics.padHorizontal)
    }

    /// Width required to draw `items` with nothing truncated.
    ///
    /// A pure arithmetic model rather than "run the layout at a huge width and
    /// see how far it reaches": a right-aligned span is positioned from the
    /// RIGHT margin, so laying out at an arbitrary width and measuring the last
    /// item's `maxX` reports that arbitrary width as the requirement. This
    /// computes what the strip actually needs, and it is the same quantity the
    /// Windows renderer's `left_total` feeds the marquee decision.
    ///
    /// The model mirrors `BarRenderer::DrawFrame`'s position pass:
    ///   - left-aligned spans stack from `contentOriginX`, with a separator
    ///     advance between consecutive ones
    ///   - right-aligned spans stack leftwards from the right margin and carry
    ///     no separator
    ///   - a centre-aligned span is centred in the strip and does not advance
    ///     the left cursor
    ///
    /// The two runs overlap exactly when the content does not fit, which is the
    /// overflow condition `truncateToFit` acts on.
    private func requiredWidth(_ items: [Item]) -> CGFloat {
        let separatorAdvance = style.showSeparators
            ? metrics.separatorGap * 2 + metrics.separatorWidth
            : 0

        var leftTotal: CGFloat = 0
        var rightTotal: CGFloat = 0
        var centerMax: CGFloat = 0
        var leftCount = 0

        // The gap before an item is the icon-to-text gap when it has one, and
        // the separator advance otherwise — the two never stack. This must match
        // `layout`'s cursor arithmetic exactly, or the measured width and the
        // drawn width disagree and the strip is permanently one edit behind.
        func gap(before item: Item) -> CGFloat {
            item.gapBefore > 0 ? item.gapBefore : separatorAdvance
        }

        for item in items where !item.dropped {
            let width = item.effectiveWidth
            guard width > 0 else { continue }
            switch item.span.align {
            case .left:
                if leftCount > 0 { leftTotal += gap(before: item) }
                leftTotal += width
                leftCount += 1
            case .right:
                rightTotal += gap(before: item) + width
            case .center:
                centerMax = max(centerMax, gap(before: item) + width)
            }
        }

        return contentOriginX + leftTotal + max(rightTotal, centerMax) + metrics.padHorizontal
    }

    /// Build the span list for the ONE line macOS renders.
    ///
    /// A `newline` span starts line 2, which the menu bar cannot show, so this
    /// stops there — mirroring `TpBarContent.lines[0]` on the Dart side.
    private func buildItems() -> [Item] {
        var items: [Item] = []
        var previousWasImage = false

        for span in spans {
            if span.newline { break } // line 1 is all macOS has

            var item = Item(
                span: span,
                line: nil,
                image: nil,
                naturalWidth: 0,
                maxWidth: 0,
                height: 0,
                ascent: 0,
                descent: 0
            )
            // The text a `icon()` introduces belongs to the same segment as the
            // icon (VISUAL_SPEC §9.5 rule 1), so it is separated by the 4 pt
            // icon-to-text gap rather than by a 1 pt rule.
            item.gapBefore = previousWasImage ? metrics.iconTextGap : 0

            if span.isImage {
                guard !span.text.isEmpty else { continue }
                let image = BarIconCache.shared.image(for: span.text)
                let w = span.imageWidth > 0 ? CGFloat(span.imageWidth) : metrics.iconSize
                let h = span.imageHeight > 0 ? CGFloat(span.imageHeight) : metrics.iconSize
                item.image = image
                // Even when the image has not loaded yet, reserve its box: the
                // strip must not reflow the moment an icon arrives.
                item.naturalWidth = w
                item.maxWidth = w
                item.height = h
                items.append(item)
                previousWasImage = true
                continue
            }

            guard !span.text.isEmpty else { continue }
            let font = font(for: span)
            guard let line = makeLine(span.text, font: font, color: textColor(span)) else {
                continue
            }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            item.line = line
            item.naturalWidth = width
            item.maxWidth = width
            item.height = ascent + descent
            item.ascent = ascent
            item.descent = descent
            items.append(item)
            previousWasImage = false
        }

        return items
    }

    /// Width the content wants when nothing is truncated.
    private func naturalContentWidth() -> CGFloat {
        requiredWidth(buildItems())
    }

    /// Ellipsis-truncate from the last text span backwards until it fits.
    ///
    /// `width` is the size the status item is actually taking. It is passed in
    /// rather than read from `bounds` because truncation has to be decided
    /// against the SAME number `measuredWidth` reported to the plugin — using
    /// `bounds.width` would measure against the previous frame's width and the
    /// strip would shrink one step behind every change.
    ///
    /// Uses `CTLineCreateTruncatedLine` rather than chopping characters by
    /// hand: Core Text places the ellipsis glyph correctly and keeps the
    /// remaining glyphs on their real advances, which is what "do not clip half
    /// a glyph" means in practice.
    private func truncateToFit(_ items: inout [Item], width: CGFloat) {
        let available = contentWidthLimit(width)
        guard available > 0 else {
            for i in items.indices { items[i].dropped = true }
            return
        }

        // Each pass either shrinks a span's allowance (strictly decreasing
        // `requiredWidth`) or drops one (strictly reducing the span count), so
        // the loop terminates. The counter is belt and braces against a
        // rounding edge case where a shrink is a no-op.
        var guardCounter = items.count * 2 + 2
        while guardCounter > 0 {
            guardCounter -= 1

            let excess = requiredWidth(items) - width
            if excess <= 0 { break }

            guard let index = items.lastIndex(where: { $0.isText && !$0.dropped }) else {
                break
            }
            let natural = items[index].naturalWidth

            // The token alone needs some room; below that the span is better
            // dropped entirely than reduced to a bare ellipsis.
            let tokenWidth = ellipsisWidth(items[index])
            if natural - excess >= tokenWidth + 2 {
                // Never grow a span, and never take it below the ellipsis.
                let allowed = max(tokenWidth, min(natural - excess, natural))
                if allowed < items[index].maxWidth {
                    items[index].maxWidth = allowed
                    if let truncated = makeTruncatedLine(items[index], width: allowed) {
                        items[index].line = truncated
                    } else {
                        items[index].dropped = true
                    }
                } else {
                    // Cannot shrink further; drop so the loop makes progress.
                    items[index].dropped = true
                }
            } else {
                items[index].dropped = true
            }
        }
    }

    /// Position the items, mirroring `BarRenderer::DrawFrame`'s position pass.
    ///
    /// Left-aligned spans stack from the left, right-aligned ones stack
    /// leftwards from the right margin, centre-aligned ones are centred in the
    /// strip. A separator is drawn before every span except the first on the
    /// line, and never before a right-aligned span (matching the Windows
    /// renderer, whose right group carries its own visual separation).
    private func layout(_ items: [Item], in bounds: CGRect) -> LayoutResult {
        var result = LayoutResult()
        guard !items.isEmpty else { return result }

        let w = bounds.width
        let h = bounds.height
        var leftX = contentOriginX
        var rightX = w - metrics.padHorizontal

        let separatorAdvance = style.showSeparators
            ? metrics.separatorGap * 2 + metrics.separatorWidth
            : 0

        // Tracks whether a LEFT-aligned span has already been placed, which is
        // exactly the condition `requiredWidth` uses (`leftCount > 0`) to decide
        // whether a gap is consumed. The two must agree or a separator lands
        // where no gap was reserved and the strip is a rule-width too narrow.
        var sawLeftOnLine = false

        for item in items where !item.dropped {
            let width = item.effectiveWidth
            guard width > 0 else { continue }

            // How much room stands before this span: the icon-to-text gap if it
            // has one, otherwise the separator advance. Mirrors `requiredWidth`'s
            // `gap(before:)` exactly.
            let gap = item.gapBefore > 0 ? item.gapBefore : separatorAdvance

            let x: CGFloat
            switch item.span.align {
            case .left:
                x = leftX
                leftX += width
                leftX += gap
            case .right:
                rightX -= width
                x = rightX
                rightX -= gap
            case .center:
                x = (w - width) / 2
            }

            // Separator before this span: only for a left-aligned span that is
            // not the first left one on the line, and only when an icon-to-text
            // gap is not already standing there. Mirrors `requiredWidth`'s
            // `gap(before:)` + `leftCount > 0`.
            if style.showSeparators && item.span.align == .left
                && sawLeftOnLine && item.gapBefore == 0 {
                let sepX = x - (metrics.separatorGap + metrics.separatorWidth)
                result.separators.append(CGRect(
                    x: sepX,
                    y: (h - metrics.separatorHeight) / 2,
                    width: metrics.separatorWidth,
                    height: metrics.separatorHeight
                ))
            }

            // Vertical placement: an icon sits on the centre line; text sits on
            // a baseline that centres its ascent+descent box.
            let baseline: CGFloat
            let rect: CGRect
            if item.image != nil {
                rect = CGRect(x: x, y: (h - item.height) / 2, width: width, height: item.height)
                baseline = rect.minY
            } else {
                let boxBottom = (h - item.height) / 2
                baseline = boxBottom + item.descent
                rect = CGRect(x: x, y: boxBottom, width: width, height: item.height)
            }

            result.placed.append(Placed(item: item, rect: rect, baseline: baseline, line: item.line))
            if item.span.align == .left { sawLeftOnLine = true }
        }

        return result
    }

    // MARK: fonts and lines

    /// The Core Text font for a span.
    ///
    /// Tabular figures come from `NSFont.monospacedDigitSystemFont`, which is
    /// AppKit's own spelling for "SF Pro with `tnum` on". The alternative — a
    /// font descriptor with an AAT `.featureSettings` dictionary — needs
    /// NSNumber-boxed type/selector pairs and silently degrades if the boxing is
    /// wrong, so the first-class API is used instead.
    ///
    /// Weight is not selectable here: the bar distinguishes labels from values
    /// by COLOUR (`bar/label` vs `bar/value`), not by weight, which is also what
    /// the Dart preview strip does. `TpBarTypography.valueWeight` (500) is
    /// therefore not reproduced on macOS. Recorded as a known divergence in
    /// native/mac/README.md rather than faked with a synthetic bold.
    private func font(for span: BarSpan) -> CTFont {
        var size = span.fontSize > 0 ? span.fontSize : style.fontSize
        size = min(metrics.maxFontSize, max(metrics.minFontSize, size))
        let tabular = span.tabular
        let key = "\(size)|\(tabular ? 1 : 0)"
        if let hit = fonts[key] { return hit }

        // The bar uses the SYSTEM font (SF Pro), never Inter — forcing Inter
        // onto the menu bar would make TaskPin's strip visibly foreign next to
        // every other status item.
        //
        // `as CTFont` is an explicit toll-free bridge: NSFont and CTFont are the
        // same object, but Swift will not implicitly convert between them.
        let base = tabular
            ? NSFont.monospacedDigitSystemFont(ofSize: CGFloat(size), weight: .regular)
            : NSFont.systemFont(ofSize: CGFloat(size))
        let font: CTFont = base as CTFont
        fonts[key] = font
        return font
    }

    /// The colour a span's text is drawn in.
    ///
    /// A span that did not set a colour falls back to `bar/value` — the
    /// brightest default, because values are the point of the strip.
    private func textColor(_ span: BarSpan) -> UInt32 {
        span.color == BarTokens.useDefault ? BarTokens.textDefault : span.color
    }

    private func makeLine(_ text: String, font: CTFont, color: UInt32) -> CTLine? {
        let attributes: [String: Any] = [
            kCTFontAttributeName as String: font,
            kCTForegroundColorAttributeName as String: barCGColor(color),
        ]
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            attributes as CFDictionary
        ) else { return nil }
        return CTLineCreateWithAttributedString(attributed)
    }

    /// Re-cut an item's line to `width`, ending in an ellipsis.
    private func makeTruncatedLine(_ item: Item, width: CGFloat) -> CTLine? {
        guard let line = item.line else { return nil }
        guard let token = makeLine(
            "\u{2026}", // HORIZONTAL ELLIPSIS
            font: font(for: item.span),
            color: textColor(item.span)
        ) else { return nil }
        return CTLineCreateTruncatedLine(line, Double(width), .end, token)
    }

    /// How much room the ellipsis alone needs in this item's font.
    private func ellipsisWidth(_ item: Item) -> CGFloat {
        guard let token = makeLine(
            "\u{2026}",
            font: font(for: item.span),
            color: textColor(item.span)
        ) else { return 0 }
        return CGFloat(CTLineGetTypographicBounds(token, nil, nil, nil))
    }

    // MARK: icons

    /// Draw an icon at its box, template-tinting it when the source is
    /// monochrome.
    ///
    /// The tint is done with a transparency layer rather than by filling over
    /// the image: outside a layer the strip's own background is part of the
    /// destination, so a `sourceAtop` fill would paint the whole box. Inside a
    /// layer the backdrop is transparent and `sourceAtop` touches only the
    /// icon's own pixels, anti-aliased edges included.
    private func drawIcon(_ image: NSImage, source: String, in rect: CGRect, ctx: CGContext) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        if BarIconCache.shared.isMonochrome(source) {
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.draw(cg, in: rect)
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(barCGColor(style.icon))
            ctx.fill(rect)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        } else {
            ctx.draw(cg, in: rect)
        }
    }

    // MARK: hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    // MARK: mouse

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseUp(with event: NSEvent) {
        // `event.locationInWindow` is in window coordinates; the plugin needs
        // screen coordinates to place an NSMenu.
        let inWindow = event.locationInWindow
        let onScreen = window?.convertPoint(toScreen: inWindow) ?? inWindow
        onContextMenu?(onScreen)
    }

    override func scrollWheel(with event: NSEvent) {
        // Momentum events would otherwise keep firing after the user's fingers
        // leave a trackpad, and the width would run to its clamp.
        if event.momentumPhase != [] { return }

        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        // Normalise to the Windows unit: one notch is +120 / -120
        // (`WM_MOUSEWHEEL`'s GET_WHEEL_DELTA_WPARAM). A trackpad's precise
        // deltas are ignored in magnitude so a flick does not slam the bar to
        // 600 pt, and so the Dart side sees one number scale on both platforms.
        let notches = dy > 0 ? 120 : -120
        let shift = event.modifierFlags.contains(.shift)
        onWheel?(notches, shift)
    }
}

// MARK: - Geometry maths

/// The wheel -> width rule, kept as a pure function so it is testable without a
/// status item.
///
/// PARITY: `BarWindow::OnWheel` (`native/win/bar_window.cpp`) — normal wheel
/// `width += delta > 0 ? 5 : -5`, clamped to [min, max]. Shift+wheel moves X on
/// Windows; the macOS menu bar is placed by the system, so X is not applicable
/// and `x` comes back as -1 — the same sentinel `bar_x` uses in config.json for
/// "auto".
enum BarGeometryMath {
    static func applyWheel(width: Int, delta: Int, shift: Bool) -> (width: Int, x: Int) {
        let metrics = BarMetrics.shared
        if shift {
            return (width, -1)
        }
        let step = delta > 0 ? metrics.widthStep : -metrics.widthStep
        let next = min(metrics.maxWidth, max(metrics.minWidth, width + step))
        return (next, -1)
    }

    /// Clamp a width coming off the wire into the macOS range.
    static func clampWidth(_ width: Int) -> Int {
        let metrics = BarMetrics.shared
        return min(metrics.maxWidth, max(metrics.minWidth, width))
    }
}
