// ============================================================================
//  TaskPin bar — one child window per pinned item (implementation)
// ============================================================================
#include "bar_window.h"
#include "bar_image.h"

#include <windowsx.h>
#include <shellapi.h>

namespace taskpin {
namespace bar {

const wchar_t* BarWindow::kClassName = L"TaskPinBarD2DClass";

bool BarWindowRegisterClass(HINSTANCE hinst) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = BarWindow::WndProcThunk;
    wc.hInstance = hinst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;   // D2D paints everything
    wc.lpszClassName = BarWindow::kClassName;
    return RegisterClassExW(&wc) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

BarWindow::BarWindow() {}
BarWindow::~BarWindow() { Destroy(); D2DGlobalsRelease(&m_globals); }

bool BarWindow::Create(HINSTANCE hinst, BarWindowHost* host, int bar_id,
                       const std::wstring& title, int width, int height) {
    m_hinst = hinst;
    m_host = host;
    m_bar_id = bar_id;
    m_title = title;
    m_width = width > 0 ? width : 200;
    m_height = height > 0 ? height : kHeightWin10;

    // WS_EX_LAYERED can only be applied at creation time for a CHILD window;
    // setting it later via SetWindowLongPtr is silently ignored by Windows.
    // So the transparency decision is taken here (SetStyle must have been
    // called first) and a runtime change recreates the window.
    m_layered = m_style.WantsLayered();
    m_layered_at_create = m_layered;

    DWORD ex_style = WS_EX_TOOLWINDOW;
    if (m_layered) ex_style |= WS_EX_LAYERED;

    m_hwnd = CreateWindowExW(
        ex_style, kClassName, title.c_str(), WS_POPUP,
        0, 0, m_width, m_height, nullptr, nullptr, hinst, this);
    if (!m_hwnd) {
        bar_log("bar %d: CreateWindowExW failed err=%lu", bar_id, GetLastError());
        return false;
    }
    LONG_PTR got = GetWindowLongPtrW(m_hwnd, GWL_EXSTYLE);
    bar_log("bar %d: created hwnd=%p w=%d h=%d ex=0x%08llX layered_bit=%d", bar_id,
            (void*)m_hwnd, m_width, m_height, (unsigned long long)got,
            (got & WS_EX_LAYERED) ? 1 : 0);
    return true;
}

bool BarWindow::EmbedInto(const BarTarget& target, int cfg_x, int cfg_y) {
    if (!m_hwnd) return false;
    m_target = target;
    m_cfg_x = cfg_x;
    m_cfg_y = cfg_y;

    // Now that there IS a taskbar to sample, resolve "follow the taskbar"
    // before the transparency decision below reads the alpha.
    ResolveFollowTaskbar();

    // Decide transparency from the style before embedding so the ex-style is
    // correct on the first SetWindowPos.
    m_layered = m_style.WantsLayered();

    bool ok = bar_embed_into(target, m_hwnd, m_width, cfg_x, cfg_y, m_layered, &m_geom);
    if (ok) {
        m_x = m_geom.x;
        m_height = m_geom.h;
        m_width = m_geom.w;
        m_embedded = true;
    }

    if (EnsureRenderer()) {
        m_renderer.Resize(m_width, m_height, target.dpi);
    }

    // Timers: marquee + animation + refresh.
    SetTimer(m_hwnd, kScrollTimerId, kScrollInterval, nullptr);
    SetTimer(m_hwnd, kAnimTimerId, kAnimInterval, nullptr);
    UpdateAnimTimer();

    ShowWindow(m_hwnd, SW_SHOWNOACTIVATE);
    UpdateWindow(m_hwnd);
    return ok;
}

bool BarWindow::ReEmbed() {
    if (!m_hwnd) return false;
    BarTarget fresh = m_target.primary ? bar_embed_find_primary() : m_target;
    if (!fresh.valid()) {
        // Secondary monitor disappeared; fall back to the primary.
        fresh = bar_embed_find_primary();
    }
    bar_log("bar %d: re-embed (target=%p primary=%d)", m_bar_id,
            (void*)fresh.taskbar, fresh.primary ? 1 : 0);
    return EmbedInto(fresh, m_cfg_x, m_cfg_y);
}

void BarWindow::Destroy() {
    if (m_hwnd) {
        KillTimer(m_hwnd, kScrollTimerId);
        KillTimer(m_hwnd, kAnimTimerId);
        KillTimer(m_hwnd, kRefreshTimerId);
        bar_embed_detach(m_hwnd);
        DestroyWindow(m_hwnd);
        m_hwnd = nullptr;
    }
}

void BarWindow::SetContent(const SpanContent& content) {
    m_content = content;
    m_scroll_offset = 0;
    UpdateAnimTimer();
    Invalidate();
}

void BarWindow::SetStyle(const BarStyle& style) {
    m_style = style;
    ResolveFollowTaskbar();

    if (m_hwnd && m_style.WantsLayered() != m_layered_at_create) {
        // The layered bit is creation-time only for child windows, so a change
        // requires recreating the window and re-embedding.
        bar_log("bar %d: transparency change %d -> %d, recreating window",
                m_bar_id, m_layered_at_create ? 1 : 0, m_style.WantsLayered() ? 1 : 0);
        BarTarget keep = m_target;
        int kx = m_cfg_x, ky = m_cfg_y, kw = m_width;
        Destroy();
        Create(m_hinst, m_host, m_bar_id, m_title, kw, m_height);
        if (keep.valid()) EmbedInto(keep, kx, ky);
    } else if (m_hwnd) {
        ApplyTransparency();
    }
    Invalidate();
}

bool BarWindow::ApplyTransparency() {
    if (!m_hwnd) return false;
    bool layered = bar_embed_apply_transparency(m_hwnd, m_style);
    if (layered != m_layered) {
        m_layered = layered;
        if (m_renderer.Attach(&m_globals, m_hwnd, m_layered))
            m_renderer.Resize(m_width, m_height, m_target.dpi);
    }
    return m_layered;
}

// FOLLOW THE TASKBAR.
//
// `kColorFollowTaskbar` is the sentinel Dart sends when the item has no colour
// of its own (the `bar_bg_color: "FFFFFFFF"` default, and a global `bg_color`
// of the same value). Rather than paint a guessed dark grey, sample what the
// shell actually painted, so the bar sits IN the taskbar instead of on top of
// it — under a light taskbar, a coloured accent, or Win11 Mica.
//
// Called from BOTH SetStyle and EmbedInto, and the second one is the one that
// matters: the style arrives before the bar has a target (Dart sends
// `setStyle` then `setSpans`, and the target is only known once the bar is
// embedded). Sampling in SetStyle alone therefore always saw
// `m_target.valid() == false` and left the bar white — which is exactly what
// `transparency: bg=0xFFFFFFFF` in the log was reporting.
//
// A failed sample (0) leaves the token default, so a locked-down or remote
// session still renders.
void BarWindow::ResolveFollowTaskbar() {
    if (m_style.bg != kColorFollowTaskbar) return;
    if (!m_target.valid()) return;
    const uint32_t sampled = bar_embed_taskbar_background(m_target);
    if (sampled == 0) return;
    m_style.bg = sampled;
    // Hover is the same hue lifted slightly, which is what the shell does when
    // the pointer is over a taskbar item.
    m_style.bgHover = LightenArgb(sampled, 0.06f);
}

bool BarWindow::EnsureRenderer() {
    if (!D2DGlobalsInit(&m_globals)) return false;
    if (!m_renderer.attached() || m_renderer.layered() != m_layered ||
        m_renderer.dpi() != m_target.dpi) {
        return m_renderer.Attach(&m_globals, m_hwnd, m_layered);
    }
    return true;
}

// ------------------------------------------------------------- painting -----

void BarWindow::Paint() {
    if (!m_hwnd) return;
    if (!EnsureRenderer()) { bar_log("bar %d: Paint EnsureRenderer FAILED", m_bar_id); return; }

    PAINTSTRUCT ps;
    HDC hdc = BeginPaint(m_hwnd, &ps);
    (void)hdc;

    bool ok = m_renderer.Render(m_content, m_style, m_width, m_height, m_hover, m_scroll_offset);
    if (!ok) {
        bar_log("bar %d: Render failed, resetting device", m_bar_id);
        m_renderer.ResetDevice();
        m_renderer.Resize(m_width, m_height, m_target.dpi);
        ok = m_renderer.Render(m_content, m_style, m_width, m_height, m_hover, m_scroll_offset);
    }
    static bool first_paint_logged = false;
    if (!first_paint_logged) {
        first_paint_logged = true;
        bar_log("bar %d: first paint visible=%d rect=(%d,%d %dx%d) spans=%d ok=%d layered=%d",
                m_bar_id, IsWindowVisible(m_hwnd) ? 1 : 0,
                m_geom.x, m_geom.y, m_width, m_height, m_content.Count(), ok ? 1 : 0,
                m_layered ? 1 : 0);
    }

    // Marquee width mirrors src/bar_window.c's `bar->text_width = left_total[0]`
    // (only left/centre-aligned spans; a right-aligned value must not scroll).
    m_text_width = m_renderer.last_left_total(0);

    EndPaint(m_hwnd, &ps);
}

// -------------------------------------------------------------- timers ------

void BarWindow::UpdateAnimTimer() {
    if (!m_hwnd) return;
    bool need = false;
    for (const Span& s : m_content.spans) {
        if (s.is_image && BarImageIsAnimated(s.text.c_str(), s.img_w, s.img_h)) {
            need = true;
            break;
        }
    }
    if (need) SetTimer(m_hwnd, kAnimTimerId, kAnimInterval, nullptr);
    else KillTimer(m_hwnd, kAnimTimerId);
}

void BarWindow::UpdateMarquee() {
    if (!m_scroll_enabled || !m_style.scroll_enabled) return;
    int avail = m_width - 12;
    if (m_text_width > avail) {
        m_scroll_offset += kScrollSpeed;
        if (m_scroll_offset > m_text_width + kScrollWrapPad) m_scroll_offset = 0;
        InvalidateRect(m_hwnd, nullptr, FALSE);
    } else if (m_scroll_offset != 0) {
        m_scroll_offset = 0;
        InvalidateRect(m_hwnd, nullptr, FALSE);
    }
}

void BarWindow::OnTimer(UINT_PTR id) {
    if (id == kScrollTimerId) {
        UpdateMarquee();
    } else if (id == kAnimTimerId) {
        InvalidateRect(m_hwnd, nullptr, FALSE);
    } else if (id == kRefreshTimerId) {
        if (m_host) m_host->OnBarRefresh(m_bar_id);
    }
}

// --------------------------------------------------------------- wheel ------

void BarWindow::OnWheel(int delta, bool shift) {
    if (shift) {
        // Shift+wheel: move X within the taskbar (src/bar_window.c:368-381).
        m_x += (delta > 0) ? -kShiftWheelStep : kShiftWheelStep;
        if (m_x < 0) m_x = 0;
        RECT prc = {};
        if (m_target.taskbar) GetClientRect(m_target.taskbar, &prc);
        int max_x = prc.right - kXMinMargin;
        if (max_x < 0) max_x = 0;
        if (m_x > max_x) m_x = max_x;
        m_geom.x = m_x;
        // A bar the user placed by hand is no longer auto-tiled. The channel
        // also records this when Dart persists the new x; doing it here keeps
        // the two from disagreeing for the rest of the drag.
        m_auto_index = -1;
        SetWindowPos(m_hwnd, nullptr, m_x, m_geom.y, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        if (m_host) m_host->OnBarGeometryChanged(m_bar_id, m_width, m_x, true);
    } else {
        // Normal wheel: width += 5, clamp 50..800 (src/bar_window.c:383-393).
        m_width += (delta > 0) ? kWheelWidthStep : -kWheelWidthStep;
        if (m_width < kWidthMin) m_width = kWidthMin;
        if (m_width > kWidthMax) m_width = kWidthMax;
        m_geom.w = m_width;
        SetWindowPos(m_hwnd, nullptr, 0, 0, m_width, m_height,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
        m_renderer.Resize(m_width, m_height, m_target.dpi);
        if (m_host) m_host->OnBarGeometryChanged(m_bar_id, m_width, m_x, false);
        InvalidateRect(m_hwnd, nullptr, TRUE);
    }
}

void BarWindow::TestWheel(int delta, bool shift) { OnWheel(delta, shift); }

void BarWindow::SetAutoPlacement(int auto_index, int cfg_x) {
    m_cfg_x = cfg_x;
    m_auto_index = auto_index;
}

int BarWindow::AutoAnchor(const BarTarget& target) {
    int anchor = target.client_rect.right;
    if (target.notify) {
        RECT nrc = {};
        if (GetWindowRect(target.notify, &nrc)) {
            POINT p = { nrc.left, nrc.top };
            ScreenToClient(target.taskbar, &p);
            anchor = p.x;
        }
    }
    return anchor;
}

bool BarWindow::ApplyAutoX(int anchor, int offset) {
    if (!m_hwnd) return false;
    int x = anchor - offset - m_width;
    if (x < 0) x = 0;
    if (x == m_x && m_geom.x == x) return false;
    m_x = x;
    m_geom.x = x;
    SetWindowPos(m_hwnd, nullptr, x, m_geom.y, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    bar_log("bar %d: auto x=%d (anchor=%d offset=%d w=%d)", m_bar_id, x, anchor,
            offset, m_width);
    return true;
}

void BarWindow::ApplyPlacement(int x, int width, bool size_changed,
                               bool move_changed) {
    if (!m_hwnd || (!size_changed && !move_changed)) return;
    SetWindowPos(m_hwnd, nullptr,
                 move_changed ? x : 0, 0,
                 size_changed ? width : 0, size_changed ? m_height : 0,
                 SWP_NOZORDER | SWP_NOACTIVATE |
                     (move_changed ? 0u : static_cast<UINT>(SWP_NOMOVE)) |
                     (size_changed ? 0u : static_cast<UINT>(SWP_NOSIZE)));
    if (size_changed) {
        m_renderer.Resize(m_width, m_height, m_target.dpi);
        InvalidateRect(m_hwnd, nullptr, TRUE);
    }
}

void BarWindow::SetGeometry(int width, int x) {
    if (!m_hwnd) return;
    bool size_changed = false, move_changed = false;

    if (width > 0) {
        int w = width;
        if (w < kWidthMin) w = kWidthMin;
        if (w > kWidthMax) w = kWidthMax;
        if (w != m_width) { m_width = w; m_geom.w = w; size_changed = true; }
    }

    if (x >= 0) {
        // Same clamp the Shift+wheel path applies (src/bar_window.c:375-377):
        // x >= 0 and x <= parent.right - kXMinMargin.
        int nx = x;
        if (nx < 0) nx = 0;
        RECT prc = {};
        if (m_target.taskbar) GetClientRect(m_target.taskbar, &prc);
        int max_x = prc.right - kXMinMargin;
        if (max_x < 0) max_x = 0;
        if (nx > max_x) nx = max_x;
        if (nx != m_x) { m_x = nx; m_geom.x = nx; move_changed = true; }
    }

    if (!size_changed && !move_changed) return;

    ApplyPlacement(m_x, m_width, size_changed, move_changed);
    bar_log("bar %d: SetGeometry -> w=%d x=%d", m_bar_id, m_width, m_x);
}

// --------------------------------------------------------- context menu -----

void BarWindow::ShowContextMenu() {
    POINT pt;
    GetCursorPos(&pt);
    HMENU menu = CreatePopupMenu();
    if (m_bar_id >= 0)
        AppendMenuW(menu, MF_STRING, kMenuUnpin, L"Unpin");
    AppendMenuW(menu, MF_STRING, kMenuShow, L"Manage Items...");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kMenuExit, L"Exit");
    SetForegroundWindow(m_hwnd);
    TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, m_hwnd, nullptr);
    DestroyMenu(menu);
}

// --------------------------------------------------------------- wndproc ----

LRESULT CALLBACK BarWindow::WndProcThunk(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    BarWindow* self = nullptr;
    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
        self = static_cast<BarWindow*>(cs->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self) self->m_hwnd = hwnd;
    } else {
        self = reinterpret_cast<BarWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }
    if (self) return self->WndProc(hwnd, msg, wp, lp);
    return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT BarWindow::WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_ERASEBKGND:
        return 1;   // D2D paints the whole surface

    case WM_PAINT:
        Paint();
        return 0;

    case WM_MOUSEMOVE:
        if (!m_tracking_mouse) {
            TRACKMOUSEEVENT tme = { sizeof(tme), TME_LEAVE, hwnd, 0 };
            TrackMouseEvent(&tme);
            m_tracking_mouse = true;
        }
        if (!m_hover) {
            m_hover = true;
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;

    case WM_MOUSELEAVE:
        m_tracking_mouse = false;
        if (m_hover) {
            m_hover = false;
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;

    case WM_LBUTTONUP:
        if (m_host) m_host->OnBarClick(m_bar_id, m_content);
        return 0;

    case WM_LBUTTONDBLCLK:
        if (m_host) m_host->OnBarOpenManager(m_bar_id);
        return 0;

    case WM_MOUSEWHEEL: {
        int delta = GET_WHEEL_DELTA_WPARAM(wp);
        bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        OnWheel(delta, shift);
        return 0;
    }

    case WM_RBUTTONUP:
        ShowContextMenu();
        return 0;

    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case kMenuShow:  if (m_host) m_host->OnBarOpenManager(m_bar_id); return 0;
        case kMenuExit:  if (m_host) m_host->OnBarExit(); return 0;
        case kMenuUnpin: if (m_host) m_host->OnBarUnpin(m_bar_id); return 0;
        }
        return 0;

    case WM_TIMER:
        OnTimer(wp);
        return 0;

    case WM_DPICHANGED: {
        UINT new_dpi = HIWORD(wp);
        bar_log("bar %d: WM_DPICHANGED dpi=%u", m_bar_id, new_dpi);
        m_target.dpi = new_dpi;
        m_renderer.Resize(m_width, m_height, new_dpi);
        // Re-embed so the height matches the (possibly rescaled) taskbar.
        ReEmbed();
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
    }

    case WM_DISPLAYCHANGE:
        bar_log("bar %d: WM_DISPLAYCHANGE -> re-embed", m_bar_id);
        ReEmbed();
        return 0;

    case WM_DESTROY:
        KillTimer(hwnd, kScrollTimerId);
        KillTimer(hwnd, kAnimTimerId);
        KillTimer(hwnd, kRefreshTimerId);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

} // namespace bar
} // namespace taskpin
