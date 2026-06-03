#include "ui.h"
#include "image.h"
#include "json.h"
#include "logger.h"
#include <stdio.h>

static void event_log_btn(const char *msg) {
    logger_write(LOG_INFO, "button clicked: %s", msg);
}

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
        bar->button_count = 0;
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rc;
        GetClientRect(hwnd, &rc);

        COLORREF bg = (bar->item_index >= 0 && bar->item_index < g_cfg.count
            && g_cfg.items[bar->item_index].bar_bg_color != 0xFFFFFFFF)
            ? g_cfg.items[bar->item_index].bar_bg_color : g_cfg.bg_color;
        BOOL has_buttons = FALSE;
        for (int i = 0; i < bar->rich.count; i++) {
            if (bar->rich.spans[i].is_button) { has_buttons = TRUE; break; }
        }
        if (bar->show_border && !has_buttons) bg = RGB(39, 39, 39);
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

                if (sp->is_image) {
                    int iw = 0, ih = 0;
                    HBITMAP hbmp = image_load(sp->img_source, sp->img_w, sp->img_h, &iw, &ih);
                    span_widths[i] = hbmp ? iw : 0;
                    span_heights[i] = hbmp ? ih : 0;
                    if (sp->align != SPAN_ALIGN_RIGHT) left_total[cur_line] += span_widths[i];
                    continue;
                }

                if (!sp->text[0]) continue;

                int pt = sp->font_size > 0 ? sp->font_size : g_cfg.font_size;
                int fh = -MulDiv(pt, 96, 72);
                HFONT hf = CreateFontW(fh, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
                HFONT old = (HFONT)SelectObject(hdc, hf);
                SIZE sz;
                GetTextExtentPoint32W(hdc, sp->text, lstrlenW(sp->text), &sz);
                /* Buttons get extra padding */
                int extra_w = sp->is_button ? 12 : 0;
                int margin = sp->margin;
                span_widths[i] = sz.cx + extra_w + margin;
                span_heights[i] = sz.cy;
                if (sp->align != SPAN_ALIGN_RIGHT) left_total[cur_line] += sz.cx + extra_w;
                SelectObject(hdc, old);
                DeleteObject(hf);
            }

            int margin = 8;
            int left_x[2] = { margin - bar->scroll_offset, margin };
            int right_x[2] = { rc.right - margin, rc.right - margin };
            cur_line = 0;

            /* Calculate first line's image offset for second line alignment */
            if (has_newline) {
                int img_offset = 0;
                for (int i = 0; i < bar->rich.count; i++) {
                    DisplaySpan *sp = &bar->rich.spans[i];
                    if (sp->newline) break;
                    if (sp->is_image && span_widths[i] > 0) {
                        img_offset += span_widths[i];
                    } else {
                        break;
                    }
                }
                left_x[1] = margin + img_offset;
            }

            for (int i = 0; i < bar->rich.count; i++) {
                DisplaySpan *sp = &bar->rich.spans[i];
                if (sp->newline) { cur_line = 1; continue; }

                if (sp->is_image) {
                    if (span_widths[i] <= 0) continue;
                    int draw_x, draw_y;
                    draw_y = (rc.bottom - span_heights[i]) / 2;
                    if (sp->align == SPAN_ALIGN_RIGHT) {
                        right_x[cur_line] -= span_widths[i];
                        draw_x = right_x[cur_line];
                    } else if (sp->align == SPAN_ALIGN_CENTER) {
                        draw_x = (rc.right - span_widths[i]) / 2;
                    } else {
                        draw_x = left_x[cur_line];
                        left_x[cur_line] += span_widths[i];
                    }
                    int iw = 0, ih = 0;
                    HBITMAP hbmp = image_load(sp->img_source, sp->img_w, sp->img_h, &iw, &ih);
                    if (hbmp) {
                        HDC hMemDC = CreateCompatibleDC(hdc);
                        HBITMAP hOld = (HBITMAP)SelectObject(hMemDC, hbmp);
                        BLENDFUNCTION bf = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
                        AlphaBlend(hdc, draw_x, draw_y, iw, ih, hMemDC, 0, 0, iw, ih, bf);
                        SelectObject(hMemDC, hOld);
                        DeleteDC(hMemDC);
                    }
                    continue;
                }

                if (!sp->text[0]) continue;

                int pt = sp->font_size > 0 ? sp->font_size : g_cfg.font_size;
                int fh = -MulDiv(pt, 96, 72);
                HFONT hf = CreateFontW(fh, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
                HFONT old = (HFONT)SelectObject(hdc, hf);

                COLORREF clr = (sp->color != 0xFFFFFFFF) ? sp->color : g_cfg.font_color;

                int draw_x, draw_y;
                if (has_newline) {
                    int line_h = rc.bottom / 2;
                    draw_y = line_y[cur_line] + (line_h - span_heights[i]) / 2;
                } else {
                    draw_y = (rc.bottom - span_heights[i]) / 2;
                }

                if (sp->align == SPAN_ALIGN_RIGHT) {
                    right_x[cur_line] -= span_widths[i];
                    draw_x = right_x[cur_line];
                } else if (sp->align == SPAN_ALIGN_CENTER) {
                    draw_x = (rc.right - span_widths[i]) / 2;
                } else {
                    draw_x = left_x[cur_line];
                    left_x[cur_line] += span_widths[i];
                }

                if (sp->is_button) {
                    int bbd = 1, brad = 4;
                    int bh = 28;
                    int by = (rc.bottom - bh) / 2;
                    int btn_w = span_widths[i] - sp->margin;
                    RECT br = { draw_x, by, draw_x + btn_w, by + bh };

                    BOOL is_hover = (bar->button_count == bar->hover_button);
                    COLORREF bgc;
                    if (is_hover && sp->hover_bg != 0xFFFFFFFF)
                        bgc = sp->hover_bg;
                    else if (is_hover)
                        bgc = RGB(39, 39, 39);
                    else
                        bgc = (sp->bg_color != 0xFFFFFFFF) ? sp->bg_color : RGB(64,64,64);

                    COLORREF txt_clr;
                    if (is_hover && sp->hover_color != 0xFFFFFFFF)
                        txt_clr = sp->hover_color;
                    else
                        txt_clr = clr;

                    HBRUSH hb = CreateSolidBrush(bgc);
                    COLORREF bdr = (sp->border_color != 0xFFFFFFFF) ? sp->border_color : bgc;
                    HPEN hp = CreatePen(PS_SOLID, bbd, bdr);
                    HBRUSH hOldBr = (HBRUSH)SelectObject(hdc, hb);
                    HPEN hOldPn = (HPEN)SelectObject(hdc, hp);
                    RoundRect(hdc, br.left, br.top, br.right, br.bottom, brad, brad);
                    SelectObject(hdc, hOldBr);
                    SelectObject(hdc, hOldPn);
                    DeleteObject(hb);
                    DeleteObject(hp);

                    SetTextColor(hdc, txt_clr);
                    SetBkMode(hdc, TRANSPARENT);
                    DrawTextW(hdc, sp->text, lstrlenW(sp->text), &br,
                        DT_SINGLELINE | DT_VCENTER | DT_CENTER);

                    /* Store for hit-test */
                    if (bar->button_count < MAX_BAR_BUTTONS) {
                        BarButton *bb = &bar->buttons[bar->button_count];
                        bb->rect = br;
                        if (sp->cmd[0]) strncpy(bb->cmd, sp->cmd, 511);
                        else bb->cmd[0] = '\0';
                        if (sp->response[0]) strncpy(bb->response, sp->response, 4095);
                        else bb->response[0] = '\0';
                        bb->bg_color = (sp->bg_color != 0xFFFFFFFF) ? sp->bg_color : RGB(64,64,64);
                        bb->color = clr;
                        bb->hover_bg = sp->hover_bg;
                        bb->hover_color = sp->hover_color;
                        bar->button_count++;
                    }
                } else if (sp->is_input) {
                    int ih = 22;
                    int iy = (rc.bottom - ih) / 2;
                    int iw = span_widths[i] > 0 ? span_widths[i] : 120;
                    if (!bar->input_hwnd) {
                        bar->input_hwnd = CreateWindowExW(0, L"EDIT", L"",
                            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
                            draw_x, iy, iw, ih,
                            hwnd, NULL, GetModuleHandle(NULL), NULL);
                        HFONT hif = CreateFontW(-12, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                            CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
                        SendMessageW(bar->input_hwnd, WM_SETFONT, (WPARAM)hif, TRUE);
                        if (sp->prompt[0]) {
                            WCHAR wp[256];
                            MultiByteToWideChar(CP_UTF8, 0, sp->prompt, -1, wp, 256);
                            SendMessageW(bar->input_hwnd, EM_SETCUEBANNER, TRUE, (LPARAM)wp);
                        }
                    } else {
                        MoveWindow(bar->input_hwnd, draw_x, iy, iw, ih, TRUE);
                        ShowWindow(bar->input_hwnd, SW_SHOW);
                    }
                } else {
                    SetTextColor(hdc, clr);
                    TextOutW(hdc, draw_x, draw_y, sp->text, lstrlenW(sp->text));
                }
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

        EndPaint(hwnd, &ps);

        /* Auto-expand when buttons present */
        if (bar->button_count > 0 && !bar->width_expanded) {
            int needed = bar->text_width + 16;
            RECT wr;
            GetWindowRect(hwnd, &wr);
            int cur_w = wr.right - wr.left;
            if (needed > cur_w) {
                bar->configured_width = cur_w;
                bar->width_expanded = TRUE;
                int idx = bar->item_index;
                int px = (idx >= 0) ? g_cfg.items[idx].bar_x : -1;
                int py = (idx >= 0) ? g_cfg.items[idx].bar_y : -1;
                appbar_embed(hwnd, needed, px, py);
            }
        }

        return 0;
    }

    case WM_TIMER:
        if (!bar) break;
        if (wp == IDT_REFRESH) start_fetch(bar);
        if (wp == IDT_ANIM) InvalidateRect(hwnd, NULL, FALSE);
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
        /* Start/stop animation timer based on whether any span is animated GIF */
        {
            BOOL need_anim = FALSE;
            for (int i = 0; i < bar->rich.count; i++) {
                DisplaySpan *sp = &bar->rich.spans[i];
                if (sp->is_image && sp->img_source[0]) {
                    if (image_is_animated(sp->img_source, sp->img_w, sp->img_h)) {
                        need_anim = TRUE;
                        break;
                    }
                }
            }
            if (need_anim) SetTimer(hwnd, IDT_ANIM, ANIM_INTERVAL, NULL);
            else KillTimer(hwnd, IDT_ANIM);
        }
        return 0;
    }

    case WM_MOUSEMOVE:
        if (bar) {
            if (!bar->show_border) {
                TRACKMOUSEEVENT tme = { sizeof(tme), TME_LEAVE, hwnd, 0 };
                TrackMouseEvent(&tme);
                bar->show_border = TRUE;
                if (bar->button_count == 0)
                    InvalidateRect(hwnd, NULL, TRUE);
            }
            if (bar->button_count > 0) {
                POINT pt = { GET_X_LPARAM(lp), GET_Y_LPARAM(lp) };
                int prev = bar->hover_button;
                bar->hover_button = -1;
                for (int i = 0; i < bar->button_count; i++) {
                    if (PtInRect(&bar->buttons[i].rect, pt)) {
                        bar->hover_button = i;
                        break;
                    }
                }
                if (bar->hover_button != prev)
                    InvalidateRect(hwnd, NULL, TRUE);
            }
        }
        return 0;

    case WM_MOUSELEAVE:
        if (bar && bar->show_border) {
            bar->show_border = FALSE;
            bar->hover_button = -1;
            InvalidateRect(hwnd, NULL, TRUE);
        }
        return 0;

    case WM_LBUTTONDOWN:
        if (bar && bar->button_count > 0) {
            POINT pt = { GET_X_LPARAM(lp), GET_Y_LPARAM(lp) };
            for (int i = 0; i < bar->button_count; i++) {
                BarButton *bb = &bar->buttons[i];
                if (PtInRect(&bb->rect, pt) && (bb->cmd[0] || bb->response[0])) {
                    event_log_btn(bb->response[0] ? bb->response : bb->cmd);
                    if (bb->response[0]) {
                        char resp_path[MAX_PATH];
                        event_get_response_file(resp_path, MAX_PATH);
                        if (resp_path[0]) {
                            /* Replace {input} with text from input control */
                            char final_resp[4096];
                            char *placeholder = strstr(bb->response, "{input}");
                            if (placeholder && bar->input_hwnd) {
                                WCHAR winput[512];
                                GetWindowTextW(bar->input_hwnd, winput, 512);
                                char input_utf8[1024];
                                WideCharToMultiByte(CP_UTF8, 0, winput, -1, input_utf8, sizeof(input_utf8), NULL, NULL);
                                int prefix_len = (int)(placeholder - bb->response);
                                memcpy(final_resp, bb->response, prefix_len);
                                int ilen = (int)strlen(input_utf8);
                                memcpy(final_resp + prefix_len, input_utf8, ilen);
                                strcpy(final_resp + prefix_len + ilen, placeholder + 7);
                                FILE *f = fopen(resp_path, "w");
                                if (f) { fputs(final_resp, f); fclose(f); }
                            } else {
                                FILE *f = fopen(resp_path, "w");
                                if (f) { fputs(bb->response, f); fclose(f); }
                            }
                        }
                    } else if (bb->cmd[0]) {
                        STARTUPINFOW si;
                        memset(&si, 0, sizeof(si));
                        si.cb = sizeof(si);
                        si.dwFlags = STARTF_USESHOWWINDOW;
                        si.wShowWindow = SW_HIDE;
                        PROCESS_INFORMATION pi;
                        WCHAR wcmd[600];
                        MultiByteToWideChar(CP_UTF8, 0, bb->cmd, -1, wcmd, 600);
                        WCHAR cmdline[700];
                        wsprintfW(cmdline, L"cmd /c %s", wcmd);
                        if (CreateProcessW(NULL, cmdline, NULL, NULL, FALSE,
                                CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
                            CloseHandle(pi.hProcess);
                            CloseHandle(pi.hThread);
                        }
                    }
                    event_clear();
                    bar->button_count = 0;
                    bar->hover_button = -1;
                    bar->rich.count = 0;
                    bar->width_expanded = FALSE;
                    bar->script_result.clickable = FALSE;
                    if (bar->input_hwnd) {
                        DestroyWindow(bar->input_hwnd);
                        bar->input_hwnd = NULL;
                    }
                    /* Restore configured width and refresh immediately */
                    if (bar->configured_width > 0) {
                        int idx = bar->item_index;
                        int px = (idx >= 0) ? g_cfg.items[idx].bar_x : -1;
                        int py = (idx >= 0) ? g_cfg.items[idx].bar_y : -1;
                        appbar_embed(hwnd, bar->configured_width, px, py);
                    }
                    start_fetch(bar);
                    return 0;
                }
            }
        }
        break;

    case WM_LBUTTONUP:
        if (bar) {
            /* Check if click is on a bar button first */
            POINT pt = { GET_X_LPARAM(lp), GET_Y_LPARAM(lp) };
            for (int i = 0; i < bar->button_count; i++) {
                BarButton *bb = &bar->buttons[i];
                if (PtInRect(&bb->rect, pt) && bb->cmd[0]) {
                    /* Execute button command async */
                    STARTUPINFOW si;
                    memset(&si, 0, sizeof(si));
                    si.cb = sizeof(si);
                    si.dwFlags = STARTF_USESHOWWINDOW;
                    si.wShowWindow = SW_HIDE;
                    PROCESS_INFORMATION pi;
                    WCHAR wcmd[600];
                    MultiByteToWideChar(CP_UTF8, 0, bb->cmd, -1, wcmd, 600);
                    WCHAR cmdline[700];
                    wsprintfW(cmdline, L"cmd /c %s", wcmd);
                    if (CreateProcessW(NULL, cmdline, NULL, NULL, FALSE,
                            CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
                        CloseHandle(pi.hProcess);
                        CloseHandle(pi.hThread);
                    }
                    bar->button_count = 0;
                    InvalidateRect(hwnd, NULL, TRUE);
                    return 0;
                }
            }
            /* Fall through to global click action */
            bar->button_count = 0;
            InvalidateRect(hwnd, NULL, TRUE);
            if (bar->script_result.clickable) {
                if (bar->script_result.click_action == CLICK_DIALOG && bar->item_index >= 0) {
                    PinItem *it = &g_cfg.items[bar->item_index];
                    show_script_dialog(it->lua_path, it->params, it->param_count,
                        &bar->script_result.dialog);
                } else if (bar->script_result.click_url[0]) {
                    ShellExecuteW(NULL, L"open", bar->script_result.click_url, NULL, NULL, SW_SHOWNORMAL);
                }
            }
        }
        return 0;

    case WM_LBUTTONDBLCLK:
        show_main_window();
        return 0;

    case WM_COPYDATA: {
        COPYDATASTRUCT *cds = (COPYDATASTRUCT *)lp;
        if (cds && cds->dwData == COPYDATA_EVENT_ID) {
            event_receive(cds->lpData, (int)cds->cbData);
            for (int i = 0; i < g_bar_count; i++) {
                if (g_bars[i].hwnd)
                    PostMessageW(g_bars[i].hwnd, WM_TIMER, IDT_REFRESH, 0);
            }
            return TRUE;
        }
        if (cds && cds->dwData == 0x5451) {
            const WCHAR *url = (const WCHAR *)cds->lpData;
            import_script_from_url(url);
            return TRUE;
        }
        break;
    }

    case WM_MOUSEWHEEL: {
        if (!bar || bar->item_index < 0) break;
        int delta = GET_WHEEL_DELTA_WPARAM(wp);
        int idx = bar->item_index;
        BOOL shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;

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
        KillTimer(hwnd, IDT_ANIM);
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
        bar->hover_button = -1;
        lstrcpyW(bar->display, g_cfg.items[i].name);

        int w = g_cfg.items[i].bar_width;
        if (w <= 0 && g_cfg.items[i].lua_path[0]) {
            w = script_parse_bar_width(g_cfg.items[i].lua_path);
        }
        if (w <= 0) w = g_cfg.width;
        bar->configured_width = w;

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
        bar->hover_button = -1;
        bar->configured_width = g_cfg.width;
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