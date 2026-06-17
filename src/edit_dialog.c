#include "ui.h"
#include "layout.h"

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
    cJSON *json_root;
} EditDlgState;

static EditDlgState *g_edit = NULL;
static BOOL g_edit_done = FALSE;
static BOOL g_edit_accepted = FALSE;
static BOOL g_in_relayout = FALSE;
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
    if (g_in_relayout) return;
    g_in_relayout = TRUE;
    int sel = (int)SendMessageW(g_edit->hType, CB_GETCURSEL, 0, 0);
    BOOL is_url = (sel == ITEM_TYPE_URL);


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

    RECT dlg_rc;
    GetClientRect(g_edit->hDlg, &dlg_rc);

    /* Set font on labels for ui_auto measurement */
    HWND labels[] = { g_edit->hTypeLabel, g_edit->hNameLabel, g_edit->hUrlLabel,
        g_edit->hHeadersLabel, g_edit->hIntLabel, g_edit->hRespLabel,
        g_edit->hTemplateLabel, g_edit->hPreviewLabel, g_edit->hClickUrlLabel,
        g_edit->hLuaLabel, g_edit->hBarWidthLabel, g_edit->hBarXLabel,
        g_edit->hBarYLabel, g_edit->hBarBgLabel };
    for (int i = 0; i < (int)(sizeof(labels)/sizeof(labels[0])); i++)
        SendMessageW(labels[i], WM_SETFONT, (WPARAM)g_font, TRUE);

    ui_begin(g_edit->hDlg, g_font, 10, 6);

    /* Row 1: Type + Name */
    ui_row(5);
    ui_auto(g_edit->hTypeLabel, 22);
    ui_add(g_edit->hType, 120, 22);
    ui_auto(g_edit->hNameLabel, 22);
    ui_add(g_edit->hName, UI_FILL, 22);
    ui_end_row();

    if (is_url) {
        /* URL + Load */
        ui_row(5);
        ui_auto(g_edit->hUrlLabel, 22);
        ui_add(g_edit->hUrl, UI_FILL, 22);
        ui_add(g_edit->hLoadBtn, 60, 22);
        ui_end_row();

        /* Headers */
        ui_row(5);
        ui_auto(g_edit->hHeadersLabel, 48);
        ui_add(g_edit->hHeaders, UI_FILL, 48);
        ui_end_row();

        /* Interval */
        ui_row(5);
        ui_auto(g_edit->hIntLabel, 22);
        ui_add(g_edit->hInt, 80, 22);
        ui_end_row();

        /* Response structure label */
        ui_row(0);
        ui_add(g_edit->hRespLabel, 0, 18);
        ui_end_row();

        /* TreeView - fill remaining space */
        int bottom_reserve = 250;
        int tree_h = dlg_rc.bottom - ui_top()->y - bottom_reserve;
        if (tree_h < 80) tree_h = 80;
        ui_row(0);
        ui_add(g_edit->hTree, 0, tree_h);
        ui_end_row();

        /* Template label + expr */
        ui_row(0);
        ui_add(g_edit->hTemplateLabel, 0, 18);
        ui_end_row();
        ui_row(0);
        ui_add(g_edit->hExpr, 0, 60);
        ui_end_row();

        /* Preview */
        ui_row(5);
        ui_auto(g_edit->hPreviewLabel, 22);
        ui_add(g_edit->hPreview, UI_FILL, 22);
        ui_end_row();

        /* Click checkbox + URL */
        ui_row(0);
        ui_add(g_edit->hClickCheck, 0, 22);
        ui_end_row();
        ui_row(5);
        ui_auto(g_edit->hClickUrlLabel, 22);
        ui_add(g_edit->hClickUrl, UI_FILL, 22);
        ui_end_row();
    } else {
        /* Lua path + Browse */
        ui_row(5);
        ui_auto(g_edit->hLuaLabel, 22);
        ui_add(g_edit->hLuaPath, UI_FILL, 22);
        ui_add(g_edit->hBrowseBtn, 30, 22);
        ui_end_row();

        /* Interval */
        ui_row(5);
        ui_auto(g_edit->hIntLabel, 22);
        ui_add(g_edit->hInt, 80, 22);
        ui_end_row();

        /* Params */
        for (int i = 0; i < g_edit->param_decl_count; i++) {
            ui_row(5);
            ui_add(g_edit->hParamLabel[i], 100, 22);
            ui_add(g_edit->hParamEdit[i], UI_FILL, 22);
            if (strcmp(g_edit->param_types[i], "file") == 0 && g_edit->hParamBrowse[i]) {
                ui_add(g_edit->hParamBrowse[i], 30, 22);
            }
            ui_end_row();
        }
    }

    /* Bar config row */
    ui_row(5);
    ui_add(g_edit->hBarWidthLabel, 40, 22);
    ui_add(g_edit->hBarWidth, 50, 22);
    ui_add(g_edit->hBarXLabel, 15, 22);
    ui_add(g_edit->hBarX, 50, 22);
    ui_add(g_edit->hBarYLabel, 15, 22);
    ui_add(g_edit->hBarY, 50, 22);
    ui_add(g_edit->hBarBgLabel, 25, 22);
    ui_add(g_edit->hBarBg, 70, 22);
    ui_end_row();

    /* OK / Cancel buttons */
    HWND hOk = GetDlgItem(g_edit->hDlg, IDB_OK);
    HWND hCancel = GetDlgItem(g_edit->hDlg, IDB_CANCEL);
    ui_row(10);
    ui_add(hOk, 80, 28);
    ui_add(hCancel, 80, 28);
    ui_end_row();

    /* Resize window to fit content */
    int content_h = ui_top()->y + 10;

    ui_end();

    RECT wr; GetWindowRect(g_edit->hDlg, &wr);
    int frame_h = (wr.bottom - wr.top) - dlg_rc.bottom;
    int target_h = content_h + frame_h;
    if (is_url && target_h < 800) target_h = 800;
    if ((wr.bottom - wr.top) != target_h) {
        SetWindowPos(g_edit->hDlg, NULL, 0, 0, wr.right - wr.left, target_h,
            SWP_NOMOVE | SWP_NOZORDER | SWP_NOREDRAW);
    }

    ShowWindow(g_edit->hIntLabel, SW_SHOW);
    ShowWindow(g_edit->hInt, SW_SHOW);

    InvalidateRect(g_edit->hDlg, NULL, TRUE);
    g_in_relayout = FALSE;
}

static int g_dlg_proc_depth = 0;

static LRESULT CALLBACK edit_dlg_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (g_dlg_proc_depth > 2)
        return DefWindowProcW(hwnd, msg, wp, lp);
    g_dlg_proc_depth++;

    LRESULT result = 0;
    switch (msg) {
    case WM_COMMAND: {
        WORD id = LOWORD(wp);
        WORD code = HIWORD(wp);
        if (id == 5050 && code == CBN_SELCHANGE) {
            edit_relayout();
            result = 0; goto done;
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
            result = 0; goto done;
        }
        if (id == IDB_LOAD && code == BN_CLICKED) {
            edit_load_response(g_edit);
            result = 0; goto done;
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
            result = 0; goto done;
        }
        if (id == IDE_EXPR && code == EN_CHANGE) {
            edit_update_preview(g_edit);
            result = 0; goto done;
        }
        if (id == IDB_OK && code == BN_CLICKED) {
            g_edit_accepted = TRUE;
            g_edit_done = TRUE;
            result = 0; goto done;
        }
        if (id == IDB_CANCEL && code == BN_CLICKED) {
            g_edit_done = TRUE;
            result = 0; goto done;
        }
        break;
    }
    case WM_NOTIFY: {
        NMHDR *nm = (NMHDR *)lp;
        if (g_edit && nm->hwndFrom == g_edit->hTree && nm->code == TVN_SELCHANGEDW) {
            static BOOL in_sel_change = FALSE;
            if (in_sel_change) { result = 0; goto done; }
            in_sel_change = TRUE;
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
            in_sel_change = FALSE;
            result = 0; goto done;
        }
        break;
    }
    case WM_SIZE: {
        if (!g_in_relayout)
            edit_relayout();
        result = 0;
        goto done;
    }
    case WM_CLOSE:
        g_edit_done = TRUE;
        result = 0;
        goto done;
    }
    result = CallWindowProcW(g_orig_dlg_proc, hwnd, msg, wp, lp);
done:
    g_dlg_proc_depth--;
    return result;
}

static void cjson_node_to_string(cJSON *node, char *buf, int buf_size) {
    if (!node || buf_size <= 0) { buf[0] = '\0'; return; }
    if (cJSON_IsString(node)) {
        snprintf(buf, buf_size, "\"%s\"", node->valuestring ? node->valuestring : "");
    } else if (cJSON_IsNumber(node)) {
        if (node->valuedouble == (double)(int)node->valuedouble)
            snprintf(buf, buf_size, "%d", node->valueint);
        else
            snprintf(buf, buf_size, "%g", node->valuedouble);
    } else if (cJSON_IsBool(node)) {
        snprintf(buf, buf_size, "%s", cJSON_IsTrue(node) ? "true" : "false");
    } else if (cJSON_IsNull(node)) {
        snprintf(buf, buf_size, "null");
    } else if (cJSON_IsObject(node)) {
        snprintf(buf, buf_size, "{...}");
    } else if (cJSON_IsArray(node)) {
        snprintf(buf, buf_size, "[...]");
    } else {
        buf[0] = '\0';
    }
}

static void tree_add_json(HWND hTree, HTREEITEM parent, cJSON *node, char *path_buf, int path_len) {
    (void)path_len;
    if (!node) return;
    if (!cJSON_IsObject(node) && !cJSON_IsArray(node)) return;

    int idx = 0;
    cJSON *c = NULL;
    cJSON_ArrayForEach(c, node) {
        char label[256];
        char child_path[512];

        if (cJSON_IsObject(node) && c->string) {
            snprintf(child_path, 512, "%s.%s", path_buf, c->string);
            char val_str[128];
            cjson_node_to_string(c, val_str, 128);
            snprintf(label, 256, "%s: %s", c->string, val_str);
        } else {
            snprintf(child_path, 512, "%s[%d]", path_buf, idx);
            char val_str[128];
            cjson_node_to_string(c, val_str, 128);
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

        if (cJSON_IsObject(c) || cJSON_IsArray(c)) {
            tree_add_json(hTree, hItem, c, child_path, (int)strlen(child_path));
        }
        idx++;
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

    if (st->json_root) { cJSON_Delete(st->json_root); st->json_root = NULL; }
    st->json_root = cJSON_Parse(st->cached_response);

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

    edit_update_preview(st);
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
        ScriptResult *sr = (ScriptResult *)HeapAlloc(
            GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(ScriptResult));
        if (sr) {
            BOOL handled = FALSE;
            /* Try DeepSeek-style: substitute $.path with JSON values, then run Lua */
            if (strstr(lua_code, "$.")) {
                WCHAR substituted[FETCH_BUF_SIZE];
                extract_fields(st->cached_response, expr, substituted, FETCH_BUF_SIZE);
                char sub8[CFG_MAX_EXPR * 3];
                WideCharToMultiByte(CP_UTF8, 0, substituted, -1, sub8, sizeof(sub8), NULL, NULL);
                if (script_exec(sub8, st->cached_response, sr)) {
                    lstrcpynW(preview, sr->display, FETCH_BUF_SIZE);
                    handled = TRUE;
                }
            }
            if (!handled) {
                if (script_exec(lua_code, st->cached_response, sr)) {
                    lstrcpynW(preview, sr->display, FETCH_BUF_SIZE);
                } else {
                    extract_fields(st->cached_response, expr, preview, FETCH_BUF_SIZE);
                }
            }
            HeapFree(GetProcessHeap(), 0, sr);
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

    const WCHAR *title = (item_idx >= 0) ? tr("edit.title_edit") : tr("edit.title_add");
    st->hDlg = CreateWindowExW(WS_EX_DLGMODALFRAME | WS_EX_TOPMOST,
        L"#32770", title,
        WS_VISIBLE | WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME,
        150, 80, 640, 800, parent, NULL, g_hinst, NULL);
    if (!st->hDlg) { free(st); g_edit = NULL; return; }

    int y = 10;
    st->hTypeLabel = CreateWindowExW(0, L"STATIC", tr("edit.type"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        10, y + 2, 40, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hType = CreateWindowExW(0, L"COMBOBOX", L"",
        WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
        55, y, 120, 100, st->hDlg, (HMENU)5050, g_hinst, NULL);
    SendMessageW(st->hType, CB_ADDSTRING, 0, (LPARAM)tr("edit.type_url"));
    SendMessageW(st->hType, CB_ADDSTRING, 0, (LPARAM)tr("edit.type_lua"));
    SendMessageW(st->hType, CB_SETCURSEL, 0, 0);
    SendMessageW(st->hType, WM_SETFONT, (WPARAM)g_font, TRUE);

    st->hNameLabel = CreateWindowExW(0, L"STATIC", tr("edit.name"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        200, y + 2, 40, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hName = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        245, y, 365, 22, st->hDlg, (HMENU)IDE_NAME, g_hinst, NULL);

    y += 30;
    st->hUrlLabel = CreateWindowExW(0, L"STATIC", tr("edit.url"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        10, y + 2, 50, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hUrl = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"http://localhost:8080/status",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        70, y, 440, 22, st->hDlg, (HMENU)IDE_URL, g_hinst, NULL);
    st->hLoadBtn = CreateWindowExW(0, L"BUTTON", tr("edit.load"),
        WS_CHILD | WS_VISIBLE, 520, y, 60, 22, st->hDlg, (HMENU)IDB_LOAD, g_hinst, NULL);

    y += 28;
    st->hHeadersLabel = CreateWindowExW(0, L"STATIC", tr("edit.headers"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        10, y + 2, 55, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hHeaders = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL,
        70, y, 540, 48, st->hDlg, NULL, g_hinst, NULL);
    SendMessageW(st->hHeaders, WM_SETFONT, (WPARAM)g_font, TRUE);

    st->hLuaLabel = CreateWindowExW(0, L"STATIC", tr("edit.lua_file"), WS_CHILD | SS_LEFTNOWORDWRAP,
        10, y + 2, 60, 20, st->hDlg, NULL, g_hinst, NULL);
    st->hLuaPath = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | ES_AUTOHSCROLL,
        75, y, 470, 22, st->hDlg, (HMENU)5051, g_hinst, NULL);
    SendMessageW(st->hLuaPath, WM_SETFONT, (WPARAM)g_font, TRUE);
    st->hBrowseBtn = CreateWindowExW(0, L"BUTTON", L"...",
        WS_CHILD, 550, y, 30, 22, st->hDlg, (HMENU)5052, g_hinst, NULL);

    y += 56;
    st->hIntLabel = CreateWindowExW(0, L"STATIC", tr("edit.interval"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
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
    st->hRespLabel = CreateWindowExW(0, L"STATIC", tr("edit.response_structure"),
        WS_CHILD | WS_VISIBLE, 10, y, 350, 18, st->hDlg, NULL, g_hinst, NULL);

    y += 20;
    st->hTree = CreateWindowExW(WS_EX_CLIENTEDGE, WC_TREEVIEWW, L"",
        WS_CHILD | WS_VISIBLE | TVS_HASLINES | TVS_HASBUTTONS | TVS_LINESATROOT | TVS_SHOWSELALWAYS,
        10, y, 600, 180, st->hDlg, (HMENU)IDC_TREE, g_hinst, NULL);

    y += 188;
    st->hTemplateLabel = CreateWindowExW(0, L"STATIC", tr("edit.template"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        10, y, 60, 18, st->hDlg, NULL, g_hinst, NULL);

    y += 20;
    st->hExpr = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL,
        10, y, 600, 60, st->hDlg, (HMENU)IDE_EXPR, g_hinst, NULL);

    y += 68;
    st->hPreviewLabel = CreateWindowExW(0, L"STATIC", tr("edit.preview"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        10, y + 2, 55, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hPreview = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY,
        70, y, 540, 22, st->hDlg, (HMENU)IDC_PREVIEW, g_hinst, NULL);

    y += 30;
    st->hClickCheck = CreateWindowExW(0, L"BUTTON", tr("edit.enable_click_url"),
        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
        10, y, 200, 20, st->hDlg, NULL, g_hinst, NULL);

    y += 24;
    st->hClickUrlLabel = CreateWindowExW(0, L"STATIC", tr("edit.click_url"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        10, y + 2, 70, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hClickUrl = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        85, y, 525, 22, st->hDlg, NULL, g_hinst, NULL);

    y += 30;
    st->hBarWidthLabel = CreateWindowExW(0, L"STATIC", tr("edit.bar_w"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        10, y + 2, 40, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarWidth = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"0",
        WS_CHILD | WS_VISIBLE | ES_NUMBER, 52, y, 50, 22, st->hDlg, NULL, g_hinst, NULL);
    st->hBarXLabel = CreateWindowExW(0, L"STATIC", tr("edit.bar_x"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        115, y + 2, 15, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarX = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"-1",
        WS_CHILD | WS_VISIBLE, 132, y, 50, 22, st->hDlg, NULL, g_hinst, NULL);
    st->hBarYLabel = CreateWindowExW(0, L"STATIC", tr("edit.bar_y"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        195, y + 2, 15, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarY = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"-1",
        WS_CHILD | WS_VISIBLE, 212, y, 50, 22, st->hDlg, NULL, g_hinst, NULL);
    st->hBarBgLabel = CreateWindowExW(0, L"STATIC", tr("edit.bar_bg"), WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        275, y + 2, 25, 18, st->hDlg, NULL, g_hinst, NULL);
    st->hBarBg = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"FFFFFFFF",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 302, y, 70, 22, st->hDlg, NULL, g_hinst, NULL);
    SendMessageW(st->hBarWidth, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hBarX, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hBarY, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(st->hBarBg, WM_SETFONT, (WPARAM)g_font, TRUE);

    y += 30;
    CreateWindowExW(0, L"BUTTON", tr("edit.ok"),
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        230, y, 80, 28, st->hDlg, (HMENU)IDB_OK, g_hinst, NULL);
    CreateWindowExW(0, L"BUTTON", tr("edit.cancel"),
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
                if (!it->realtime && refresh_ms < 1000) refresh_ms = 1000;
                it->interval_ms = (DWORD)refresh_ms;
            }
            it->realtime = script_parse_realtime(it->lua_path);
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
    if (st->json_root) cJSON_Delete(st->json_root);
    DestroyWindow(st->hDlg);
    free(st);
    g_edit = NULL;
    g_orig_dlg_proc = NULL;
    SetForegroundWindow(parent);
}