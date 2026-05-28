#include "ui.h"

/* ─── Helper: get BarInstance from HWND ─── */

static BarInstance *bar_from_hwnd(HWND hwnd) {
    return (BarInstance *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
}

/* ─── Lua worker thread ─── */

static DWORD WINAPI lua_worker_thread(LPVOID param) {
    LuaContext *ctx = (LuaContext *)param;
    ctx->success = script_exec_file(ctx->lua_path, ctx->params, ctx->param_count, &ctx->result);
    PostMessageW(ctx->hwnd, WM_LUA_DONE, 0, (LPARAM)ctx);
    return 0;
}

/* ─── Fetch logic (per-instance) ─── */

void start_fetch(BarInstance *bar) {
    if (bar->fetching) return;
    int idx = bar->item_index;
    if (idx < 0 || idx >= g_cfg.count) {
        lstrcpyW(bar->display, L"(no item)");
        InvalidateRect(bar->hwnd, NULL, TRUE);
        return;
    }

    PinItem *it = &g_cfg.items[idx];

    if (it->type == ITEM_TYPE_LUA) {
        if (!it->lua_path[0]) {
            lstrcpyW(bar->display, L"(no script)");
            bar->rich.count = 0;
            InvalidateRect(bar->hwnd, NULL, TRUE);
            return;
        }
        bar->fetching = TRUE;
        LuaContext *lctx = (LuaContext *)HeapAlloc(
            GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(LuaContext));
        if (!lctx) { bar->fetching = FALSE; return; }
        lctx->hwnd = bar->hwnd;
        lstrcpynW(lctx->lua_path, it->lua_path, MAX_PATH);
        memcpy(lctx->params, it->params, sizeof(it->params));
        lctx->param_count = it->param_count;
        HANDLE hThread = CreateThread(NULL, 0, lua_worker_thread, lctx, 0, NULL);
        if (hThread) CloseHandle(hThread);
        else { HeapFree(GetProcessHeap(), 0, lctx); bar->fetching = FALSE; }
        return;
    }

    /* URL mode: async HTTP fetch */
    bar->fetching = TRUE;
    FetchContext *ctx = (FetchContext *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(FetchContext));
    if (!ctx) { bar->fetching = FALSE; return; }

    ctx->hwnd = bar->hwnd;
    lstrcpynW(ctx->url, it->url, 1024);
    lstrcpynW(ctx->headers, it->req_headers, 1024);

    HANDLE hThread = CreateThread(NULL, 0, fetcher_thread, ctx, 0, NULL);
    if (hThread) CloseHandle(hThread);
    else { HeapFree(GetProcessHeap(), 0, ctx); bar->fetching = FALSE; }
}

/* ─── Bar window proc ─── */

LRESULT CALLBACK bar_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    BarInstance *bar = bar_from_hwnd(hwnd);

    switch (msg) {
    case WM_CREATE: {
        int font_height = -MulDiv(g_cfg.font_size, 96, 72);
        if (!g_font) {
            g_font = CreateFontW(font_height, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
        }
        SetTimer(hwnd, IDT_SCROLL, SCROLL_INTERVAL, NULL);
        return 0;
    }

    case WM_PAINT: {
        if (!bar) break;
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rc;
        GetClientRect(hwnd, &rc);

        COLORREF bg = (bar->item_index >= 0 && bar->item_index < g_cfg.count
            && g_cfg.items[bar->item_index].bar_bg_color != 0xFFFFFFFF)
            ? g_cfg.items[bar->item_index].bar_bg_color : g_cfg.bg_color;
        HBRUSH hBrush = CreateSolidBrush(bg);
        FillRect(hdc, &rc, hBrush);
        DeleteObject(hBrush);

        SetBkMode(hdc, TRANSPARENT);

        if (bar->rich.count > 0) {
            BOOL has_newline = FALSE;
            for (int i = 0; i < bar->rich.count; i++) {
                if (bar->rich.spans[i].newline) { has_newline = TRUE; break; }
            }

            int line_y[2];
            if (has_newline) { line_y[0] = 2; line_y[1] = rc.bottom / 2 + 1; }
            else { line_y[0] = 0; line_y[1] = 0; }

            int span_widths[MAX_SPANS] = {0};
            int span_heights[MAX_SPANS] = {0};
            int left_total[2] = {0, 0};
            int cur_line = 0;

            for (int i = 0; i < bar->rich.count; i++) {
                DisplaySpan *sp = &bar->rich.spans[i];
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
                if (sp->align != SPAN_ALIGN_RIGHT) left_total[cur_line] += sz.cx;
                SelectObject(hdc, old);
                DeleteObject(hf);
            }

            int margin = 8;
            int left_x[2] = { margin - bar->scroll_offset, margin };
            int right_x[2] = { rc.right - margin, rc.right - margin };
            cur_line = 0;

            for (int i = 0; i < bar->rich.count; i++) {
                DisplaySpan *sp = &bar->rich.spans[i];
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
            bar->text_width = left_total[0];
        } else {
            SetTextColor(hdc, g_cfg.font_color);
            SelectObject(hdc, g_font);
            SIZE sz;
            GetTextExtentPoint32W(hdc, bar->display, lstrlenW(bar->display), &sz);
            bar->text_width = sz.cx;

            int avail = rc.right - rc.left - 12;
            if (sz.cx <= avail) {
                bar->scroll_offset = 0;
                rc.left += 8; rc.right -= 4;
                DrawTextW(hdc, bar->display, -1, &rc,
                    DT_SINGLELINE | DT_VCENTER | DT_LEFT);
            } else {
                RECT clip = rc;
                clip.left += 4; clip.right -= 4;
                IntersectClipRect(hdc, clip.left, clip.top, clip.right, clip.bottom);
                rc.left = 8 - bar->scroll_offset;
                rc.right = rc.left + sz.cx + 50;
                DrawTextW(hdc, bar->display, -1, &rc,
                    DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOCLIP);
            }
        }

        if (bar->show_border) {
            HPEN pen = CreatePen(PS_SOLID, 1, RGB(128, 128, 128));
            HPEN old_pen = (HPEN)SelectObject(hdc, pen);
            HBRUSH old_br = (HBRUSH)SelectObject(hdc, GetStockObject(NULL_BRUSH));
            RECT brc;
            GetClientRect(hwnd, &brc);
            Rectangle(hdc, brc.left, brc.top, brc.right, brc.bottom);
            SelectObject(hdc, old_br);
            SelectObject(hdc, old_pen);
            DeleteObject(pen);
        }

        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_TIMER:
        if (!bar) break;
        if (wp == IDT_REFRESH) start_fetch(bar);
        if (wp == IDT_BORDER) {
            KillTimer(hwnd, IDT_BORDER);
            bar->show_border = FALSE;
            InvalidateRect(hwnd, NULL, TRUE);
        }
        if (wp == IDT_SCROLL && g_cfg.scroll_enabled) {
            RECT rc;
            GetClientRect(hwnd, &rc);
            int avail = rc.right - rc.left - 12;
            if (bar->text_width > avail) {
                bar->scroll_offset += SCROLL_SPEED;
                if (bar->scroll_offset > bar->text_width + 40)
                    bar->scroll_offset = 0;
                InvalidateRect(hwnd, NULL, FALSE);
            }
        }
        return 0;

    case WM_FETCH_DONE: {
        if (!bar) break;
        FetchContext *ctx = (FetchContext *)lp;
        if (ctx->success) {
            memcpy(bar->last_response, ctx->result, FETCH_BUF_SIZE);
            BOOL handled = FALSE;
            int idx = bar->item_index;
            if (idx >= 0 && idx < g_cfg.count) {
                PinItem *it = &g_cfg.items[idx];
                if (it->field_expr[0]) {
                    char lua_code[CFG_MAX_EXPR * 3];
                    WideCharToMultiByte(CP_UTF8, 0, it->field_expr, -1,
                        lua_code, sizeof(lua_code), NULL, NULL);
                    if (script_exec(lua_code, ctx->result, &bar->script_result)) {
                        lstrcpynW(bar->display, bar->script_result.display, FETCH_BUF_SIZE);
                        bar->rich = bar->script_result.rich;
                        handled = TRUE;
                    } else {
                        extract_fields(ctx->result, it->field_expr, bar->display, FETCH_BUF_SIZE);
                        bar->rich.count = 0;
                        bar->script_result.clickable = it->click_enabled;
                        if (it->click_enabled)
                            extract_fields(ctx->result, it->click_url, bar->script_result.click_url, 1024);
                        handled = TRUE;
                    }
                }
            }
            if (!handled) {
                MultiByteToWideChar(CP_UTF8, 0, ctx->result, -1, bar->display, FETCH_BUF_SIZE);
            }
        } else {
            lstrcpyW(bar->display, L"[error]");
        }
        HeapFree(GetProcessHeap(), 0, ctx);
        bar->fetching = FALSE;
        bar->scroll_offset = 0;
        InvalidateRect(hwnd, NULL, TRUE);
        return 0;
    }

    case WM_LUA_DONE: {
        if (!bar) break;
        LuaContext *lctx = (LuaContext *)lp;
        if (lctx->success) {
            bar->script_result = lctx->result;
            lstrcpynW(bar->display, lctx->result.display, FETCH_BUF_SIZE);
            bar->rich = lctx->result.rich;
        } else {
            lstrcpyW(bar->display, L"[script error]");
            bar->rich.count = 0;
        }
        HeapFree(GetProcessHeap(), 0, lctx);
        bar->fetching = FALSE;
        bar->scroll_offset = 0;
        InvalidateRect(hwnd, NULL, TRUE);
        return 0;
    }

    case WM_LBUTTONUP:
        if (bar && bar->script_result.clickable && bar->script_result.click_url[0]) {
            ShellExecuteW(NULL, L"open", bar->script_result.click_url, NULL, NULL, SW_SHOWNORMAL);
        }
        return 0;

    case WM_LBUTTONDBLCLK:
        show_main_window();
        return 0;

    case WM_MOUSEWHEEL: {
        if (!bar || bar->item_index < 0) break;
        int delta = GET_WHEEL_DELTA_WPARAM(wp);
        int idx = bar->item_index;
        BOOL shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;

        bar->show_border = TRUE;
        SetTimer(hwnd, IDT_BORDER, 800, NULL);

        if (shift) {
            /* Shift+wheel: adjust X position within taskbar */
            RECT wr; GetWindowRect(hwnd, &wr);
            POINT pt = { wr.left, wr.top };
            HWND parent = GetParent(hwnd);
            if (parent) ScreenToClient(parent, &pt);
            pt.x += (delta > 0) ? -10 : 10;
            /* Clamp within parent */
            if (pt.x < 0) pt.x = 0;
            RECT prc; GetClientRect(parent ? parent : GetDesktopWindow(), &prc);
            if (pt.x > prc.right - 50) pt.x = prc.right - 50;
            g_cfg.items[idx].bar_x = pt.x;
            SetWindowPos(hwnd, NULL, pt.x, pt.y, 0, 0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        } else {
            /* Normal wheel: adjust width */
            int cur_w = g_cfg.items[idx].bar_width > 0 ? g_cfg.items[idx].bar_width : g_cfg.width;
            cur_w += (delta > 0) ? 5 : -5;
            if (cur_w < 50) cur_w = 50;
            if (cur_w > 800) cur_w = 800;
            g_cfg.items[idx].bar_width = cur_w;
            RECT wr; GetWindowRect(hwnd, &wr);
            SetWindowPos(hwnd, NULL, 0, 0, cur_w, wr.bottom - wr.top,
                SWP_NOMOVE | SWP_NOZORDER);
            InvalidateRect(hwnd, NULL, TRUE);
        }
        config_save(&g_cfg);
        return 0;
    }

    case WM_RBUTTONUP: {
        POINT pt;
        GetCursorPos(&pt);
        HMENU hMenu = CreatePopupMenu();
        if (bar && bar->item_index >= 0)
            AppendMenuW(hMenu, MF_STRING, IDM_UNPIN, L"Unpin");
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
        case IDM_EXIT: bars_destroy_all(); PostQuitMessage(0); break;
        case IDM_UNPIN:
            if (bar && bar->item_index >= 0 && bar->item_index < g_cfg.count) {
                g_cfg.items[bar->item_index].pinned = FALSE;
                config_save(&g_cfg);
                bars_destroy_all();
                bars_create_all();
                listview_populate();
            }
            break;
        }
        return 0;

    case WM_DESTROY:
        KillTimer(hwnd, IDT_REFRESH);
        KillTimer(hwnd, IDT_SCROLL);
        appbar_remove(hwnd);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

/* ─── Multi-bar lifecycle ─── */

void bars_create_all(void) {
    g_bar_count = 0;
    int offset_x = 0;

    for (int i = 0; i < g_cfg.count && g_bar_count < MAX_BARS; i++) {
        if (!g_cfg.items[i].pinned) continue;

        BarInstance *bar = &g_bars[g_bar_count];
        memset(bar, 0, sizeof(*bar));
        bar->item_index = i;
        lstrcpyW(bar->display, g_cfg.items[i].name);

        int w = g_cfg.items[i].bar_width > 0 ? g_cfg.items[i].bar_width : g_cfg.width;

        bar->hwnd = CreateWindowExW(
            WS_EX_TOOLWINDOW,
            L"TaskPinBarClass", L"TaskPin",
            WS_POPUP,
            0, 0, w, 40,
            NULL, NULL, g_hinst, NULL);
        if (!bar->hwnd) continue;

        SetWindowLongPtrW(bar->hwnd, GWLP_USERDATA, (LONG_PTR)bar);

        int px = g_cfg.items[i].bar_x;
        int py = g_cfg.items[i].bar_y;
        if (px == -1) px = (g_cfg.pos_x >= 0) ? g_cfg.pos_x + offset_x : -1 - offset_x;
        if (py == -1) py = g_cfg.pos_y;
        appbar_embed(bar->hwnd, w, px, py);
        ShowWindow(bar->hwnd, SW_SHOWNOACTIVATE);
        UpdateWindow(bar->hwnd);

        SetTimer(bar->hwnd, IDT_REFRESH, g_cfg.items[i].interval_ms, NULL);
        start_fetch(bar);

        offset_x += w + 2;
        g_bar_count++;
    }

    /* If nothing pinned, create a placeholder bar */
    if (g_bar_count == 0) {
        BarInstance *bar = &g_bars[0];
        memset(bar, 0, sizeof(*bar));
        bar->item_index = -1;
        lstrcpyW(bar->display, L"TaskPin");

        bar->hwnd = CreateWindowExW(
            WS_EX_TOOLWINDOW,
            L"TaskPinBarClass", L"TaskPin",
            WS_POPUP,
            0, 0, g_cfg.width, 40,
            NULL, NULL, g_hinst, NULL);
        if (bar->hwnd) {
            SetWindowLongPtrW(bar->hwnd, GWLP_USERDATA, (LONG_PTR)bar);
            appbar_embed(bar->hwnd, g_cfg.width, g_cfg.pos_x, g_cfg.pos_y);
            ShowWindow(bar->hwnd, SW_SHOWNOACTIVATE);
            UpdateWindow(bar->hwnd);
            g_bar_count = 1;
        }
    }
}

void bars_destroy_all(void) {
    for (int i = 0; i < g_bar_count; i++) {
        if (g_bars[i].hwnd) {
            DestroyWindow(g_bars[i].hwnd);
            g_bars[i].hwnd = NULL;
        }
    }
    g_bar_count = 0;
    if (g_main_hwnd) DestroyWindow(g_main_hwnd);
    if (g_font) { DeleteObject(g_font); g_font = NULL; }
}