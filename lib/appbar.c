#include "appbar.h"

static HWND s_orig_parent = NULL;

BOOL appbar_embed(HWND hwnd, int width, int cfg_x, int cfg_y) {
    HWND hTaskbar = FindWindowW(L"Shell_TrayWnd", NULL);
    if (!hTaskbar) return FALSE;

    RECT rcTaskbar;
    GetClientRect(hTaskbar, &rcTaskbar);
    int bar_h = rcTaskbar.bottom - rcTaskbar.top;

    int x, y;
    if (cfg_x >= 0) {
        x = cfg_x;
    } else {
        /* Auto: position left of notification area */
        HWND hNotify = FindWindowExW(hTaskbar, NULL, L"TrayNotifyWnd", NULL);
        if (hNotify) {
            RECT rcNotify;
            GetWindowRect(hNotify, &rcNotify);
            POINT pt = { rcNotify.left, rcNotify.top };
            ScreenToClient(hTaskbar, &pt);
            x = pt.x - width;
        } else {
            x = rcTaskbar.right - width;
        }
    }
    if (x < 0) x = 0;
    y = (cfg_y >= 0) ? cfg_y : 0;

    /* Reparent into taskbar */
    s_orig_parent = SetParent(hwnd, hTaskbar);

    /* Remove WS_POPUP, add WS_CHILD for proper embedding */
    LONG style = GetWindowLongW(hwnd, GWL_STYLE);
    style = (style & ~WS_POPUP) | WS_CHILD;
    SetWindowLongW(hwnd, GWL_STYLE, style);

    SetWindowPos(hwnd, HWND_TOP, x, y, width, bar_h,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);

    return TRUE;
}

void appbar_remove(HWND hwnd) {
    if (s_orig_parent) {
        SetParent(hwnd, s_orig_parent);
        s_orig_parent = NULL;
    }
}