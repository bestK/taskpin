#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>
#include <winhttp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"
#include "appbar.h"
#include "fetcher.h"
#include "json.h"
#include "scripting.h"
#include "update.h"

#define IDT_REFRESH        1
#define IDT_SCROLL         2
#define SCROLL_SPEED       2   /* pixels per tick */
#define SCROLL_INTERVAL    50  /* ms between scroll ticks */

#define IDM_SHOW    3001
#define IDM_EXIT    3002

#define IDB_ADD     4001
#define IDB_DEL     4002
#define IDB_SELECT  4003
#define IDB_SETTINGS 4004
#define IDC_LIST    4010

/* Edit dialog controls */
#define IDE_NAME    5001
#define IDE_URL     5002
#define IDE_INT     5003
#define IDE_EXPR    5004
#define IDB_LOAD    5005
#define IDC_TREE    5006
#define IDC_PREVIEW 5007
#define IDB_OK      5008
#define IDB_CANCEL  5009

static TaskPinConfig g_cfg;
static WCHAR g_display[FETCH_BUF_SIZE];
static HFONT g_font;
static BOOL  g_fetching = FALSE;
static char  g_last_response[FETCH_BUF_SIZE];
static ScriptResult g_script_result = {0};
static int   g_scroll_offset = 0;
static int   g_text_width = 0;  /* measured text width in pixels */  /* last script result for click handling */

static HWND g_bar_hwnd  = NULL;
static HWND g_main_hwnd = NULL;
static HWND g_listview  = NULL;
static HINSTANCE g_hinst;

/* ─── field expression engine (template interpolation) ─── */
/* Template syntax: literal text mixed with $.path expressions.
   Example: "车辆:$.name 速度:$.speed km/h"
   $. starts a JSONPath, ends at whitespace or end-of-string.
   If no $ found, treat entire expr as raw JSONPath for backward compat. */

static void extract_fields(const char *raw, const WCHAR *expr, WCHAR *out, int out_size) {
    out[0] = L'\0';
    if (!expr || !expr[0]) {
        MultiByteToWideChar(CP_UTF8, 0, raw, -1, out, out_size);
        return;
    }

    char expr8[CFG_MAX_EXPR];
    WideCharToMultiByte(CP_UTF8, 0, expr, -1, expr8, CFG_MAX_EXPR, NULL, NULL);

    JsonNode *root = json_parse(raw);

    char result[FETCH_BUF_SIZE] = {0};
    int rpos = 0;
    const char *p = expr8;

    while (*p && rpos < FETCH_BUF_SIZE - 2) {
        if (*p == '$' && *(p + 1) == '.') {
            /* Extract JSONPath: $. until whitespace, comma, or end */
            const char *start = p;
            p += 2;
            while (*p && *p != ' ' && *p != '\t' && *p != ',' &&
                   *p != '\n' && *p != '\r') p++;
            int pathlen = (int)(p - start);
            char path[512];
            if (pathlen >= 512) pathlen = 511;
            memcpy(path, start, pathlen);
            path[pathlen] = '\0';

            if (root) {
                JsonNode *node = json_path_query(root, path);
                if (node) {
                    rpos += json_node_to_string(node, result + rpos, FETCH_BUF_SIZE - rpos);
                } else {
                    /* path not found, keep original */
                    int copylen = pathlen;
                    if (rpos + copylen >= FETCH_BUF_SIZE) copylen = FETCH_BUF_SIZE - rpos - 1;
                    memcpy(result + rpos, start, copylen);
                    rpos += copylen;
                }
            } else {
                /* not JSON, keep original */
                int copylen = pathlen;
                if (rpos + copylen >= FETCH_BUF_SIZE) copylen = FETCH_BUF_SIZE - rpos - 1;
                memcpy(result + rpos, start, copylen);
                rpos += copylen;
            }
        } else {
            result[rpos++] = *p++;
        }
    }
    result[rpos] = '\0';
    if (root) json_free(root);

    MultiByteToWideChar(CP_UTF8, 0, result, -1, out, out_size);
}

/* ─── fetch logic ─── */

static void start_fetch(HWND hwnd) {
    if (g_fetching) return;
    if (g_cfg.selected < 0 || g_cfg.selected >= g_cfg.count) {
        lstrcpyW(g_display, L"(no item selected)");
        InvalidateRect(hwnd, NULL, TRUE);
        return;
    }

    PinItem *it = &g_cfg.items[g_cfg.selected];

    if (it->type == ITEM_TYPE_LUA) {
        /* Lua file mode: execute script directly (blocking, but fast) */
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

    /* URL mode: async HTTP fetch */
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

/* ─── edit dialog state ─── */

typedef struct {
    HWND hDlg;
    HWND hType, hName, hUrl, hInt, hExpr;
    HWND hTree, hPreview;
    HWND hClickCheck, hClickUrl;
    HWND hLuaPath;
    HWND hUrlLabel, hLuaLabel, hLoadBtn;
    HWND hHeaders, hHeadersLabel;
    HWND hTypeLabel, hNameLabel;
    HWND hIntLabel, hRespLabel, hTemplateLabel, hPreviewLabel, hClickUrlLabel;
    HWND hBrowseBtn;
    /* Param fields for Lua scripts */
    HWND hParamLabel[CFG_MAX_PARAMS];
    HWND hParamEdit[CFG_MAX_PARAMS];
    int  param_decl_count;
    int  item_index;   /* -1 = new item */
    char cached_response[FETCH_BUF_SIZE];
    JsonNode *json_root;
} EditDlgState;

static EditDlgState *g_edit = NULL;
static BOOL g_edit_done = FALSE;
static BOOL g_edit_accepted = FALSE;
static WNDPROC g_orig_dlg_proc = NULL;

/* Forward declarations */
static void edit_load_response(EditDlgState *st);
static void edit_update_preview(EditDlgState *st);

static void edit_load_params(const WCHAR *lua_path, const PinItem *existing) {
    if (!g_edit) return;
    /* Hide all param slots first */
    for (int i = 0; i < CFG_MAX_PARAMS; i++) {
        ShowWindow(g_edit->hParamLabel[i], SW_HIDE);
        ShowWindow(g_edit->hParamEdit[i], SW_HIDE);
    }
    g_edit->param_decl_count = 0;
    if (!lua_path || !lua_path[0]) return;

    ScriptParamDecl decls[CFG_MAX_PARAMS];
    int n = script_parse_params(lua_path, decls, CFG_MAX_PARAMS);
    g_edit->param_decl_count = n;

    for (int i = 0; i < n; i++) {
        /* Set label */
        WCHAR lbl[128];
        MultiByteToWideChar(CP_UTF8, 0, decls[i].label[0] ? decls[i].label : decls[i].key,
            -1, lbl, 128);
        SetWindowTextW(g_edit->hParamLabel[i], lbl);
        ShowWindow(g_edit->hParamLabel[i], SW_SHOW);
        ShowWindow(g_edit->hParamEdit[i], SW_SHOW);

        /* Pre-fill from existing config if key matches */
        if (existing) {
            WCHAR wkey[64];
            MultiByteToWideChar(CP_UTF8, 0, decls[i].key, -1, wkey, 64);
            for (int j = 0; j < existing->param_count; j++) {
                if (lstrcmpW(existing->params[j].key, wkey) == 0) {
                    SetWindowTextW(g_edit->hParamEdit[i], existing->params[j].value);
                    break;
                }
            }
        }
    }
}

static void edit_relayout(void) {
    if (!g_edit) return;
    int sel = (int)SendMessageW(g_edit->hType, CB_GETCURSEL, 0, 0);
    BOOL is_url = (sel == ITEM_TYPE_URL);

    RECT dlg_rc;
    GetClientRect(g_edit->hDlg, &dlg_rc);
    int cw = dlg_rc.right;
    int margin = 10;
    int w = cw - 2 * margin;

    /* --- Visibility --- */
    int url_sw = is_url ? SW_SHOW : SW_HIDE;
    int lua_sw = is_url ? SW_HIDE : SW_SHOW;

    ShowWindow(g_edit->hUrlLabel, url_sw);
    ShowWindow(g_edit->hUrl, url_sw);
    ShowWindow(g_edit->hLoadBtn, url_sw);
    ShowWindow(g_edit->hHeaders, url_sw);
    ShowWindow(g_edit->hHeadersLabel, url_sw);
    ShowWindow(g_edit->hExpr, url_sw);
    ShowWindow(g_edit->hTree, url_sw);
    ShowWindow(g_edit->hPreview, url_sw);
    ShowWindow(g_edit->hPreviewLabel, url_sw);
    ShowWindow(g_edit->hClickCheck, url_sw);
    ShowWindow(g_edit->hClickUrl, url_sw);
    ShowWindow(g_edit->hClickUrlLabel, url_sw);
    ShowWindow(g_edit->hRespLabel, url_sw);
    ShowWindow(g_edit->hTemplateLabel, url_sw);

    ShowWindow(g_edit->hLuaLabel, lua_sw);
    ShowWindow(g_edit->hLuaPath, lua_sw);
    ShowWindow(g_edit->hBrowseBtn, lua_sw);

    /* Params: visible only in Lua mode and only declared ones */
    for (int i = 0; i < CFG_MAX_PARAMS; i++) {
        int ps = (!is_url && i < g_edit->param_decl_count) ? SW_SHOW : SW_HIDE;
        ShowWindow(g_edit->hParamLabel[i], ps);
        ShowWindow(g_edit->hParamEdit[i], ps);
    }

    /* --- Layout: top-down Y accumulation --- */
    int y = margin;

    /* Row: Type + Name (always visible) */
    MoveWindow(g_edit->hTypeLabel, margin, y + 2, 40, 18, TRUE);
    MoveWindow(g_edit->hType, margin + 45, y, 120, 200, TRUE);
    MoveWindow(g_edit->hNameLabel, 190, y + 2, 40, 18, TRUE);
    MoveWindow(g_edit->hName, 235, y, cw - 235 - margin, 22, TRUE);
    y += 30;

    if (is_url) {
        /* URL row */
        MoveWindow(g_edit->hUrlLabel, margin, y + 2, 50, 18, TRUE);
        MoveWindow(g_edit->hUrl, 65, y, w - 120, 22, TRUE);
        MoveWindow(g_edit->hLoadBtn, cw - margin - 60, y, 60, 22, TRUE);
        y += 28;

        /* Headers row */
        MoveWindow(g_edit->hHeadersLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hHeaders, 65, y, w - 55, 48, TRUE);
        y += 56;

        /* Interval row */
        MoveWindow(g_edit->hIntLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hInt, 65, y, 80, 22, TRUE);
        y += 30;

        /* Response structure label */
        MoveWindow(g_edit->hRespLabel, margin, y, 350, 18, TRUE);
        y += 20;

        /* TreeView: fill available vertical space, reserve room for controls below */
        int bottom_reserve = 230;
        int tree_h = dlg_rc.bottom - y - bottom_reserve;
        if (tree_h < 80) tree_h = 80;
        MoveWindow(g_edit->hTree, margin, y, w, tree_h, TRUE);
        y += tree_h + 8;

        /* Template label + expr */
        MoveWindow(g_edit->hTemplateLabel, margin, y, 60, 18, TRUE);
        y += 20;
        MoveWindow(g_edit->hExpr, margin, y, w, 60, TRUE);
        y += 68;

        /* Preview row */
        MoveWindow(g_edit->hPreviewLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hPreview, 65, y, w - 55, 22, TRUE);
        y += 30;

        /* Click checkbox */
        MoveWindow(g_edit->hClickCheck, margin, y, 200, 20, TRUE);
        y += 24;

        /* Click URL row */
        MoveWindow(g_edit->hClickUrlLabel, margin, y + 2, 70, 18, TRUE);
        MoveWindow(g_edit->hClickUrl, 80, y, w - 70, 22, TRUE);
        y += 30;
    } else {
        /* Lua File row */
        MoveWindow(g_edit->hLuaLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hLuaPath, 70, y, w - 100, 22, TRUE);
        MoveWindow(g_edit->hBrowseBtn, cw - margin - 30, y, 30, 22, TRUE);
        y += 30;

        /* Interval row */
        MoveWindow(g_edit->hIntLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hInt, 70, y, 80, 22, TRUE);
        y += 30;

        /* Param rows */
        for (int i = 0; i < g_edit->param_decl_count; i++) {
            MoveWindow(g_edit->hParamLabel[i], margin, y + 2, 100, 18, TRUE);
            MoveWindow(g_edit->hParamEdit[i], 115, y, w - 105, 22, TRUE);
            y += 28;
        }
        y += 10;
    }

    /* OK / Cancel buttons */
    HWND hOk = GetDlgItem(g_edit->hDlg, IDB_OK);
    HWND hCancel = GetDlgItem(g_edit->hDlg, IDB_CANCEL);
    if (hOk) MoveWindow(hOk, cw / 2 - 85, y, 80, 28, TRUE);
    if (hCancel) MoveWindow(hCancel, cw / 2 + 5, y, 80, 28, TRUE);
    y += 40;

    /* Resize dialog height to fit content */
    RECT wr; GetWindowRect(g_edit->hDlg, &wr);
    int frame_h = (wr.bottom - wr.top) - dlg_rc.bottom;
    int target_h = y + frame_h;
    if (is_url && target_h < 760) target_h = 760;
    SetWindowPos(g_edit->hDlg, NULL, 0, 0, wr.right - wr.left, target_h,
        SWP_NOMOVE | SWP_NOZORDER);

    /* Interval label always visible */
    ShowWindow(g_edit->hIntLabel, SW_SHOW);
    ShowWindow(g_edit->hInt, SW_SHOW);

    InvalidateRect(g_edit->hDlg, NULL, TRUE);
}

/* Subclassed window proc for edit dialog */
static LRESULT CALLBACK edit_dlg_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_COMMAND: {
        WORD id = LOWORD(wp);
        WORD code = HIWORD(wp);
        if (id == 5050 && code == CBN_SELCHANGE) {
            edit_relayout();
            return 0;
        }
        if (id == 5052 && code == BN_CLICKED) {
            /* Browse for .lua file */
            WCHAR file[MAX_PATH] = {0};
            OPENFILENAMEW ofn = {0};
            ofn.lStructSize = sizeof(ofn);
            ofn.hwndOwner = hwnd;
            ofn.lpstrFilter = L"Lua Scripts (*.lua)\0*.lua\0All Files\0*.*\0";
            ofn.lpstrFile = file;
            ofn.nMaxFile = MAX_PATH;
            ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
            if (GetOpenFileNameW(&ofn)) {
                SetWindowTextW(g_edit->hLuaPath, file);
                edit_load_params(file, NULL);
            }
            return 0;
        }
        if (id == IDB_LOAD && code == BN_CLICKED) {
            edit_load_response(g_edit);
            return 0;
        }
        if (id == IDE_EXPR && code == EN_CHANGE) {
            edit_update_preview(g_edit);
            return 0;
        }
        if (id == IDB_OK && code == BN_CLICKED) {
            g_edit_accepted = TRUE;
            g_edit_done = TRUE;
            return 0;
        }
        if (id == IDB_CANCEL && code == BN_CLICKED) {
            g_edit_done = TRUE;
            return 0;
        }
        break;
    }
    case WM_NOTIFY: {
        NMHDR *nm = (NMHDR *)lp;
        if (g_edit && nm->hwndFrom == g_edit->hTree && nm->code == TVN_SELCHANGEDW) {
            NMTREEVIEWW *ntv = (NMTREEVIEWW *)lp;
            char *path = (char *)ntv->itemNew.lParam;
            if (path) {
                WCHAR wpath[512];
                MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 512);
                /* Insert at cursor position in expr edit */
                DWORD start = 0, end = 0;
                SendMessageW(g_edit->hExpr, EM_GETSEL, (WPARAM)&start, (LPARAM)&end);
                SendMessageW(g_edit->hExpr, EM_REPLACESEL, TRUE, (LPARAM)wpath);
                edit_update_preview(g_edit);
            }
        }
        break;
    }
    case WM_SIZE: {
        edit_relayout();
        return 0;
    }
    case WM_CLOSE:
        g_edit_done = TRUE;
        return 0;
    }
    return CallWindowProcW(g_orig_dlg_proc, hwnd, msg, wp, lp);
}

/* Build TreeView from JSON node recursively */
static void tree_add_json(HWND hTree, HTREEITEM parent, JsonNode *node, char *path_buf, int path_len) {
    (void)path_len;
    if (!node) return;
    for (JsonNode *c = (node->type == JSON_OBJECT || node->type == JSON_ARRAY) ? node->children : NULL;
         c; c = c->next) {
        char label[256];
        char child_path[512];

        if (node->type == JSON_OBJECT && c->key) {
            snprintf(child_path, 512, "%s.%s", path_buf, c->key);
            char val_str[128];
            json_node_to_string(c, val_str, 128);
            snprintf(label, 256, "%s: %s", c->key, val_str);
        } else {
            int idx = 0;
            for (JsonNode *t = node->children; t && t != c; t = t->next) idx++;
            snprintf(child_path, 512, "%s[%d]", path_buf, idx);
            char val_str[128];
            json_node_to_string(c, val_str, 128);
            snprintf(label, 256, "[%d]: %s", idx, val_str);
        }

        WCHAR wlabel[256];
        MultiByteToWideChar(CP_UTF8, 0, label, -1, wlabel, 256);

        TVINSERTSTRUCTW tvis = {0};
        tvis.hParent = parent;
        tvis.hInsertAfter = TVI_LAST;
        tvis.item.mask = TVIF_TEXT | TVIF_PARAM;
        tvis.item.pszText = wlabel;
        /* Store path string as lParam — allocate copy */
        char *path_copy = _strdup(child_path);
        tvis.item.lParam = (LPARAM)path_copy;

        HTREEITEM hItem = TreeView_InsertItem(hTree, &tvis);

        if (c->type == JSON_OBJECT || c->type == JSON_ARRAY) {
            tree_add_json(hTree, hItem, c, child_path, (int)strlen(child_path));
        }
    }
}

static void edit_load_response(EditDlgState *st) {
    /* Synchronous fetch for edit dialog */
    WCHAR url[CFG_MAX_URL];
    GetWindowTextW(st->hUrl, url, CFG_MAX_URL);

    /* Use fetcher in blocking mode */
    FetchContext ctx = {0};
    ctx.hwnd = NULL;
    lstrcpynW(ctx.url, url, 1024);
    GetWindowTextW(st->hHeaders, ctx.headers, 1024);
    fetcher_thread(&ctx);

    if (ctx.success) {
        memcpy(st->cached_response, ctx.result, FETCH_BUF_SIZE);
    } else {
        strcpy(st->cached_response, "[fetch error]");
    }

    /* Parse JSON */
    if (st->json_root) { json_free(st->json_root); st->json_root = NULL; }
    st->json_root = json_parse(st->cached_response);

    /* Populate TreeView */
    TreeView_DeleteAllItems(st->hTree);
    if (st->json_root) {
        tree_add_json(st->hTree, TVI_ROOT, st->json_root, "$", 1);
    } else {
        /* Not JSON — show as plain text fields split by | */
        char *p = st->cached_response;
        int idx = 0;
        while (p && *p) {
            char *sep = strchr(p, '|');
            char label[256];
            if (sep) {
                int flen = (int)(sep - p);
                if (flen > 200) flen = 200;
                snprintf(label, 256, "[%d]: %.*s", idx, flen, p);
            } else {
                snprintf(label, 256, "[%d]: %.200s", idx, p);
            }
            WCHAR wlabel[256];
            MultiByteToWideChar(CP_UTF8, 0, label, -1, wlabel, 256);

            char path[32];
            snprintf(path, 32, "%d", idx);

            TVINSERTSTRUCTW tvis = {0};
            tvis.hParent = TVI_ROOT;
            tvis.hInsertAfter = TVI_LAST;
            tvis.item.mask = TVIF_TEXT | TVIF_PARAM;
            tvis.item.pszText = wlabel;
            tvis.item.lParam = (LPARAM)_strdup(path);
            TreeView_InsertItem(st->hTree, &tvis);

            p = sep ? sep + 1 : NULL;
            idx++;
        }
    }

    /* Update preview */
    WCHAR expr[CFG_MAX_EXPR];
    GetWindowTextW(st->hExpr, expr, CFG_MAX_EXPR);
    WCHAR preview[FETCH_BUF_SIZE];
    extract_fields(st->cached_response, expr, preview, FETCH_BUF_SIZE);
    SetWindowTextW(st->hPreview, preview);
}

static void edit_update_preview(EditDlgState *st) {
    if (!st->cached_response[0]) return;
    WCHAR expr[CFG_MAX_EXPR];
    GetWindowTextW(st->hExpr, expr, CFG_MAX_EXPR);
    WCHAR preview[FETCH_BUF_SIZE];
    preview[0] = L'\0';

    if (expr[0]) {
        char lua_code[CFG_MAX_EXPR * 3];
        WideCharToMultiByte(CP_UTF8, 0, expr, -1, lua_code, sizeof(lua_code), NULL, NULL);
        ScriptResult sr = {0};
        if (script_exec(lua_code, st->cached_response, &sr)) {
            lstrcpynW(preview, sr.display, FETCH_BUF_SIZE);
        } else {
            /* Lua failed — fallback to $.path template engine */
            extract_fields(st->cached_response, expr, preview, FETCH_BUF_SIZE);
        }
    } else {
        MultiByteToWideChar(CP_UTF8, 0, st->cached_response, -1, preview, FETCH_BUF_SIZE);
    }
    SetWindowTextW(st->hPreview, preview);
}

/* Free TreeView lParam strings */
static void tree_free_params(HWND hTree, HTREEITEM hItem) {
    if (!hItem) return;
    TVITEMW tvi = {0};
    tvi.mask = TVIF_PARAM;
    tvi.hItem = hItem;
    if (TreeView_GetItem(hTree, &tvi) && tvi.lParam) {
        free((void *)tvi.lParam);
    }
    HTREEITEM child = TreeView_GetChild(hTree, hItem);
    while (child) {
        tree_free_params(hTree, child);
        child = TreeView_GetNextSibling(hTree, child);
    }
}

static void show_edit_dialog(HWND parent, int item_idx);
static void show_settings_dialog(HWND parent);

/* ─── main list window ─── */

static void listview_populate(void) {
    if (!g_listview) return;
    ListView_DeleteAllItems(g_listview);
    for (int i = 0; i < g_cfg.count; i++) {
        LVITEMW lvi = {0};
        lvi.mask    = LVIF_TEXT;
        lvi.iItem   = i;
        lvi.pszText = g_cfg.items[i].name;
        ListView_InsertItem(g_listview, &lvi);

        WCHAR *type_str = (g_cfg.items[i].type == ITEM_TYPE_LUA) ? L"Lua" : L"URL";
        ListView_SetItemText(g_listview, i, 1, type_str);

        WCHAR *source = (g_cfg.items[i].type == ITEM_TYPE_LUA)
            ? g_cfg.items[i].lua_path : g_cfg.items[i].url;
        ListView_SetItemText(g_listview, i, 2, source);

        WCHAR ms[32];
        wsprintfW(ms, L"%u", g_cfg.items[i].interval_ms);
        ListView_SetItemText(g_listview, i, 3, ms);
    }
    if (g_cfg.selected >= 0 && g_cfg.selected < g_cfg.count) {
        ListView_SetItemState(g_listview, g_cfg.selected,
            LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
    }
}

static LRESULT CALLBACK main_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        g_listview = CreateWindowExW(WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
            WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
            0, 0, 620, 260, hwnd, (HMENU)IDC_LIST, g_hinst, NULL);
        ListView_SetExtendedListViewStyle(g_listview,
            LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES);

        LVCOLUMNW col = {0};
        col.mask = LVCF_TEXT | LVCF_WIDTH;
        col.pszText = L"Name"; col.cx = 100;
        ListView_InsertColumn(g_listview, 0, &col);
        col.pszText = L"Type"; col.cx = 50;
        ListView_InsertColumn(g_listview, 1, &col);
        col.pszText = L"Source"; col.cx = 300;
        ListView_InsertColumn(g_listview, 2, &col);
        col.pszText = L"Interval"; col.cx = 70;
        ListView_InsertColumn(g_listview, 3, &col);

        SendMessageW(g_listview, WM_SETFONT, (WPARAM)g_font, TRUE);

        CreateWindowExW(0, L"BUTTON", L"Add",
            WS_CHILD | WS_VISIBLE, 10, 268, 70, 28, hwnd, (HMENU)IDB_ADD, g_hinst, NULL);
        CreateWindowExW(0, L"BUTTON", L"Delete",
            WS_CHILD | WS_VISIBLE, 90, 268, 70, 28, hwnd, (HMENU)IDB_DEL, g_hinst, NULL);
        CreateWindowExW(0, L"BUTTON", L"Pin to Bar",
            WS_CHILD | WS_VISIBLE, 170, 268, 90, 28, hwnd, (HMENU)IDB_SELECT, g_hinst, NULL);
        CreateWindowExW(0, L"BUTTON", L"Settings",
            WS_CHILD | WS_VISIBLE, 270, 268, 80, 28, hwnd, (HMENU)IDB_SETTINGS, g_hinst, NULL);

        /* Version label (clickable → opens GitHub) */
        CreateWindowExW(0, L"STATIC", L"v" TASKPIN_VERSION,
            WS_CHILD | WS_VISIBLE | SS_RIGHT | SS_NOTIFY,
            520, 274, 100, 18, hwnd, (HMENU)4099, g_hinst, NULL);

        listview_populate();
        return 0;
    }

    case WM_NOTIFY: {
        NMHDR *nm = (NMHDR *)lp;
        if (nm->hwndFrom == g_listview && nm->code == NM_DBLCLK) {
            int sel = ListView_GetNextItem(g_listview, -1, LVNI_SELECTED);
            if (sel >= 0 && sel < g_cfg.count) {
                show_edit_dialog(hwnd, sel);
            }
        }
        return 0;
    }

    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case IDB_ADD:
            show_edit_dialog(hwnd, -1);
            break;
        case 4099: /* Version label clicked */
            ShellExecuteW(NULL, L"open", L"https://github.com/bestK/taskpin", NULL, NULL, SW_SHOWNORMAL);
            break;
        case IDB_SETTINGS:
            show_settings_dialog(hwnd);
            break;
        case IDB_DEL: {
            int sel = ListView_GetNextItem(g_listview, -1, LVNI_SELECTED);
            if (sel >= 0 && sel < g_cfg.count) {
                for (int i = sel; i < g_cfg.count - 1; i++)
                    g_cfg.items[i] = g_cfg.items[i + 1];
                g_cfg.count--;
                if (g_cfg.selected == sel) g_cfg.selected = -1;
                else if (g_cfg.selected > sel) g_cfg.selected--;
                config_save(&g_cfg);
                listview_populate();
                if (g_cfg.selected >= 0 && g_cfg.selected < g_cfg.count) {
                    KillTimer(g_bar_hwnd, IDT_REFRESH);
                    SetTimer(g_bar_hwnd, IDT_REFRESH, g_cfg.items[g_cfg.selected].interval_ms, NULL);
                }
                start_fetch(g_bar_hwnd);
            }
            break;
        }
        case IDB_SELECT: {
            int sel = ListView_GetNextItem(g_listview, -1, LVNI_SELECTED);
            if (sel >= 0 && sel < g_cfg.count) {
                g_cfg.selected = sel;
                config_save(&g_cfg);
                KillTimer(g_bar_hwnd, IDT_REFRESH);
                SetTimer(g_bar_hwnd, IDT_REFRESH, g_cfg.items[sel].interval_ms, NULL);
                g_fetching = FALSE;
                start_fetch(g_bar_hwnd);
                /* Immediate visual feedback */
                WCHAR tmp[256];
                wsprintfW(tmp, L"Pinned: %s", g_cfg.items[sel].name);
                lstrcpynW(g_display, tmp, FETCH_BUF_SIZE);
                InvalidateRect(g_bar_hwnd, NULL, TRUE);
            } else {
                MessageBoxW(hwnd, L"Please select an item first.", L"TaskPin", MB_OK | MB_ICONINFORMATION);
            }
            break;
        }
        }
        return 0;

    case WM_SIZE: {
        RECT rc;
        GetClientRect(hwnd, &rc);
        int cw = rc.right, ch = rc.bottom;
        if (g_listview)
            MoveWindow(g_listview, 0, 0, cw, ch - 36, TRUE);
        return 0;
    }

    case WM_CLOSE:
        ShowWindow(hwnd, SW_HIDE);
        return 0;

    case WM_DESTROY:
        g_main_hwnd = NULL;
        g_listview  = NULL;
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static void show_main_window(void) {
    if (g_main_hwnd) {
        ShowWindow(g_main_hwnd, SW_SHOW);
        SetForegroundWindow(g_main_hwnd);
        listview_populate();
        return;
    }
    g_main_hwnd = CreateWindowExW(0, L"TaskPinMainClass", L"TaskPin - Items",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 640, 340,
        NULL, NULL, g_hinst, NULL);
    ShowWindow(g_main_hwnd, SW_SHOW);
    UpdateWindow(g_main_hwnd);
}

/* ─── settings dialog ─── */

static BOOL g_settings_done = FALSE;
static BOOL g_settings_accepted = FALSE;
static WNDPROC g_settings_orig_proc = NULL;

static HWND s_eFontSize, s_eFontColor, s_eBgColor, s_eWidth, s_ePosX, s_ePosY;

static LRESULT CALLBACK settings_dlg_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_COMMAND) {
        WORD id = LOWORD(wp);
        if (id == IDOK && HIWORD(wp) == BN_CLICKED) {
            g_settings_accepted = TRUE;
            g_settings_done = TRUE;
            return 0;
        }
        if (id == IDCANCEL && HIWORD(wp) == BN_CLICKED) {
            g_settings_done = TRUE;
            return 0;
        }
    }
    if (msg == WM_CLOSE) { g_settings_done = TRUE; return 0; }
    return CallWindowProcW(g_settings_orig_proc, hwnd, msg, wp, lp);
}

static void show_settings_dialog(HWND parent) {
    HWND hDlg = CreateWindowExW(WS_EX_DLGMODALFRAME | WS_EX_TOPMOST,
        L"#32770", L"Settings",
        WS_VISIBLE | WS_POPUP | WS_CAPTION | WS_SYSMENU,
        200, 200, 360, 370, parent, NULL, g_hinst, NULL);
    if (!hDlg) return;

    int y = 10;
    CreateWindowExW(0, L"STATIC", L"Font Size (pt):", WS_CHILD | WS_VISIBLE,
        10, y+2, 100, 20, hDlg, NULL, g_hinst, NULL);
    s_eFontSize = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_NUMBER, 120, y, 50, 22, hDlg, NULL, g_hinst, NULL);

    y += 30;
    CreateWindowExW(0, L"STATIC", L"Font Color (hex):", WS_CHILD | WS_VISIBLE,
        10, y+2, 110, 20, hDlg, NULL, g_hinst, NULL);
    s_eFontColor = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 120, y, 80, 22, hDlg, NULL, g_hinst, NULL);

    y += 30;
    CreateWindowExW(0, L"STATIC", L"BG Color (hex):", WS_CHILD | WS_VISIBLE,
        10, y+2, 100, 20, hDlg, NULL, g_hinst, NULL);
    s_eBgColor = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 120, y, 80, 22, hDlg, NULL, g_hinst, NULL);

    y += 30;
    CreateWindowExW(0, L"STATIC", L"Width (px):", WS_CHILD | WS_VISIBLE,
        10, y+2, 80, 20, hDlg, NULL, g_hinst, NULL);
    s_eWidth = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_NUMBER, 120, y, 60, 22, hDlg, NULL, g_hinst, NULL);

    y += 30;
    CreateWindowExW(0, L"STATIC", L"Pos X (-1=auto):", WS_CHILD | WS_VISIBLE,
        10, y+2, 105, 20, hDlg, NULL, g_hinst, NULL);
    s_ePosX = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE, 120, y, 60, 22, hDlg, NULL, g_hinst, NULL);

    CreateWindowExW(0, L"STATIC", L"Y:", WS_CHILD | WS_VISIBLE,
        195, y+2, 20, 20, hDlg, NULL, g_hinst, NULL);
    s_ePosY = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE, 218, y, 60, 22, hDlg, NULL, g_hinst, NULL);

    y += 30;
    HWND s_eAutoStart = CreateWindowExW(0, L"BUTTON", L"Start with Windows",
        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
        10, y, 180, 20, hDlg, (HMENU)5060, g_hinst, NULL);
    SendMessageW(s_eAutoStart, WM_SETFONT, (WPARAM)g_font, TRUE);
    /* Check current autostart state */
    {
        HKEY hk;
        if (RegOpenKeyExW(HKEY_CURRENT_USER,
                L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                0, KEY_READ, &hk) == ERROR_SUCCESS) {
            if (RegQueryValueExW(hk, L"TaskPin", NULL, NULL, NULL, NULL) == ERROR_SUCCESS)
                SendMessageW(s_eAutoStart, BM_SETCHECK, BST_CHECKED, 0);
            RegCloseKey(hk);
        }
    }

    y += 24;
    HWND s_eScroll = CreateWindowExW(0, L"BUTTON", L"Auto-scroll long text",
        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
        10, y, 200, 20, hDlg, (HMENU)5061, g_hinst, NULL);
    SendMessageW(s_eScroll, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(s_eScroll, BM_SETCHECK, g_cfg.scroll_enabled ? BST_CHECKED : BST_UNCHECKED, 0);

    y += 30;
    CreateWindowExW(0, L"BUTTON", L"OK",
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        90, y, 70, 28, hDlg, (HMENU)IDOK, g_hinst, NULL);
    CreateWindowExW(0, L"BUTTON", L"Cancel",
        WS_CHILD | WS_VISIBLE,
        170, y, 70, 28, hDlg, (HMENU)IDCANCEL, g_hinst, NULL);

    /* Fill current values */
    WCHAR tmp[32];
    wsprintfW(tmp, L"%d", g_cfg.font_size);
    SetWindowTextW(s_eFontSize, tmp);
    wsprintfW(tmp, L"%06X", g_cfg.font_color & 0xFFFFFF);
    SetWindowTextW(s_eFontColor, tmp);
    wsprintfW(tmp, L"%06X", g_cfg.bg_color & 0xFFFFFF);
    SetWindowTextW(s_eBgColor, tmp);
    wsprintfW(tmp, L"%d", g_cfg.width);
    SetWindowTextW(s_eWidth, tmp);
    wsprintfW(tmp, L"%d", g_cfg.pos_x);
    SetWindowTextW(s_ePosX, tmp);
    wsprintfW(tmp, L"%d", g_cfg.pos_y);
    SetWindowTextW(s_ePosY, tmp);

    /* Set font */
    SendMessageW(s_eFontSize, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(s_eFontColor, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(s_eBgColor, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(s_eWidth, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(s_ePosX, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(s_ePosY, WM_SETFONT, (WPARAM)g_font, TRUE);

    g_settings_orig_proc = (WNDPROC)SetWindowLongPtrW(hDlg, GWLP_WNDPROC, (LONG_PTR)settings_dlg_proc);
    g_settings_done = FALSE;
    g_settings_accepted = FALSE;

    EnableWindow(parent, FALSE);
    MSG msg;
    while (!g_settings_done && GetMessageW(&msg, NULL, 0, 0)) {
        if (!IsDialogMessageW(hDlg, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    if (g_settings_accepted) {
        WCHAR tmp2[32];
        GetWindowTextW(s_eFontSize, tmp2, 32);
        g_cfg.font_size = _wtoi(tmp2);
        if (g_cfg.font_size < 6) g_cfg.font_size = 6;
        if (g_cfg.font_size > 72) g_cfg.font_size = 72;

        GetWindowTextW(s_eFontColor, tmp2, 32);
        g_cfg.font_color = (COLORREF)wcstoul(tmp2, NULL, 16);

        GetWindowTextW(s_eBgColor, tmp2, 32);
        g_cfg.bg_color = (COLORREF)wcstoul(tmp2, NULL, 16);

        GetWindowTextW(s_eWidth, tmp2, 32);
        g_cfg.width = _wtoi(tmp2);
        if (g_cfg.width < 50) g_cfg.width = 50;

        GetWindowTextW(s_ePosX, tmp2, 32);
        g_cfg.pos_x = _wtoi(tmp2);

        GetWindowTextW(s_ePosY, tmp2, 32);
        g_cfg.pos_y = _wtoi(tmp2);

        g_cfg.scroll_enabled = (SendMessageW(s_eScroll, BM_GETCHECK, 0, 0) == BST_CHECKED);

        config_save(&g_cfg);

        /* Handle autostart registry */
        {
            HKEY hk;
            BOOL want_auto = (SendMessageW(s_eAutoStart, BM_GETCHECK, 0, 0) == BST_CHECKED);
            if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    0, KEY_SET_VALUE, &hk) == ERROR_SUCCESS) {
                if (want_auto) {
                    WCHAR exe_path[MAX_PATH];
                    GetModuleFileNameW(NULL, exe_path, MAX_PATH);
                    RegSetValueExW(hk, L"TaskPin", 0, REG_SZ,
                        (BYTE *)exe_path, (DWORD)((lstrlenW(exe_path) + 1) * sizeof(WCHAR)));
                } else {
                    RegDeleteValueW(hk, L"TaskPin");
                }
                RegCloseKey(hk);
            }
        }

        /* Recreate font and reposition bar */
        if (g_font) DeleteObject(g_font);
        int fh = -MulDiv(g_cfg.font_size, 96, 72);
        g_font = CreateFontW(fh, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");

        /* Reposition embedded bar */
        appbar_remove(g_bar_hwnd);
        LONG style = GetWindowLongW(g_bar_hwnd, GWL_STYLE);
        style = (style & ~WS_CHILD) | WS_POPUP;
        SetWindowLongW(g_bar_hwnd, GWL_STYLE, style);
        appbar_embed(g_bar_hwnd, g_cfg.width, g_cfg.pos_x, g_cfg.pos_y);
        InvalidateRect(g_bar_hwnd, NULL, TRUE);
    }

    EnableWindow(parent, TRUE);
    DestroyWindow(hDlg);
    g_settings_orig_proc = NULL;
    SetForegroundWindow(parent);
}

/* ─── edit dialog ─── */

static void show_edit_dialog(HWND parent, int item_idx) {
    EditDlgState *st = (EditDlgState *)calloc(1, sizeof(EditDlgState));
    if (!st) return;
    st->item_index = item_idx;
    g_edit = st;

    const WCHAR *title = (item_idx >= 0) ? L"Edit Item" : L"Add Item";
    st->hDlg = CreateWindowExW(WS_EX_DLGMODALFRAME | WS_EX_TOPMOST,
        L"#32770", title,
        WS_VISIBLE | WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME,
        150, 80, 640, 760, parent, NULL, g_hinst, NULL);
    if (!st->hDlg) { free(st); g_edit = NULL; return; }

    int y = 10;
    st->hTypeLabel = CreateWindowExW(0, L"STATIC", L"Type:", WS_CHILD | WS_VISIBLE,
        10, y + 2, 40, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hType = CreateWindowExW(0, L"COMBOBOX", L"",
        WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
        55, y, 120, 100, st->hDlg, (HMENU)5050, g_hinst, NULL);
    SendMessageW(st->hType, CB_ADDSTRING, 0, (LPARAM)L"URL");
    SendMessageW(st->hType, CB_ADDSTRING, 0, (LPARAM)L"Lua File");
    SendMessageW(st->hType, CB_SETCURSEL, 0, 0);
    SendMessageW(st->hType, WM_SETFONT, (WPARAM)g_font, TRUE);

    st->hNameLabel = CreateWindowExW(0, L"STATIC", L"Name:", WS_CHILD | WS_VISIBLE,
        200, y + 2, 40, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hName = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        245, y, 365, 22, st->hDlg, (HMENU)IDE_NAME, g_hinst, NULL);

    y += 30;
    st->hUrlLabel = CreateWindowExW(0, L"STATIC", L"URL:", WS_CHILD | WS_VISIBLE,
        10, y + 2, 50, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hUrl = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"http://localhost:8080/status",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        70, y, 440, 22, st->hDlg, (HMENU)IDE_URL, g_hinst, NULL);
    st->hLoadBtn = CreateWindowExW(0, L"BUTTON", L"Load",
        WS_CHILD | WS_VISIBLE, 520, y, 60, 22, st->hDlg, (HMENU)IDB_LOAD, g_hinst, NULL);

    y += 28;
    st->hHeadersLabel = CreateWindowExW(0, L"STATIC", L"Headers:", WS_CHILD | WS_VISIBLE,
        10, y + 2, 55, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hHeaders = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL,
        70, y, 540, 48, st->hDlg, NULL, g_hinst, NULL);
    SendMessageW(st->hHeaders, WM_SETFONT, (WPARAM)g_font, TRUE);

    st->hLuaLabel = CreateWindowExW(0, L"STATIC", L"Lua File:", WS_CHILD,
        10, y + 2, 60, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hLuaPath = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | ES_AUTOHSCROLL,
        75, y, 470, 22, st->hDlg, (HMENU)5051, g_hinst, NULL);
    SendMessageW(st->hLuaPath, WM_SETFONT, (WPARAM)g_font, TRUE);
    st->hBrowseBtn = CreateWindowExW(0, L"BUTTON", L"...",
        WS_CHILD, 550, y, 30, 22, st->hDlg, (HMENU)5052, g_hinst, NULL);

    y += 56;
    st->hIntLabel = CreateWindowExW(0, L"STATIC", L"Interval:", WS_CHILD | WS_VISIBLE,
        10, y + 2, 55, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hInt = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"5000",
        WS_CHILD | WS_VISIBLE | ES_NUMBER,
        70, y, 80, 22, st->hDlg, (HMENU)IDE_INT, g_hinst, NULL);

    /* Create param input slots (hidden initially, below Interval) */
    for (int pi = 0; pi < CFG_MAX_PARAMS; pi++) {
        int py = y + 28 + pi * 26;
        st->hParamLabel[pi] = CreateWindowExW(0, L"STATIC", L"",
            WS_CHILD, 10, py + 2, 100, 18, st->hDlg, NULL, g_hinst, NULL);
        st->hParamEdit[pi] = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | ES_AUTOHSCROLL, 115, py, 495, 22, st->hDlg, NULL, g_hinst, NULL);
        SendMessageW(st->hParamLabel[pi], WM_SETFONT, (WPARAM)g_font, TRUE);
        SendMessageW(st->hParamEdit[pi], WM_SETFONT, (WPARAM)g_font, TRUE);
    }
    st->param_decl_count = 0;

    y += 30;
    st->hRespLabel = CreateWindowExW(0, L"STATIC", L"Response structure (click to insert):",
        WS_CHILD | WS_VISIBLE, 10, y, 350, 18, st->hDlg, NULL, g_hinst, NULL);

    y += 20;
    st->hTree = CreateWindowExW(WS_EX_CLIENTEDGE, WC_TREEVIEWW, L"",
        WS_CHILD | WS_VISIBLE | TVS_HASLINES | TVS_HASBUTTONS | TVS_LINESATROOT | TVS_SHOWSELALWAYS,
        10, y, 600, 180, st->hDlg, (HMENU)IDC_TREE, g_hinst, NULL);

    y += 188;
    st->hTemplateLabel = CreateWindowExW(0, L"STATIC", L"Template:", WS_CHILD | WS_VISIBLE,
        10, y, 60, 18, st->hDlg, NULL, g_hinst, NULL);

    y += 20;
    st->hExpr = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL,
        10, y, 600, 60, st->hDlg, (HMENU)IDE_EXPR, g_hinst, NULL);

    y += 68;
    st->hPreviewLabel = CreateWindowExW(0, L"STATIC", L"Preview:", WS_CHILD | WS_VISIBLE,
        10, y + 2, 55, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hPreview = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY,
        70, y, 540, 22, st->hDlg, (HMENU)IDC_PREVIEW, g_hinst, NULL);

    y += 30;
    st->hClickCheck = CreateWindowExW(0, L"BUTTON", L"Enable click to open URL",
        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
        10, y, 200, 20, st->hDlg, NULL, g_hinst, NULL);

    y += 24;
    st->hClickUrlLabel = CreateWindowExW(0, L"STATIC", L"Click URL:", WS_CHILD | WS_VISIBLE,
        10, y + 2, 70, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hClickUrl = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        85, y, 525, 22, st->hDlg, NULL, g_hinst, NULL);

    y += 30;
    CreateWindowExW(0, L"BUTTON", L"OK",
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        230, y, 80, 28, st->hDlg, (HMENU)IDB_OK, g_hinst, NULL);
    CreateWindowExW(0, L"BUTTON", L"Cancel",
        WS_CHILD | WS_VISIBLE,
        320, y, 80, 28, st->hDlg, (HMENU)IDB_CANCEL, g_hinst, NULL);

    /* Set font on all children */
    EnumChildWindows(st->hDlg, (WNDENUMPROC)(void*)SendMessageW,
        (LPARAM)0); /* can't easily set font this way, do manually */
    SendMessageW(st->hName, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hUrl, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hInt, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hExpr, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hTree, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hPreview, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hClickCheck, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hClickUrl, WM_SETFONT, (WPARAM)g_font, TRUE);

    /* Pre-fill if editing */
    if (item_idx >= 0) {
        PinItem *it = &g_cfg.items[item_idx];
        SendMessageW(st->hType, CB_SETCURSEL, it->type, 0);
        SetWindowTextW(st->hName, it->name);
        SetWindowTextW(st->hUrl, it->url);
        SetWindowTextW(st->hHeaders, it->req_headers);
        WCHAR tmp[32];
        wsprintfW(tmp, L"%u", it->interval_ms);
        SetWindowTextW(st->hInt, tmp);
        SetWindowTextW(st->hExpr, it->field_expr);
        SendMessageW(st->hClickCheck, BM_SETCHECK,
            it->click_enabled ? BST_CHECKED : BST_UNCHECKED, 0);
        SetWindowTextW(st->hClickUrl, it->click_url);
        SetWindowTextW(st->hLuaPath, it->lua_path);
        if (it->type == ITEM_TYPE_LUA && it->lua_path[0])
            edit_load_params(it->lua_path, it);
    }

    /* Set initial visibility based on type */
    edit_relayout();

    EnableWindow(parent, FALSE);

    /* Subclass the dialog to handle WM_COMMAND/WM_NOTIFY */
    g_orig_dlg_proc = (WNDPROC)SetWindowLongPtrW(st->hDlg, GWLP_WNDPROC, (LONG_PTR)edit_dlg_proc);
    g_edit_done = FALSE;
    g_edit_accepted = FALSE;

    /* Modal message loop */
    MSG msg;
    while (!g_edit_done && GetMessageW(&msg, NULL, 0, 0)) {
        if (!IsDialogMessageW(st->hDlg, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    /* Save if accepted */
    if (g_edit_accepted) {
        PinItem *it;
        if (item_idx >= 0) {
            it = &g_cfg.items[item_idx];
        } else {
            if (g_cfg.count < CFG_MAX_ITEMS) {
                it = &g_cfg.items[g_cfg.count];
                g_cfg.count++;
            } else {
                it = NULL;
            }
        }
        if (it) {
            it->type = (int)SendMessageW(st->hType, CB_GETCURSEL, 0, 0);
            GetWindowTextW(st->hName, it->name, CFG_MAX_NAME);
            GetWindowTextW(st->hUrl, it->url, CFG_MAX_URL);
            GetWindowTextW(st->hHeaders, it->req_headers, CFG_MAX_URL);
            WCHAR tmp[32];
            GetWindowTextW(st->hInt, tmp, 32);
            it->interval_ms = (DWORD)_wtoi(tmp);
            if (it->interval_ms < 1000) it->interval_ms = 1000;
            GetWindowTextW(st->hExpr, it->field_expr, CFG_MAX_EXPR);
            it->click_enabled = (SendMessageW(st->hClickCheck, BM_GETCHECK, 0, 0) == BST_CHECKED);
            GetWindowTextW(st->hClickUrl, it->click_url, CFG_MAX_URL);
            GetWindowTextW(st->hLuaPath, it->lua_path, CFG_MAX_PATH);
            /* Save params */
            ScriptParamDecl decls[CFG_MAX_PARAMS];
            int ndecls = script_parse_params(it->lua_path, decls, CFG_MAX_PARAMS);
            it->param_count = ndecls;
            for (int pi = 0; pi < ndecls && pi < CFG_MAX_PARAMS; pi++) {
                MultiByteToWideChar(CP_UTF8, 0, decls[pi].key, -1,
                    it->params[pi].key, CFG_MAX_PARAM_KEY);
                MultiByteToWideChar(CP_UTF8, 0, decls[pi].label, -1,
                    it->params[pi].label, CFG_MAX_NAME);
                GetWindowTextW(st->hParamEdit[pi], it->params[pi].value, CFG_MAX_PARAM_VAL);
            }
            config_save(&g_cfg);
            listview_populate();
        }
    }

    EnableWindow(parent, TRUE);
    /* Free tree lParam strings */
    HTREEITEM root_item = TreeView_GetRoot(st->hTree);
    while (root_item) {
        tree_free_params(st->hTree, root_item);
        root_item = TreeView_GetNextSibling(st->hTree, root_item);
    }
    if (st->json_root) json_free(st->json_root);
    DestroyWindow(st->hDlg);
    free(st);
    g_edit = NULL;
    g_orig_dlg_proc = NULL;
    SetForegroundWindow(parent);
}

/* ─── appbar (taskbar embedded) window ─── */

static LRESULT CALLBACK bar_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
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

        /* Measure text width */
        SIZE sz;
        GetTextExtentPoint32W(hdc, g_display, lstrlenW(g_display), &sz);
        g_text_width = sz.cx;

        int avail = rc.right - rc.left - 12;
        if (sz.cx <= avail) {
            /* Text fits — no scroll needed */
            g_scroll_offset = 0;
            rc.left += 8; rc.right -= 4;
            DrawTextW(hdc, g_display, -1, &rc,
                DT_SINGLELINE | DT_VCENTER | DT_LEFT);
        } else {
            /* Scrolling: draw text offset to the left */
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
                        /* Lua failed — fallback to $.path template */
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

/* ─── entry ─── */

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, LPWSTR cmdLine, int nShow) {
    (void)hPrev; (void)cmdLine; (void)nShow;
    g_hinst = hInst;

    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_LISTVIEW_CLASSES | ICC_TREEVIEW_CLASSES };
    InitCommonControlsEx(&icc);

    config_load(&g_cfg);
    script_init();

    /* Load app icon */
    HICON hIcon = LoadIconW(hInst, L"IDI_APPICON");

    /* Register bar class */
    WNDCLASSEXW wc = {0};
    wc.cbSize        = sizeof(wc);
    wc.lpfnWndProc   = bar_wnd_proc;
    wc.hInstance     = hInst;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hIcon         = hIcon;
    wc.hIconSm       = hIcon;
    wc.lpszClassName = L"TaskPinBarClass";
    wc.style         = CS_DBLCLKS;
    RegisterClassExW(&wc);

    /* Register main window class */
    wc.lpfnWndProc   = main_wnd_proc;
    wc.lpszClassName = L"TaskPinMainClass";
    wc.style         = 0;
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    RegisterClassExW(&wc);

    /* Create bar window */
    g_bar_hwnd = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        L"TaskPinBarClass", L"TaskPin",
        WS_POPUP,
        0, 0, g_cfg.width, 40,
        NULL, NULL, hInst, NULL);
    if (!g_bar_hwnd) return 1;

    appbar_embed(g_bar_hwnd, g_cfg.width, g_cfg.pos_x, g_cfg.pos_y);
    ShowWindow(g_bar_hwnd, SW_SHOWNOACTIVATE);
    UpdateWindow(g_bar_hwnd);

    DWORD interval = 5000;
    if (g_cfg.selected >= 0 && g_cfg.selected < g_cfg.count)
        interval = g_cfg.items[g_cfg.selected].interval_ms;
    SetTimer(g_bar_hwnd, IDT_REFRESH, interval, NULL);
    start_fetch(g_bar_hwnd);

    /* Background update check */
    HANDLE hUpd = CreateThread(NULL, 0, check_update_thread, NULL, 0, NULL);
    if (hUpd) CloseHandle(hUpd);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    script_shutdown();
    return (int)msg.wParam;
}