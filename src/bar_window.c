#include "ui.h"

void start_fetch(HWND hwnd) {
    if (g_fetching) return;
    if (g_cfg.selected < 0 || g_cfg.selected >= g_cfg.count) {
        lstrcpyW(g_display, L"(no item selected)");
        InvalidateRect(hwnd, NULL, TRUE);
        return;
    }

    PinItem *it = &g_cfg.items[g_cfg.selected];

    if (it->type == ITEM_TYPE_LUA) {
        if (it->lua_path[0]) {
            if (script_exec_file(it->lua_path, it->params, it->param_count, &g_script_result)) {
                lstrcpynW(g_display, g_script_result.display, FETCH_BUF_SIZE);
            } else {
                lstrcpyW(g_display, L"[script error]");
            }
        } else {
            lstrcpyW(g_display, L"(no script)");
        }
        InvalidateRect(hwnd, NULL, TRUE);
        return;
    }

    g_fetching = TRUE;

    FetchContext *ctx = (FetchContext *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(FetchContext));
    if (!ctx) { g_fetching = FALSE; return; }

    ctx->hwnd = hwnd;
    lstrcpynW(ctx->url, it->url, 1024);
    lstrcpynW(ctx->headers, it->req_headers, 1024);

    HANDLE hThread = CreateThread(NULL, 0, fetcher_thread, ctx, 0, NULL);
    if (hThread) CloseHandle(hThread);
    else { HeapFree(GetProcessHeap(), 0, ctx); g_fetching = FALSE; }
}

LRESULT CALLBACK bar_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        int font_height = -MulDiv(g_cfg.font_size, 96, 72);
        g_font = CreateFontW(font_height, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
        lstrcpyW(g_display, L"TaskPin");
        SetTimer(hwnd, IDT_SCROLL, SCROLL_INTERVAL, NULL);
        return 0;
    }

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rc;
        GetClientRect(hwnd, &rc);

        HBRUSH hBrush = CreateSolidBrush(g_cfg.bg_color);
        FillRect(hdc, &rc, hBrush);
        DeleteObject(hBrush);

        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, g_cfg.font_color);
        SelectObject(hdc, g_font);

        SIZE sz;
        GetTextExtentPoint32W(hdc, g_display, lstrlenW(g_display), &sz);
        g_text_width = sz.cx;

        int avail = rc.right - rc.left - 12;
        if (sz.cx <= avail) {
            g_scroll_offset = 0;
            rc.left += 8; rc.right -= 4;
            DrawTextW(hdc, g_display, -1, &rc,
                DT_SINGLELINE | DT_VCENTER | DT_LEFT);
        } else {
            RECT clip = rc;
            clip.left += 4; clip.right -= 4;
            IntersectClipRect(hdc, clip.left, clip.top, clip.right, clip.bottom);
            rc.left = 8 - g_scroll_offset;
            rc.right = rc.left + sz.cx + 50;
            DrawTextW(hdc, g_display, -1, &rc,
                DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOCLIP);
        }

        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_TIMER:
        if (wp == IDT_REFRESH) start_fetch(hwnd);
        if (wp == IDT_SCROLL && g_cfg.scroll_enabled) {
            RECT rc;
            GetClientRect(hwnd, &rc);
            int avail = rc.right - rc.left - 12;
            if (g_text_width > avail) {
                g_scroll_offset += SCROLL_SPEED;
                if (g_scroll_offset > g_text_width + 40)
                    g_scroll_offset = 0;
                InvalidateRect(hwnd, NULL, FALSE);
            }
        }
        return 0;

    case WM_FETCH_DONE: {
        FetchContext *ctx = (FetchContext *)lp;
        if (ctx->success) {
            memcpy(g_last_response, ctx->result, FETCH_BUF_SIZE);
            BOOL handled = FALSE;
            if (g_cfg.selected >= 0 && g_cfg.selected < g_cfg.count) {
                PinItem *it = &g_cfg.items[g_cfg.selected];
                if (it->field_expr[0]) {
                    char lua_code[CFG_MAX_EXPR * 3];
                    WideCharToMultiByte(CP_UTF8, 0, it->field_expr, -1,
                        lua_code, sizeof(lua_code), NULL, NULL);
                    if (script_exec(lua_code, ctx->result, &g_script_result)) {
                        lstrcpynW(g_display, g_script_result.display, FETCH_BUF_SIZE);
                        handled = TRUE;
                    } else {
                        extract_fields(ctx->result, it->field_expr, g_display, FETCH_BUF_SIZE);
                        g_script_result.clickable = it->click_enabled;
                        if (it->click_enabled)
                            extract_fields(ctx->result, it->click_url, g_script_result.click_url, 1024);
                        handled = TRUE;
                    }
                }
            }
            if (!handled) {
                MultiByteToWideChar(CP_UTF8, 0, ctx->result, -1,
                    g_display, FETCH_BUF_SIZE);
            }
        } else {
            lstrcpyW(g_display, L"[error]");
        }
        HeapFree(GetProcessHeap(), 0, ctx);
        g_fetching = FALSE;
        g_scroll_offset = 0;
        InvalidateRect(hwnd, NULL, TRUE);
        return 0;
    }

    case WM_LBUTTONUP: {
        if (g_script_result.clickable && g_script_result.click_url[0]) {
            ShellExecuteW(NULL, L"open", g_script_result.click_url, NULL, NULL, SW_SHOWNORMAL);
        }
        return 0;
    }

    case WM_LBUTTONDBLCLK:
        show_main_window();
        return 0;

    case WM_RBUTTONUP: {
        POINT pt;
        GetCursorPos(&pt);
        HMENU hMenu = CreatePopupMenu();
        AppendMenuW(hMenu, MF_STRING, IDM_SHOW, L"Manage Items...");
        AppendMenuW(hMenu, MF_SEPARATOR, 0, NULL);
        AppendMenuW(hMenu, MF_STRING, IDM_EXIT, L"Exit");
        SetForegroundWindow(hwnd);
        TrackPopupMenu(hMenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, NULL);
        DestroyMenu(hMenu);
        return 0;
    }

    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case IDM_SHOW: show_main_window(); break;
        case IDM_EXIT: DestroyWindow(hwnd); break;
        }
        return 0;

    case WM_DESTROY:
        KillTimer(hwnd, IDT_REFRESH);
        KillTimer(hwnd, IDT_SCROLL);
        appbar_remove(hwnd);
        if (g_main_hwnd) DestroyWindow(g_main_hwnd);
        if (g_font) DeleteObject(g_font);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}