#include "script_dialog.h"
#include "scripting.h"
#include "config.h"
#include <stdlib.h>
#include <string.h>

#define DIALOG_CLASS L"TaskPinScriptDialog"
#define DIALOG_BG       RGB(30, 30, 30)
#define DIALOG_FG       RGB(220, 220, 220)
#define DIALOG_HR_COLOR RGB(60, 60, 60)
#define TABLE_ROW_EVEN  RGB(35, 35, 35)
#define TABLE_ROW_ODD   RGB(40, 40, 40)
#define TABLE_HDR_BG    RGB(45, 45, 45)
#define PADDING_X 12
#define PADDING_Y 8

typedef struct {
    DialogSpec spec;
    WCHAR lua_path[MAX_PATH];
    ParamEntry params[CFG_MAX_PARAMS];
    int param_count;
    int scroll_y;
    int content_height;
} ScriptDialogState;

static HWND s_dialog_hwnd = NULL;
static BOOL s_class_registered = FALSE;

static int calc_content_height(HDC hdc, DialogSpec *spec);
static void paint_dialog(HWND hwnd, HDC hdc, ScriptDialogState *state);
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

void show_script_dialog(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                        const DialogSpec *spec) {
    if (s_dialog_hwnd) {
        SetForegroundWindow(s_dialog_hwnd);
        return;
    }

    ScriptDialogState *state = (ScriptDialogState *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScriptDialogState));
    if (!state) return;

    memcpy(&state->spec, spec, sizeof(DialogSpec));
    lstrcpynW(state->lua_path, lua_path, MAX_PATH);
    state->param_count = param_count;
    if (params && param_count > 0)
        memcpy(state->params, params, sizeof(ParamEntry) * param_count);
    state->scroll_y = 0;

    int w = spec->width > 0 ? spec->width : 400;
    int h = spec->height > 0 ? spec->height : 300;

    DWORD style = WS_OVERLAPPEDWINDOW | WS_VSCROLL;
    RECT wr = {0, 0, w, h};
    AdjustWindowRectEx(&wr, style, FALSE, WS_EX_TOPMOST);

    int win_w = wr.right - wr.left;
    int win_h = wr.bottom - wr.top;
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    int x = (screen_w - win_w) / 2;
    int y = (screen_h - win_h) / 2;

    s_dialog_hwnd = CreateWindowExW(WS_EX_TOPMOST, DIALOG_CLASS, spec->title,
        style,
        x, y, win_w, win_h,
        NULL, NULL, GetModuleHandle(NULL), state);

    ShowWindow(s_dialog_hwnd, SW_SHOW);
    UpdateWindow(s_dialog_hwnd);
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
            int row_h = tm.tmHeight + 6;
            y += row_h; /* header */
            y += 2;     /* header separator */
            y += row_h * item->row_count;
            SelectObject(hdc, old);
            DeleteObject(hf);
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

    HBRUSH bg = CreateSolidBrush(DIALOG_BG);
    FillRect(hdc, &rc, bg);
    DeleteObject(bg);

    SetBkMode(hdc, TRANSPARENT);

    int y = PADDING_Y - state->scroll_y;
    int client_w = rc.right - rc.left;

    for (int i = 0; i < state->spec.item_count; i++) {
        DialogItem *item = &state->spec.items[i];

        switch (item->type) {
        case DI_TEXT: {
            int pt = item->font_size > 0 ? item->font_size : 10;
            HFONT hf = create_dialog_font(pt, item->bold);
            HFONT old = (HFONT)SelectObject(hdc, hf);
            COLORREF clr = (item->color != 0xFFFFFFFF) ? item->color : DIALOG_FG;
            SetTextColor(hdc, clr);
            TEXTMETRICW tm;
            GetTextMetricsW(hdc, &tm);
            TextOutW(hdc, PADDING_X, y, item->text, lstrlenW(item->text));
            y += tm.tmHeight + 4;
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
            int row_h = tm.tmHeight + 6;
            int col_w = (client_w - PADDING_X * 2) / (item->col_count > 0 ? item->col_count : 1);

            /* Header */
            RECT hdr_rc = { PADDING_X, y, client_w - PADDING_X, y + row_h };
            HBRUSH hdr_bg = CreateSolidBrush(TABLE_HDR_BG);
            FillRect(hdc, &hdr_rc, hdr_bg);
            DeleteObject(hdr_bg);

            SelectObject(hdc, hf_bold);
            SetTextColor(hdc, DIALOG_FG);
            for (int c = 0; c < item->col_count; c++) {
                TextOutW(hdc, PADDING_X + c * col_w + 4, y + 3,
                    item->columns[c], lstrlenW(item->columns[c]));
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
                RECT row_rc = { PADDING_X, y, client_w - PADDING_X, y + row_h };
                HBRUSH row_bg = CreateSolidBrush((r % 2 == 0) ? TABLE_ROW_EVEN : TABLE_ROW_ODD);
                FillRect(hdc, &row_rc, row_bg);
                DeleteObject(row_bg);

                COLORREF row_clr = (item->row_colors[r] != 0) ? item->row_colors[r] : DIALOG_FG;
                SetTextColor(hdc, row_clr);

                for (int c = 0; c < item->col_count; c++) {
                    TextOutW(hdc, PADDING_X + c * col_w + 4, y + 3,
                        item->cells[r][c], lstrlenW(item->cells[r][c]));
                }
                y += row_h;
            }

            SelectObject(hdc, old);
            DeleteObject(hf_bold);
            DeleteObject(hf_norm);
            break;
        }
        }
        y += 4;
    }

    state->content_height = y + state->scroll_y + PADDING_Y;
}

static void refresh_dialog(HWND hwnd, ScriptDialogState *state) {
    ScriptResult *result = (ScriptResult *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScriptResult));
    if (!result) return;
    if (script_exec_file(state->lua_path, state->params, state->param_count, result)) {
        if (result->click_action == CLICK_DIALOG && result->dialog.item_count > 0) {
            memcpy(&state->spec, &result->dialog, sizeof(DialogSpec));
            InvalidateRect(hwnd, NULL, TRUE);
        }
    }
    HeapFree(GetProcessHeap(), 0, result);
}

static void update_scrollbar(HWND hwnd, ScriptDialogState *state) {
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
    case WM_CREATE: {
        CREATESTRUCTW *cs = (CREATESTRUCTW *)lp;
        state = (ScriptDialogState *)cs->lpCreateParams;
        SetWindowLongPtr(hwnd, GWLP_USERDATA, (LONG_PTR)state);
        if (state->spec.refresh > 0) {
            SetTimer(hwnd, IDT_DIALOG_REFRESH, state->spec.refresh * 1000, NULL);
        }
        return 0;
    }

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        if (state) {
            paint_dialog(hwnd, hdc, state);
            update_scrollbar(hwnd, state);
        }
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_TIMER:
        if (wp == IDT_DIALOG_REFRESH && state) {
            refresh_dialog(hwnd, state);
        }
        return 0;

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

    case WM_SIZE:
        if (state) InvalidateRect(hwnd, NULL, TRUE);
        return 0;

    case WM_DESTROY:
        KillTimer(hwnd, IDT_DIALOG_REFRESH);
        if (state) HeapFree(GetProcessHeap(), 0, state);
        s_dialog_hwnd = NULL;
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wp, lp);
}