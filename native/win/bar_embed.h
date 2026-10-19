// ============================================================================
//  TaskPin bar — taskbar embedding + hardening
// ============================================================================
//  Hardened port of lib/appbar.c. Two bugs the rewrite plan identifies are
//  fixed here:
//
//   1. explorer restart  — when Shell_TrayWnd is destroyed the bars vanish and
//      are never restored. TaskbarWatcher installs a
//      SetWinEventHook(EVENT_OBJECT_CREATE) listener AND polls every 2s
//      (kTaskbarPollMs) for a handle change, then asks the host to re-embed.
//      Acceptance target: recovery within 5s (kTaskbarHealDeadlineMs).
//
//   2. secondary monitors — FindWindowW(L"Shell_TrayWnd") only finds the
//      PRIMARY taskbar; per-monitor taskbars are class
//      Shell_SecondaryTrayWnd. The target taskbar is a *parameter* here
//      (BarTarget), and bar_embed_enum_targets() returns all of them.
//
//  Also handled: DPI changes (100% / 150%) and the transparency trade-off
//  (opaque child by default; WS_EX_LAYERED + UpdateLayeredWindow only when the
//  configured background alpha < 255).
// ============================================================================
#ifndef TASKPIN_BAR_EMBED_H
#define TASKPIN_BAR_EMBED_H

#include <windows.h>
#include <functional>
#include <vector>
#include "bar_types.h"

namespace taskpin {
namespace bar {

// ------------------------------------------------------------- BarTarget ----
// One embeddable taskbar. `taskbar` is the window we SetParent into; `notify`
// is its TrayNotifyWnd (used for auto X placement) and may be null.
struct BarTarget {
    HWND  taskbar     = nullptr;
    HWND  notify      = nullptr;
    RECT  client_rect = {0, 0, 0, 0};   // taskbar client rect
    RECT  screen_rect = {0, 0, 0, 0};   // taskbar screen rect
    UINT  dpi         = 96;
    int   height      = 40;             // client height == bar height
    bool  primary     = true;
    bool  valid() const { return taskbar != nullptr && IsWindow(taskbar) != FALSE; }
};

// Enumerate every taskbar: primary (Shell_TrayWnd) + all secondary monitors
// (Shell_SecondaryTrayWnd).
std::vector<BarTarget> bar_embed_enum_targets();

// Just the primary taskbar (Shell_TrayWnd), or an invalid target.
BarTarget bar_embed_find_primary();

// --------------------------------------------------------------- embed ------
// Embed `child` into `target`. `cfg_x < 0` means "auto: left of the tray notify
// area". `cfg_y < 0` means 0. Returns false if the target is invalid.
//
// `layered` selects the transparency path: when true the child gets
// WS_EX_LAYERED and the renderer is expected to use UpdateLayeredWindow;
// otherwise the child is a plain opaque WS_CHILD.
bool bar_embed_into(const BarTarget& target, HWND child, int width,
                    int cfg_x, int cfg_y, bool layered, BarGeometry* out_geom);

// Undo an embed (used on destroy): detach from the taskbar and restore the
// popup style so the window is not orphaned inside a dead parent.
void bar_embed_detach(HWND child);

// Toggle the layered style on an already-embedded child.
void bar_embed_set_layered(HWND child, bool layered);

// Apply the transparency decision from a style. Returns true when the caller
// must render through UpdateLayeredWindow.
bool bar_embed_apply_transparency(HWND child, const BarStyle& style);

// Per-monitor DPI for a window (GetDpiForWindow when available, else
// GetDeviceCaps). Dynamically resolved so the module still runs on old Win10.
UINT bar_embed_dpi_for_window(HWND hwnd);

// ------------------------------------------------------- TaskbarWatcher -----
// Detects taskbar destruction/recreation and asks the host to re-embed.
// The callback fires on the thread that called Start() (which must pump
// messages, so the WinEvent hook can be delivered).
class TaskbarWatcher {
public:
    using Callback = std::function<void()>;

    ~TaskbarWatcher();

    // `owner` hosts the poll timer; it must pump messages.
    bool Start(HWND owner, Callback on_needs_reembed);
    void Stop();

    // Force a detection pass now (used by the injection self-test and after
    // WM_DPICHANGED / WM_DISPLAYCHANGE).
    // Returns true if a change was detected and the callback was invoked.
    bool PollNow();

    // ---- test seam -------------------------------------------------------
    // Overwrite the tracked handle so the next PollNow() sees a mismatch and
    // fires the re-embed path. This exercises the real detect -> re-embed code
    // without touching the live desktop (we must NOT kill explorer here).
    void InjectTrackedHandleForTest(HWND bogus);

    // Diagnostics.
    HWND tracked_primary() const { return m_tracked_primary; }
    int  reembed_count() const { return m_reembed_count; }
    DWORD last_reembed_tick() const { return m_last_reembed_tick; }

private:
    void HandleWinEvent();

    HWND m_owner = nullptr;
    HWND m_tracked_primary = nullptr;
    std::vector<HWND> m_tracked_secondaries;
    Callback m_cb;
    HWINEVENTHOOK m_hook = nullptr;
    int   m_reembed_count = 0;
    DWORD m_last_reembed_tick = 0;
    DWORD m_start_tick = 0;
    bool  m_started = false;

    static void CALLBACK WinEventProcThunk(HWINEVENTHOOK, DWORD event, HWND hwnd,
                                           LONG idObject, LONG idChild,
                                           DWORD thread, DWORD time);
    static TaskbarWatcher* s_active;
};

// ------------------------------------------------------------- logging ------
// Simple append logger so the demo's evidence is greppable. Writes to stderr
// and (if configured) a log file.
void bar_log_set_file(const wchar_t* path);
void bar_log(const char* fmt, ...);

} // namespace bar
} // namespace taskpin

#endif // TASKPIN_BAR_EMBED_H
