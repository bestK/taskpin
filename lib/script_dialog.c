#include "script_dialog.h"
#include "scripting.h"
#include "config.h"
#include "image.h"
#include "webview2.h"
#include "i18n.h"
#include "logger.h"
#include <shellapi.h>
#include <shlwapi.h>
#include <windowsx.h>
#include <stdlib.h>
#include <string.h>

extern TaskPinConfig g_cfg;

#define DIALOG_CLASS L"TaskPinScriptDialog"
#define DIALOG_BG       RGB(30, 30, 30)
#define DIALOG_FG       RGB(220, 220, 220)
#define DIALOG_HR_COLOR RGB(60, 60, 60)
#define IDT_DIALOG_ESC     11
#define TABLE_ROW_EVEN  RGB(35, 35, 35)
#define TABLE_ROW_ODD   RGB(40, 40, 40)
#define TABLE_HDR_BG    RGB(45, 45, 45)
#define PADDING_X 12
#define PADDING_Y 8
#define DLG_BTN_BASE_ID 7000
#define DLG_MAX_BUTTONS 8
#define DLG_TBL_BTN_BASE_ID 7100
#define DLG_MAX_TBL_BUTTONS 24

/* Find config item index by lua_path */
static int dlg_find_item(const WCHAR *lua_path) {
    for (int i = 0; i < g_cfg.count; i++) {
        if (lstrcmpiW(g_cfg.items[i].lua_path, lua_path) == 0)
            return i;
    }
    return -1;
}

typedef struct {
    DialogSpec spec;
    WCHAR lua_path[MAX_PATH];
    ParamEntry params[CFG_MAX_PARAMS];
    int param_count;
    int scroll_y;
    int content_height;
    HWND buttons[DLG_MAX_BUTTONS];
    int button_count;
    HWND tbl_buttons[DLG_MAX_TBL_BUTTONS];
    int tbl_button_count;
    int item_y[DIALOG_MAX_ITEMS];
    int item_h[DIALOG_MAX_ITEMS];
    WebView *webviews[DIALOG_MAX_ITEMS];
    BOOL webview_creating;
    BOOL dragging;
    POINT drag_start;
    BOOL shift_hiding_webview;
} ScriptDialogState;

#define MAX_SCRIPT_DIALOGS 16
static HWND s_dialog_hwnds[MAX_SCRIPT_DIALOGS];
static int s_dialog_count = 0;
static BOOL s_class_registered = FALSE;

static HWND find_dialog_by_path(const WCHAR *lua_path) {
    for (int i = 0; i < s_dialog_count; i++) {
        if (!s_dialog_hwnds[i]) continue;
        ScriptDialogState *st = (ScriptDialogState *)GetWindowLongPtr(s_dialog_hwnds[i], GWLP_USERDATA);
        if (st && lstrcmpiW(st->lua_path, lua_path) == 0)
            return s_dialog_hwnds[i];
    }
    return NULL;
}

static void register_dialog(HWND hwnd) {
    for (int i = 0; i < s_dialog_count; i++) {
        if (!s_dialog_hwnds[i]) { s_dialog_hwnds[i] = hwnd; return; }
    }
    if (s_dialog_count < MAX_SCRIPT_DIALOGS)
        s_dialog_hwnds[s_dialog_count++] = hwnd;
}

static void unregister_dialog(HWND hwnd) {
    for (int i = 0; i < s_dialog_count; i++) {
        if (s_dialog_hwnds[i] == hwnd) { s_dialog_hwnds[i] = NULL; return; }
    }
}

static int calc_content_height(HDC hdc, DialogSpec *spec);
static void paint_dialog(HWND hwnd, HDC hdc, ScriptDialogState *state);
static void ulw_render(HWND hwnd, ScriptDialogState *state);
static LRESULT CALLBACK dialog_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

void script_dialog_init(HINSTANCE hinst) {
    if (s_class_registered) return;
    WNDCLASSEXW wc = {0};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = dialog_wnd_proc;
    wc.hInstance = hinst;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = CreateSolidBrush(DIALOG_BG);
    wc.lpszClassName = DIALOG_CLASS;
    RegisterClassExW(&wc);
    s_class_registered = TRUE;
}

void script_dialog_close_all(void) {
    for (int i = 0; i < s_dialog_count; i++) {
        if (s_dialog_hwnds[i]) {
            DestroyWindow(s_dialog_hwnds[i]);
            s_dialog_hwnds[i] = NULL;
        }
    }
}

void script_dialog_close_by_path(const WCHAR *lua_path) {
    HWND hwnd = find_dialog_by_path(lua_path);
    if (hwnd) DestroyWindow(hwnd);
}

BOOL script_dialog_is_open(const WCHAR *lua_path) {
    return find_dialog_by_path(lua_path) != NULL;
}

void show_script_dialog(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                        const DialogSpec *spec) {
    /* Resolve to absolute path for consistent matching */
    WCHAR full_path[MAX_PATH];
    if (lua_path[0] != L'\\' && lua_path[0] != L'/' &&
        !(lua_path[0] && lua_path[1] == L':')) {
        GetModuleFileNameW(NULL, full_path, MAX_PATH);
        WCHAR *slash = wcsrchr(full_path, L'\\');
        if (slash) *(slash + 1) = L'\0';
        lstrcatW(full_path, lua_path);
    } else {
        lstrcpynW(full_path, lua_path, MAX_PATH);
    }

    HWND existing = find_dialog_by_path(full_path);
    if (existing) {
        SetForegroundWindow(existing);
        return;
    }

    ScriptDialogState *state = (ScriptDialogState *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScriptDialogState));
    if (!state) return;

    memcpy(&state->spec, spec, sizeof(DialogSpec));
    lstrcpynW(state->lua_path, full_path, MAX_PATH);
    state->param_count = param_count;
    if (params && param_count > 0)
        memcpy(state->params, params, sizeof(ParamEntry) * param_count);
    state->scroll_y = 0;

    int w = spec->width > 0 ? spec->width : 400;
    int h = spec->height > 0 ? spec->height : 300;

    /* Use saved size if available */
    {
        int idx = dlg_find_item(full_path);
        if (idx >= 0) {
            if (g_cfg.items[idx].dlg_w > 0) w = g_cfg.items[idx].dlg_w;
            if (g_cfg.items[idx].dlg_h > 0) h = g_cfg.items[idx].dlg_h;
        }
    }

    DWORD style = spec->borderless
        ? (WS_POPUP)
        : (WS_OVERLAPPEDWINDOW | WS_VSCROLL);
    DWORD exstyle = WS_EX_TOPMOST;
    if (spec->borderless)
        exstyle |= WS_EX_TOOLWINDOW;

    /* Check if dialog has webview ??layered windows can't host child windows */
    BOOL has_webview = FALSE;
    for (int i = 0; i < spec->item_count; i++) {
        if (spec->items[i].type == DI_WEBVIEW) { has_webview = TRUE; break; }
    }

    if (has_webview) {
        /* WS_EX_NOREDIRECTIONBITMAP: true per-pixel transparency via DirectComposition */
        exstyle |= 0x00200000L;
    } else if (spec->clickthrough || spec->opacity < 255 || spec->transparent_bg) {
        exstyle |= WS_EX_LAYERED;
    }
    RECT wr = {0, 0, w, h};
    AdjustWindowRectEx(&wr, style, FALSE, exstyle);

    int win_w = wr.right - wr.left;
    int win_h = wr.bottom - wr.top;
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    int x = (screen_w - win_w) / 2;
    int y = (screen_h - win_h) / 2;

    /* Use explicit x/y from spec first, then saved position */
    if (spec->x >= 0 && spec->y >= 0) {
        x = spec->x; y = spec->y;
    } else {
        int idx = dlg_find_item(state->lua_path);
        if (idx >= 0 && g_cfg.items[idx].dlg_x >= 0 && g_cfg.items[idx].dlg_y >= 0) {
            x = g_cfg.items[idx].dlg_x;
            y = g_cfg.items[idx].dlg_y;
        }
    }

    HWND dlg_hwnd = CreateWindowExW(exstyle, DIALOG_CLASS, spec->title,
        style,
        x, y, win_w, win_h,
        NULL, NULL, GetModuleHandle(NULL), state);
    register_dialog(dlg_hwnd);

    if (!has_webview) {
        if (spec->transparent_bg) {
            SetLayeredWindowAttributes(dlg_hwnd, RGB(255, 0, 255), 0, LWA_COLORKEY);
        } else if (spec->opacity < 255 || spec->clickthrough) {
            SetLayeredWindowAttributes(dlg_hwnd, 0,
                (BYTE)(spec->opacity < 255 ? spec->opacity : 255), LWA_ALPHA);
        }
    }

    /* Custom title bar colors (Windows 10 1809+) */
    if (spec->title_bg_color != 0xFFFFFFFF || spec->title_color != 0xFFFFFFFF) {
        HMODULE dwm = LoadLibraryW(L"dwmapi.dll");
        if (dwm) {
            typedef HRESULT (WINAPI *DwmSetAttrFn)(HWND, DWORD, LPCVOID, DWORD);
            DwmSetAttrFn pDwmSetAttr = (DwmSetAttrFn)GetProcAddress(dwm, "DwmSetWindowAttribute");
            if (pDwmSetAttr) {
                if (spec->title_bg_color != 0xFFFFFFFF) {
                    COLORREF bg = spec->title_bg_color;
                    pDwmSetAttr(dlg_hwnd, 35, &bg, sizeof(bg));
                }
                if (spec->title_color != 0xFFFFFFFF) {
                    COLORREF fg = spec->title_color;
                    pDwmSetAttr(dlg_hwnd, 36, &fg, sizeof(fg));
                }
            }
        }
    }

    /* Custom window icon */
    if (spec->icon[0]) {
        int out_w = 0, out_h = 0;
        HBITMAP hbmp = image_load(spec->icon, 32, 32, &out_w, &out_h);
        if (hbmp) {
            ICONINFO ii = {0};
            ii.fIcon = TRUE;
            ii.hbmMask = hbmp;
            ii.hbmColor = hbmp;
            HICON hIcon = CreateIconIndirect(&ii);
            if (hIcon) {
                SendMessageW(dlg_hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);
                SendMessageW(dlg_hwnd, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
            }
        }
    }

    ShowWindow(dlg_hwnd, SW_SHOW);
    UpdateWindow(dlg_hwnd);
}

static HFONT create_dialog_font(int pt, BOOL bold) {
    int fh = -MulDiv(pt > 0 ? pt : 10, 96, 72);
    return CreateFontW(fh, 0, 0, 0, bold ? FW_BOLD : FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
}

static int calc_content_height(HDC hdc, DialogSpec *spec) {
    int y = PADDING_Y;
    for (int i = 0; i < spec->item_count; i++) {
        DialogItem *item = &spec->items[i];
        switch (item->type) {
        case DI_TEXT: {
            int pt = item->font_size > 0 ? item->font_size : 10;
            HFONT hf = create_dialog_font(pt, item->bold);
            HFONT old = (HFONT)SelectObject(hdc, hf);
            TEXTMETRICW tm;
            GetTextMetricsW(hdc, &tm);
            y += tm.tmHeight + 4;
            SelectObject(hdc, old);
            DeleteObject(hf);
            break;
        }
        case DI_HR:
            y += 12;
            break;
        case DI_TABLE: {
            HFONT hf = create_dialog_font(10, FALSE);
            HFONT old = (HFONT)SelectObject(hdc, hf);
            TEXTMETRICW tm;
            GetTextMetricsW(hdc, &tm);
            int row_h = item->height > 0 ? item->height : (tm.tmHeight + 6);
            y += row_h; /* header */
            y += 2;     /* header separator */
            y += row_h * item->row_count;
            SelectObject(hdc, old);
            DeleteObject(hf);
            break;
        }
        case DI_IMG: {
            int rh = item->height > 0 ? item->height : 64;
            y += rh;
            break;
        }
        case DI_BUTTON: {
            int btn_h = item->height > 0 ? item->height : 26;
            if (item->align != ALIGN_INLINE) y += btn_h;
            break;
        }
        case DI_WEBVIEW: {
            int rh = item->height > 0 ? item->height : 300;
            y += rh;
            break;
        }
        }
        y += 4; /* gap between items */
    }
    return y + PADDING_Y;
}

static void paint_dialog(HWND hwnd, HDC hdc, ScriptDialogState *state) {
    RECT rc;
    GetClientRect(hwnd, &rc);

    state->button_count = 0;
    state->tbl_button_count = 0;

    /* Show loading indicator when content hasn't been populated yet */
    if (state->spec.item_count == 0) {
        HBRUSH bg = CreateSolidBrush(DIALOG_BG);
        FillRect(hdc, &rc, bg);
        DeleteObject(bg);
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, RGB(136, 136, 136));
        HFONT hf = create_dialog_font(10, FALSE);
        HFONT old = (HFONT)SelectObject(hdc, hf);
        const WCHAR *msg = L"Loading...";
        DrawTextW(hdc, msg, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        SelectObject(hdc, old);
        DeleteObject(hf);
        return;
    }

    BOOL has_wv = FALSE;
    for (int i = 0; i < state->spec.item_count; i++) {
        if (state->spec.items[i].type == DI_WEBVIEW) { has_wv = TRUE; break; }
    }

    if (!has_wv) {
        COLORREF bg_color = state->spec.transparent_bg ? RGB(255, 0, 255) : DIALOG_BG;
        HBRUSH bg = CreateSolidBrush(bg_color);
        FillRect(hdc, &rc, bg);
        DeleteObject(bg);
    }

    SetBkMode(hdc, TRANSPARENT);

    int y = PADDING_Y - state->scroll_y;
    int client_w = rc.right - rc.left;

    for (int i = 0; i < state->spec.item_count; i++) {
        DialogItem *item = &state->spec.items[i];
        state->item_y[i] = y;
        int y_before = y;

        switch (item->type) {
        case DI_TEXT: {
            int pt = item->font_size > 0 ? item->font_size : 10;
            HFONT hf = create_dialog_font(pt, item->bold);
            HFONT old = (HFONT)SelectObject(hdc, hf);
            COLORREF clr = (item->color != 0xFFFFFFFF) ? item->color : DIALOG_FG;
            SetTextColor(hdc, clr);
            TEXTMETRICW tm;
            GetTextMetricsW(hdc, &tm);
            int text_x = PADDING_X;
            int line_h = tm.tmHeight;
            /* Draw inline icon if present */
            if (item->img_source[0]) {
                int iw = item->width > 0 ? item->width : tm.tmHeight;
                int ih = item->height > 0 ? item->height : tm.tmHeight;
                int out_w = 0, out_h = 0;
                HBITMAP hbmp = image_load(item->img_source, iw, ih, &out_w, &out_h);
                if (hbmp) {
                    HDC mem = CreateCompatibleDC(hdc);
                    HBITMAP old_bmp = (HBITMAP)SelectObject(mem, hbmp);
                    int dw = out_w > 0 ? out_w : iw;
                    int dh = out_h > 0 ? out_h : ih;
                    int iy = y + (tm.tmHeight - dh) / 2;
                    StretchBlt(hdc, text_x, iy, dw, dh, mem, 0, 0, dw, dh, SRCCOPY);
                    SelectObject(mem, old_bmp);
                    DeleteDC(mem);
                    text_x += dw + 4;
                    if (dh > line_h) line_h = dh;
                }
            }
            if (item->align == ALIGN_CENTER || item->align == ALIGN_RIGHT) {
                SIZE sz;
                GetTextExtentPoint32W(hdc, item->text, lstrlenW(item->text), &sz);
                int content_w = (text_x - PADDING_X) + sz.cx;
                if (item->align == ALIGN_CENTER)
                    text_x = (client_w - content_w) / 2 + (text_x - PADDING_X);
                else
                    text_x = client_w - PADDING_X - sz.cx;
            }
            TextOutW(hdc, text_x, y, item->text, lstrlenW(item->text));
            y += line_h + 4;
            SelectObject(hdc, old);
            DeleteObject(hf);
            break;
        }
        case DI_HR: {
            int line_y = y + 6;
            HPEN pen = CreatePen(PS_SOLID, 1, DIALOG_HR_COLOR);
            HPEN old_pen = (HPEN)SelectObject(hdc, pen);
            MoveToEx(hdc, PADDING_X, line_y, NULL);
            LineTo(hdc, client_w - PADDING_X, line_y);
            SelectObject(hdc, old_pen);
            DeleteObject(pen);
            y += 12;
            break;
        }
        case DI_TABLE: {
            HFONT hf_bold = create_dialog_font(10, TRUE);
            HFONT hf_norm = create_dialog_font(10, FALSE);
            HFONT old = (HFONT)SelectObject(hdc, hf_norm);
            TEXTMETRICW tm;
            GetTextMetricsW(hdc, &tm);
            int row_h = item->height > 0 ? item->height : (tm.tmHeight + 6);
            int total_w = client_w - PADDING_X * 2;

            /* Compute per-column widths */
            int cw[DIALOG_MAX_COLS];
            int fixed_sum = 0, auto_count = 0;
            for (int c = 0; c < item->col_count; c++) {
                if (item->col_widths[c] > 0) { cw[c] = item->col_widths[c]; fixed_sum += cw[c]; }
                else { cw[c] = 0; auto_count++; }
            }
            int auto_w = auto_count > 0 ? (total_w - fixed_sum) / auto_count : 0;
            if (auto_w < 0) auto_w = 0;
            for (int c = 0; c < item->col_count; c++) {
                if (cw[c] == 0) cw[c] = auto_w;
            }
            /* Compute column x offsets */
            int cx[DIALOG_MAX_COLS];
            cx[0] = PADDING_X;
            for (int c = 1; c < item->col_count; c++) cx[c] = cx[c-1] + cw[c-1];

            /* Header */
            RECT hdr_rc = { PADDING_X, y, client_w - PADDING_X, y + row_h };
            HBRUSH hdr_bg = CreateSolidBrush(TABLE_HDR_BG);
            FillRect(hdc, &hdr_rc, hdr_bg);
            DeleteObject(hdr_bg);

            SelectObject(hdc, hf_bold);
            SetTextColor(hdc, DIALOG_FG);
            for (int c = 0; c < item->col_count; c++) {
                RECT hdr_cell = { cx[c] + 4, y + 3, cx[c] + cw[c] - 2, y + row_h - 1 };
                DrawTextW(hdc, item->columns[c], -1, &hdr_cell,
                    DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
            }
            y += row_h;

            /* Header separator */
            HPEN sep = CreatePen(PS_SOLID, 1, DIALOG_HR_COLOR);
            HPEN old_sep = (HPEN)SelectObject(hdc, sep);
            MoveToEx(hdc, PADDING_X, y, NULL);
            LineTo(hdc, client_w - PADDING_X, y);
            SelectObject(hdc, old_sep);
            DeleteObject(sep);
            y += 2;

            /* Rows */
            SelectObject(hdc, hf_norm);
            for (int r = 0; r < item->row_count; r++) {
                /* Compute actual row height */
                int actual_row_h = row_h;
                if (item->word_wrap) {
                    for (int c = 0; c < item->col_count; c++) {
                        RECT measure = { 0, 0, cw[c] - 6, 0 };
                        DrawTextW(hdc, item->cells[r][c], -1, &measure,
                            DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
                        int cell_h = measure.bottom + 6;
                        if (cell_h > actual_row_h) actual_row_h = cell_h;
                    }
                }
                if (item->height > 0 && actual_row_h < item->height) actual_row_h = item->height;

                RECT row_rc = { PADDING_X, y, client_w - PADDING_X, y + actual_row_h };
                HBRUSH row_bg = CreateSolidBrush((r % 2 == 0) ? TABLE_ROW_EVEN : TABLE_ROW_ODD);
                FillRect(hdc, &row_rc, row_bg);
                DeleteObject(row_bg);

                COLORREF row_clr = (item->row_colors[r] != 0) ? item->row_colors[r] : DIALOG_FG;
                SetTextColor(hdc, row_clr);

                int btn_w_px = 0;
                if (item->row_urls[r][0] || item->row_cmds[r][0] || item->row_luas[r][0]) {
                    btn_w_px = 50;
                }

                DWORD dt_flags = DT_LEFT | DT_END_ELLIPSIS | DT_NOPREFIX;
                if (item->word_wrap) dt_flags |= DT_WORDBREAK;
                else dt_flags |= DT_SINGLELINE | DT_VCENTER;

                for (int c = 0; c < item->col_count; c++) {
                    RECT cell_rc = { cx[c] + 4, y + 3, cx[c] + cw[c] - 2, y + actual_row_h - 1 };
                    DrawTextW(hdc, item->cells[r][c], -1, &cell_rc, dt_flags);
                }

                /* Row action button */
                if ((item->row_urls[r][0] || item->row_cmds[r][0] || item->row_luas[r][0]) && state->tbl_button_count < DLG_MAX_TBL_BUTTONS) {
                    int btn_id = DLG_TBL_BTN_BASE_ID + state->tbl_button_count;
                    int bx = client_w - PADDING_X - btn_w_px;
                    WCHAR btn_label[32];
                    if (item->row_btn_text[r][0])
                        lstrcpynW(btn_label, item->row_btn_text[r], 32);
                    else
                        btn_label[0] = L'\0';
                    HWND hbtn = state->tbl_buttons[state->tbl_button_count];
                    if (!hbtn) {
                        hbtn = CreateWindowExW(WS_EX_TRANSPARENT, L"BUTTON", btn_label,
                            WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                            bx, y, btn_w_px, actual_row_h,
                            hwnd, (HMENU)(INT_PTR)btn_id, GetModuleHandle(NULL), NULL);
                        state->tbl_buttons[state->tbl_button_count] = hbtn;
                    } else {
                        SetWindowTextW(hbtn, btn_label);
                        MoveWindow(hbtn, bx, y, btn_w_px, actual_row_h, TRUE);
                    }
                    state->tbl_button_count++;
                }

                y += actual_row_h;
            }

            SelectObject(hdc, old);
            DeleteObject(hf_bold);
            DeleteObject(hf_norm);
            break;
        }
        case DI_IMG: {
            if (!item->img_source[0]) break;
            int rw = item->width > 0 ? item->width : 64;
            int rh = item->height > 0 ? item->height : 64;

            if (item->src_w > 0 && item->src_h > 0) {
                /* Sprite sheet crop mode: load at native size, blit region centered */
                int out_w = 0, out_h = 0;
                HBITMAP hbmp = image_load(item->img_source, 0, 0, &out_w, &out_h);
                if (hbmp) {
                    HDC mem = CreateCompatibleDC(hdc);
                    HBITMAP old_bmp = (HBITMAP)SelectObject(mem, hbmp);
                    int dx = (rc.right - rc.left - rw) / 2;
                    int dy = (rc.bottom - rc.top - rh) / 2;
                    BLENDFUNCTION bf = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
                    AlphaBlend(hdc, dx, dy, rw, rh,
                        mem, item->src_x, item->src_y, item->src_w, item->src_h, bf);
                    SelectObject(mem, old_bmp);
                    DeleteDC(mem);
                    y += rh;
                }
            } else {
                int out_w = 0, out_h = 0;
                HBITMAP hbmp = image_load(item->img_source, rw, rh, &out_w, &out_h);
                if (hbmp) {
                    HDC mem = CreateCompatibleDC(hdc);
                    HBITMAP old_bmp = (HBITMAP)SelectObject(mem, hbmp);
                    int dw = out_w > 0 ? out_w : rw;
                    int dh = out_h > 0 ? out_h : rh;
                    BLENDFUNCTION bf = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
                    AlphaBlend(hdc, PADDING_X, y, dw, dh, mem, 0, 0, dw, dh, bf);
                    SelectObject(mem, old_bmp);
                    DeleteDC(mem);
                    y += dh;
                }
            }
            break;
        }
        case DI_BUTTON: {
            if (state->button_count < DLG_MAX_BUTTONS) {
                int btn_h = item->height > 0 ? item->height : 26;
                int btn_w = item->width > 0 ? item->width : (client_w - PADDING_X * 2);
                int btn_x = PADDING_X;
                if (item->align == ALIGN_CENTER) btn_x = (client_w - btn_w) / 2;
                else if (item->align == ALIGN_RIGHT) btn_x = client_w - PADDING_X - btn_w;
                int btn_id = DLG_BTN_BASE_ID + state->button_count;
                HWND hbtn = state->buttons[state->button_count];
                if (!hbtn) {
                    hbtn = CreateWindowExW(0, L"BUTTON", item->text,
                        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                        btn_x, y, btn_w, btn_h,
                        hwnd, (HMENU)(INT_PTR)btn_id, GetModuleHandle(NULL), NULL);
                    state->buttons[state->button_count] = hbtn;
                } else {
                    MoveWindow(hbtn, btn_x, y, btn_w, btn_h, TRUE);
                    SetWindowTextW(hbtn, item->text);
                }
                state->button_count++;
                if (item->align != ALIGN_INLINE) y += btn_h + 2;
            }
            break;
        }
        case DI_WEBVIEW: {
            int rw = client_w;
            int rh = rc.bottom - rc.top;
            if (!state->webviews[i] && item->url[0] && !state->webview_creating) {
                if (webview_available()) {
                    state->webview_creating = TRUE;
                    PostMessage(hwnd, WM_USER + 100, 0, 0);
                } else {
                    SetTextColor(hdc, RGB(180, 180, 180));
                    SetBkMode(hdc, TRANSPARENT);
                    int err = webview_init_error();
                    if (err == 2) {
                        WCHAR exe_dir[MAX_PATH];
                        GetModuleFileNameW(NULL, exe_dir, MAX_PATH);
                        PathRemoveFileSpecW(exe_dir);
                        WCHAR msg[1024];
                        wsprintfW(msg, tr("webview.err_download_failed"), exe_dir);
                        RECT tr_rc = { PADDING_X, PADDING_Y, rw - PADDING_X, rh - PADDING_Y };
                        DrawTextW(hdc, msg, -1, &tr_rc, DT_LEFT | DT_WORDBREAK);
                    } else {
                        const WCHAR *msg = tr("webview.err_no_runtime");
                        TextOutW(hdc, PADDING_X, rh / 2 - 8, msg, lstrlenW(msg));
                    }
                }
            } else if (state->webviews[i] && !webview_is_dragging()) {
                webview_resize(state->webviews[i], 0, 0, rw, rh);
            }
            y += rh;
            break;
        }
        }
        state->item_h[i] = y - y_before;
        y += 4;
    }

    state->content_height = y + state->scroll_y + PADDING_Y;

    /* Draw drag hint overlay when Shift held on borderless non-webview dialog */
    if (state->spec.borderless && !has_wv && (GetAsyncKeyState(VK_SHIFT) & 0x8000)) {
        RECT crc;
        GetClientRect(hwnd, &crc);
        HBRUSH overlay = CreateSolidBrush(RGB(30, 30, 30));
        BLENDFUNCTION bf = {AC_SRC_OVER, 0, 200, 0};
        HDC memdc = CreateCompatibleDC(hdc);
        HBITMAP bmp = CreateCompatibleBitmap(hdc, crc.right, crc.bottom);
        HBITMAP oldbmp = (HBITMAP)SelectObject(memdc, bmp);
        FillRect(memdc, &crc, overlay);
        DeleteObject(overlay);
        GdiAlphaBlend(hdc, 0, 0, crc.right, crc.bottom, memdc, 0, 0, crc.right, crc.bottom, bf);
        SelectObject(memdc, oldbmp);
        DeleteObject(bmp);
        DeleteDC(memdc);
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, RGB(170, 170, 170));
        HFONT hf = create_dialog_font(10, FALSE);
        HFONT oldf = (HFONT)SelectObject(hdc, hf);
        DrawTextW(hdc, tr("webview.drag_hint"), -1, &crc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        SelectObject(hdc, oldf);
        DeleteObject(hf);
    }
}

static void refresh_dialog(HWND hwnd, ScriptDialogState *state) {
    ScriptResult *result = (ScriptResult *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScriptResult));
    if (!result) return;
    if (!script_exec_file_try(state->lua_path, state->params, state->param_count, result)) {
        HeapFree(GetProcessHeap(), 0, result);
        return;
    }
    if (result->click_action == CLICK_DIALOG) {
        if (result->dialog.item_count > 0) {
            RECT wr; GetWindowRect(hwnd, &wr);
            memcpy(&state->spec, &result->dialog, sizeof(DialogSpec));
            state->spec.x = wr.left;
            state->spec.y = wr.top;
        }
        InvalidateRect(hwnd, NULL, FALSE);
    }
    HeapFree(GetProcessHeap(), 0, result);
}

static void ulw_render(HWND hwnd, ScriptDialogState *state) {
    RECT rc;
    GetClientRect(hwnd, &rc);
    int cw = rc.right - rc.left;
    int ch = rc.bottom - rc.top;
    if (cw <= 0 || ch <= 0) return;

    BITMAPINFO bmi = {0};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = cw;
    bmi.bmiHeader.biHeight = -ch;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    void *bits = NULL;
    HDC memdc = CreateCompatibleDC(NULL);
    HBITMAP dib = CreateDIBSection(memdc, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!dib || !bits) { DeleteDC(memdc); return; }
    HBITMAP old_dib = (HBITMAP)SelectObject(memdc, dib);

    memset(bits, 0, (size_t)cw * ch * 4);
    paint_dialog(hwnd, memdc, state);

    POINT pt_src = {0, 0};
    SIZE sz = {cw, ch};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    POINT pt_wnd;
    if (state->spec.x >= 0 && state->spec.y >= 0) {
        pt_wnd.x = state->spec.x;
        pt_wnd.y = state->spec.y;
    } else {
        RECT wr;
        GetWindowRect(hwnd, &wr);
        pt_wnd.x = wr.left;
        pt_wnd.y = wr.top;
    }
    UpdateLayeredWindow(hwnd, NULL, &pt_wnd, &sz, memdc, &pt_src, 0, &blend, ULW_ALPHA);

    SelectObject(memdc, old_dib);
    DeleteObject(dib);
    DeleteDC(memdc);
}

static void update_scrollbar(HWND hwnd, ScriptDialogState *state) {
    if (state->spec.borderless) return;
    RECT rc;
    GetClientRect(hwnd, &rc);
    int page = rc.bottom - rc.top;

    SCROLLINFO si = {0};
    si.cbSize = sizeof(si);
    si.fMask = SIF_RANGE | SIF_PAGE | SIF_POS;
    si.nMin = 0;
    si.nMax = state->content_height;
    si.nPage = page;
    si.nPos = state->scroll_y;
    SetScrollInfo(hwnd, SB_VERT, &si, TRUE);
}

static LRESULT CALLBACK dialog_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    ScriptDialogState *state = (ScriptDialogState *)GetWindowLongPtr(hwnd, GWLP_USERDATA);

    switch (msg) {
    case WM_SETCURSOR: {
        if (state && state->spec.borderless && (GetKeyState(VK_SHIFT) & 0x8000)) {
            SetCursor(LoadCursor(NULL, state->dragging ? IDC_HAND : IDC_HAND));
            return TRUE;
        }
        if ((HWND)wp != hwnd) {
            WCHAR cls[16];
            GetClassNameW((HWND)wp, cls, 16);
            if (lstrcmpiW(cls, L"BUTTON") == 0) {
                SetCursor(LoadCursorW(NULL, IDC_HAND));
                return TRUE;
            }
        }
        break;
    }

    case WM_CREATE: {
        CREATESTRUCTW *cs = (CREATESTRUCTW *)lp;
        state = (ScriptDialogState *)cs->lpCreateParams;
        SetWindowLongPtr(hwnd, GWLP_USERDATA, (LONG_PTR)state);
        if (state->spec.refresh > 0) {
            SetTimer(hwnd, IDT_DIALOG_REFRESH, (UINT)state->spec.refresh, NULL);
        }
        PostMessage(hwnd, WM_TIMER, IDT_DIALOG_REFRESH, 0);
        if (state->spec.borderless) {
            SetTimer(hwnd, IDT_DIALOG_ESC, 100, NULL);
        }
        /* Webviews are created lazily in paint_dialog after first refresh */
        return 0;
    }

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        if (state) {
            RECT rc;
            GetClientRect(hwnd, &rc);
            int cw = rc.right - rc.left;
            int ch = rc.bottom - rc.top;
            HDC memdc = CreateCompatibleDC(hdc);
            HBITMAP membmp = CreateCompatibleBitmap(hdc, cw, ch);
            HBITMAP oldbmp = (HBITMAP)SelectObject(memdc, membmp);
            paint_dialog(hwnd, memdc, state);
            BitBlt(hdc, 0, 0, cw, ch, memdc, 0, 0, SRCCOPY);
            SelectObject(memdc, oldbmp);
            DeleteObject(membmp);
            DeleteDC(memdc);
            update_scrollbar(hwnd, state);
        }
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_USER + 100: {
        if (!state) break;
        RECT crc;
        GetClientRect(hwnd, &crc);
        int rw = crc.right - crc.left;
        int rh = crc.bottom - crc.top;
        if (rw <= 0) rw = state->spec.width > 0 ? state->spec.width : 400;
        if (rh <= 0) rh = state->spec.height > 0 ? state->spec.height : 300;
        for (int i = 0; i < state->spec.item_count; i++) {
            if (state->spec.items[i].type == DI_WEBVIEW &&
                state->spec.items[i].url[0] && !state->webviews[i]) {
                state->webviews[i] = webview_create(hwnd, 0, 0, rw, rh,
                    state->spec.items[i].url, state->lua_path);
            }
        }
        state->webview_creating = FALSE;
        InvalidateRect(hwnd, NULL, TRUE);
        return 0;
    }

    case WM_TIMER:
        if (wp == IDT_DIALOG_ESC && state && state->spec.borderless) {
            if (GetAsyncKeyState(VK_ESCAPE) & 0x8000) {
                POINT pt; GetCursorPos(&pt);
                RECT wr; GetWindowRect(hwnd, &wr);
                if (PtInRect(&wr, pt)) {
                    DestroyWindow(hwnd);
                    return 0;
                }
            }
            /* Toggle drag overlay (only when mouse is over this dialog + Shift held) */
            POINT pt2; GetCursorPos(&pt2);
            RECT wr2; GetWindowRect(hwnd, &wr2);
            BOOL mouse_over = PtInRect(&wr2, pt2);
            if (mouse_over) {
                BOOL shift_down = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
                BOOL should_hide = shift_down;
                if (should_hide != state->shift_hiding_webview) {
                    state->shift_hiding_webview = should_hide;
                for (int i = 0; i < DIALOG_MAX_ITEMS; i++) {
                    if (!state->webviews[i]) continue;
                    if (should_hide) {
                        char js[2048];
                        char hint[128];
                        WideCharToMultiByte(CP_UTF8, 0, tr("webview.drag_hint"), -1, hint, sizeof(hint), NULL, NULL);
                        snprintf(js, sizeof(js),
                            "(function(){"
                            "if(document.getElementById('__tp_drag'))return;"
                            "var d=document.createElement('div');d.id='__tp_drag';"
                            "d.style.cssText='position:fixed;top:0;left:0;width:100vw;height:100vh;"
                            "background:rgba(30,30,30,0.85);z-index:999999;display:flex;"
                            "align-items:center;justify-content:center;cursor:grab;user-select:none;';"
                            "d.innerHTML='<span style=\"color:#aaa;font:14px sans-serif;pointer-events:none\">"
                            "%s</span>';"
                            "var lx,ly,moving=false;"
                            "d.onmousedown=function(e){lx=e.screenX;ly=e.screenY;moving=true;d.style.cursor=\"grabbing\";};"
                            "d.onmousemove=function(e){if(!moving)return;var dx=e.screenX-lx,dy=e.screenY-ly;"
                            "lx=e.screenX;ly=e.screenY;window.chrome.webview.postMessage('__taskpin_move_delta__:'+dx+':'+dy);};"
                            "d.onmouseup=function(){moving=false;d.style.cursor=\"grab\";};"
                            "d.onwheel=function(e){e.preventDefault();var delta=e.deltaY>0?-20:20;"
                            "window.chrome.webview.postMessage('__taskpin_resize__:'+delta);};"
                            "document.body.appendChild(d);"
                            "})()", hint);
                        webview_eval(state->webviews[i], js);
                    } else
                        webview_eval(state->webviews[i],
                            "(function(){var d=document.getElementById('__tp_drag');if(d)d.remove();})()");
                }
                InvalidateRect(hwnd, NULL, TRUE);
            }
            } else if (state->shift_hiding_webview) {
                state->shift_hiding_webview = FALSE;
                for (int i = 0; i < DIALOG_MAX_ITEMS; i++) {
                    if (!state->webviews[i]) continue;
                    webview_eval(state->webviews[i],
                        "(function(){var d=document.getElementById('__tp_drag');if(d)d.remove();})()");
                }
                InvalidateRect(hwnd, NULL, TRUE);
            }
        }
        if (wp == IDT_DIALOG_REFRESH && state) {
            if (!(GetAsyncKeyState(VK_SHIFT) & 0x8000) && !webview_is_dragging())
                refresh_dialog(hwnd, state);
        }
        return 0;

    case WM_DRAWITEM: {
        DRAWITEMSTRUCT *dis = (DRAWITEMSTRUCT *)lp;
        if (!state || dis->CtlType != ODT_BUTTON) break;
        int id = (int)dis->CtlID;

        /* Table row buttons - transparent bg matching row */
        if (id >= DLG_TBL_BTN_BASE_ID && id < DLG_TBL_BTN_BASE_ID + DLG_MAX_TBL_BUTTONS) {
            int row_idx = id - DLG_TBL_BTN_BASE_ID;
            COLORREF bg = (row_idx % 2 == 0) ? TABLE_ROW_EVEN : TABLE_ROW_ODD;
            HBRUSH hbr = CreateSolidBrush(bg);
            FillRect(dis->hDC, &dis->rcItem, hbr);
            DeleteObject(hbr);
            SetBkMode(dis->hDC, TRANSPARENT);
            WCHAR btn_text[32];
            GetWindowTextW(dis->hwndItem, btn_text, 32);
            SetTextColor(dis->hDC, RGB(100, 180, 255));
            HFONT hf = create_dialog_font(9, FALSE);
            HFONT old = (HFONT)SelectObject(dis->hDC, hf);
            DrawTextW(dis->hDC, btn_text, -1, &dis->rcItem, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            SelectObject(dis->hDC, old);
            DeleteObject(hf);
            return TRUE;
        }

        /* Regular DI_BUTTON items */
        int btn_idx = id - DLG_BTN_BASE_ID;
        if (btn_idx < 0 || btn_idx >= DLG_MAX_BUTTONS) break;

        /* Find the matching DI_BUTTON item */
        int btn_count = 0;
        DialogItem *item = NULL;
        for (int i = 0; i < state->spec.item_count; i++) {
            if (state->spec.items[i].type == DI_BUTTON) {
                if (btn_count == btn_idx) { item = &state->spec.items[i]; break; }
                btn_count++;
            }
        }
        if (!item) break;

        COLORREF bg = (item->bg_color != 0xFFFFFFFF) ? item->bg_color : RGB(50, 50, 50);
        COLORREF fg = (item->color != 0xFFFFFFFF) ? item->color : DIALOG_FG;

        /* Hover/pressed effect */
        if (dis->itemState & ODS_SELECTED)
            bg = RGB(GetRValue(bg) + 30, GetGValue(bg) + 30, GetBValue(bg) + 30);

        HBRUSH hbr = CreateSolidBrush(bg);
        FillRect(dis->hDC, &dis->rcItem, hbr);
        DeleteObject(hbr);

        /* Draw text */
        SetBkMode(dis->hDC, TRANSPARENT);
        SetTextColor(dis->hDC, fg);
        HFONT hf = create_dialog_font(9, FALSE);
        HFONT old = (HFONT)SelectObject(dis->hDC, hf);
        RECT tr = dis->rcItem;
        tr.left += 8;
        DrawTextW(dis->hDC, item->text, -1, &tr, DT_SINGLELINE | DT_VCENTER | DT_LEFT);
        SelectObject(dis->hDC, old);
        DeleteObject(hf);

        /* Border */
        HPEN pen = CreatePen(PS_SOLID, 1, RGB(70, 70, 70));
        HPEN old_pen = (HPEN)SelectObject(dis->hDC, pen);
        HBRUSH null_br = (HBRUSH)GetStockObject(NULL_BRUSH);
        HBRUSH old_br = (HBRUSH)SelectObject(dis->hDC, null_br);
        Rectangle(dis->hDC, dis->rcItem.left, dis->rcItem.top, dis->rcItem.right, dis->rcItem.bottom);
        SelectObject(dis->hDC, old_pen);
        SelectObject(dis->hDC, old_br);
        DeleteObject(pen);
        return TRUE;
    }

    case WM_COMMAND: {
        int id = LOWORD(wp);
        if (state && id >= DLG_BTN_BASE_ID && id < DLG_BTN_BASE_ID + DLG_MAX_BUTTONS) {
            int btn_idx = id - DLG_BTN_BASE_ID;
            int btn_count = 0;
            for (int i = 0; i < state->spec.item_count; i++) {
                if (state->spec.items[i].type == DI_BUTTON) {
                    if (btn_count == btn_idx) {
                        if (state->spec.items[i].lua_code[0]) {
                            ScriptResult *sr = (ScriptResult *)HeapAlloc(
                                GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScriptResult));
                            if (sr) {
                                script_exec(state->spec.items[i].lua_code, NULL, sr);
                                HeapFree(GetProcessHeap(), 0, sr);
                            }
                        } else if (state->spec.items[i].url[0]) {
                            WCHAR wurl[512];
                            MultiByteToWideChar(CP_UTF8, 0, state->spec.items[i].url, -1, wurl, 512);
                            ShellExecuteW(NULL, L"open", wurl, NULL, NULL, SW_SHOWNORMAL);
                        } else if (state->spec.items[i].cmd[0]) {
                            WCHAR wcmd[512];
                            MultiByteToWideChar(CP_UTF8, 0, state->spec.items[i].cmd, -1, wcmd, 512);
                            STARTUPINFOW si = { .cb = sizeof(si) };
                            PROCESS_INFORMATION pi = {0};
                            WCHAR cmdline[600];
                            wsprintfW(cmdline, L"cmd /c %s", wcmd);
                            CreateProcessW(NULL, cmdline, NULL, NULL, FALSE,
                                CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
                            if (pi.hProcess) CloseHandle(pi.hProcess);
                            if (pi.hThread) CloseHandle(pi.hThread);
                        }
                        break;
                    }
                    btn_count++;
                }
            }
        }
        /* Table row buttons */
        if (state && id >= DLG_TBL_BTN_BASE_ID && id < DLG_TBL_BTN_BASE_ID + DLG_MAX_TBL_BUTTONS) {
            int tbl_idx = id - DLG_TBL_BTN_BASE_ID;
            int tbl_count = 0;
            for (int i = 0; i < state->spec.item_count; i++) {
                if (state->spec.items[i].type != DI_TABLE) continue;
                DialogItem *tbl = &state->spec.items[i];
                for (int r = 0; r < tbl->row_count; r++) {
                    if (tbl->row_urls[r][0] || tbl->row_cmds[r][0] || tbl->row_luas[r][0]) {
                        if (tbl_count == tbl_idx) {
                            if (tbl->row_luas[r][0]) {
                                ScriptResult *sr = (ScriptResult *)HeapAlloc(
                                    GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScriptResult));
                                if (sr) {
                                    script_exec(tbl->row_luas[r], NULL, sr);
                                    HeapFree(GetProcessHeap(), 0, sr);
                                }
                            } else if (tbl->row_urls[r][0]) {
                                WCHAR wurl[256];
                                MultiByteToWideChar(CP_UTF8, 0, tbl->row_urls[r], -1, wurl, 256);
                                ShellExecuteW(NULL, L"open", wurl, NULL, NULL, SW_SHOWNORMAL);
                            } else if (tbl->row_cmds[r][0]) {
                                WCHAR wcmd[256];
                                MultiByteToWideChar(CP_UTF8, 0, tbl->row_cmds[r], -1, wcmd, 256);
                                STARTUPINFOW si = { .cb = sizeof(si) };
                                PROCESS_INFORMATION pi = {0};
                                WCHAR cmdline[320];
                                wsprintfW(cmdline, L"cmd /c %s", wcmd);
                                CreateProcessW(NULL, cmdline, NULL, NULL, FALSE,
                                    CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
                                if (pi.hProcess) CloseHandle(pi.hProcess);
                                if (pi.hThread) CloseHandle(pi.hThread);
                            }
                            goto cmd_done;
                        }
                        tbl_count++;
                    }
                }
            }
        }
        cmd_done:
        return 0;
    }

    case WM_VSCROLL: {
        if (!state) break;
        int pos = state->scroll_y;
        RECT rc; GetClientRect(hwnd, &rc);
        int page = rc.bottom - rc.top;

        switch (LOWORD(wp)) {
        case SB_LINEUP:    pos -= 20; break;
        case SB_LINEDOWN:  pos += 20; break;
        case SB_PAGEUP:    pos -= page; break;
        case SB_PAGEDOWN:  pos += page; break;
        case SB_THUMBTRACK: pos = HIWORD(wp); break;
        }
        if (pos < 0) pos = 0;
        if (pos > state->content_height - page) pos = state->content_height - page;
        if (pos < 0) pos = 0;
        state->scroll_y = pos;
        InvalidateRect(hwnd, NULL, TRUE);
        return 0;
    }

    case WM_MOUSEWHEEL: {
        if (!state) break;
        int delta = GET_WHEEL_DELTA_WPARAM(wp);
        /* Shift+scroll = resize borderless dialog */
        if (state->spec.borderless && (GetKeyState(VK_SHIFT) & 0x8000)) {
            RECT wr; GetWindowRect(hwnd, &wr);
            int w = wr.right - wr.left;
            int h = wr.bottom - wr.top;
            int step = delta > 0 ? 20 : -20;
            w += step; h += step;
            if (w < 80) w = 80;
            if (h < 40) h = 40;
            SetWindowPos(hwnd, NULL, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER);
            return 0;
        }
        state->scroll_y -= delta / 2;
        if (state->scroll_y < 0) state->scroll_y = 0;
        RECT rc; GetClientRect(hwnd, &rc);
        int page = rc.bottom - rc.top;
        if (state->scroll_y > state->content_height - page)
            state->scroll_y = state->content_height - page;
        if (state->scroll_y < 0) state->scroll_y = 0;
        InvalidateRect(hwnd, NULL, TRUE);
        return 0;
    }

    case WM_MOVE:
        if (state) {
            RECT wr; GetWindowRect(hwnd, &wr);
            state->spec.x = wr.left;
            state->spec.y = wr.top;
        }
        return 0;

    case WM_SIZE:
        if (state && !webview_is_dragging()) InvalidateRect(hwnd, NULL, TRUE);
        return 0;

    case WM_LBUTTONDOWN:
        if (state && state->spec.borderless && (GetKeyState(VK_SHIFT) & 0x8000)) {
            state->dragging = TRUE;
            state->drag_start.x = GET_X_LPARAM(lp);
            state->drag_start.y = GET_Y_LPARAM(lp);
            SetCapture(hwnd);
            return 0;
        }
        break;

    case WM_MOUSEMOVE:
        if (state && state->dragging) {
            POINT cur = { GET_X_LPARAM(lp), GET_Y_LPARAM(lp) };
            int dx = cur.x - state->drag_start.x;
            int dy = cur.y - state->drag_start.y;
            RECT wr; GetWindowRect(hwnd, &wr);
            int nx = wr.left + dx;
            int ny = wr.top + dy;
            SetWindowPos(hwnd, NULL, nx, ny, 0, 0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            state->spec.x = nx;
            state->spec.y = ny;
            return 0;
        }
        break;

    case WM_LBUTTONUP:
        if (state && state->dragging) {
            state->dragging = FALSE;
            ReleaseCapture();
            return 0;
        }
        break;

    case WM_CAPTURECHANGED:
        if (state) state->dragging = FALSE;
        break;

    case WM_NCHITTEST: {
        if (!state) break;
        if (state->spec.clickthrough && !(GetKeyState(VK_SHIFT) & 0x8000))
            return HTTRANSPARENT;
        break;
    }

    case WM_KEYDOWN:
        if (state && state->spec.borderless && wp == VK_ESCAPE) {
            DestroyWindow(hwnd);
            return 0;
        }
        break;

    case WM_RBUTTONUP: {
        if (!state) break;
        int click_y = (short)HIWORD(lp) + state->scroll_y;
        WCHAR copy_buf[4096] = {0};
        for (int i = 0; i < state->spec.item_count; i++) {
            if (click_y >= state->item_y[i] && click_y < state->item_y[i] + state->item_h[i]) {
                DialogItem *item = &state->spec.items[i];
                if (item->type == DI_TEXT && item->text[0]) {
                    lstrcpynW(copy_buf, item->text, 4096);
                } else if (item->type == DI_TABLE) {
                    int off = 0;
                    for (int c = 0; c < item->col_count && off < 4000; c++) {
                        if (c > 0) copy_buf[off++] = L'\t';
                        int len = lstrlenW(item->columns[c]);
                        lstrcpynW(copy_buf + off, item->columns[c], 4096 - off);
                        off += len;
                    }
                    for (int r = 0; r < item->row_count && off < 4000; r++) {
                        copy_buf[off++] = L'\r'; copy_buf[off++] = L'\n';
                        for (int c = 0; c < item->col_count && off < 4000; c++) {
                            if (c > 0) copy_buf[off++] = L'\t';
                            int len = lstrlenW(item->cells[r][c]);
                            lstrcpynW(copy_buf + off, item->cells[r][c], 4096 - off);
                            off += len;
                        }
                    }
                }
                break;
            }
        }
        if (copy_buf[0]) {
            HMENU menu = CreatePopupMenu();
            AppendMenuW(menu, MF_STRING, 1, L"Copy");
            POINT pt; GetCursorPos(&pt);
            int cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, NULL);
            DestroyMenu(menu);
            if (cmd == 1) {
                int wlen = lstrlenW(copy_buf) + 1;
                HGLOBAL hg = GlobalAlloc(GMEM_MOVEABLE, wlen * sizeof(WCHAR));
                if (hg) {
                    WCHAR *dst = (WCHAR *)GlobalLock(hg);
                    lstrcpyW(dst, copy_buf);
                    GlobalUnlock(hg);
                    if (OpenClipboard(hwnd)) {
                        EmptyClipboard();
                        SetClipboardData(CF_UNICODETEXT, hg);
                        CloseClipboard();
                    } else {
                        GlobalFree(hg);
                    }
                }
            }
        }
        return 0;
    }

    case WM_DESTROY:
        KillTimer(hwnd, IDT_DIALOG_REFRESH);
        KillTimer(hwnd, IDT_DIALOG_ESC);
        if (state && state->lua_path[0]) {
            RECT wr2;
            GetWindowRect(hwnd, &wr2);
            int idx = dlg_find_item(state->lua_path);
            if (idx >= 0) {
                g_cfg.items[idx].dlg_x = wr2.left;
                g_cfg.items[idx].dlg_y = wr2.top;
                g_cfg.items[idx].dlg_w = wr2.right - wr2.left;
                g_cfg.items[idx].dlg_h = wr2.bottom - wr2.top;
                config_save(&g_cfg);
            }
        }
        if (state) {
            for (int i = 0; i < DIALOG_MAX_ITEMS; i++) {
                if (state->webviews[i]) webview_destroy(state->webviews[i]);
            }
            HeapFree(GetProcessHeap(), 0, state);
        }
        unregister_dialog(hwnd);
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wp, lp);
}
