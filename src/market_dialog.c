#include "ui.h"
#include "httputil.h"
#include <shlwapi.h>

#define MKT_ID_LIST     6001
#define MKT_ID_COMBO    6002
#define MKT_ID_DOWNLOAD 6003
#define MKT_ID_REFRESH  6004
#define MKT_ID_ADDSRC   6005
#define MKT_ID_DELSRC   6006
#define MKT_ID_STATUS   6007

#define MKT_MAX_SCRIPTS 64

static BOOL s_is_china = FALSE;
static BOOL s_geo_checked = FALSE;

static void mkt_check_geo(void) {
    if (s_geo_checked) return;
    s_geo_checked = TRUE;
    char *resp = http_request_sync(L"https://api.ip.sb/geoip", L"GET", NULL, NULL, NULL, 0);
    if (!resp) return;
    JsonNode *root = json_parse(resp);
    if (root) {
        for (JsonNode *c = root->children; c; c = c->next) {
            if (c->key && strcmp(c->key, "country_code") == 0 &&
                c->str_val && strcmp(c->str_val, "CN") == 0) {
                s_is_china = TRUE;
                break;
            }
        }
        json_free(root);
    }
    free(resp);
}

static void mkt_build_raw_url(WCHAR *out, int out_size, const WCHAR *repo, const char *file) {
    if (s_is_china)
        _snwprintf(out, out_size, L"https://gh-proxy.com/https://raw.githubusercontent.com/%s/master/%S", repo, file);
    else
        _snwprintf(out, out_size, L"https://raw.githubusercontent.com/%s/master/%S", repo, file);
}

typedef struct {
    char name[128];
    char file[256];
    char description[256];
    char author[64];
    char version[32];
} MarketScript;

typedef struct {
    HWND hDlg;
    HWND hCombo;
    HWND hList;
    HWND hStatus;
    MarketScript scripts[MKT_MAX_SCRIPTS];
    int script_count;
} MarketState;

static MarketState *s_mkt = NULL;
static BOOL s_mkt_done = FALSE;

static void mkt_set_status(const WCHAR *text) {
    if (s_mkt && s_mkt->hStatus)
        SetWindowTextW(s_mkt->hStatus, text);
}

static void mkt_populate_combo(void) {
    if (!s_mkt) return;
    SendMessageW(s_mkt->hCombo, CB_RESETCONTENT, 0, 0);
    for (int i = 0; i < g_cfg.source_count; i++) {
        SendMessageW(s_mkt->hCombo, CB_ADDSTRING, 0, (LPARAM)g_cfg.sources[i]);
    }
    if (g_cfg.source_count > 0)
        SendMessageW(s_mkt->hCombo, CB_SETCURSEL, 0, 0);
}

static void mkt_fetch_scripts(const WCHAR *repo) {
    s_mkt->script_count = 0;
    ListView_DeleteAllItems(s_mkt->hList);
    mkt_set_status(L"正在获取...");

    char repo8[256];
    WideCharToMultiByte(CP_UTF8, 0, repo, -1, repo8, 256, NULL, NULL);

    /* Try manifest.json first */
    WCHAR url[512];
    mkt_build_raw_url(url, 512, repo, "manifest.json");
    char *resp = http_request_sync(url, L"GET", NULL, NULL, NULL, 0);

    if (resp) {
        JsonNode *root = json_parse(resp);
        if (root) {
            JsonNode *scripts = NULL;
            for (JsonNode *c = root->children; c; c = c->next) {
                if (c->key && strcmp(c->key, "scripts") == 0 && c->type == JSON_ARRAY) {
                    scripts = c;
                    break;
                }
            }
            if (scripts) {
                for (JsonNode *s = scripts->children; s && s_mkt->script_count < MKT_MAX_SCRIPTS; s = s->next) {
                    MarketScript *ms = &s_mkt->scripts[s_mkt->script_count];
                    memset(ms, 0, sizeof(*ms));
                    for (JsonNode *f = s->children; f; f = f->next) {
                        if (!f->key || !f->str_val) continue;
                        if (strcmp(f->key, "name") == 0) strncpy(ms->name, f->str_val, 127);
                        else if (strcmp(f->key, "file") == 0) strncpy(ms->file, f->str_val, 255);
                        else if (strcmp(f->key, "description") == 0) strncpy(ms->description, f->str_val, 255);
                        else if (strcmp(f->key, "author") == 0) strncpy(ms->author, f->str_val, 63);
                        else if (strcmp(f->key, "version") == 0) strncpy(ms->version, f->str_val, 31);
                    }
                    if (ms->file[0]) s_mkt->script_count++;
                }
                json_free(root);
                free(resp);
                goto populate;
            }
            json_free(root);
        }
        free(resp);
    }

    /* Fallback: GitHub API */
    wsprintfW(url, L"https://api.github.com/repos/%s/contents/", repo);
    resp = http_request_sync(url, L"GET", NULL,
        L"User-Agent: TaskPin\r\nAccept: application/vnd.github.v3+json\r\n", NULL, 0);
    if (resp) {
        JsonNode *root = json_parse(resp);
        if (root && root->type == JSON_ARRAY) {
            for (JsonNode *item = root->children; item && s_mkt->script_count < MKT_MAX_SCRIPTS; item = item->next) {
                char *name = NULL;
                for (JsonNode *f = item->children; f; f = f->next) {
                    if (f->key && strcmp(f->key, "name") == 0 && f->str_val)
                        name = f->str_val;
                }
                if (!name) continue;
                int len = (int)strlen(name);
                if (len < 5 || strcmp(name + len - 4, ".lua") != 0) continue;

                MarketScript *ms = &s_mkt->scripts[s_mkt->script_count];
                memset(ms, 0, sizeof(*ms));
                strncpy(ms->name, name, 127);
                strncpy(ms->file, name, 255);
                strcpy(ms->author, repo8);
                s_mkt->script_count++;
            }
            json_free(root);
        }
        free(resp);
    }

populate:
    /* Fill ListView */
    for (int i = 0; i < s_mkt->script_count; i++) {
        MarketScript *ms = &s_mkt->scripts[i];
        WCHAR wname[128], wdesc[256], wauthor[64], wver[32];
        MultiByteToWideChar(CP_UTF8, 0, ms->name, -1, wname, 128);
        MultiByteToWideChar(CP_UTF8, 0, ms->description, -1, wdesc, 256);
        MultiByteToWideChar(CP_UTF8, 0, ms->author, -1, wauthor, 64);
        MultiByteToWideChar(CP_UTF8, 0, ms->version, -1, wver, 32);

        LVITEMW lvi = {0};
        lvi.mask = LVIF_TEXT;
        lvi.iItem = i;
        lvi.pszText = wname;
        ListView_InsertItem(s_mkt->hList, &lvi);
        ListView_SetItemText(s_mkt->hList, i, 1, wdesc);
        ListView_SetItemText(s_mkt->hList, i, 2, wauthor);
        ListView_SetItemText(s_mkt->hList, i, 3, wver);
    }

    WCHAR status[64];
    wsprintfW(status, L"共 %d 个脚本", s_mkt->script_count);
    mkt_set_status(status);
}

static void mkt_download_script(void) {
    int sel = ListView_GetNextItem(s_mkt->hList, -1, LVNI_SELECTED);
    if (sel < 0 || sel >= s_mkt->script_count) {
        MessageBoxW(s_mkt->hDlg, L"请先选择一个脚本", L"TaskPin", MB_OK);
        return;
    }

    int src_idx = (int)SendMessageW(s_mkt->hCombo, CB_GETCURSEL, 0, 0);
    WCHAR repo[CFG_MAX_NAME] = {0};
    if (src_idx >= 0 && src_idx < g_cfg.source_count)
        lstrcpynW(repo, g_cfg.sources[src_idx], CFG_MAX_NAME);
    else
        GetWindowTextW(s_mkt->hCombo, repo, CFG_MAX_NAME);
    if (!repo[0]) return;

    MarketScript *ms = &s_mkt->scripts[sel];

    WCHAR url[512];
    mkt_build_raw_url(url, 512, repo, ms->file);

    mkt_set_status(L"正在下载...");
    char *content = http_request_sync(url, L"GET", NULL, NULL, NULL, 0);
    if (!content) {
        mkt_set_status(L"下载失败");
        return;
    }

    /* Save to scripts/ directory next to exe */
    WCHAR dir[MAX_PATH];
    GetModuleFileNameW(NULL, dir, MAX_PATH);
    WCHAR *slash = wcsrchr(dir, L'\\');
    if (slash) *(slash + 1) = L'\0';
    lstrcatW(dir, L"scripts");
    CreateDirectoryW(dir, NULL);

    WCHAR filepath[MAX_PATH];
    wsprintfW(filepath, L"%s\\%S", dir, ms->file);

    FILE *f = _wfopen(filepath, L"wb");
    if (f) {
        fwrite(content, 1, strlen(content), f);
        fclose(f);

        /* Auto-add to config and pin */
        if (g_cfg.count < CFG_MAX_ITEMS) {
            PinItem *it = &g_cfg.items[g_cfg.count];
            memset(it, 0, sizeof(*it));
            it->type = ITEM_TYPE_LUA;
            lstrcpynW(it->lua_path, filepath, CFG_MAX_PATH);
            /* Use @name or first-line description as display name */
            WCHAR parsed_name[CFG_MAX_NAME] = {0};
            script_parse_name(filepath, parsed_name, CFG_MAX_NAME);
            if (parsed_name[0]) {
                lstrcpynW(it->name, parsed_name, CFG_MAX_NAME);
            } else {
                WCHAR wname[CFG_MAX_NAME];
                MultiByteToWideChar(CP_UTF8, 0, ms->name[0] ? ms->name : ms->file, -1, wname, CFG_MAX_NAME);
                lstrcpynW(it->name, wname, CFG_MAX_NAME);
            }
            int refresh = script_parse_refresh(filepath);
            it->interval_ms = refresh > 0 ? (DWORD)refresh : 5000;
            int bw = script_parse_bar_width(filepath);
            if (bw > 0) it->bar_width = bw;
            it->bar_x = -1;
            it->bar_y = -1;
            it->bar_bg_color = 0xFFFFFFFF;
            it->pinned = TRUE;
            g_cfg.count++;
            config_save(&g_cfg);
            bars_destroy_all();
            bars_create_all();
            listview_populate();
        }
        mkt_set_status(L"下载并添加成功!");
    } else {
        mkt_set_status(L"保存失败");
    }
    free(content);
}

static LRESULT CALLBACK mkt_dlg_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case MKT_ID_REFRESH: {
            int idx = (int)SendMessageW(s_mkt->hCombo, CB_GETCURSEL, 0, 0);
            if (idx >= 0 && idx < g_cfg.source_count) {
                mkt_fetch_scripts(g_cfg.sources[idx]);
            } else {
                WCHAR text[CFG_MAX_NAME] = {0};
                GetWindowTextW(s_mkt->hCombo, text, CFG_MAX_NAME);
                if (text[0]) mkt_fetch_scripts(text);
            }
            break;
        }
        case MKT_ID_DOWNLOAD:
            mkt_download_script();
            break;
        case MKT_ID_ADDSRC: {
            WCHAR input[CFG_MAX_NAME] = {0};
            /* Simple input via edit control text - prompt user */
            if (g_cfg.source_count >= CFG_MAX_SOURCES) {
                MessageBoxW(hwnd, L"最多支持 8 个源", L"TaskPin", MB_OK);
                break;
            }
            /* Use a simple input box approach: get text from combo edit */
            GetWindowTextW(s_mkt->hCombo, input, CFG_MAX_NAME);
            if (input[0] == L'\0') {
                MessageBoxW(hwnd, L"请在下拉框中输入仓库地址\n格式: user/repo", L"TaskPin", MB_OK);
                break;
            }
            /* Check if already exists */
            BOOL exists = FALSE;
            for (int i = 0; i < g_cfg.source_count; i++) {
                if (lstrcmpiW(g_cfg.sources[i], input) == 0) { exists = TRUE; break; }
            }
            if (!exists) {
                lstrcpynW(g_cfg.sources[g_cfg.source_count], input, CFG_MAX_NAME);
                g_cfg.source_count++;
                config_save(&g_cfg);
                mkt_populate_combo();
                SendMessageW(s_mkt->hCombo, CB_SETCURSEL, g_cfg.source_count - 1, 0);
                mkt_fetch_scripts(input);
            }
            break;
        }
        case MKT_ID_DELSRC: {
            int idx = (int)SendMessageW(s_mkt->hCombo, CB_GETCURSEL, 0, 0);
            if (idx < 0 || idx >= g_cfg.source_count) break;
            for (int i = idx; i < g_cfg.source_count - 1; i++)
                lstrcpyW(g_cfg.sources[i], g_cfg.sources[i + 1]);
            g_cfg.source_count--;
            config_save(&g_cfg);
            mkt_populate_combo();
            ListView_DeleteAllItems(s_mkt->hList);
            s_mkt->script_count = 0;
            mkt_set_status(L"已删除源");
            break;
        }
        case IDCANCEL:
            s_mkt_done = TRUE;
            break;
        }
        return 0;

    case WM_NOTIFY: {
        NMHDR *nm = (NMHDR *)lp;
        if (nm->idFrom == MKT_ID_LIST && nm->code == NM_DBLCLK) {
            mkt_download_script();
        }
        return 0;
    }

    case WM_CLOSE:
        s_mkt_done = TRUE;
        return 0;

    default:
        return DefWindowProcW(hwnd, msg, wp, lp);
    }
}

void show_market_dialog(HWND parent) {
    MarketState mkt = {0};
    s_mkt = &mkt;
    s_mkt_done = FALSE;

    mkt_check_geo();

    HWND hwnd = CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_TOPMOST,
        L"#32770", L"Plugin Market",
        WS_VISIBLE | WS_POPUP | WS_CAPTION | WS_SYSMENU,
        200, 120, 580, 420,
        parent, NULL, g_hinst, NULL);
    mkt.hDlg = hwnd;

    SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)mkt_dlg_proc);

    /* Source combo (editable) */
    mkt.hCombo = CreateWindowExW(0, L"COMBOBOX", L"",
        WS_CHILD | WS_VISIBLE | CBS_DROPDOWN | CBS_AUTOHSCROLL,
        10, 10, 340, 200, hwnd, (HMENU)MKT_ID_COMBO, g_hinst, NULL);

    CreateWindowExW(0, L"BUTTON", L"Add",
        WS_CHILD | WS_VISIBLE, 358, 10, 50, 24, hwnd, (HMENU)MKT_ID_ADDSRC, g_hinst, NULL);
    CreateWindowExW(0, L"BUTTON", L"Del",
        WS_CHILD | WS_VISIBLE, 414, 10, 50, 24, hwnd, (HMENU)MKT_ID_DELSRC, g_hinst, NULL);
    CreateWindowExW(0, L"BUTTON", L"Refresh",
        WS_CHILD | WS_VISIBLE, 470, 10, 60, 24, hwnd, (HMENU)MKT_ID_REFRESH, g_hinst, NULL);

    /* Script list */
    mkt.hList = CreateWindowExW(WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
        10, 42, 545, 290, hwnd, (HMENU)MKT_ID_LIST, g_hinst, NULL);
    ListView_SetExtendedListViewStyle(mkt.hList, LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES);

    LVCOLUMNW col = {0};
    col.mask = LVCF_TEXT | LVCF_WIDTH;
    col.pszText = L"Name"; col.cx = 120;
    ListView_InsertColumn(mkt.hList, 0, &col);
    col.pszText = L"Description"; col.cx = 240;
    ListView_InsertColumn(mkt.hList, 1, &col);
    col.pszText = L"Author"; col.cx = 100;
    ListView_InsertColumn(mkt.hList, 2, &col);
    col.pszText = L"Version"; col.cx = 60;
    ListView_InsertColumn(mkt.hList, 3, &col);

    /* Bottom bar */
    CreateWindowExW(0, L"BUTTON", L"Download",
        WS_CHILD | WS_VISIBLE, 10, 340, 80, 28, hwnd, (HMENU)MKT_ID_DOWNLOAD, g_hinst, NULL);
    mkt.hStatus = CreateWindowExW(0, L"STATIC", L"选择源后点击 Refresh",
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        100, 346, 300, 20, hwnd, (HMENU)MKT_ID_STATUS, g_hinst, NULL);

    /* Apply font */
    SendMessageW(mkt.hCombo, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(mkt.hList, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(mkt.hStatus, WM_SETFONT, (WPARAM)g_font, TRUE);

    mkt_populate_combo();

    /* Auto-fetch if source exists */
    if (g_cfg.source_count > 0)
        mkt_fetch_scripts(g_cfg.sources[0]);

    /* Modal loop */
    EnableWindow(parent, FALSE);
    MSG msg;
    while (!s_mkt_done && GetMessageW(&msg, NULL, 0, 0)) {
        if (!IsDialogMessageW(hwnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    EnableWindow(parent, TRUE);
    SetForegroundWindow(parent);
    DestroyWindow(hwnd);
    s_mkt = NULL;
}

void import_script_from_url(const WCHAR *url) {
    mkt_check_geo();
    char *content = http_request_sync(url, L"GET", NULL, NULL, NULL, 0);
    if (!content) {
        MessageBoxW(NULL, L"Failed to download script", L"TaskPin", MB_OK | MB_ICONERROR);
        return;
    }

    /* Extract filename from URL */
    const WCHAR *slash = wcsrchr(url, L'/');
    WCHAR filename[256] = L"imported.lua";
    if (slash) lstrcpynW(filename, slash + 1, 256);

    /* Save to temp to parse metadata */
    WCHAR tmp_path[MAX_PATH];
    GetTempPathW(MAX_PATH, tmp_path);
    lstrcatW(tmp_path, filename);
    FILE *tf = _wfopen(tmp_path, L"wb");
    if (tf) { fwrite(content, 1, strlen(content), tf); fclose(tf); }

    /* Parse script info */
    WCHAR parsed_name[CFG_MAX_NAME] = {0};
    script_parse_name(tmp_path, parsed_name, CFG_MAX_NAME);
    char version[32] = {0};
    script_parse_version(tmp_path, version, sizeof(version));

    /* Build confirm message */
    WCHAR info[512];
    wsprintfW(info, L"Name: %s\nFile: %s\nVersion: %S",
        parsed_name[0] ? parsed_name : filename,
        filename,
        version[0] ? version : "unknown");

    enum { BTN_INSTALL = 100, BTN_VIEW = 101, BTN_CANCEL = 102 };
    TASKDIALOG_BUTTON buttons[] = {
        { BTN_INSTALL, L"Install" },
        { BTN_VIEW,    L"View Code" },
        { BTN_CANCEL,  L"Cancel" },
    };
    TASKDIALOGCONFIG tdc = {0};
    tdc.cbSize = sizeof(tdc);
    tdc.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION;
    tdc.pszWindowTitle = L"TaskPin";
    tdc.pszMainIcon = TD_INFORMATION_ICON;
    tdc.pszMainInstruction = L"Install this script?";
    tdc.pszContent = info;
    tdc.cButtons = 3;
    tdc.pButtons = buttons;
    tdc.nDefaultButton = BTN_INSTALL;

    int pressed = 0;
    for (;;) {
        pressed = 0;
        TaskDialogIndirect(&tdc, &pressed, NULL, NULL);
        if (pressed == BTN_VIEW) {
            WCHAR review_url[2048];
            if (s_is_china)
                wsprintfW(review_url, L"https://chatgpt.com/?q=帮我审查 %s 这个代码的安全性，重点检查是否存在：破坏计算机、盗取隐私信息、窃取私钥、盗取钱包等恶意行为", url);
            else
                wsprintfW(review_url, L"https://chatgpt.com/?q=Review this code for security risks: %s - Check for: system damage, data theft, private key stealing, wallet stealing, or other malicious behavior", url);
            ShellExecuteW(NULL, L"open", review_url, NULL, NULL, SW_SHOWNORMAL);
            continue;
        }
        break;
    }
    if (pressed != BTN_INSTALL) {
        DeleteFileW(tmp_path);
        free(content);
        return;
    }

    /* Move to scripts/ directory */
    WCHAR dir[MAX_PATH];
    GetModuleFileNameW(NULL, dir, MAX_PATH);
    WCHAR *ds = wcsrchr(dir, L'\\');
    if (ds) *(ds + 1) = L'\0';
    lstrcatW(dir, L"scripts");
    CreateDirectoryW(dir, NULL);

    WCHAR filepath[MAX_PATH];
    wsprintfW(filepath, L"%s\\%s", dir, filename);

    /* Check if file already exists */
    if (GetFileAttributesW(filepath) != INVALID_FILE_ATTRIBUTES) {
        WCHAR ow_msg[512];
        wsprintfW(ow_msg, L"Script \"%s\" already exists. Overwrite?", filename);
        int ow = MessageBoxW(NULL, ow_msg, L"TaskPin - Overwrite",
            MB_YESNO | MB_ICONWARNING);
        if (ow != IDYES) {
            DeleteFileW(tmp_path);
            free(content);
            return;
        }
    }

    MoveFileExW(tmp_path, filepath, MOVEFILE_REPLACE_EXISTING);

    if (g_cfg.count < CFG_MAX_ITEMS) {
        PinItem *it = &g_cfg.items[g_cfg.count];
        memset(it, 0, sizeof(*it));
        it->type = ITEM_TYPE_LUA;
        lstrcpynW(it->lua_path, filepath, CFG_MAX_PATH);
        if (parsed_name[0])
            lstrcpynW(it->name, parsed_name, CFG_MAX_NAME);
        else
            lstrcpynW(it->name, filename, CFG_MAX_NAME);
        int refresh = script_parse_refresh(filepath);
        it->interval_ms = refresh > 0 ? (DWORD)refresh : 5000;
        int bw = script_parse_bar_width(filepath);
        if (bw > 0) it->bar_width = bw;
        it->bar_x = -1;
        it->bar_y = -1;
        it->bar_bg_color = 0xFFFFFFFF;
        it->pinned = TRUE;
        g_cfg.count++;
        config_save(&g_cfg);
        bars_destroy_all();
        bars_create_all();
        listview_populate();
    }
    free(content);
}
