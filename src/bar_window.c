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
                g_display_rich = g_script_result.rich;
            } else {
                lstrcpyW(g_display, L"[script error]");
                g_display_rich.count = 0;
            }
        } else {
            lstrcpyW(g_display, L"(no script)");
            g_display_rich.count = 0;
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

        if (g_display_rich.count > 0) {
            /* Rich text rendering: multi-span with align support */
            BOOL has_newline = FALSE;
            for (int i = 0; i < g_display_rich.count; i++) {
                if (g_display_rich.spans[i].newline) { has_newline = TRUE; break; }
            }

            int line_y[2];
            if (has_newline) {
                line_y[0] = 2;
                line_y[1] = rc.bottom / 2 + 1;
            } else {
                line_y[0] = 0;
                line_y[1] = 0;
            }

            /* Measure pass: compute width of each span and totals per align group */
            int span_widths[MAX_SPANS] = {0};
            int span_heights[MAX_SPANS] = {0};
            int left_total[2] = {0, 0};
            int right_total[2] = {0, 0};
            int cur_line = 0;

            for (int i = 0; i < g_display_rich.count; i++) {
                DisplaySpan *sp = &g_display_rich.spans[i];
                if (sp->newline) { cur_line = 1; continue; }
                if (!sp->text[0]) continue;

                int pt = sp->font_size > 0 ? sp->font_size : g_cfg.font_size;
                int fh = -MulDiv(pt, 96, 72);
                HFONT hf = CreateFontW(fh, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
                HFONT old = (HFONT)SelectObject(hdc, hf);

                SIZE sz;
                GetTextExtentPoint32W(hdc, sp->text, lstrlenW(sp->text), &sz);
                span_widths[i] = sz.cx;
                span_heights[i] = sz.cy;

                if (sp->align == SPAN_ALIGN_RIGHT) right_total[cur_line] += sz.cx;
                else left_total[cur_line] += sz.cx;

                SelectObject(hdc, old);
                DeleteObject(hf);
            }

            /* Draw pass */
            int margin = 8;
            int left_x[2] = { margin - g_scroll_offset, margin };
            int right_x[2] = { rc.right - margin, rc.right - margin };
            cur_line = 0;

            for (int i = 0; i < g_display_rich.count; i++) {
                DisplaySpan *sp = &g_display_rich.spans[i];
                if (sp->newline) { cur_line = 1; continue; }
                if (!sp->text[0]) continue;

                int pt = sp->font_size > 0 ? sp->font_size : g_cfg.font_size;
                int fh = -MulDiv(pt, 96, 72);
                HFONT hf = CreateFontW(fh, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
                HFONT old = (HFONT)SelectObject(hdc, hf);

                COLORREF clr = (sp->color != 0xFFFFFFFF) ? sp->color : g_cfg.font_color;
                SetTextColor(hdc, clr);

                int draw_x, draw_y;
                draw_y = has_newline ? line_y[cur_line] : (rc.bottom - span_heights[i]) / 2;

                if (sp->align == SPAN_ALIGN_RIGHT) {
                    right_x[cur_line] -= span_widths[i];
                    draw_x = right_x[cur_line];
                } else if (sp->align == SPAN_ALIGN_CENTER) {
                    draw_x = (rc.right - span_widths[i]) / 2;
                } else {
                    draw_x = left_x[cur_line];
                    left_x[cur_line] += span_widths[i];
                }

                TextOutW(hdc, draw_x, draw_y, sp->text, lstrlenW(sp->text));

                SelectObject(hdc, old);
                DeleteObject(hf);
            }

            g_text_width = left_total[0];
        } else {
            /* Plain text rendering (original path) */
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
                        g_display_rich = g_script_result.rich;
                        handled = TRUE;
                    } else {
                        extract_fields(ctx->result, it->field_expr, g_display, FETCH_BUF_SIZE);
                        g_display_rich.count = 0;
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