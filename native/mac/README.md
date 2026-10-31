# `native/mac` — TaskPin's native macOS menu-bar bar (Phase 8)

The macOS counterpart to `native/win`. Same job, different shell: render a
pinned item's full span list into the menu bar, drive it over the `taskpin/bar`
MethodChannel, and open a Flutter-hosted popover on click.

Flutter **cannot** render into an `NSStatusItem` — the status-bar button is a
system-owned layer-backed `NSView`, and Flutter needs its own `NSWindow`/`NSView`
+ Metal layer + `FlutterViewController`. So, mirroring Windows: a native status
item with a custom `NSView` drawn with Core Text, and the *same* channel contract
so the Dart `BarController` stays platform-agnostic
(`docs/FLUTTER_REWRITE_PLAN.md`, "macOS 菜单栏条").

## ⚠️ NOTHING HERE HAS BEEN BUILT OR RUN

There is no `FlutterMacOS` SDK on the development machine (no Flutter install
here at all), so the files that import it — `StatusItemPlugin.swift`,
`PopoverHost.swift`, `DialogWindowStyles.swift` — are **uncompiled and unrun**.
`StatusItemView.swift` imports only AppKit/Core Text and is typechecked with
`xcrun swiftc -typecheck` (see below); it has still never been run inside a
menu bar. Treat the whole directory as a careful draft to be built and debugged
on a Mac or in CI, not as working code.

What *has* been verified on this machine:

| Check | How | Result |
|---|---|---|
| `StatusItemView.swift` typechecks | `xcrun swiftc -typecheck -target arm64-apple-macos12.0` | **passes** |
| Frozen token names + values match C++ and Dart | text parse of all three files, 10/10 tokens compared | **agree** |
| Bracket balance of all four `.swift` files | string/comment-stripped brace count | balanced |
| AppKit/Core Text API spellings | read against the AppKit API and `desktop_multi_window`'s own macOS sources | see risk list |
| Dart-side contract | read against `bar_controller.dart` / `bar_channel.dart` | matches (with the key aliases below) |

`StatusItemPlugin.swift` still cannot be typechecked here: it imports
`FlutterMacOS` and `PopoverHost.swift`, and no `FlutterMacOS.framework` exists
on this machine. Its changes are reviewed by hand; the full integrated build is
the first real check.

## Files

| File | Role |
|---|---|
| `StatusItemView.swift` | The `NSView`: span model, frozen tokens, metrics, Core Text renderer, icon cache, hit testing |
| `StatusItemPlugin.swift` | The `taskpin/bar` `FlutterMethodChannel` handler; owns one `NSStatusItem` per bar |
| `PopoverHost.swift` | The `NSPopover` + `FlutterViewController` behind a click |
| `DialogWindowStyles.swift` | The Phase 6 `taskpin/window` handler (written earlier, unchanged) |
| `taskpin_bar.podspec` | Compiles all four into the Runner target |

## The `taskpin/bar` channel contract

Reconcile this against `native/win/taskpin_bar_plugin.cpp` (the Windows half) and
the Dart `BarController`. **The Windows half did not exist on disk when this was
written**, so the contract below is the one the plan specifies
(`docs/FLUTTER_REWRITE_PLAN.md:216`) plus what the Windows *module* already does
(`native/win/bar_window.cpp` `OnWheel`, `ShowContextMenu`), not a diff against
the Windows plugin's source.

Channel name: `taskpin/bar`.

### Dart → native

| Method | Arguments | Notes |
|---|---|---|
| `setSpans` | `barId:int`, `spans:List<Map>`, `state?:string\|int`, `tabular?:bool` | Creates the status item on first call. Caps at 32 spans (`kMaxSpans`). |
| `setGeometry` | `barId:int`, `width:int`, `x?:int` | `width > 0` = explicit (clamped 40–600); `<= 0` = size to content. **`x` is ignored** — the menu bar places its own items. |
| `setStyle` | `barId:int`, `bg?`, `bgHover?`, `label?`, `value?`, `icon?` (colour strings), `fontSize?:int`, `state?`, `scrollEnabled?:bool`, `showSeparators?:bool` | Every field optional; absent leaves the current value. |
| `showPopover` | `barId:int`, `spec:Map` | Opens/updates the popover. `spec` is `DialogSpec.toJson()`'s shape. |
| `hidePopover` | `barId:int` | |
| `showContextMenu` | `barId:int`, `items:List<{title,tag}>` | Native presents an `NSMenu` at the last right-click point. |
| `remove` | `barId:int` | Destroys the status item and its popover. |
| `removeAll` | — | |

### native → Dart (`channel.invokeMethod`)

| Event | Arguments |
|---|---|
| `onClick` | `barId:int`, `button:"left"` |
| `onWheel` | `barId:int`, `delta:int` (±120 per notch, the Windows unit), `shift:bool`, `width:int` (post-clamp) |
| `onContextMenu` | `barId:int` |
| `onHoverChange` | `barId:int`, `hovered:bool` |
| `onContextMenuSelection` | `tag:int` — which menu item was picked |
| `onPopoverClosed` | `barId:int` — the popover dismissed itself (outside click / Escape) |

### Span payload keys

`text`, `color`, `size` (`0` = default), `align` (`0` left / `1` right / `2`
center), `newline`, `image`, `img_w`, `img_h`, plus the optional `tabular`.

**Colour is a number, not a string.** The Dart controller serialises
`TpBarSpan.color.toARGB32()` and `BarStyleSpec`'s colours as 32-bit ints, and
the standard method codec delivers them as `NSNumber`. The renderer accepts
both the numeric ARGB form and the older `"#RRGGBB"` / `"AARRGGBB"` string
form; a colour it cannot parse means "use the default".

The short key names above are what `spanToWire` in
`lib/core/bar/bar_channel.dart` actually sends. The older contract documented
`fontSize` / `isImage` / `imageWidth` / `imageHeight` (the Dart model's
camelCase names). `BarSpan.from` accepts **both** spellings, so a Windows
plugin that emits either shape keeps working. The channel contract itself is
unchanged.

### State value

`state` accepts either a string (`"running"` / `"error"` / `"stale"`, the Dart
`TpBarState` names) or the C++ `ItemState` int (0 none / 1 running / 2 error /
3 stale).

**This is a real hazard, flagged rather than papered over.** The two enums have
the same four members and disagree on every value:

| Concept | `taskpin::bar::ItemState` (C++) | `TpBarState` (Dart) |
|---|---|---|
| none / — | `StateNone = 0` | — |
| running | `StateRunning = 1` | `running = 0` |
| error | `StateError = 2` | `error = 1` |
| stale | `StateStale = 3` | `stale = 2` |
| loading | — | `loading = 3` |

A bare `3` means "stale" to C++ and "loading" to Dart. The string form is
unambiguous and is what the Dart side should send; the int form is accepted only
so a C++-shaped payload does not silently mis-colour the bottom state
indicator. In practice the Dart controller sends `BarItemState.wireValue`,
which uses the C++ numbering, so the int path is the one in use.

## The pod decision

`macos/Runner.xcodeproj/project.pbxproj` was **not** hand-edited. Instead
`macos/Podfile` gains one line:

```ruby
pod 'taskpin_bar', :path => '../native/mac'
```

Why (the full argument is in `taskpin_bar.podspec`'s header):

- A hand-edit means inventing four 24-hex-digit object IDs that must not collide
  with the ~700 lines already in the file, plus three `PBXBuildFile` entries,
  three `PBXFileReference` entries, and insertions into the Runner group and the
  Runner target's `PBXSourcesBuildPhase`. Get it wrong and Xcode refuses to open
  the project, or a file is silently dropped from the compile — and a pbxproj
  diff is unreadable, so nobody catches it in review.
- `flutter build macos` already runs `pod install` on this template, so the
  Podfile line is the *whole* wiring, regenerated by the tool that owns that job.
- The podspec globs `*.swift`, so adding a file to `native/mac/` needs no build
  change at all.

The one thing CocoaPods cannot do is *register* the plugin, because
`macos/Flutter/GeneratedPluginRegistrant.swift` is generated and must not be
hand-edited. That is one line in `macos/Runner/MainFlutterWindow.swift`:

```swift
TaskpinBarPluginRegistrar.register(
  with: flutterViewController.registrar(forPlugin: "TaskpinBarPlugin")
)
```

### First `pod install` on a Mac

`pod install` will fail with `Unable to find a specification for taskpin_bar` if
it cannot see the podspec. Check that `native/mac/taskpin_bar.podspec` exists and
that the Podfile's `:path => '../native/mac'` resolves relative to
`macos/Podfile` — it should, `../native/mac` from `macos/` is the repo's
`native/mac`.

## Deliberate divergences from the Windows renderer

These are choices, not oversights. Each is a candidate for reconciliation.

1. **Icon fetching is asynchronous.** `native/win/bar_image.cpp` fetches `http(s)`
   sources synchronously inside the paint pass. On macOS the paint pass is the
   main thread and the main thread draws the menu bar, so a blocking fetch would
   beachball the whole system UI. Network icons load on a background queue and
   post `.barIconDidLoad`. `data:` URIs and local files stay synchronous.
2. **Animated GIFs do not animate.** One frame only. Windows drives an 80 ms
   invalidation timer (`kAnimInterval`); reproducing that here means a repeating
   `Timer` on the main thread per animated bar, which was not worth adding
   unbuilt. **Known gap.**
3. **No marquee.** Windows scrolls long content (2 px / 50 ms, wraps at
   `text_width + 40`). The plan says macOS truncates with an ellipsis instead
   ("macOS 末尾省略号截断"), so this is per spec — but it means a long script
   result is *unreadable in full* on macOS, where Windows eventually shows it.
4. **Shift+wheel does nothing.** Windows moves the bar's X within the taskbar.
   The menu bar places its own items; `x` comes back as `-1`, the same "auto"
   sentinel `bar_x` uses in config.json.
5. **No font weight distinction.** `TpBarTypography` gives values weight 500 and
   labels 400. Weight selection would need a per-span weight on the wire, which
   the ABI does not carry. The bar therefore distinguishes labels from values by
   colour — and on macOS an *uncoloured* span uses the system menu-bar colour
   (item 8), not `bar/label` / `bar/value`.
6. **Icon-to-text gap.** VISUAL_SPEC §9.2 gives macOS a 4 pt gap where Windows
   has 6. Implemented via `metrics.iconTextGap`, and a text span right after an
   icon gets that gap *instead of* a separator (VISUAL_SPEC §9.5 rule 1: the text
   an icon introduces is the same segment).
7. **Transparent by default.** VISUAL_SPEC §7.1: `bar/bg` is never painted.
   The Dart controller sends `0xFFFFFFFF` (`kFollowTaskbarArgb`) when the user
   has not chosen a colour, and that sentinel maps to "draw no background", so
   the menu bar shows through. A user-set `bar_bg_color` is drawn as the rounded
   fill, alpha included.
8. **System text and separator colours.** An uncoloured span resolves
   `NSColor.labelColor` against the status button's `effectiveAppearance` at
   draw time; script-specified span colours are used as-is. The separator uses
   `bar/separator` (`#33FFFFFF`) on a dark menu bar and `#1F000000` on a light
   one (VISUAL_SPEC §7.3). `viewDidChangeEffectiveAppearance` repaints on a
   light/dark switch, because the menu bar can differ from the app's appearance.
9. **Bottom state indicator, not the left stripe.** VISUAL_SPEC §7.2: stale and
   error draw a bottom-centred 16 x 3 rounded bar (`status/caution` /
   `status/critical`); a healthy item draws nothing. The old 2 pt full-height
   left stripe is gone. Positioned at y = 1.0 pt with integer-point coordinates
   so the bottom pill radius is fully preserved and pixel-crisp on Retina.
   The Dart preview still draws the stripe — a divergence for the Dart lane to close.
10. **Hover uses the system highlight.** No `bar/bgHover` fill or `bar/hairline`
    is painted; the view is transparent and drives the `NSStatusBarButton`'s own
    `highlight(_:)` from `mouseDown` / `mouseUp` (VISUAL_SPEC §7.1 "系统高亮").
    The two tokens stay frozen for Windows, where a taskbar segment has no
    system highlight of its own.
11. **Font size 13, not 9, with 10 pt legible floor.** VISUAL_SPEC §7.1 gives
    macOS SF Pro 13. The Dart controller sends `kBarDefaultFontSize` (9) when
    the config has no opinion; the renderer treats 9 as "unspecified" and draws
    13 instead. Furthermore, tiny font sizes (such as size 4 authored for Windows
    two-line layouts or size 8 for secondary badges) are clamped to a legible floor
    of 10 pt (`minFontSize`), sitting between Apple's 9 pt mini and 11 pt small
    system fonts so scripts like `zeeho.lua` remain glanceable without squinting.
12. **Menu-bar order is deterministic.** `NSStatusBar` inserts each new status
    item to the LEFT of the existing ones, so creating bars in config order
    displays them reversed. The plugin recreates the system items from the
    highest bar id down, giving left-to-right = ascending bar id (config order).
    Views are reused, so content and callbacks survive. `autosaveName` is
    deliberately not set: a persisted ⌘-drag position would fight the config
    order, and there is no API to reorder the other items around it.
13. **Two-line script horizontal joining and left-to-right flow.** The macOS menu bar is
    24 pt tall: ONE line only (VISUAL_SPEC §7.1). Rather than silently dropping
    line 2 and losing critical information (e.g. tire pressure in `zeeho.lua`),
    multi-line spans are joined horizontally with segment spacing, and embedded
    newlines are sanitized to spaces. Explicit alignment attributes (e.g. `align: right`,
    authored for two-line Windows taskbar layouts) are ignored on the single-line menu bar;
    all spans flow sequentially from left to right in source order so items pack
    naturally without gaping empty voids. If the joined content exceeds the strip width,
    `truncateToFit` cleanly ellipsis-truncates (`…`) from the rightmost span.
14. **Strip width matches content; explicit width is an upper cap.** Strips are
    auto-sized to their content (`requiredWidth()`) so no blank space is left at the end.
    Configured `bar_width` (such as Windows `375`) acts as an upper bound rather than
    inflating the menu-bar item.
15. **Optical baseline alignment.** Mixed font sizes within a strip share a
    single optical baseline (7.5 pt from bottom for standard menu-bar fonts,
    adjusted gracefully for oversized fonts). This prevents secondary badges
    (e.g. `[27]` in `net_monitor.lua`) from jumping vertically and aligns
    text optically with the macOS system clock.
16. **Width hysteresis for auto-sized strips.** Dynamic numerical scripts
    (e.g. bandwidth monitors) expand immediately on growth so content never
    clips, but apply a 4 pt hysteresis buffer on minor contractions to absorb
    single-character and punctuation fluctuations, eliminating menu-bar jitter.

## Known value disagreements in others' files (not changed here)

Reported, not fixed — these are outside this lane:

1. **`fontSize` default.** `taskpin::bar::BarStyle::font_size = 9`
   (`native/win/bar_types.h`), `kBarDefaultFontSize = 9` (Dart controller) vs
   `TpBarTypography.labelSize = 11` (`bar_tokens.dart`) and VISUAL_SPEC §7.1
   (macOS SF Pro 13). This file maps the 9 sentinel to 13 and honours any other
   value; the Dart preview draws 11. All three should eventually agree per
   platform.
2. **Separator geometry.** VISUAL_SPEC §7.3 says 1×14 with 6 pt either side.
   This renderer uses that. `TpBarMetrics.macOS` still says 1×12 gap 4, so the
   Dart preview and the menu bar disagree until the Dart lane catches up.
3. **`bar/bg` alpha sentinel.** `native/win/bar_types.h`'s `WantsLayered()` uses
   `bgAlpha < 255` to pick the layered-window path, and
   `BarStyle::bg` defaults to `kColorBg` (opaque). But `lib/config.c`'s
   "use the default" sentinel is `0xFFFFFFFF`, which is also alpha 255 — so an
   item that explicitly wants *fully transparent* cannot express it through
   `bar_bg_color`. This file treats `0xFFFFFFFF` as "no background" (which is
   the macOS default anyway) and honours any other alpha. Worth confirming the
   Windows side agrees.
4. **`newline` spans are drawn on Windows and dropped by Dart.** A span with
   `newline: true` is a line-break *marker*, not content:
   `BarRenderer::DrawFrame` does `if (sp.newline) { cur_line = 1; continue; }`
   (`native/win/bar_render_d2d.cpp`), skipping it entirely. But
   `TpBarContent.lines` (`bar_span.dart`) *adds* it to the start of the new line:

   ```dart
   if (s.newline && current.isNotEmpty) { out.add(current); current = []; }
   current.add(s);   // <- the marker becomes content
   ```

   So Windows line 2 starts one span later than the Dart preview's line 2. Line
   **1** is identical in both (and identical to this file, which stops at the
   first `newline` since the menu bar has one line), so macOS is unaffected —
   but the Windows two-line rendering and the preview disagree. Worth aligning
   one way; the C++ reading ("a marker is not content") looks like the intent.

## Highest-risk items to check first on a Mac

In rough order of "most likely to fail the build or look wrong":

1. **`FlutterViewController(project:)`** in `PopoverHost.swift`. Verified against
   `desktop_multi_window`'s own macOS source, which uses exactly this call — the
   best available evidence, but still uncompiled.
2. **`statusItem.button.addSubview(view)`** in `StatusItemPlugin.swift`. A custom
   view inside the status button is a widely used pattern, but `NSStatusItem`
   sizing is quirky: `statusItem.length` is applied to the button, and the view
   relies on `autoresizingMask` to follow. If the strip draws at the wrong width
   or does not appear at all, this is the first thing to inspect.
3. **`NSGraphicsContext.current` being non-nil inside `draw(_:)`.** Standard, but
   if the view is ever drawn outside a graphics context the guard silently
   no-ops and the strip is blank.
4. **`CTLineCreateTruncatedLine` returning nil.** It returns nil when asked to
   truncate to a width >= the line's natural width (that is "not truncating").
   The truncation loop only ever passes a *smaller* width, and the guard stops
   once the content fits, so it should not be reached — but a nil here drops a
   span rather than crashing.
5. **`NSFont.monospacedDigitSystemFont` availability.** macOS 10.11+, and the
   pod declares `osx 12.0`, so fine — but it is the one call whose whole purpose
   (tabular figures) is invisible when it silently falls back.
6. **The `taskpin/dialog_spec` handshake needs a Dart-side branch that does not
   exist yet.** `PopoverHost` starts the popover engine with
   `FlutterDartProject.dartEntrypointArguments = ["popover"]` — the same
   positional-argv convention `desktop_multi_window` uses for its own child
   windows (`["multi_window", windowId, arguments]`). But `lib/main.dart`'s
   `main(List<String> args)` ignores `args` entirely: it loads config and calls
   `runApp` unconditionally, so a popover engine would render the manager shell
   instead of the dialog.
7. **The menu-bar ordering rebuild.** `rebuildStatusItems` removes and re-adds
   every status item to defeat macOS's "new items go left" rule. The assumption
   to verify is that re-adding in descending id order really does display
   ascending id order, and that reusing a view across status items leaves its
   `autoresizingMask`/frame intact. A brief reflow on the first pin is expected;
   items appearing duplicated or in the old order means this pass is wrong.
8. **The native pressed highlight.** The view is transparent and calls
   `NSStatusBarButton.highlight(_:)`; if a click shows no highlight at all, the
   button is drawing its highlight above the subview (or not drawing one without
   its tracking loop), and this is the place to fix it.
9. **Transparent background.** If the strip still paints an opaque rectangle,
   look for a fill left in `draw(_:)` or for the button drawing its own
   background; the view must leave its layer transparent when
   `style.bg == useDefault`.

   `lib/` is outside this lane, so it was not changed. The required change is the
   branch already sketched in `lib/app/windows/dialog_window.dart`'s header
   comment, plus a check on `args.first`:

   ```dart
   void main(List<String> args) async {
     WidgetsFlutterBinding.ensureInitialized();
     // desktop_multi_window's own child windows and our popover both arrive here.
     if (args.isNotEmpty && args.first == 'popover') {
       await dialogWindowMain(const DialogWindowArguments(kind: 'popover'));
       return;
     }
     final w = await dialogWindowArguments();   // desktop_multi_window's path
     if (w != null) { await dialogWindowMain(w); return; }
     await taskpinMain(args);
   }
   ```

   `dialogWindowArguments()` alone is not enough for the popover: it reads
   `WindowController.fromCurrentEngine()` → `getWindowDefinition`, which only
   exists when `desktop_multi_window`'s plugin is registered on that engine. The
   popover engine has no such plugin (and does not need one), so the argv check
   has to come first.

   Also note `MethodChannelDialogWindowApi` (`taskpin/window`) is deliberately
   **not** registered on the popover engine. A popover is not a dialog window —
   the `NSPopover` supplies the chrome — and letting a dialog's `setFrame`/
   `setOpacity` apply to the popover's private window would move it away from its
   anchor. Those calls degrade to no-ops via `_invoke`'s
   `MissingPluginException` handling, which is the designed behaviour.
7. **The app sandbox is off** (`macos/Runner/*.entitlements`). Required for
   TaskPin to work at all, but it is a change from the `flutter create` template
   and it has release consequences (no Mac App Store; needs Developer ID +
   notarisation). See the comments in those files.

## Not in this phase

- No config.json integration, no Lua engine: the bar does not fetch or execute
  anything. The host supplies spans over the channel.
- No `FlutterViewController` lifecycle management beyond one lazily-created
  engine. `PopoverHost` never tears the engine down.
