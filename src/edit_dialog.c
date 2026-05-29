#include "ui.h"

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
    HWND hBarWidthLabel, hBarWidth;
    HWND hBarXLabel, hBarX;
    HWND hBarYLabel, hBarY;
    HWND hBarBgLabel, hBarBg;
    HWND hParamLabel[CFG_MAX_PARAMS];
    HWND hParamEdit[CFG_MAX_PARAMS];
    HWND hParamBrowse[CFG_MAX_PARAMS];
    char param_types[CFG_MAX_PARAMS][16];
    int  param_decl_count;
    int  item_index;
    char cached_response[FETCH_BUF_SIZE];
    JsonNode *json_root;
} EditDlgState;

static EditDlgState *g_edit = NULL;
static BOOL g_edit_done = FALSE;
static BOOL g_edit_accepted = FALSE;
static WNDPROC g_orig_dlg_proc = NULL;

static void edit_load_response(EditDlgState *st);
static void edit_update_preview(EditDlgState *st);

static void edit_load_params(const WCHAR *lua_path, const PinItem *existing) {
    if (!g_edit) return;
    for (int i = 0; i < CFG_MAX_PARAMS; i++) {
        ShowWindow(g_edit->hParamLabel[i], SW_HIDE);
        ShowWindow(g_edit->hParamEdit[i], SW_HIDE);
        if (g_edit->hParamBrowse[i]) ShowWindow(g_edit->hParamBrowse[i], SW_HIDE);
    }
    g_edit->param_decl_count = 0;
    if (!lua_path || !lua_path[0]) return;

    ScriptParamDecl decls[CFG_MAX_PARAMS];
    int n = script_parse_params(lua_path, decls, CFG_MAX_PARAMS);
    g_edit->param_decl_count = n;

    for (int i = 0; i < n; i++) {
        WCHAR lbl[128];
        MultiByteToWideChar(CP_UTF8, 0, decls[i].label[0] ? decls[i].label : decls[i].key,
            -1, lbl, 128);
        const int MAX_LABEL_CHARS = 12;
        if (lstrlenW(lbl) > MAX_LABEL_CHARS) {
            lbl[MAX_LABEL_CHARS] = L'\0';
            lstrcatW(lbl, L"...");
        }
        SetWindowTextW(g_edit->hParamLabel[i], lbl);
        ShowWindow(g_edit->hParamLabel[i], SW_SHOW);
        ShowWindow(g_edit->hParamEdit[i], SW_SHOW);
        strncpy(g_edit->param_types[i], decls[i].type, 15);

        /* Show browse button for file type */
        if (strcmp(decls[i].type, "file") == 0 && g_edit->hParamBrowse[i]) {
            ShowWindow(g_edit->hParamBrowse[i], SW_SHOW);
        }

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

    /* URL mode needs minimum height for TreeView; ensure window is tall enough first */
    if (is_url) {
        RECT wr; GetWindowRect(g_edit->hDlg, &wr);
        int cur_h = wr.bottom - wr.top;
        if (cur_h < 800) {
            SetWindowPos(g_edit->hDlg, NULL, 0, 0, wr.right - wr.left, 800,
                SWP_NOMOVE | SWP_NOZORDER);
        }
    }

    RECT dlg_rc;
    GetClientRect(g_edit->hDlg, &dlg_rc);
    int cw = dlg_rc.right;
    int margin = 10;
    int w = cw - 2 * margin;

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

    for (int i = 0; i < CFG_MAX_PARAMS; i++) {
        int ps = (!is_url && i < g_edit->param_decl_count) ? SW_SHOW : SW_HIDE;
        ShowWindow(g_edit->hParamLabel[i], ps);
        ShowWindow(g_edit->hParamEdit[i], ps);
    }

    int y = margin;

    MoveWindow(g_edit->hTypeLabel, margin, y + 2, 40, 18, TRUE);
    MoveWindow(g_edit->hType, margin + 45, y, 120, 200, TRUE);
    MoveWindow(g_edit->hNameLabel, 190, y + 2, 40, 18, TRUE);
    MoveWindow(g_edit->hName, 235, y, cw - 235 - margin, 22, TRUE);
    y += 30;

    if (is_url) {
        MoveWindow(g_edit->hUrlLabel, margin, y + 2, 50, 18, TRUE);
        MoveWindow(g_edit->hUrl, 65, y, w - 120, 22, TRUE);
        MoveWindow(g_edit->hLoadBtn, cw - margin - 60, y, 60, 22, TRUE);
        y += 28;

        MoveWindow(g_edit->hHeadersLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hHeaders, 65, y, w - 55, 48, TRUE);
        y += 56;

        MoveWindow(g_edit->hIntLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hInt, 65, y, 80, 22, TRUE);
        y += 30;

        MoveWindow(g_edit->hRespLabel, margin, y, 350, 18, TRUE);
        y += 20;

        int bottom_reserve = 270;
        int tree_h = dlg_rc.bottom - y - bottom_reserve;
        if (tree_h < 80) tree_h = 80;
        MoveWindow(g_edit->hTree, margin, y, w, tree_h, TRUE);
        y += tree_h + 8;

        MoveWindow(g_edit->hTemplateLabel, margin, y, 60, 18, TRUE);
        y += 20;
        MoveWindow(g_edit->hExpr, margin, y, w, 60, TRUE);
        y += 68;

        MoveWindow(g_edit->hPreviewLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hPreview, 65, y, w - 55, 22, TRUE);
        y += 30;

        MoveWindow(g_edit->hClickCheck, margin, y, 200, 20, TRUE);
        y += 24;

        MoveWindow(g_edit->hClickUrlLabel, margin, y + 2, 70, 18, TRUE);
        MoveWindow(g_edit->hClickUrl, 80, y, w - 70, 22, TRUE);
        y += 30;
    } else {
        MoveWindow(g_edit->hLuaLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hLuaPath, 70, y, w - 100, 22, TRUE);
        MoveWindow(g_edit->hBrowseBtn, cw - margin - 30, y, 30, 22, TRUE);
        y += 30;

        MoveWindow(g_edit->hIntLabel, margin, y + 2, 55, 18, TRUE);
        MoveWindow(g_edit->hInt, 70, y, 80, 22, TRUE);
        y += 30;

        for (int i = 0; i < g_edit->param_decl_count; i++) {
            MoveWindow(g_edit->hParamLabel[i], margin, y + 2, 100, 18, TRUE);
            MoveWindow(g_edit->hParamEdit[i], 115, y, w - 105, 22, TRUE);
            y += 28;
        }
        y += 10;
    }

    /* Bar config row (both modes) */
    MoveWindow(g_edit->hBarWidthLabel, margin, y + 2, 40, 18, TRUE);
    MoveWindow(g_edit->hBarWidth, margin + 42, y, 50, 22, TRUE);
    MoveWindow(g_edit->hBarXLabel, margin + 105, y + 2, 15, 18, TRUE);
    MoveWindow(g_edit->hBarX, margin + 122, y, 50, 22, TRUE);
    MoveWindow(g_edit->hBarYLabel, margin + 185, y + 2, 15, 18, TRUE);
    MoveWindow(g_edit->hBarY, margin + 202, y, 50, 22, TRUE);
    MoveWindow(g_edit->hBarBgLabel, margin + 265, y + 2, 25, 18, TRUE);
    MoveWindow(g_edit->hBarBg, margin + 292, y, 70, 22, TRUE);
    y += 30;

    HWND hOk = GetDlgItem(g_edit->hDlg, IDB_OK);
    HWND hCancel = GetDlgItem(g_edit->hDlg, IDB_CANCEL);
    if (hOk) MoveWindow(hOk, cw / 2 - 85, y, 80, 28, TRUE);
    if (hCancel) MoveWindow(hCancel, cw / 2 + 5, y, 80, 28, TRUE);
    y += 40;

    RECT wr; GetWindowRect(g_edit->hDlg, &wr);
    int frame_h = (wr.bottom - wr.top) - dlg_rc.bottom;
    int target_h = y + frame_h;
    if (is_url && target_h < 800) target_h = 800;
    SetWindowPos(g_edit->hDlg, NULL, 0, 0, wr.right - wr.left, target_h,
        SWP_NOMOVE | SWP_NOZORDER);

    ShowWindow(g_edit->hIntLabel, SW_SHOW);
    ShowWindow(g_edit->hInt, SW_SHOW);

    InvalidateRect(g_edit->hDlg, NULL, TRUE);
}

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
        /* File browse buttons for @param file type */
        if (id >= 8000 && id < 8000 + CFG_MAX_PARAMS && code == BN_CLICKED) {
            int pi = id - 8000;
            if (strcmp(g_edit->param_types[pi], "file") == 0) {
                WCHAR file[MAX_PATH] = {0};
                OPENFILENAMEW ofn = {0};
                ofn.lStructSize = sizeof(ofn);
                ofn.hwndOwner = hwnd;
                ofn.lpstrFilter = L"All Files\0*.*\0Text Files (*.txt)\0*.txt\0";
                ofn.lpstrFile = file;
                ofn.nMaxFile = MAX_PATH;
                ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
                if (GetOpenFileNameW(&ofn)) {
                    SetWindowTextW(g_edit->hParamEdit[pi], file);
                }
            }
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
        char *path_copy = _strdup(child_path);
        tvis.item.lParam = (LPARAM)path_copy;

        HTREEITEM hItem = TreeView_InsertItem(hTree, &tvis);

        if (c->type == JSON_OBJECT || c->type == JSON_ARRAY) {
            tree_add_json(hTree, hItem, c, child_path, (int)strlen(child_path));
        }
    }
}

static void edit_load_response(EditDlgState *st) {
    WCHAR url[CFG_MAX_URL];
    GetWindowTextW(st->hUrl, url, CFG_MAX_URL);

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

    if (st->json_root) { json_free(st->json_root); st->json_root = NULL; }
    st->json_root = json_parse(st->cached_response);

    TreeView_DeleteAllItems(st->hTree);
    if (st->json_root) {
        tree_add_json(st->hTree, TVI_ROOT, st->json_root, "$", 1);
    } else {
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
            extract_fields(st->cached_response, expr, preview, FETCH_BUF_SIZE);
        }
    } else {
        MultiByteToWideChar(CP_UTF8, 0, st->cached_response, -1, preview, FETCH_BUF_SIZE);
    }
    SetWindowTextW(st->hPreview, preview);
}

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

void show_edit_dialog(HWND parent, int item_idx) {
    EditDlgState *st = (EditDlgState *)calloc(1, sizeof(EditDlgState));
    if (!st) return;
    st->item_index = item_idx;
    g_edit = st;

    const WCHAR *title = (item_idx >= 0) ? L"Edit Item" : L"Add Item";
    st->hDlg = CreateWindowExW(WS_EX_DLGMODALFRAME | WS_EX_TOPMOST,
        L"#32770", title,
        WS_VISIBLE | WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME,
        150, 80, 640, 800, parent, NULL, g_hinst, NULL);
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

    for (int pi = 0; pi < CFG_MAX_PARAMS; pi++) {
        int py = y + 28 + pi * 26;
        st->hParamLabel[pi] = CreateWindowExW(0, L"STATIC", L"",
            WS_CHILD, 10, py + 2, 100, 18, st->hDlg, NULL, g_hinst, NULL);
        st->hParamEdit[pi] = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | ES_AUTOHSCROLL, 115, py, 455, 22, st->hDlg, NULL, g_hinst, NULL);
        st->hParamBrowse[pi] = CreateWindowExW(0, L"BUTTON", L"...",
            WS_CHILD, 575, py, 35, 22, st->hDlg, (HMENU)(INT_PTR)(8000 + pi), g_hinst, NULL);
        SendMessageW(st->hParamLabel[pi], WM_SETFONT, (WPARAM)g_font, TRUE);
        SendMessageW(st->hParamEdit[pi], WM_SETFONT, (WPARAM)g_font, TRUE);
        SendMessageW(st->hParamBrowse[pi], WM_SETFONT, (WPARAM)g_font, TRUE);
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
    st->hBarWidthLabel = CreateWindowExW(0, L"STATIC", L"Bar W:", WS_CHILD | WS_VISIBLE,
        10, y + 2, 40, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarWidth = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"0",
        WS_CHILD | WS_VISIBLE | ES_NUMBER, 52, y, 50, 22, st->hDlg, NULL, g_hinst, NULL);
    st->hBarXLabel = CreateWindowExW(0, L"STATIC", L"X:", WS_CHILD | WS_VISIBLE,
        115, y + 2, 15, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarX = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"-1",
        WS_CHILD | WS_VISIBLE, 132, y, 50, 22, st->hDlg, NULL, g_hinst, NULL);
    st->hBarYLabel = CreateWindowExW(0, L"STATIC", L"Y:", WS_CHILD | WS_VISIBLE,
        195, y + 2, 15, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarY = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"-1",
        WS_CHILD | WS_VISIBLE, 212, y, 50, 22, st->hDlg, NULL, g_hinst, NULL);
    st->hBarBgLabel = CreateWindowExW(0, L"STATIC", L"BG:", WS_CHILD | WS_VISIBLE,
        275, y + 2, 25, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarBg = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"FFFFFFFF",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 302, y, 70, 22, st->hDlg, NULL, g_hinst, NULL);
    SendMessageW(st->hBarWidth, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hBarX, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hBarY, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hBarBg, WM_SETFONT, (WPARAM)g_font, TRUE);

    y += 30;
    CreateWindowExW(0, L"BUTTON", L"OK",
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        230, y, 80, 28, st->hDlg, (HMENU)IDB_OK, g_hinst, NULL);
    CreateWindowExW(0, L"BUTTON", L"Cancel",
        WS_CHILD | WS_VISIBLE,
        320, y, 80, 28, st->hDlg, (HMENU)IDB_CANCEL, g_hinst, NULL);

    SendMessageW(st->hName, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hUrl, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hInt, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hExpr, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hTree, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hPreview, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hClickCheck, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hClickUrl, WM_SETFONT, (WPARAM)g_font, TRUE);

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
        /* Bar config fields */
        WCHAR bw[16];
        wsprintfW(bw, L"%d", it->bar_width);
        SetWindowTextW(st->hBarWidth, bw);
        wsprintfW(bw, L"%d", it->bar_x);
        SetWindowTextW(st->hBarX, bw);
        wsprintfW(bw, L"%d", it->bar_y);
        SetWindowTextW(st->hBarY, bw);
        wsprintfW(bw, L"%08X", (unsigned int)it->bar_bg_color);
        SetWindowTextW(st->hBarBg, bw);
    }

    edit_relayout();

    EnableWindow(parent, FALSE);

    g_orig_dlg_proc = (WNDPROC)SetWindowLongPtrW(st->hDlg, GWLP_WNDPROC, (LONG_PTR)edit_dlg_proc);
    g_edit_done = FALSE;
    g_edit_accepted = FALSE;

    MSG msg;
    while (!g_edit_done && GetMessageW(&msg, NULL, 0, 0)) {
        if (!IsDialogMessageW(st->hDlg, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

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
            /* Apply @refresh if declared in script */
            int refresh_ms = script_parse_refresh(it->lua_path);
            if (refresh_ms > 0) {
                if (refresh_ms < 1000) refresh_ms = 1000;
                it->interval_ms = (DWORD)refresh_ms;
            }
            /* Save bar config */
            WCHAR bv[32];
            GetWindowTextW(st->hBarWidth, bv, 32);
            it->bar_width = _wtoi(bv);
            GetWindowTextW(st->hBarX, bv, 32);
            it->bar_x = _wtoi(bv);
            GetWindowTextW(st->hBarY, bv, 32);
            it->bar_y = _wtoi(bv);
            GetWindowTextW(st->hBarBg, bv, 32);
            it->bar_bg_color = (COLORREF)wcstoul(bv, NULL, 16);

            config_save(&g_cfg);
            listview_populate();
            /* Recreate bars if this item is pinned */
            if (it->pinned) {
                bars_destroy_all();
                bars_create_all();
            }
        }
    }

    EnableWindow(parent, TRUE);
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