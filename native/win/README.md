# `native/win` — TaskPin native Windows taskbar bar (Phase 7 prototype)

A **standalone, testable** native module that renders TaskPin's taskbar bars with
**Direct2D + DirectWrite** and embeds them in the Windows taskbar. No Flutter
required. A later phase wraps this in a Flutter plugin (`taskpin_bar_plugin.cpp`)
driven over the `taskpin/bar` MethodChannel.

This is additive: nothing in `src/`, `lib/` or `third_party/` is modified.
`lib/stb_image.h` is included read-only.

## Build

MinGW-w64 g++ 11.2.0 (MSVC is not installed on the dev box; this module is
deliberately MinGW-clean so it also compiles under MSVC for the Flutter runner).

```bash
cmake -S native/win -B native/win/build -G Ninja \
      -DCMAKE_C_COMPILER=D:/mingw64/bin/gcc.exe \
      -DCMAKE_CXX_COMPILER=D:/mingw64/bin/g++.exe
ninja -C native/win/build
```

Produces:

| Target | What it is |
|---|---|
| `native/win/build/taskpin_bar_demo.exe` | standalone harness (live demo + `--selftest`) |
| `native/win/build/libtaskpin_bar.a` | static library for the later Flutter plugin |

## Run

```bash
# machine-checkable self-test (offscreen render + assertions, no taskbar needed)
native/win/build/taskpin_bar_demo.exe --selftest    # exit 0 = pass

# live demo: embeds 3 bars in the real taskbar
native/win/build/taskpin_bar_demo.exe               # right-click a bar -> Exit, or press Esc
```

Logs go to stdout **and** `native/win/build/bar_demo.log`.
The self-test also writes `native/win/build/selftest_bars.png` (the three bars
stacked) so the render can be inspected without a live taskbar.

## What the demo shows

Three bars, tiled to the left of the notification area like the current app:

1. **emoji bar** — 🌈 😀 + tabular `CPU 42%`. The colour emoji is the proof the
   DirectWrite colour-font path is live (GDI cannot render colour emoji).
2. **CJK bar** — 中文 / 日本語 / 한국어 in three colours, right-aligned `12.3 GB`.
   Proves DirectWrite font fallback.
3. **error bar** — danger (red) 2px left state stripe, two-line model
   (`newline` span on the second line).

## Behaviours (parity with `src/bar_window.c`)

| Behaviour | Status |
|---|---|
| wheel: width ±5, clamp 50–800, persist | ported |
| Shift+wheel: X ∓10, clamp inside the taskbar, persist | ported |
| hover: `bar/bgHover` fill + 1px hairlines | ported (new visual) |
| left click → click action; double click → manager | ported (host callbacks) |
| right click → Unpin / Manage Items… / Exit | ported (same IDs) |
| marquee: 2px / 50ms, wraps at `text_width + 40` | ported |
| animated GIF: 80ms invalidate | ported |
| two-line model (`newline`, `line_y = {2, h/2+1}`) | ported |
| per-span colour / font size / align L·R·C | ported (DirectWrite metrics) |
| segment separators, state stripe, tabular figures | new (plan visual language) |
| explorer-restart self-heal | new (bug fix) |
| secondary monitors | new (bug fix) |
| DPI 100% / 150% | new |

### Known, intentional difference from the GDI baseline

Text **metrics differ** from `GetTextExtentPoint32`: DirectWrite measures and
positions glyphs differently (advance widths, hinting, line metrics). This is
expected and desirable — it is part of what the rewrite buys (correct CJK
fallback, colour emoji, per-glyph alpha). It is not a regression.

One parity detail that *was* matched deliberately: the marquee width is
`left_total[0]` — only left/centre-aligned spans count. A right-aligned value
must not make the bar scroll (see `BarRenderer::last_left_total`).

## Architecture

| File | Role |
|---|---|
| `bar_tokens.h` | **FROZEN** bar tokens + Windows metrics, mirrored 1:1 in Dart/Swift |
| `bar_types.h` | `Span` / `SpanContent` / `BarStyle` — mirrors `DisplaySpan`/`DisplayContent` |
| `bar_embed.h/.cpp` | embedding + hardening: `BarTarget`, `TaskbarWatcher`, DPI, transparency |
| `bar_render_d2d.h/.cpp` | D2D 1.1 + DirectWrite renderer, colour emoji, CJK fallback, tabular figures |
| `bar_image.h/.cpp` | PNG/JPEG/BMP/GIF + `data:` URI + URL decode → `ID2D1Bitmap` |
| `bar_window.h/.cpp` | one child window per pinned item; input, marquee, animation, menu |
| `bar_demo.cpp` | demo harness + `--selftest` |

### Rendering path

`ID2D1Factory1` → `ID2D1Device` → `ID2D1DeviceContext`. Colour-font rendering
requires Direct2D **1.1**, so the device context (not `ID2D1HwndRenderTarget`) is
required — that is the whole point of the rewrite.

**Presentation.** A DXGI swapchain cannot be created on a child window that lives
inside another process's window tree (explorer's taskbar) —
`CreateSwapChainForHwnd` returns `E_ACCESSDENIED`. So the renderer draws into a
D2D bitmap target and presents by blitting:

- **opaque child** (default): `BitBlt`
- **layered** (`bg` alpha < 255): `UpdateLayeredWindow`

Rendering is still 100% Direct2D + DirectWrite; only presentation differs. The
frame is read back through a `D2D1_BITMAP_OPTIONS_CPU_READ` bitmap (a WIC-backed
target does not reliably reflect the rendered pixels back into the WIC bitmap).

### The two bug fixes

**explorer restart.** `SetWinEventHook(EVENT_OBJECT_CREATE)` watches for
`Shell_TrayWnd` / `Shell_SecondaryTrayWnd` creation, plus a 2s poll
(`kTaskbarPollMs`) on the tracked handle. On detection every bar is re-embedded;
acceptance target is 5s (`kTaskbarHealDeadlineMs`).

**secondary monitors.** `FindWindowW(L"Shell_TrayWnd")` only finds the primary
taskbar; per-monitor taskbars are class `Shell_SecondaryTrayWnd`.
`bar_embed_enum_targets()` returns all of them, and the target taskbar is a
parameter (`BarTarget`) everywhere, so a bar can be placed on any monitor.

### Transparency

A child window cannot truly pass clicks through. Default is an **opaque child**;
`WS_EX_LAYERED` + `UpdateLayeredWindow` is used only when the configured `bg`
alpha < 255. Note `WS_EX_LAYERED` is **creation-time only** for child windows —
`SetWindowLongPtr` silently ignores it afterwards — so a runtime transparency
change recreates the window (`BarWindow::SetStyle`).

## Not in this prototype

No MethodChannel yet, no `config.json` integration, no Lua engine. The bar does
not fetch or execute anything: the host supplies spans and handles
click / refresh / persist callbacks (`BarWindowHost`). That is what the Flutter
plugin wires up later.
