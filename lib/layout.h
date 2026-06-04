#ifndef TASKPIN_LAYOUT_H
#define TASKPIN_LAYOUT_H

#include <windows.h>
#include <string.h>

/*
 * Declarative layout engine for Win32 dialogs.
 *
 *   ui_begin(hDlg, g_font, 10, 8);
 *   ui_row(8);
 *     ui_label(tr("Name:"));
 *     ui_add(hEdit, UI_FILL, 22);
 *   ui_end_row();
 *   ui_end();
 *
 * Labels are created internally with correct font/style/width.
 * UI_FILL = fill remaining width in row.
 */

#define UI_FILL (-1)
#define UI_MAX_ITEMS 16
#define UI_MAX_DEPTH 8
#define UI_MAX_LABELS 32

typedef struct { HWND hwnd; int w, h; } UiItem;
typedef enum { UI_DIR_ROW, UI_DIR_COL } UiDir;

typedef struct {
    UiDir dir;
    int gap;
    UiItem items[UI_MAX_ITEMS];
    int count;
    int x, y, w;
} UiFrame;

static struct {
    UiFrame stack[UI_MAX_DEPTH];
    int depth;
    HWND parent;
    HFONT font;
    HINSTANCE hinst;
    HWND labels[UI_MAX_LABELS];
    int label_count;
} g_ui;

static void ui_begin(HWND hDlg, HFONT font, int padding, int gap) {
    memset(&g_ui, 0, sizeof(g_ui));
    g_ui.parent = hDlg;
    g_ui.font = font;
    g_ui.hinst = (HINSTANCE)GetWindowLongPtr(hDlg, GWLP_HINSTANCE);
    RECT rc; GetClientRect(hDlg, &rc);
    UiFrame *root = &g_ui.stack[0];
    root->dir = UI_DIR_COL;
    root->gap = gap;
    root->x = padding;
    root->y = padding;
    root->w = rc.right - padding * 2;
    root->count = 0;
    g_ui.depth = 1;
}

static UiFrame *ui_top(void) {
    return &g_ui.stack[g_ui.depth - 1];
}

static void ui_push(UiDir dir, int gap) {
    if (g_ui.depth >= UI_MAX_DEPTH) return;
    UiFrame *parent = ui_top();
    UiFrame *f = &g_ui.stack[g_ui.depth++];
    memset(f, 0, sizeof(UiFrame));
    f->dir = dir;
    f->gap = gap;
    f->x = parent->x;
    f->y = parent->y;
    f->w = parent->w;
}

static void ui_add(HWND hwnd, int w, int h) {
    UiFrame *f = ui_top();
    if (f->count >= UI_MAX_ITEMS) return;
    UiItem *it = &f->items[f->count++];
    it->hwnd = hwnd;
    it->w = w;
    it->h = h;
}

static int ui_measure_text(const WCHAR *text) {
    HDC hdc = GetDC(g_ui.parent);
    HFONT old = g_ui.font ? (HFONT)SelectObject(hdc, g_ui.font) : NULL;
    SIZE sz;
    GetTextExtentPoint32W(hdc, text, lstrlenW(text), &sz);
    if (old) SelectObject(hdc, old);
    ReleaseDC(g_ui.parent, hdc);
    return sz.cx + 4;
}

static void ui_label(const WCHAR *text) {
    if (g_ui.label_count >= UI_MAX_LABELS) return;
    int w = ui_measure_text(text);
    HWND lbl = CreateWindowExW(0, L"STATIC", text,
        WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP | SS_CENTERIMAGE,
        0, 0, 0, 0, g_ui.parent, NULL, g_ui.hinst, NULL);
    SendMessageW(lbl, WM_SETFONT, (WPARAM)g_ui.font, TRUE);
    g_ui.labels[g_ui.label_count++] = lbl;
    ui_add(lbl, w, 0);
}

static void ui_auto(HWND hwnd, int h) {
    WCHAR text[256];
    GetWindowTextW(hwnd, text, 256);
    int w = ui_measure_text(text);
    ui_add(hwnd, w, h);
}

static int ui_pop(void) {
    if (g_ui.depth <= 1) return 0;
    UiFrame *f = ui_top();
    int n = f->count;

    if (f->dir == UI_DIR_ROW) {
        int total_gap = (n > 1) ? f->gap * (n - 1) : 0;
        int fixed_w = 0, fill_count = 0, max_h = 0;
        for (int i = 0; i < n; i++) {
            if (f->items[i].w == UI_FILL) fill_count++;
            else if (f->items[i].w > 0) fixed_w += f->items[i].w;
            int h = f->items[i].h > 0 ? f->items[i].h : 22;
            if (h > max_h) max_h = h;
        }
        int remain = f->w - fixed_w - total_gap;
        if (remain < 0) remain = 0;
        int fill_w = fill_count > 0 ? remain / fill_count : 0;

        int cx = f->x;
        for (int i = 0; i < n; i++) {
            int w = (f->items[i].w == UI_FILL) ? fill_w :
                    (f->items[i].w > 0 ? f->items[i].w : f->w);
            int h = f->items[i].h > 0 ? f->items[i].h : max_h;
            if (f->items[i].hwnd)
                MoveWindow(f->items[i].hwnd, cx, f->y, w, h, TRUE);
            cx += w + f->gap;
        }

        g_ui.depth--;
        UiFrame *parent = ui_top();
        if (parent->dir == UI_DIR_COL)
            parent->y += max_h + parent->gap;
        return max_h;
    } else {
        int cy = f->y;
        int total_h = 0;
        for (int i = 0; i < n; i++) {
            int w = (f->items[i].w == UI_FILL || f->items[i].w == 0) ? f->w : f->items[i].w;
            int h = f->items[i].h > 0 ? f->items[i].h : 22;
            if (f->items[i].hwnd)
                MoveWindow(f->items[i].hwnd, f->x, cy, w, h, TRUE);
            cy += h + f->gap;
            total_h += h + f->gap;
        }
        if (n > 0) total_h -= f->gap;

        g_ui.depth--;
        UiFrame *parent = ui_top();
        if (parent->dir == UI_DIR_COL)
            parent->y += total_h + parent->gap;
        return total_h;
    }
}

static void ui_end(void) {
    while (g_ui.depth > 1) ui_pop();
}

static void ui_destroy_labels(void) {
    for (int i = 0; i < g_ui.label_count; i++) {
        if (g_ui.labels[i]) DestroyWindow(g_ui.labels[i]);
    }
    g_ui.label_count = 0;
}

#define ui_row(gap)    ui_push(UI_DIR_ROW, gap)
#define ui_end_row()   ui_pop()
#define ui_col(pad, gap) do { ui_push(UI_DIR_COL, gap); UiFrame *_f = ui_top(); _f->x += pad; _f->w -= pad*2; } while(0)
#define ui_end_col()   ui_pop()

#endif
