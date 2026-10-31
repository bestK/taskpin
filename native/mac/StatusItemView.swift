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
//    - the menu bar is ~24 pt tall (taller on a notched display). One line by
//      default. A `newline` span switches to two lines, each with half the
//      height, laid out as left/right columns (see `layoutTwoLine`). Overlong
//      content is ellipsis-truncated per line, never clipped mid-glyph.
//    - icons are 16 pt; a monochrome source is template-tinted with `bar/icon`.
//    - the bar uses the SYSTEM font (SF Pro), never Inter.
//    - tabular figures always: `CPU: 9%` -> `CPU: 100%` must not shift
//      everything to its right. This is the bar's most important typographic
//      rule (VISUAL_SPEC §4.3).
//
//  TYPECHECKED, NOT RUN. This file imports only AppKit/Core Text, so it can be
//  checked with `xcrun swiftc -typecheck -target arm64-apple-macos12.0`; it has
//  never been run inside a real menu bar. The risk list and the full
//  `taskpin/bar` contract live in `native/mac/README.md`.
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

    /// `kColorTextDefault` in `bar_tokens.h`: the Windows fallback for a span
    /// whose colour is the "use default" sentinel. Same VALUE as `value`, but
    /// its own name so a Swift-side parity check can look for both, and so a
    /// future change to one is not silently a change to the other.
    ///
    /// NOT USED ON macOS: an uncoloured span resolves the system menu-bar text
    /// colour instead (VISUAL_SPEC §7.1), so a light menu bar stays readable.
    /// Kept because the token list is frozen and three-way.
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

/// Drives the bottom-centred state indicator.
///
/// VISUAL_SPEC §7.2: a healthy item shows nothing; stale/error draw a small
/// rounded bar under the content. The old 2 pt full-height left stripe was a
/// Windows-10-era cue and is deliberately gone (see native/mac/README.md).
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
    /// `ItemState::StateNone` — no indicator at all.
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

    /// This span starts a new line. Any `newline` span switches the strip to
    /// two-line mode (see `isTwoLine`). A third line is joined onto the second.
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
    ///
    /// KEY NAMES: the Dart controller (`spanToWire` in
    /// `lib/core/bar/bar_channel.dart`) sends the C-ABI short names —
    /// `size`, `image`, `img_w`, `img_h` — while the older contract documented
    /// here used the camelCase model names. Both are accepted so the channel
    /// stays compatible with either producer; the wire contract itself is
    /// unchanged.
    static func from(_ json: [String: Any]) -> BarSpan {
        func intValue(_ keys: String...) -> Int {
            for key in keys {
                if let n = json[key] as? NSNumber { return n.intValue }
            }
            return 0
        }
        func boolValue(_ keys: String...) -> Bool? {
            for key in keys {
                if let n = json[key] as? NSNumber { return n.boolValue }
            }
            return nil
        }

        var s = BarSpan()
        s.text = (json["text"] as? String) ?? ""
        s.color = parseHexColor(json["color"])
        s.fontSize = intValue("fontSize", "size")
        s.align = BarAlign.from(json["align"])
        s.newline = boolValue("newline") ?? false
        s.isImage = boolValue("isImage", "image") ?? false
        s.imageWidth = intValue("imageWidth", "img_w")
        s.imageHeight = intValue("imageHeight", "img_h")
        s.tabular = boolValue("tabular") ?? true
        return s
    }
}

/// Per-item visual configuration.
///
/// PARITY: `taskpin::bar::BarStyle`. `fontSize` defaults to 13
/// (`BarMetrics().labelSize`, the macOS system size from VISUAL_SPEC §7.1), NOT
/// the C++ `BarStyle::font_size = 9` and NOT the Dart preview's
/// `TpBarTypography.labelSize = 11`. All three disagree; flagged for
/// reconciliation in native/mac/README.md.
///
/// `BarMetrics().labelSize` is a construction-time constant (every field of
/// `BarMetrics` is a `let` with an initialiser), so this default is a compile
/// time constant, not a shared-instance lookup at init.
struct BarStyle {
    /// `useDefault` means "no background": VISUAL_SPEC §7.1 makes the macOS
    /// menu-bar strip transparent unless the user picked a colour. The Dart
    /// controller sends `0xFFFFFFFF` (`kFollowTaskbarArgb`) for that case, so
    /// the sentinel maps to "draw nothing" here rather than to `bar/bg`.
    var bg: UInt32 = BarTokens.useDefault
    var bgHover: UInt32 = BarTokens.bgHover
    var label: UInt32 = BarTokens.label
    var value: UInt32 = BarTokens.value
    /// `useDefault` means "follow the menu bar": monochrome icons take the system
    /// secondary label colour, resolved per draw like the text. The Dart side only
    /// sends `icon` when a script or config sets one, so the default is the usual case.
    var icon: UInt32 = BarTokens.useDefault
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
    /// The maximum lines the strip draws. A `newline` beyond this joins the last line.
    let maxLines: Int = 2
    /// VISUAL_SPEC §7.3: a 1 x 14 rule with 6 pt either side. The Dart
    /// `TpBarMetrics.macOS` still says 1 x 12 / gap 4; this renderer follows
    /// the spec and native/mac/README.md records the divergence.
    let separatorWidth: CGFloat = 1
    let separatorHeight: CGFloat = 14
    let separatorGap: CGFloat = 6

    /// VISUAL_SPEC §7.2: a bottom-centred rounded bar, 16 pt long and 3 pt
    /// thick ("3 x 16" in the spec, read as thickness x length like the
    /// separator's "1 x 14").
    let stateIndicatorWidth: CGFloat = 16
    let stateIndicatorHeight: CGFloat = 3
    let stateIndicatorRadius: CGFloat = 1.5

    /// Scroll-wheel width clamping, mirroring the Windows clamp
    /// (`kWidthMin` / `kWidthMax` / `kWheelWidthStep`).
    ///
    /// On macOS, an icon-only item (16 pt icon + 6 pt padding either side) has
    /// a natural width of 28 pt, so `minWidth` is 28 pt rather than Windows's
    /// 40 pt button width, avoiding artificial empty padding.
    let minWidth: Int = 28
    let maxWidth: Int = 600
    let widthStep: Int = 5

    /// VISUAL_SPEC §7.1: the macOS menu bar draws SF Pro at 13 pt. The Dart
    /// controller still sends 9 (`kBarDefaultFontSize`) when the config has no
    /// opinion, because 9 pt is the Windows value; [windowsDefaultFontSize]
    /// is how that sentinel is recognised and replaced.
    let labelSize: Int = 13

    /// `kBarDefaultFontSize` on the Dart side. A wire size equal to this is
    /// treated as "unspecified" and rendered at [labelSize] instead: 9 pt next
    /// to the system clock would be visibly foreign. An explicit other size
    /// (12, 14, ...) is still honoured. See native/mac/README.md.
    let windowsDefaultFontSize: Int = 9

    /// Font size clamp. The plan says "字号钳制": at 24 pt with no vertical
    /// padding, 18 pt (line height ~22.5) is the largest that still leaves the
    /// descenders inside the strip.
    ///
    /// Legible floor on macOS: Apple's system UI defines `miniSystemFontSize`
    /// as 9 pt and `smallSystemFontSize` as 11 pt. Clamping to 10 pt ensures that
    /// tiny script sizes (e.g. size 4 in `zeeho.lua` authored for Windows two-line
    /// layout, or size 8 in `net_monitor.lua`) remain comfortably readable in the
    /// 24 pt menu bar next to the 13 pt system clock.
    let minFontSize: Int = 10
    let maxFontSize: Int = 18

    /// Two-line mode (any `newline` span). Modelled on the menu-bar network
    /// meters that stack two short readings ("920 B/s" over "2 KB/s") in the
    /// bar's full height.
    ///
    /// Grid size per line: the smaller of
    ///   - the size whose pitch fits one band: (bar - 2 x edge) / 2 / 1.1, which
    ///     is 10 pt on a 24 pt bar;
    ///   - 40% of the bar height (`twoLineFontFraction`), which is 9.6 pt on 24 pt;
    /// then rounded down to a half point, giving 9.5 pt on a 24 pt bar. A taller
    /// notched bar scales with the height; a 37 pt bar would give 14.5 pt.
    /// Each span's own size (script size, mapped as in single-line mode) is then
    /// floored at 8 pt (`twoLineMinFontSize`) and capped at the grid size.
    /// Line pitch is `lineHeightFactor` x grid size: 10.45 pt on 24 pt, so the two
    /// lines sit tight with no visible gap. The two-line block is centred.
    let twoLineEdge: CGFloat = 1
    let twoLineFontFraction: CGFloat = 0.40
    let lineHeightFactor: CGFloat = 1.1
    let twoLineMinFontSize: CGFloat = 8
    /// Gap between a line's left run and its right run. Wider than a word space,
    /// narrower than a separator's 13 pt advance, so the two columns read apart
    /// without a rule between them.
    let columnGap: CGFloat = 8
    /// Status indicator in two-line mode: 2 pt thick at y = 0.5 (top edge 2.5).
    /// The 3 pt bar at y = 1 would reach 4 pt, above the lower line's baseline
    /// (about 3.45 pt up on a 24 pt bar), so it would touch the digits. At 2 pt
    /// only glyphs with descenders can reach it.
    let twoLineStateIndicatorHeight: CGFloat = 2
    let twoLineStateIndicatorY: CGFloat = 0.5

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
///
/// Also accepts a numeric `0xAARRGGBB`: the Dart controller serialises
/// `TpBarSpan.color.toARGB32()` and `BarStyleSpec`'s colours as ints, and the
/// standard method codec delivers those as `NSNumber`. Without this branch
/// every script-specified colour would silently become the default.
func parseHexColor(_ any: Any?) -> UInt32 {
    if let n = any as? NSNumber {
        // Truncate rather than trap: a 32-bit ARGB arrives as a positive
        // 64-bit NSNumber, and the mask is exactly what is wanted.
        return UInt32(truncatingIfNeeded: n.int64Value)
    }
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
    var explicitWidth: Int = 0 {
        didSet {
            // A deliberate width change is not jitter, so the shrink hysteresis
            // starts over. `setSpans` re-sends the same value every call, hence the guard.
            guard explicitWidth != oldValue else { return }
            lastAppliedWidth = 0
            shrinkStreak = 0
        }
    }

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

    /// Width the strip last took, the baseline for the shrink hysteresis.
    private var lastAppliedWidth: CGFloat = 0
    /// Consecutive `settledWidth` calls that wanted a narrower strip than the
    /// one applied. The shrink lands once this reaches `shrinkSettleCount`.
    private var shrinkStreak = 0
    /// How many content updates in a row must want a narrower strip before it
    /// narrows. Each update is one `setSpans` call from the script's refresh.
    private static let shrinkSettleCount = 3

    /// The width the status item would take for the current spans, with no
    /// side effects, so it is safe to call from `draw`.
    ///
    /// On macOS menu bar, status items are compact indicators and should never
    /// carry empty void in the middle or at the end.
    /// If an explicit width was requested (from a Windows `bar_width` config or
    /// mouse wheel resize), it acts as an upper limit / cap; the strip sizes
    /// to its natural content up to that limit without inflating with blank space.
    var measuredWidth: CGFloat {
        let natural = naturalContentWidth().rounded(.up)
        guard natural > 0 else { return 0 }
        let maxAllowed: CGFloat = explicitWidth > 0
            ? CGFloat(BarGeometryMath.clampWidth(explicitWidth))
            : CGFloat(metrics.maxWidth)
        return min(maxAllowed, natural)
    }

    /// The width to apply after a content change, with jitter hysteresis.
    ///
    /// Numerals and units change width from tick to tick ("1023K/s" to "1.0M/s"
    /// is about 10 pt narrower), and every width change shifts the menu-bar items
    /// beside this one. So the strip grows at once, so content never truncates,
    /// but narrows only after the smaller width has held for `shrinkSettleCount`
    /// updates. Until then it keeps the wider width.
    ///
    /// Stateful: call from the content-change path (`setSpans`) only.
    func settledWidth() -> CGFloat {
        let target = measuredWidth
        guard target > 0 else {
            // Empty content resets the hysteresis, so the next content grows at once.
            lastAppliedWidth = 0
            shrinkStreak = 0
            return 0
        }
        if lastAppliedWidth == 0 || target >= lastAppliedWidth {
            lastAppliedWidth = target
            shrinkStreak = 0
            return target
        }
        shrinkStreak += 1
        guard shrinkStreak >= StatusItemView.shrinkSettleCount else {
            return lastAppliedWidth
        }
        lastAppliedWidth = target
        shrinkStreak = 0
        return target
    }

    /// The width `settledWidth` would give right now, without advancing the
    /// hysteresis. Used by geometry calls and `draw`, which must agree with the
    /// width the last content change applied.
    var heldWidth: CGFloat {
        let target = measuredWidth
        guard target > 0 else { return 0 }
        if lastAppliedWidth == 0 || target >= lastAppliedWidth { return target }
        return lastAppliedWidth
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        guard b.width > 1, b.height > 1 else { return }

        // Clip everything to the strip's rounded rect so a user-set background
        // and the state indicator cannot bleed into the corners. On the default
        // transparent background this clip paints nothing by itself.
        ctx.saveGState()
        ctx.addPath(CGPath(
            roundedRect: b,
            cornerWidth: metrics.radius,
            cornerHeight: metrics.radius,
            transform: nil
        ))
        ctx.clip()

        // ---- background: transparent unless the user chose a colour ----
        // VISUAL_SPEC §7.1. The Dart controller sends 0xFFFFFFFF for "follow
        // the taskbar", which maps to `useDefault`; macOS has no taskbar colour
        // to follow, so the menu bar itself shows through. `bar/bg` is only
        // the Windows resting fill and is never painted here.
        if style.bg != BarTokens.useDefault && barAlpha(style.bg) > 0 {
            ctx.setFillColor(barCGColor(style.bg))
            ctx.fill(b)
        }

        // ---- hover / pressed: the NSStatusBarButton's own highlight ----
        // Nothing is painted here. The view is transparent, so the button's
        // native highlight (driven from mouseDown/mouseUp below) shows through
        // instead of a custom rounded fill — VISUAL_SPEC §7.1 "系统高亮".
        // `bar/bgHover` stays in the frozen token list for Windows, where a
        // taskbar segment has no system highlight of its own.

        // ---- state indicator: bottom-centred rounded bar ----
        // VISUAL_SPEC §7.2: a bottom-centred 16 x 3 rounded bar.
        // Positioned at y = 1.0 pt with rounded integer-point coordinates so the
        // bottom pill radius is fully preserved (not clipped by the view boundary)
        // and pixel-crisp on Retina.
        // Two-line mode drops it to 2 pt at y = 0.5. At 3 pt on y = 1 its top edge
        // would reach into the lower line's digits (see BarMetrics).
        let indicator = indicatorColor(style.state)
        if barAlpha(indicator) > 0 {
            let indicatorX = ((b.width - metrics.stateIndicatorWidth) / 2).rounded()
            let twoLine = isTwoLine
            let indicatorY = twoLine ? metrics.twoLineStateIndicatorY : 1.0
            let rect = CGRect(
                x: indicatorX,
                y: indicatorY,
                width: metrics.stateIndicatorWidth,
                height: twoLine ? metrics.twoLineStateIndicatorHeight : metrics.stateIndicatorHeight
            )
            ctx.setFillColor(barCGColor(indicator))
            ctx.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: metrics.stateIndicatorRadius,
                cornerHeight: metrics.stateIndicatorRadius,
                transform: nil
            ))
            ctx.fillPath()
        }

        var items = buildItems()
        guard !items.isEmpty else {
            ctx.restoreGState()
            return
        }

        // ---- truncation pass ----
        // The plan is explicit: ellipsis-truncate, do not clip. Each line is
        // truncated on its own, from its last text span backwards.
        //
        // Measured against the width the strip actually holds (`heldWidth`), so
        // text is cut to the frame it is drawn in. During a shrink hold the strip
        // is wider than the natural content, and this keeps the text unclipped.
        truncateToFit(&items, width: heldWidth)

        // ---- position pass (mirrors bar_render_d2d.cpp's DrawFrame) ----
        let result = layout(items, in: b)

        // ---- separators ----
        // Painted before the content so an icon's own pixels can never sit on
        // top of a rule. 1 x 14 pt; the colour follows the menu bar's
        // light/dark appearance (VISUAL_SPEC §7.3), which is why it is
        // resolved here rather than taken straight from `bar/separator`.
        if !result.separators.isEmpty {
            ctx.setFillColor(separatorColor())
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

    /// The colour of the bottom state indicator for a state.
    ///
    /// The frozen tokens are used as-is; they are the Windows palette and are
    /// also what the Dart preview draws, so the two shells agree on what
    /// "stale" and "error" look like.
    private func indicatorColor(_ state: BarState) -> UInt32 {
        switch state {
        case .noState, .running: return BarTokens.stateRunning
        case .error: return BarTokens.stateError
        case .stale: return BarTokens.stateStale
        }
    }

    /// True when the menu bar is currently dark.
    ///
    /// `bestMatch` rather than `name == .darkAqua`: the menu bar can be a
    /// vibrant variant (`vibrantDark`, `accessibilityHighContrastDarkAqua`),
    /// and comparing the name would misclassify those.
    private var menuBarIsDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The separator rule's colour: white 20% on a dark menu bar, black 12% on
    /// a light one (VISUAL_SPEC §7.3). Resolved at draw time because the menu
    /// bar's appearance can change without the app's.
    private func separatorColor() -> CGColor {
        barCGColor(menuBarIsDark ? BarTokens.separator : StatusItemView.separatorLight)
    }

    /// `#1F000000`: the light-menu-bar separator. Not a frozen `bar/*` token —
    /// it is the macOS-only counterpart of `bar/separator`, kept private so the
    /// three-way token list stays untouched.
    private static let separatorLight: UInt32 = 0x1F00_0000

    // MARK: layout

    /// One laid-out span: its measured size, and its Core Text line once built.
    private struct Item {
        var span: BarSpan
        /// The line drawn. Truncation replaces it with a shorter one.
        var line: CTLine?
        /// The untruncated line. Every truncation starts from this, so a line is
        /// never cut twice.
        var sourceLine: CTLine?
        var image: NSImage?
        /// Width the span wants with no truncation.
        var naturalWidth: CGFloat
        /// Width it is allowed to occupy; == naturalWidth unless truncated.
        var maxWidth: CGFloat
        /// Height of the drawn content (text block, or the icon box).
        var height: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        /// Which line the span sits on: 0 for the first, 1 for the second. Two-line
        /// mode only; a third line is joined onto the second.
        var lineIndex: Int = 0
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

    /// The x the first span starts at: the horizontal padding alone.
    ///
    /// There is no left state stripe any more (§7.2 moved the state cue to the
    /// bottom edge), so the content is not inset past one. The Dart preview
    /// strip still reserves `stateStripWidth + padHorizontal`; native/mac/
    /// README.md records that difference until the Dart side catches up.
    private var contentOriginX: CGFloat { metrics.padHorizontal }

    /// Two-line mode is on when a `newline` span is followed by visible content.
    /// A trailing `font("\n")` with nothing after it draws nothing, so it must not
    /// shrink a single-line script to the two-line size.
    private var isTwoLine: Bool {
        guard let breakIndex = spans.firstIndex(where: { $0.newline }) else { return false }
        return spans[breakIndex...].contains { span in
            if span.isImage { return !span.text.isEmpty }
            return !span.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The height content is laid out in: the view's own height. Falls back to
    /// the 24 pt metric before the view has a frame, so measuring and drawing
    /// agree on the two-line grid.
    private var barHeight: CGFloat { bounds.height > 1 ? bounds.height : metrics.height }

    /// Height of one line's band in two-line mode: the bar less the 1 pt edges,
    /// split in two. 11 pt on a 24 pt bar.
    private var twoLineBandHeight: CGFloat { (barHeight - 2 * metrics.twoLineEdge) / 2 }

    /// Font size of a two-line cell (see `BarMetrics` for the numbers): the
    /// smaller of the size that fits a band at the line pitch and a fraction of
    /// the bar, rounded down to a half point. 9.5 pt on a 24 pt bar.
    private var twoLineGridSize: CGFloat {
        let fit = twoLineBandHeight / metrics.lineHeightFactor
        let fraction = barHeight * metrics.twoLineFontFraction
        return (min(fit, fraction) * 2).rounded(.down) / 2
    }

    /// Baselines of the top and bottom lines, measured up from the view's bottom
    /// edge. The block (top line's cap height to bottom baseline) is centred on
    /// the bar, so the optical centre is the bar's centre. The pitch is
    /// `lineHeightFactor` x the grid size. Both are snapped to the device pixel
    /// grid, so the glyphs do not land on half pixels at @2x.
    private func twoLineBaselines() -> (top: CGFloat, bottom: CGFloat) {
        let grid = twoLineGridSize
        let pitch = grid * metrics.lineHeightFactor
        let cap = CTFontGetCapHeight(font(size: grid, tabular: true))
        let bottom = pixelAligned(barHeight / 2 - (pitch + cap) / 2)
        return (top: pixelAligned(bottom + pitch), bottom: bottom)
    }

    /// Rounds a point value to the nearest device pixel. The scale comes from the
    /// window when there is one; @2x is the fallback before the view is in a window.
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
    }

    /// How much horizontal room the spans have.
    private func contentWidthLimit(_ total: CGFloat) -> CGFloat {
        max(0, total - contentOriginX - metrics.padHorizontal)
    }

    /// Lines the layout uses: two in two-line mode, one otherwise.
    private var lineCount: Int { isTwoLine ? metrics.maxLines : 1 }

    /// Width the content needs when nothing is truncated: the widest line.
    ///
    /// Spans are placed from `contentOriginX` with gaps/separators between
    /// consecutive items. The arithmetic matches `layout`'s cursor arithmetic
    /// exactly so measured width and drawn bounds never disagree.
    private func requiredWidth(_ items: [Item]) -> CGFloat {
        let content = (0..<lineCount).map { contentLineWidth(items, line: $0) }.max() ?? 0
        guard content > 0 else { return 0 }
        return contentOriginX + content + metrics.padHorizontal
    }

    /// Width of one flow of spans: each span's width, plus the gap before every
    /// span after the first. Dropped and empty spans take no room.
    private func flowWidth(_ items: [Item]) -> CGFloat {
        let separatorAdvance = style.showSeparators
            ? metrics.separatorGap * 2 + metrics.separatorWidth
            : 0

        var total: CGFloat = 0
        var sawItem = false
        for item in items {
            let width = item.effectiveWidth
            guard width > 0 else { continue }
            if sawItem { total += item.gapBefore > 0 ? item.gapBefore : separatorAdvance }
            total += width
            sawItem = true
        }
        return total
    }

    /// Width one line needs. Single-line mode is one flow. Two-line mode is the
    /// left run, then the column gap (only when both runs have content), then the
    /// right run.
    private func contentLineWidth(_ items: [Item], line: Int) -> CGFloat {
        guard isTwoLine else { return flowWidth(items) }
        let row = items.filter { $0.lineIndex == line }
        let left = flowWidth(row.filter { $0.span.align != .right })
        let right = flowWidth(row.filter { $0.span.align == .right })
        return left + (left > 0 && right > 0 ? metrics.columnGap : 0) + right
    }

    /// Build the span list for the menu bar.
    ///
    /// Single-line mode (no `newline` span): spans keep source order, as before.
    /// Two-line mode: each `newline` span moves the following spans to line 2.
    /// A newline span that carries text starts line 2 with that text, which is
    /// how the Dart preview reads it. Dropping the text would lose content. A
    /// third line is joined onto line 2, so no content is lost.
    private func buildItems() -> [Item] {
        var items: [Item] = []
        var previousWasImage = false
        var afterLineBreak = false
        var currentLine = 0
        // Single-line mode keeps every span on line 0, as it always has. Only a
        // two-line strip has a second line to move to.
        let twoLine = isTwoLine
        func breakLine() {
            afterLineBreak = true
            if twoLine { currentLine = min(currentLine + 1, metrics.maxLines - 1) }
        }

        for span in spans {
            if span.newline {
                breakLine()
            }

            // A pure line break carries no drawable text. A bare "\n" span already
            // advanced the line above, so only a whitespace span with an embedded
            // newline and no flag needs to advance here.
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !span.isImage && trimmed.isEmpty && (span.newline || span.text.contains("\n")) {
                if !span.newline { breakLine() }
                continue
            }

            // Sanitize any embedded newlines into single spaces for Core Text rendering.
            var effectiveSpan = span
            if !span.isImage && span.text.contains("\n") {
                effectiveSpan.text = span.text.replacingOccurrences(of: "\n", with: " ")
            }

            var item = Item(
                span: effectiveSpan,
                line: nil,
                image: nil,
                naturalWidth: 0,
                maxWidth: 0,
                height: 0,
                ascent: 0,
                descent: 0
            )

            // Spacing before this item:
            // 1. If right after an image on the same line, use the 4 pt icon-to-text gap.
            // 2. If right after a line break or between segments, use standard separator advance (gapBefore = 0).
            if previousWasImage && !afterLineBreak {
                item.gapBefore = metrics.iconTextGap
            } else {
                item.gapBefore = 0
            }
            afterLineBreak = false
            item.lineIndex = currentLine

            if effectiveSpan.isImage {
                guard !effectiveSpan.text.isEmpty else { continue }
                let image = BarIconCache.shared.image(for: effectiveSpan.text)
                var w = effectiveSpan.imageWidth > 0 ? CGFloat(effectiveSpan.imageWidth) : metrics.iconSize
                var h = effectiveSpan.imageHeight > 0 ? CGFloat(effectiveSpan.imageHeight) : metrics.iconSize
                // An icon cannot be taller than the band its line gets, or it would
                // run into the other line. Scale it down, keeping its aspect ratio.
                if isTwoLine, h > twoLineBandHeight {
                    w *= twoLineBandHeight / h
                    h = twoLineBandHeight
                }
                item.image = image
                item.naturalWidth = w
                item.maxWidth = w
                item.height = h
                items.append(item)
                previousWasImage = true
                continue
            }

            guard !effectiveSpan.text.isEmpty else { continue }
            let font = font(for: effectiveSpan)
            guard let line = makeLine(effectiveSpan.text, font: font, color: textColor(effectiveSpan)) else {
                continue
            }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            item.line = line
            item.sourceLine = line
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
        // Each line is cut on its own, so a long line 2 never shortens line 1.
        for line in 0..<lineCount {
            truncateLine(&items, line: line, available: available)
        }
    }

    /// Truncates one line until its content fits `available`.
    ///
    /// Each pass either shrinks a span's allowance (strictly decreasing the line's
    /// width) or drops one (strictly reducing the span count), so the loop
    /// terminates. The counter is belt and braces against a rounding edge case
    /// where a shrink is a no-op.
    private func truncateLine(_ items: inout [Item], line: Int, available: CGFloat) {
        var guardCounter = items.count * 2 + 2
        while guardCounter > 0 {
            guardCounter -= 1

            let excess = contentLineWidth(items, line: line) - available
            if excess <= 0 { break }

            guard let index = items.lastIndex(where: {
                $0.isText && !$0.dropped && $0.lineIndex == line
            }) else {
                break
            }
            let current = items[index].maxWidth

            // The token alone needs some room; below that the span is better
            // dropped entirely than reduced to a bare ellipsis.
            let tokenWidth = ellipsisWidth(items[index])
            if current - excess >= tokenWidth + 2 {
                // Never take the span below the ellipsis. `current` is the width the
                // line really has, so the budget comes off the drawn width.
                let allowed = max(tokenWidth, current - excess)
                if allowed < current {
                    if let truncated = makeTruncatedLine(items[index], width: allowed) {
                        items[index].line = truncated
                        // The strip is laid out from the width the line really has.
                        // `allowed` is a budget, and Core Text can land a little under it.
                        items[index].maxWidth = CGFloat(CTLineGetTypographicBounds(truncated, nil, nil, nil))
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

    /// Position the items. Single-line content flows left to right; two-line
    /// content is split into two columns per line (see `layoutTwoLine`).
    private func layout(_ items: [Item], in bounds: CGRect) -> LayoutResult {
        isTwoLine ? layoutTwoLine(items, in: bounds) : layoutSingleLine(items, in: bounds)
    }

    /// Single-line layout: all spans flow sequentially from left to right in
    /// source order. Explicit alignment is ignored on this path.
    ///
    /// A separator is drawn before each span (except after an icon, where the 4 pt
    /// icon-to-text gap is used instead). Layout coordinates mirror `requiredWidth`
    /// exactly so the strip's physical width perfectly bounds its placed content.
    private func layoutSingleLine(_ items: [Item], in bounds: CGRect) -> LayoutResult {
        var result = LayoutResult()
        guard !items.isEmpty else { return result }

        let h = bounds.height
        var leftX = contentOriginX

        let separatorAdvance = style.showSeparators
            ? metrics.separatorGap * 2 + metrics.separatorWidth
            : 0

        var sawItemOnLine = false

        // Optical baseline calculation:
        // The baseline puts the reference cap height (SF Pro 13) centred on the bar,
        // so it tracks the bar height instead of a fixed 7.5 pt, and a taller notched
        // bar stays centred. It is then snapped to the device pixel grid.
        // To prevent mixed font sizes (e.g. 13 pt + 10 pt in net_monitor) from
        // jumping vertically, all text runs in the strip share this single baseline.
        var maxAscent: CGFloat = 0
        var maxDescent: CGFloat = 0
        for item in items where !item.dropped && item.isText {
            maxAscent = max(maxAscent, item.ascent)
            maxDescent = max(maxDescent, item.descent)
        }

        let referenceCap = CTFontGetCapHeight(font(size: CGFloat(metrics.labelSize), tabular: false))
        var sharedBaseline = pixelAligned((h - referenceCap) / 2)
        if maxAscent > 0 {
            if maxAscent + sharedBaseline > h - 0.5 {
                sharedBaseline = min(sharedBaseline, h - maxAscent - 0.5)
            }
            if sharedBaseline - maxDescent < 0.5 {
                sharedBaseline = max(sharedBaseline, maxDescent + 0.5)
            }
        }

        for item in items where !item.dropped {
            let width = item.effectiveWidth
            guard width > 0 else { continue }

            let gap = item.gapBefore > 0 ? item.gapBefore : separatorAdvance
            if sawItemOnLine {
                leftX += gap
            }
            let x = leftX

            // Separator before this span: only for spans after the first on the
            // line, and only when an icon-to-text gap is not already standing there.
            // Coordinates are rounded to integer points for Retina pixel crispness.
            if style.showSeparators && sawItemOnLine && item.gapBefore == 0 {
                let sepX = (x - (metrics.separatorGap + metrics.separatorWidth)).rounded()
                result.separators.append(CGRect(
                    x: sepX,
                    y: ((h - metrics.separatorHeight) / 2).rounded(),
                    width: metrics.separatorWidth,
                    height: metrics.separatorHeight
                ))
            }

            // Vertical placement: an icon sits on the centre line;
            // all text items share the unified optical baseline.
            let baseline: CGFloat
            let rect: CGRect
            if item.image != nil {
                let iconY = ((h - item.height) / 2).rounded()
                rect = CGRect(x: x, y: iconY, width: width, height: item.height)
                baseline = rect.minY
            } else {
                baseline = sharedBaseline
                rect = CGRect(x: x, y: sharedBaseline - item.descent, width: width, height: item.height)
            }

            result.placed.append(Placed(item: item, rect: rect, baseline: baseline, line: item.line))
            leftX += width
            sawItemOnLine = true
        }

        return result
    }

    /// Two-line layout. Line 0 is drawn on top, line 1 below. Each line has its
    /// own shared baseline, and mixed sizes within a line share it.
    ///
    /// Per line, left-aligned spans flow from the left edge and right-aligned spans
    /// pack against the right edge, so the two lines form columns. A right run
    /// keeps source order. Its spans are placed left to right, so the run's start
    /// depends only on its total width. No separator sits between a left run and
    /// its right run; `columnGap` does that job. Separators inside a run follow the
    /// single-line rule, and are sized to the line's cap height so they stay inside
    /// their line.
    private func layoutTwoLine(_ items: [Item], in bounds: CGRect) -> LayoutResult {
        var result = LayoutResult()
        guard !items.isEmpty else { return result }

        let baselines = twoLineBaselines()
        let cap = CTFontGetCapHeight(font(size: twoLineGridSize, tabular: true))
        let separatorAdvance = style.showSeparators
            ? metrics.separatorGap * 2 + metrics.separatorWidth
            : 0
        let separatorHeight = min(metrics.separatorHeight, cap + 2)
        let rightEdge = bounds.width - metrics.padHorizontal

        for line in 0..<lineCount {
            let row = items.filter { !$0.dropped && $0.lineIndex == line && $0.effectiveWidth > 0 }
            let baseline = line == 0 ? baselines.top : baselines.bottom
            let centreY = baseline + cap / 2

            // Places one run from `startX`, with the gap and separator rules of the
            // single-line flow. Returns nothing: the run owns its own width.
            func place(_ run: [Item], startX: CGFloat) {
                var x = startX
                var sawItem = false
                for item in run {
                    let width = item.effectiveWidth
                    guard width > 0 else { continue }

                    let gap = item.gapBefore > 0 ? item.gapBefore : separatorAdvance
                    if sawItem { x += gap }

                    // Separator: only between two spans of the same run, and only
                    // when an icon-to-text gap is not standing there.
                    if style.showSeparators && sawItem && item.gapBefore == 0 {
                        let sepX = (x - (metrics.separatorGap + metrics.separatorWidth)).rounded()
                        result.separators.append(CGRect(
                            x: sepX,
                            y: (centreY - separatorHeight / 2).rounded(),
                            width: metrics.separatorWidth,
                            height: separatorHeight
                        ))
                    }

                    let rect: CGRect
                    if item.image != nil {
                        // An icon is centred on the line's cap centre, but its bottom
                        // edge may not dip into the state indicator (top edge at
                        // y 2.5): it is lifted to clear it by 1 pt.
                        let indicatorTop = metrics.twoLineStateIndicatorY + metrics.twoLineStateIndicatorHeight
                        let iconY = max((centreY - item.height / 2).rounded(), indicatorTop + 1)
                        rect = CGRect(x: x, y: iconY, width: width, height: item.height)
                        result.placed.append(Placed(item: item, rect: rect, baseline: rect.minY, line: nil))
                    } else {
                        rect = CGRect(x: x, y: baseline - item.descent, width: width, height: item.height)
                        result.placed.append(Placed(item: item, rect: rect, baseline: baseline, line: item.line))
                    }

                    x += width
                    sawItem = true
                }
            }

            let leftRun = row.filter { $0.span.align != .right }
            let rightRun = row.filter { $0.span.align == .right }

            place(leftRun, startX: contentOriginX)
            place(rightRun, startX: rightEdge - flowWidth(rightRun))
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
        // The Dart controller sends the Windows default (9 pt) when the config
        // has no font size. On macOS that means "use the menu-bar size", not a
        // literal 9 pt: next to the system clock, 9 pt reads as a foreign,
        // shrunken strip (VISUAL_SPEC §7.1).
        if size == metrics.windowsDefaultFontSize {
            size = metrics.labelSize
        }
        if isTwoLine {
            // Two-line cells: the script's size, floored at 8 pt and capped at the
            // grid size so both lines fit the bar. The 8 pt floor is below the
            // single-line 10 pt floor because density is the point of this mode.
            let cell = min(twoLineGridSize, max(metrics.twoLineMinFontSize, CGFloat(size)))
            return font(size: cell, tabular: span.tabular)
        }
        size = min(metrics.maxFontSize, max(metrics.minFontSize, size))
        return font(size: CGFloat(size), tabular: span.tabular)
    }

    /// The system font at a point size, cached by size and figure style.
    private func font(size: CGFloat, tabular: Bool) -> CTFont {
        let key = "\(size)|\(tabular ? 1 : 0)"
        if let hit = fonts[key] { return hit }

        // The bar uses the SYSTEM font (SF Pro), never Inter — forcing Inter
        // onto the menu bar would make TaskPin's strip visibly foreign next to
        // every other status item.
        //
        // `as CTFont` is an explicit toll-free bridge: NSFont and CTFont are the
        // same object, but Swift will not implicitly convert between them.
        let base = tabular
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size)
        let font: CTFont = base as CTFont
        fonts[key] = font
        return font
    }

    /// The colour a span's text is drawn in.
    ///
    /// A span that did not set a colour uses the SYSTEM menu-bar text colour,
    /// not the frozen `bar/value`: the bar has to be legible on both a light
    /// and a dark menu bar, and only the system colour follows that switch
    /// (VISUAL_SPEC §7.1). Script-specified span colours are used as-is.
    ///
    /// Resolved at draw time, against this view's `effectiveAppearance` (the
    /// status button's, not the app's). `viewDidChangeEffectiveAppearance`
    /// schedules a repaint when the menu bar switches.
    private func textColor(_ span: BarSpan) -> CGColor {
        span.color == BarTokens.useDefault ? systemTextColor() : barCGColor(span.color)
    }

    /// `NSColor.labelColor` resolved against the menu bar's appearance.
    ///
    /// `performAsCurrentDrawingAppearance` is the supported way to resolve a
    /// semantic NSColor: `cgColor` alone would resolve against whatever
    /// appearance happens to be current, which is not necessarily the status
    /// item's (the app can be light while the menu bar is dark).
    private func systemTextColor() -> CGColor {
        systemColor(.labelColor)
    }

    /// `NSColor.secondaryLabelColor` resolved against the menu bar's appearance.
    private func systemSecondaryColor() -> CGColor {
        systemColor(.secondaryLabelColor)
    }

    /// Resolves a semantic colour for the status button's appearance. See
    /// `systemTextColor` for why this is not a plain `cgColor` read.
    private func systemColor(_ color: NSColor) -> CGColor {
        var resolved: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved ?? color.cgColor
    }

    private func makeLine(_ text: String, font: CTFont, color: CGColor) -> CTLine? {
        let attributes: [String: Any] = [
            kCTFontAttributeName as String: font,
            kCTForegroundColorAttributeName as String: color,
        ]
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            attributes as CFDictionary
        ) else { return nil }
        return CTLineCreateWithAttributedString(attributed)
    }

    /// Re-cut an item's untruncated line to `width`, ending in an ellipsis.
    ///
    /// Always cuts from `sourceLine`: cutting an already-cut line would lose the
    /// ellipsis and give a different result on each pass.
    private func makeTruncatedLine(_ item: Item, width: CGFloat) -> CTLine? {
        guard let line = item.sourceLine else { return nil }
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
            ctx.setFillColor(iconTintColor())
            ctx.fill(rect)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        } else {
            ctx.draw(cg, in: rect)
        }
    }

    /// The tint for a monochrome icon. A script that set an explicit `icon`
    /// colour gets it as-is. The default follows the menu bar's secondary label
    /// colour, the same way text follows `labelColor`. The frozen `bar/icon`
    /// (#A2ACBA) is a dark-theme value, about 2.3:1 on a light menu bar.
    private func iconTintColor() -> CGColor {
        style.icon == BarTokens.useDefault ? systemSecondaryColor() : barCGColor(style.icon)
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
        // A press that dragged off the item must not leave the system
        // highlight stuck on.
        (superview as? NSButton)?.highlight(false)
    }

    /// The menu bar switched light/dark (or the item moved to a display with a
    /// different appearance). The system text and separator colours are
    /// resolved at draw time, so a repaint is all that is needed.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        // Drive the NSStatusBarButton's own highlight rather than painting a
        // rounded fill ourselves (VISUAL_SPEC §7.1 "系统高亮"). Not calling
        // super keeps the button's tracking loop from consuming the matching
        // mouseUp, which is what fires `onClick`.
        (superview as? NSButton)?.highlight(true)
    }

    override func mouseUp(with event: NSEvent) {
        (superview as? NSButton)?.highlight(false)
        // A press released outside the item was a drag-out, not a click. Without
        // this check the strip would open its popover or run its action anyway.
        let inside = convert(event.locationInWindow, from: nil)
        guard bounds.contains(inside) else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        (superview as? NSButton)?.highlight(true)
    }

    override func rightMouseUp(with event: NSEvent) {
        (superview as? NSButton)?.highlight(false)
        // `event.locationInWindow` is in window coordinates; the plugin needs
        // screen coordinates to place an NSMenu.
        let inWindow = event.locationInWindow
        let onScreen = window?.convertPoint(toScreen: inWindow) ?? inWindow
        onContextMenu?(onScreen)
    }

    override func scrollWheel(with event: NSEvent) {
        // The script turned scrolling off: pass the event up rather than resize.
        guard style.scrollEnabled else {
            super.scrollWheel(with: event)
            return
        }
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
