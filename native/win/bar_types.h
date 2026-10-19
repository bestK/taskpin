// ============================================================================
//  TaskPin bar — shared model types (span list, geometry, style)
// ============================================================================
//  The span model mirrors DisplaySpan / DisplayContent in lib/scripting.h so a
//  later plugin phase can copy fields straight across the MethodChannel without
//  a translation layer.
//
//  Align values deliberately equal SPAN_ALIGN_LEFT/RIGHT/CENTER (0/1/2) from
//  lib/scripting.h.
// ============================================================================
#ifndef TASKPIN_BAR_TYPES_H
#define TASKPIN_BAR_TYPES_H

#include <windows.h>
#include <string>
#include <vector>
#include <cstdint>
#include "bar_tokens.h"

namespace taskpin {
namespace bar {

// ------------------------------------------------------------- align enum ---
enum Align : int {
    AlignLeft   = 0,  // SPAN_ALIGN_LEFT
    AlignRight  = 1,  // SPAN_ALIGN_RIGHT
    AlignCenter = 2,  // SPAN_ALIGN_CENTER
};

// ------------------------------------------------------------- item state ---
// Drives the 2px left state stripe.
enum ItemState : int {
    StateNone    = 0,
    StateRunning = 1,  // transparent stripe
    StateError   = 2,  // danger stripe
    StateStale   = 3,  // warning stripe
};

// ---------------------------------------------------------------- the span --
// One span of rich content: either text or an image.
struct Span {
    std::wstring text;        // text, or the image source when is_image
    uint32_t color   = 0xFFFFFFFFu;  // 0xFFFFFFFF = use default (lib/config.c sentinel)
    int      font_size = 0;   // 0 = use default
    int      align   = AlignLeft;
    bool     newline = false; // this span starts a new line
    bool     is_image = false;
    int      img_w = 0;       // requested display size (0 = natural)
    int      img_h = 0;
    bool     tabular = false; // render numerals with tabular figures
};

// ------------------------------------------------------------- span list ----
constexpr int kMaxSpans = 32;  // lib/scripting.h MAX_SPANS

struct SpanContent {
    std::vector<Span> spans;

    void Clear() { spans.clear(); }
    bool Empty() const { return spans.empty(); }
    int  Count() const { return static_cast<int>(spans.size()); }

    // True when any span is an animated image (host uses this to drive the
    // 80ms animation timer, matching bar_window.c WM_LUA_DONE).
    bool HasAnyImage() const {
        for (const Span& s : spans) if (s.is_image) return true;
        return false;
    }
    bool HasNewline() const {
        for (const Span& s : spans) if (s.newline) return true;
        return false;
    }
};

// ------------------------------------------------------------- bar style ----
// Per-item visual configuration. Defaults come from the frozen token list.
struct BarStyle {
    uint32_t bg      = kColorBg;
    uint32_t bgHover = kColorBgHover;
    uint32_t label   = kColorLabel;
    uint32_t value   = kColorValue;
    uint32_t icon    = kColorIcon;
    int      font_size = 9;      // point size, matches cfg.font_size default
    int      state   = StateNone;
    bool     scroll_enabled = true;
    bool     show_separators = true;

    // Effective alpha of the background. < 255 => the host must use a layered
    // window (see bar_embed). Kept as a derived helper so callers do not have
    // to remember the shift.
    int BgAlpha() const { return static_cast<int>((bg >> 24) & 0xFF); }
    bool WantsLayered() const { return BgAlpha() < 255; }
};

// ------------------------------------------------------------ geometry ------
struct BarGeometry {
    int x = 0, y = 0, w = 0, h = 0;
};

// -------------------------------------------------------- color parsing -----
// Mirrors lib/config.c colour parsing: accepts "AARRGGBB", "#RRGGBB",
// "#RRGGBBAA" and returns 0xFFFFFFFF ("use default") on failure.
inline uint32_t ParseHexColor(const std::wstring& s) {
    std::wstring t;
    t.reserve(s.size());
    for (wchar_t c : s) {
        if (c == L'#') continue;
        t.push_back(c);
    }
    auto hex = [](wchar_t c) -> int {
        if (c >= L'0' && c <= L'9') return c - L'0';
        if (c >= L'a' && c <= L'f') return c - L'a' + 10;
        if (c >= L'A' && c <= L'F') return c - L'A' + 10;
        return -1;
    };
    for (wchar_t c : t) if (hex(c) < 0) return 0xFFFFFFFFu;

    if (t.size() == 6) { // RRGGBB -> opaque
        uint32_t v = 0;
        for (wchar_t c : t) v = (v << 4) | static_cast<uint32_t>(hex(c));
        return 0xFF000000u | v;
    }
    if (t.size() == 8) { // AARRGGBB (TaskPin convention)
        uint32_t v = 0;
        for (wchar_t c : t) v = (v << 4) | static_cast<uint32_t>(hex(c));
        return v;
    }
    return 0xFFFFFFFFu;
}

} // namespace bar
} // namespace taskpin

#endif // TASKPIN_BAR_TYPES_H
