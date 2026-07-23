/*
 * Main UI host: one Win32 window for the item list.
 * Dialogs are separate windows created by ui_*_show().
 */
extern "C" {
#include "ui.h"
}

#include "ui_views.h"
#include "ui_window.h"
#include "ui_common.h"
#include "backends/imgui_impl_win32.h"

static UiWindow g_host = {};
static int g_selected_item = -1;
static bool g_host_created = false;

UiWindow *ui_host_window(void) {
    return g_host_created ? &g_host : NULL;
}

/* Host uses its own paint/timer path (not modal). */
static void host_render(void) {
    if (!g_host_created) return;
    const float clear[4] = {Theme::BgBase.x, Theme::BgBase.y, Theme::BgBase.z, Theme::BgBase.w};
    /* Main list is edge-to-edge: zero content padding. */
    if (ui_window_begin_frame(&g_host, 0.0f, 0.0f)) {
        ui_main_view_draw(&g_selected_item);
        ui_window_end_frame(&g_host, clear);
        /* Open independent dialogs after frame is closed. */
        ui_main_process_deferred();
    }
}

/* Hook host HWND messages that the shared proc doesn't handle (timer/paint). */
static WNDPROC g_orig_host_proc = NULL;

static LRESULT CALLBACK host_subclass_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_TIMER:
        if (wp == IDT_UI_FRAME) {
            if (IsWindowVisible(hwnd))
                host_render();
            return 0;
        }
        break;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        BeginPaint(hwnd, &ps);
        host_render();
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_CLOSE:
        KillTimer(hwnd, IDT_UI_FRAME);
        ShowWindow(hwnd, SW_HIDE);
        return 0;
    case WM_GETMINMAXINFO: {
        MINMAXINFO *m = reinterpret_cast<MINMAXINFO *>(lp);
        m->ptMinTrackSize.x = 700;
        m->ptMinTrackSize.y = 400;
        return 0;
    }
    case WM_DESTROY:
        KillTimer(hwnd, IDT_UI_FRAME);
        g_main_hwnd = NULL;
        break;
    }
    return CallWindowProcW(g_orig_host_proc, hwnd, msg, wp, lp);
}

static bool create_host(void) {
    if (g_host_created) return true;

    ImGui_ImplWin32_EnableDpiAwareness();

    if (!ui_window_create(&g_host, NULL, L"TaskPinUiHostClass",
            ui_title("main.window_title", L"TaskPin"), 900, 550, NULL))
        return false;

    g_main_hwnd = g_host.hwnd;
    g_orig_host_proc = (WNDPROC)SetWindowLongPtrW(g_host.hwnd, GWLP_WNDPROC,
        (LONG_PTR)host_subclass_proc);
    g_host_created = true;
    return true;
}

extern "C" void modern_ui_show(void) {
    if (!create_host()) {
        MessageBoxW(NULL, L"Unable to initialize the UI host.", L"TaskPin",
            MB_OK | MB_ICONERROR);
        return;
    }
    if (g_selected_item >= g_cfg.count) g_selected_item = g_cfg.count - 1;
    if (g_selected_item < 0 && g_cfg.count > 0) g_selected_item = 0;
    ShowWindow(g_host.hwnd, SW_SHOW);
    SetForegroundWindow(g_host.hwnd);
    SetTimer(g_host.hwnd, IDT_UI_FRAME, 16, NULL);
    host_render();
}

extern "C" void modern_ui_refresh(void) {
    if (g_selected_item >= g_cfg.count) g_selected_item = g_cfg.count - 1;
    if (g_host.hwnd) InvalidateRect(g_host.hwnd, NULL, FALSE);
}

extern "C" void modern_ui_shutdown(void) {
    if (g_host_created) {
        KillTimer(g_host.hwnd, IDT_UI_FRAME);
        ui_window_destroy(&g_host);
        g_host_created = false;
        g_main_hwnd = NULL;
    }
}
