// ============================================================================
//  TaskPin bar tokens — FROZEN
// ============================================================================
//
//  FROZEN / SHARED-WITH-DART.
//
//  This list is deliberately short and must not grow without a plan change.
//  Every token here is mirrored 1:1 in:
//      - Dart  : packages/taskpin_design (Phase 4)
//      - C++   : native/win/bar_render_d2d.cpp  (this module)
//      - Swift : native/mac/StatusItemView.swift (Phase 8)
//
//  Source of truth: docs/FLUTTER_REWRITE_PLAN.md  -> "条的视觉语言 — segments"
//  and the "Aurora" colour system.
//
//  Colours are stored as 0xAARRGGBB so they map straight onto D2D1::ColorF.
//  The value 0xFFFFFFFF is the "use default" sentinel used by lib/config.c.
//
// ============================================================================
#ifndef TASKPIN_BAR_TOKENS_H
#define TASKPIN_BAR_TOKENS_H

#include <cstdint>

namespace taskpin {
namespace bar {

// ---------------------------------------------------------------- colours ---
// bar/bg          neutral.100 #0E1116  (opaque child default)
// bar/bgHover     neutral.300 #1B1F26
// bar/hairline    white @ 12%
// bar/separator   white @ 20%
// bar/state.*     running = transparent, error = danger, stale = warning
// bar/icon        neutral.800 #A2ACBA
// bar/label       neutral.800 #A2ACBA
// bar/value       neutral.900 #E6EAF0
constexpr uint32_t kColorBg        = 0xFF0E1015u;  // bar/bg
constexpr uint32_t kColorBgHover   = 0xFF1F242Eu;  // bar/bgHover
constexpr uint32_t kColorHairline  = 0x1FFFFFFFu;  // bar/hairline  (white 12%)
constexpr uint32_t kColorSeparator = 0x33FFFFFFu;  // bar/separator (white 20%)
constexpr uint32_t kColorStateRunning = 0x00000000u;  // bar/state.running (transparent)
constexpr uint32_t kColorStateError   = 0xFFF85149u;  // bar/state.error   danger
constexpr uint32_t kColorStateStale   = 0xFFD29922u;  // bar/state.stale   warning
constexpr uint32_t kColorIcon       = 0xFFA2ACBau;  // bar/icon
constexpr uint32_t kColorLabel      = 0xFFA2ACBau;  // bar/label
constexpr uint32_t kColorValue      = 0xFFE6EAF0u;  // bar/value

// Fallback for a span whose colour is the "default" sentinel.
constexpr uint32_t kColorTextDefault = kColorValue;

// "Use the taskbar's own colour."
//
// This is the value Dart sends for the config default (`bar_bg_color` or
// `bg_color` == "FFFFFFFF"), which means "no colour chosen". The renderer
// treats it as a request to sample the shell rather than a colour: see
// `BarWindow::SetStyle`. Chosen because it is already what every existing
// config.json carries, so no schema change and no migration.
constexpr uint32_t kColorFollowTaskbar = 0xFFFFFFFFu;

// Mix `argb` toward white by `amount` (0..1), keeping the alpha.
inline uint32_t LightenArgb(uint32_t argb, float amount) {
    const uint32_t a = (argb >> 24) & 0xFFu;
    const uint32_t r = (argb >> 16) & 0xFFu;
    const uint32_t g = (argb >> 8) & 0xFFu;
    const uint32_t b = argb & 0xFFu;
    auto mix = [amount](uint32_t v) {
        const float f = static_cast<float>(v) + (255.0f - static_cast<float>(v)) * amount;
        return static_cast<uint32_t>(f + 0.5f);
    };
    return (a << 24) | (mix(r) << 16) | (mix(g) << 8) | mix(b);
}

// --------------------------------------------------------------- metrics ----
// Windows: height == taskbar height (Win10 40 @100%, Win11 48 @100%),
// padding 8h / 6v, icon 16, radius 0 (taskbar segments are square).
constexpr int kMetricPadH        = 8;   // horizontal padding
constexpr int kMetricPadV        = 6;   // vertical padding
constexpr int kMetricIcon        = 16;  // icon box, px @96dpi
constexpr int kMetricRadius      = 0;   // square
constexpr int kMetricStateStripe = 2;   // 2px full-height left state stripe
constexpr int kMetricSepWidth    = 1;   // 1 x 14px vertical rule
constexpr int kMetricSepHeight   = 14;
constexpr int kMetricSepGap      = 6;   // 6px gaps either side of a separator
constexpr int kMetricHairline    = 1;   // 1px inset top/bottom on hover

// Windows height presets (used when the taskbar rect is unavailable).
constexpr int kHeightWin10 = 40;
constexpr int kHeightWin11 = 48;

// --------------------------------------------------------------- timings ----
constexpr int  kScrollSpeed     = 2;    // px per tick  (lib/ui.h SCROLL_SPEED)
constexpr int  kScrollInterval  = 50;   // ms           (lib/ui.h SCROLL_INTERVAL)
constexpr int  kAnimInterval    = 80;   // ms           (lib/ui.h ANIM_INTERVAL)
constexpr int  kScrollWrapPad   = 40;   // wrap at text_width + 40

// ------------------------------------------------------------- interaction --
constexpr int kWheelWidthStep = 5;      // normal wheel: width += 5
constexpr int kWidthMin       = 50;     // clamp
constexpr int kWidthMax       = 800;    // clamp
constexpr int kShiftWheelStep = 10;     // Shift+wheel: x += 10
constexpr int kXMinMargin     = 50;     // Shift+wheel right clamp (parent.right - 50)

// --------------------------------------------------------------- menu ids ---
// Kept identical to lib/ui.h so the menu semantics do not drift.
constexpr int kMenuShow = 3001;  // "Manage Items..."
constexpr int kMenuExit = 3002;  // "Exit"
constexpr int kMenuUnpin = 3003; // "Unpin"

// ----------------------------------------------------------- explorer heal --
constexpr int kTaskbarPollMs        = 2000;  // poll cadence for taskbar changes
constexpr int kTaskbarHealDeadlineMs = 5000; // acceptance: re-embed within 5s
// Timer ids owned by a bar window / the watcher host. Kept above the values
// lib/ui.h uses (IDT_REFRESH=1..IDT_UI_FRAME=5) so the two never collide.
constexpr int kTaskbarPollTimerId   = 10;
constexpr int kRefreshTimerId       = 11;
constexpr int kScrollTimerId        = 12;
constexpr int kAnimTimerId          = 13;

// ----------------------------------------------------------------- helpers --
inline float ColorA(uint32_t c) { return ((c >> 24) & 0xFF) / 255.0f; }
inline float ColorR(uint32_t c) { return ((c >> 16) & 0xFF) / 255.0f; }
inline float ColorG(uint32_t c) { return ((c >> 8) & 0xFF) / 255.0f; }
inline float ColorB(uint32_t c) { return (c & 0xFF) / 255.0f; }

} // namespace bar
} // namespace taskpin

#endif // TASKPIN_BAR_TOKENS_H
