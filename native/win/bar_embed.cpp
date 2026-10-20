// ============================================================================
//  TaskPin bar — taskbar embedding + hardening (implementation)
// ============================================================================
#include "bar_embed.h"

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

namespace taskpin {
namespace bar {

// ------------------------------------------------------------- logging ------
namespace {
FILE* g_log_file = nullptr;
CRITICAL_SECTION g_log_cs;
bool g_log_cs_ready = false;
void EnsureLogCs() {
    if (!g_log_cs_ready) { InitializeCriticalSection(&g_log_cs); g_log_cs_ready = true; }
}
} // namespace

void bar_log_set_file(const wchar_t* path) {
    EnsureLogCs();
    EnterCriticalSection(&g_log_cs);
    if (g_log_file) { fclose(g_log_file); g_log_file = nullptr; }
    if (path) g_log_file = _wfopen(path, L"w");
    LeaveCriticalSection(&g_log_cs);
}

void bar_log(const char* fmt, ...) {
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    SYSTEMTIME st;
    GetLocalTime(&st);
    char line[2304];
    snprintf(line, sizeof(line), "[%02d:%02d:%02d.%03d] %s\n",
             st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, buf);

    EnsureLogCs();
    EnterCriticalSection(&g_log_cs);
    fputs(line, stderr);
    if (g_log_file) { fputs(line, g_log_file); fflush(g_log_file); }
    LeaveCriticalSection(&g_log_cs);
}

// -------------------------------------------------------------- helpers -----

// Dynamically resolved GetDpiForWindow (Win10 1607+); falls back to the DC.
typedef UINT (WINAPI *PFN_GetDpiForWindow)(HWND);

UINT bar_embed_dpi_for_window(HWND hwnd) {
    static PFN_GetDpiForWindow pfn = reinterpret_cast<PFN_GetDpiForWindow>(
        reinterpret_cast<void*>(
            GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow")));
    if (pfn && hwnd) {
        UINT d = pfn(hwnd);
        if (d) return d;
    }
    HDC dc = GetDC(hwnd);
    UINT dpi = 96;
    if (dc) { dpi = static_cast<UINT>(GetDeviceCaps(dc, LOGPIXELSX)); ReleaseDC(hwnd, dc); }
    return dpi ? dpi : 96;
}

namespace {

BarTarget MakeTarget(HWND taskbar, bool primary) {
    BarTarget t;
    t.taskbar = taskbar;
    t.primary = primary;
    if (!taskbar) return t;

    GetClientRect(taskbar, &t.client_rect);
    GetWindowRect(taskbar, &t.screen_rect);
    t.height = t.client_rect.bottom - t.client_rect.top;
    t.dpi    = bar_embed_dpi_for_window(taskbar);

    // TrayNotifyWnd is a direct child on both Shell_TrayWnd and
    // Shell_SecondaryTrayWnd.
    t.notify = FindWindowExW(taskbar, nullptr, L"TrayNotifyWnd", nullptr);
    return t;
}

BOOL CALLBACK EnumSecondaryProc(HWND hwnd, LPARAM lparam) {
    wchar_t cls[64] = {0};
    if (GetClassNameW(hwnd, cls, 63) && wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0) {
        auto* out = reinterpret_cast<std::vector<BarTarget>*>(lparam);
        out->push_back(MakeTarget(hwnd, /*primary=*/false));
    }
    return TRUE;
}

} // namespace

std::vector<BarTarget> bar_embed_enum_targets() {
    std::vector<BarTarget> out;
    if (HWND primary = FindWindowW(L"Shell_TrayWnd", nullptr))
        out.push_back(MakeTarget(primary, /*primary=*/true));
    EnumWindows(EnumSecondaryProc, reinterpret_cast<LPARAM>(&out));
    return out;
}

BarTarget bar_embed_find_primary() {
    return MakeTarget(FindWindowW(L"Shell_TrayWnd", nullptr), /*primary=*/true);
}

// --------------------------------------------------------------- embed ------

bool bar_embed_into(const BarTarget& target, HWND child, int width,
                    int cfg_x, int cfg_y, bool layered, BarGeometry* out_geom) {
    if (!child || !target.valid()) {
        bar_log("embed: FAILED (child=%p target.valid=%d)", (void*)child,
                target.valid() ? 1 : 0);
        return false;
    }
    HWND hTaskbar = target.taskbar;
    const int bar_h = target.height > 0 ? target.height : kHeightWin10;

    // ---- X placement (algorithm from lib/appbar.c, hardened) ----
    int x = 0;
    if (cfg_x >= 0) {
        x = cfg_x;
    } else if (target.notify) {
        RECT rcNotify;
        GetWindowRect(target.notify, &rcNotify);
        POINT pt = { rcNotify.left, rcNotify.top };
        ScreenToClient(hTaskbar, &pt);
        x = pt.x - width;
    } else {
        x = target.client_rect.right - width;
    }
    if (x < 0) x = 0;

    int y = (cfg_y >= 0) ? cfg_y : 0;

    // ---- reparent ----
    HWND prev = SetParent(child, hTaskbar);
    DWORD sp_err = GetLastError();

    // ---- WS_POPUP -> WS_CHILD ----
    LONG_PTR style = GetWindowLongPtrW(child, GWL_STYLE);
    style = (style & ~WS_POPUP) | WS_CHILD;
    SetWindowLongPtrW(child, GWL_STYLE, style);

    // ---- layered or opaque ----
    LONG_PTR ex = GetWindowLongPtrW(child, GWL_EXSTYLE);
    ex |= WS_EX_TOOLWINDOW;
    if (layered) ex |= WS_EX_LAYERED; else ex &= ~WS_EX_LAYERED;
    SetWindowLongPtrW(child, GWL_EXSTYLE, ex);

    BOOL pos_ok = SetWindowPos(child, HWND_TOP, x, y, width, bar_h,
                               SWP_NOACTIVATE | SWP_SHOWWINDOW);

    if (out_geom) { out_geom->x = x; out_geom->y = y; out_geom->w = width; out_geom->h = bar_h; }

    bar_log("embed: taskbar=%p (%s) notify=%p SetParent(prev=%p err=%lu) style=0x%08llX "
            "layered=%d SetWindowPos=%d rect=(%d,%d %dx%d) dpi=%u height=%d",
            (void*)hTaskbar, target.primary ? "primary" : "secondary",
            (void*)target.notify, (void*)prev, (unsigned long)sp_err,
            (unsigned long long)style, layered ? 1 : 0, pos_ok,
            x, y, width, bar_h, target.dpi, bar_h);
    return pos_ok != FALSE;
}

void bar_embed_detach(HWND child) {
    if (!child || !IsWindow(child)) return;
    // Restore a standalone popup so the window survives its parent going away.
    LONG_PTR style = GetWindowLongPtrW(child, GWL_STYLE);
    style = (style & ~WS_CHILD) | WS_POPUP;
    SetWindowLongPtrW(child, GWL_STYLE, style);
    SetParent(child, nullptr);
    bar_log("detach: child=%p restored to WS_POPUP", (void*)child);
}

void bar_embed_set_layered(HWND child, bool layered) {
    if (!child || !IsWindow(child)) return;
    LONG_PTR ex = GetWindowLongPtrW(child, GWL_EXSTYLE);
    LONG_PTR want = layered ? (ex | WS_EX_LAYERED) : (ex & ~WS_EX_LAYERED);
    LONG_PTR prev = SetWindowLongPtrW(child, GWL_EXSTYLE, want);
    LONG_PTR after = GetWindowLongPtrW(child, GWL_EXSTYLE);
    bar_log("embed: set_layered(%d) ex 0x%08llX -> want 0x%08llX (SetWindowLongPtr prev=0x%08llX "
            "err=%lu) readback=0x%08llX layered_bit=%d",
            layered ? 1 : 0, (unsigned long long)ex, (unsigned long long)want,
            (unsigned long long)prev, (unsigned long)GetLastError(),
            (unsigned long long)after, (after & WS_EX_LAYERED) ? 1 : 0);
}

bool bar_embed_apply_transparency(HWND child, const BarStyle& style) {
    const bool layered = style.WantsLayered();
    bar_embed_set_layered(child, layered);
    bar_log("transparency: bg=0x%08X alpha=%d -> %s", style.bg, style.BgAlpha(),
            layered ? "WS_EX_LAYERED + UpdateLayeredWindow" : "opaque child");
    return layered;
}

// ------------------------------------------------------- TaskbarWatcher -----

TaskbarWatcher* TaskbarWatcher::s_active = nullptr;

TaskbarWatcher::~TaskbarWatcher() { Stop(); }

void CALLBACK TaskbarWatcher::WinEventProcThunk(HWINEVENTHOOK, DWORD event, HWND hwnd,
                                                LONG idObject, LONG idChild,
                                                DWORD, DWORD) {
    if (!s_active) return;
    if (event != EVENT_OBJECT_CREATE) return;
    if (idObject != OBJID_WINDOW || idChild != 0) return;
    if (!hwnd) return;

    wchar_t cls[64] = {0};
    if (!GetClassNameW(hwnd, cls, 63)) return;
    if (wcscmp(cls, L"Shell_TrayWnd") == 0 ||
        wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0) {
        bar_log("winevent: EVENT_OBJECT_CREATE class=%ls hwnd=%p -> re-embed",
                cls, (void*)hwnd);
        s_active->HandleWinEvent();
    }
}

bool TaskbarWatcher::Start(HWND owner, Callback on_needs_reembed) {
    Stop();
    m_owner = owner;
    m_cb = std::move(on_needs_reembed);
    m_start_tick = GetTickCount();
    m_reembed_count = 0;

    m_tracked_primary = FindWindowW(L"Shell_TrayWnd", nullptr);
    m_tracked_secondaries.clear();
    for (const BarTarget& t : bar_embed_enum_targets())
        if (!t.primary) m_tracked_secondaries.push_back(t.taskbar);

    s_active = this;
    m_hook = SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_CREATE, nullptr,
                             WinEventProcThunk, 0, 0,
                             WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    if (owner)
        SetTimer(owner, kTaskbarPollTimerId, kTaskbarPollMs, nullptr);

    m_started = true;
    bar_log("watcher: started (primary=%p secondaries=%d hook=%p poll=%dms)",
            (void*)m_tracked_primary, (int)m_tracked_secondaries.size(),
            (void*)m_hook, kTaskbarPollMs);
    return m_hook != nullptr || owner != nullptr;
}

void TaskbarWatcher::Stop() {
    if (m_owner) KillTimer(m_owner, kTaskbarPollTimerId);
    if (m_hook) { UnhookWinEvent(m_hook); m_hook = nullptr; }
    if (s_active == this) s_active = nullptr;
    m_started = false;
}

bool TaskbarWatcher::PollNow() {
    // Detect: primary handle changed, primary gone, or a secondary set change.
    HWND primary = FindWindowW(L"Shell_TrayWnd", nullptr);
    bool changed = (primary != m_tracked_primary);
    if (!changed && m_tracked_primary && !IsWindow(m_tracked_primary)) changed = true;

    if (!changed) {
        std::vector<HWND> now;
        for (const BarTarget& t : bar_embed_enum_targets())
            if (!t.primary) now.push_back(t.taskbar);
        if (now.size() != m_tracked_secondaries.size()) changed = true;
    }

    if (!changed) return false;
    HandleWinEvent();
    return true;
}

void TaskbarWatcher::HandleWinEvent() {
    m_tracked_primary = FindWindowW(L"Shell_TrayWnd", nullptr);
    m_tracked_secondaries.clear();
    for (const BarTarget& t : bar_embed_enum_targets())
        if (!t.primary) m_tracked_secondaries.push_back(t.taskbar);

    m_reembed_count++;
    m_last_reembed_tick = GetTickCount();
    bar_log("watcher: taskbar changed -> re-embed #%d (new primary=%p, elapsed=%lums)",
            m_reembed_count, (void*)m_tracked_primary,
            (unsigned long)(m_last_reembed_tick - m_start_tick));
    if (m_cb) m_cb();
}

void TaskbarWatcher::InjectTrackedHandleForTest(HWND bogus) {
    bar_log("watcher: INJECT tracked primary %p -> %p (test seam; explorer untouched)",
            (void*)m_tracked_primary, (void*)bogus);
    m_tracked_primary = bogus;
}

// --------------------------------------------------- taskbar background -----

uint32_t bar_embed_taskbar_background(const BarTarget& target) {
    if (!target.valid()) return 0;

    // SCREEN coordinates, which is what GetPixel wants.
    //
    // `BarTarget::client_rect` is a CLIENT rect: it comes from
    // `GetClientRect`, so it starts at (0,0) and describes a size, not a place.
    // Using it directly put the sample at (1540,20) — 20 px from the TOP of the
    // screen rather than the bottom, where the taskbar is — and `GetPixel`
    // returned CLR_INVALID, so the bar kept its white default.
    //
    // `screen_rect` is the taskbar's window rect in screen space, which is the
    // right frame. The client area is offset from it by the window border, but
    // a few pixels either way cannot leave a 40 px-tall taskbar.
    RECT client = target.screen_rect;
    if (client.right <= client.left) {
        if (!GetWindowRect(target.taskbar, &client)) return 0;
    }

    // Sample a little to the LEFT of the tray-notify area: our bars live there,
    // so a point further left is guaranteed to be the shell's own painting.
    // Falling back to a quarter of the way in covers a missing notify window.
    int sample_x;
    if (target.notify) {
        RECT nr = {};
        if (GetWindowRect(target.notify, &nr)) {
            sample_x = nr.left - 40;
        } else {
            sample_x = client.left + (client.right - client.left) / 4;
        }
    } else {
        sample_x = client.left + (client.right - client.left) / 4;
    }
    const int sample_y = client.top + (client.bottom - client.top) / 2;

    // Clamp inside the taskbar so a narrow bar row still lands on it.
    if (sample_x < client.left + 2) sample_x = client.left + 2;
    if (sample_x > client.right - 2) sample_x = client.right - 2;

    HDC screen = GetDC(nullptr);
    if (!screen) return 0;
    COLORREF c = GetPixel(screen, sample_x, sample_y);
    ReleaseDC(nullptr, screen);

    if (c == CLR_INVALID) {
        bar_log("taskbar bg: GetPixel failed at (%d,%d) err=%lu", sample_x,
                sample_y, (unsigned long)GetLastError());
        return 0;
    }

    // COLORREF is 0x00BBGGRR; the bar style wants 0xAARRGGBB. The sample is
    // always opaque: whatever alpha the taskbar composites at, the pixel we
    // read is the final blended result.
    const uint32_t r = GetRValue(c);
    const uint32_t g = GetGValue(c);
    const uint32_t b = GetBValue(c);
    const uint32_t argb = 0xFF000000u | (r << 16) | (g << 8) | b;

    bar_log("taskbar bg: sampled (%d,%d) -> #%08X", sample_x, sample_y, argb);
    return argb;
}

} // namespace bar
} // namespace taskpin
