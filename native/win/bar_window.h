// ============================================================================
//  TaskPin bar — one child window per pinned item
// ============================================================================
//  Behavioral port of src/bar_window.c's bar_wnd_proc, re-implemented on the
//  Direct2D renderer. One BarWindow == one pinned item.
//
//  Parity with src/bar_window.c:
//    - wheel          : width += 5, clamp 50..800, persist
//    - Shift+wheel    : x += 10, clamp inside the taskbar, persist
//    - hover          : mouse-over state (bar/bgHover + hairlines)
//    - left click     : fire the click action
//    - double click   : open the manager
//    - right click    : Unpin / Manage Items... / Exit
//    - marquee        : long text scrolls (2px / 50ms, wraps at text+40)
//    - animated GIF   : invalidate every 80ms while any span is animated
//
//  The window does NOT fetch or run Lua — the host supplies spans and handles
//  click/refresh/persist callbacks. That is what the Flutter plugin will wire
//  to the MethodChannel later.
// ============================================================================
#ifndef TASKPIN_BAR_WINDOW_H
#define TASKPIN_BAR_WINDOW_H

#include <windows.h>
#include <memory>
#include "bar_types.h"
#include "bar_embed.h"
#include "bar_render_d2d.h"

namespace taskpin {
namespace bar {

// Host callbacks (the Flutter plugin / demo implements these).
class BarWindowHost {
public:
    virtual ~BarWindowHost() = default;
    virtual void OnBarClick(int bar_id, const SpanContent& content) = 0;
    virtual void OnBarOpenManager(int bar_id) = 0;
    virtual void OnBarUnpin(int bar_id) = 0;
    virtual void OnBarExit() = 0;
    // Host re-supplies spans (Lua / HTTP in the real app).
    virtual void OnBarRefresh(int bar_id) = 0;
    // Wheel changed width (normal) or x (Shift). Persist to config.
    //
    // Legacy hook, kept so an existing host (the demo harness) still compiles
    // and still receives the event: the wheel path now calls
    // OnBarGeometryChanged, whose default forwards here.
    virtual void OnBarPersistGeometry(int bar_id, int width, int x) {
        (void)bar_id; (void)width; (void)x;
    }

    // The same report, plus which wheel mode caused it. Hosts that care about
    // auto-tiling override THIS one: a Shift+wheel is an explicit placement
    // and takes the bar out of the tiling.
    virtual void OnBarGeometryChanged(int bar_id, int width, int x, bool shift) {
        (void)shift;
        OnBarPersistGeometry(bar_id, width, x);
    }

    // The bar set, a width, or an auto-tiling key changed: auto-positioned
    // bars should be re-tiled. Hosts that place bars themselves ignore this.
    virtual void OnBarLayoutDirty() {}

    // Host may veto/allow scrolling.
    virtual bool OnBarScrollEnabled(int bar_id) { (void)bar_id; return true; }
};

// Register the window class once per process.
bool BarWindowRegisterClass(HINSTANCE hinst);

class BarWindow {
public:
    BarWindow();
    ~BarWindow();

    // Create the (initially popup) window. `width` is the configured bar width.
    bool Create(HINSTANCE hinst, BarWindowHost* host, int bar_id,
                const std::wstring& title, int width, int height);

    // Embed into `target` (primary or a secondary monitor's taskbar).
    // `cfg_x < 0` = auto (left of the tray notify area).
    bool EmbedInto(const BarTarget& target, int cfg_x, int cfg_y);

    // Re-embed after an explorer restart / DPI change / monitor change.
    bool ReEmbed();

    // Detach from the taskbar and destroy the window.
    void Destroy();

    void SetContent(const SpanContent& content);
    void SetStyle(const BarStyle& style);
    void SetScrollEnabled(bool enabled) { m_scroll_enabled = enabled; }

    // Set the width and/or x directly, clamped the same way the wheel path
    // clamps (width 50..800, x inside the taskbar). Either may be omitted by
    // passing -1, meaning "leave unchanged".
    //
    // Added for the Flutter channel's `setGeometry`: the wheel handler is the
    // only other way to move a bar, and a config-driven restore must not have
    // to fake wheel events. Does NOT persist — the caller owns persistence.
    void SetGeometry(int width, int x);

    // The auto-tiling inputs, set by the channel from `setSpans`/`setGeometry`.
    //
    // `auto_index < 0` means "explicitly positioned": [cfg_x] (>= 0) is the
    // exact x and the auto pass never touches it. Otherwise the bar takes part
    // in the left-of-the-tray tiling and is sorted by [auto_index].
    void SetAutoPlacement(int auto_index, int cfg_x);

    // Recompute the auto x for this bar from [anchor] and the running [offset]
    // (the widths + 2px gaps of the auto bars before it) and apply it.
    // `x = anchor - offset - width`, clamped to >= 0. Returns true when the
    // window actually moved.
    bool ApplyAutoX(int anchor, int offset);

    // The anchor AutoX tiles leftwards from: the left edge of the tray notify
    // area, in taskbar client coordinates, or the taskbar's right edge.
    static int AutoAnchor(const BarTarget& target);

    int  auto_index() const { return m_auto_index; }
    bool is_auto() const { return m_auto_index >= 0; }

    // Force a repaint (used by the animation timer and by the host).
    void Invalidate() { if (m_hwnd) InvalidateRect(m_hwnd, nullptr, FALSE); }

    HWND hwnd() const { return m_hwnd; }
    int  bar_id() const { return m_bar_id; }
    int  width() const { return m_width; }
    int  x() const { return m_x; }
    const BarGeometry& geometry() const { return m_geom; }
    BarRenderer& renderer() { return m_renderer; }

    // Read-only state the channel needs. `embedded()` is what tells it to
    // place the window (first setSpans) rather than just resize it.
    const BarStyle& style() const { return m_style; }
    bool embedded() const { return m_embedded; }
    int  cfg_x() const { return m_cfg_x; }
    int  cfg_y() const { return m_cfg_y; }

    // Apply the transparency decision (opaque child vs layered).
    bool ApplyTransparency();

    // ---- test seam -------------------------------------------------------
    // Exercise the wheel logic without a real mouse/keyboard (Shift is read
    // from GetKeyState in the real path, which cannot be faked from a test).
    void TestWheel(int delta, bool shift);
    bool hover() const { return m_hover; }

    // Window class registration needs access to these.
    static const wchar_t* kClassName;
    static LRESULT CALLBACK WndProcThunk(HWND, UINT, WPARAM, LPARAM);

private:
    LRESULT WndProc(HWND, UINT, WPARAM, LPARAM);

    void Paint();
    void OnTimer(UINT_PTR id);
    void UpdateMarquee();
    void UpdateAnimTimer();
    void OnWheel(int delta, bool shift);
    void ShowContextMenu();
    bool EnsureRenderer();
    // Move to [x] (already clamped) and resize if asked. Shared by
    // SetGeometry, ApplyAutoX and the wheel path.
    void ApplyPlacement(int x, int width, bool size_changed, bool move_changed);

    HWND m_hwnd = nullptr;
    HINSTANCE m_hinst = nullptr;
    BarWindowHost* m_host = nullptr;
    int m_bar_id = -1;
    int m_width = 200;
    int m_height = kHeightWin10;
    int m_x = 0;
    BarGeometry m_geom;

    BarTarget m_target;
    int m_cfg_x = -1, m_cfg_y = -1;
    // Ordering key for auto tiling, sent by Dart. -1 = explicitly positioned
    // (or no key sent, in which case cfg_x >= 0 also means explicit).
    int m_auto_index = -1;
    std::wstring m_title;

    SpanContent m_content;
    BarStyle m_style;
    BarRenderer m_renderer;
    D2DGlobals m_globals;

    bool m_hover = false;
    bool m_scroll_enabled = true;
    int  m_scroll_offset = 0;
    int  m_text_width = 0;
    bool m_layered = false;
    bool m_layered_at_create = false;  // layered bit is creation-time only
    bool m_embedded = false;           // EmbedInto has succeeded at least once
    bool m_tracking_mouse = false;
};

} // namespace bar
} // namespace taskpin

#endif // TASKPIN_BAR_WINDOW_H
