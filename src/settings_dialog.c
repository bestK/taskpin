#include "ui.h"
#include "layout.h"
#include "logger.h"

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

void show_settings_dialog(HWND parent) {
    HWND hDlg = CreateWindowExW(WS_EX_DLGMODALFRAME | WS_EX_TOPMOST,
        L"#32770", tr("settings.title"),
        WS_VISIBLE | WS_POPUP | WS_CAPTION | WS_SYSMENU,
        200, 200, 380, 400, parent, NULL, g_hinst, NULL);
    if (!hDlg) return;

    #define EDT(style) CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD|WS_VISIBLE|(style), 0,0,0,0, hDlg, NULL, g_hinst, NULL)
    #define CHK(text, id) CreateWindowExW(0, L"BUTTON", text, WS_CHILD|WS_VISIBLE|BS_AUTOCHECKBOX, 0,0,0,0, hDlg, (HMENU)(id), g_hinst, NULL)
    #define BTN(text, id, style) CreateWindowExW(0, L"BUTTON", text, WS_CHILD|WS_VISIBLE|(style), 0,0,0,0, hDlg, (HMENU)(id), g_hinst, NULL)

    s_eFontSize = EDT(ES_NUMBER);
    s_eFontColor = EDT(ES_AUTOHSCROLL);
    s_eBgColor = EDT(ES_AUTOHSCROLL);
    s_eWidth = EDT(ES_NUMBER);
    s_ePosX = EDT(0);
    s_ePosY = EDT(0);
    HWND s_eAutoStart = CHK(tr("settings.auto_start"), 5060);
    HWND s_eScroll = CHK(tr("settings.auto_scroll"), 5061);
    HWND s_eLogLevel = CreateWindowExW(0, L"COMBOBOX", NULL,
        WS_CHILD|WS_VISIBLE|CBS_DROPDOWNLIST, 0,0,0,0, hDlg, (HMENU)5062, g_hinst, NULL);
    HWND btnOK = BTN(tr("settings.ok"), IDOK, BS_DEFPUSHBUTTON);
    HWND btnCancel = BTN(tr("settings.cancel"), IDCANCEL, 0);

    #undef EDT
    #undef CHK
    #undef BTN

    /* Set font on interactive controls */
    HWND ctrls[] = { s_eFontSize, s_eFontColor, s_eBgColor, s_eWidth,
        s_ePosX, s_ePosY, s_eAutoStart, s_eScroll, s_eLogLevel, btnOK, btnCancel };
    for (int i = 0; i < (int)(sizeof(ctrls)/sizeof(ctrls[0])); i++)
        SendMessageW(ctrls[i], WM_SETFONT, (WPARAM)g_font, TRUE);

    /* Layout — labels created automatically by ui_label() */
    ui_begin(hDlg, g_font, 10, 8);

    ui_row(8);  ui_label(tr("settings.font_size"));   ui_add(s_eFontSize, UI_FILL, 22);  ui_end_row();
    ui_row(8);  ui_label(tr("settings.font_color"));  ui_add(s_eFontColor, UI_FILL, 22); ui_end_row();
    ui_row(8);  ui_label(tr("settings.bg_color"));    ui_add(s_eBgColor, UI_FILL, 22);   ui_end_row();
    ui_row(8);  ui_label(tr("settings.width"));       ui_add(s_eWidth, UI_FILL, 22);     ui_end_row();
    ui_row(8);  ui_label(tr("settings.pos_x"));  ui_add(s_ePosX, 60, 22);
                ui_label(tr("settings.pos_y"));  ui_add(s_ePosY, 60, 22);   ui_end_row();
    ui_row(0);  ui_add(s_eAutoStart, 0, 22); ui_end_row();
    ui_row(0);  ui_add(s_eScroll, 0, 22);    ui_end_row();
    ui_row(8);  ui_label(tr("settings.log_level"));   ui_add(s_eLogLevel, 120, 22); ui_end_row();
    ui_row(10); ui_add(btnOK, 80, 28);  ui_add(btnCancel, 80, 28);  ui_end_row();

    ui_end();

    /* Init control state */
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
    SendMessageW(s_eScroll, BM_SETCHECK, g_cfg.scroll_enabled ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)tr("settings.log_off"));
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)tr("settings.log_error"));
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)tr("settings.log_info"));
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)tr("settings.log_debug"));
    SendMessageW(s_eLogLevel, CB_SETCURSEL, g_cfg.log_level, 0);

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
        g_cfg.log_level = (int)SendMessageW(s_eLogLevel, CB_GETCURSEL, 0, 0);
        if (g_cfg.log_level == CB_ERR) g_cfg.log_level = 0;
        logger_init(g_cfg.log_level);

        config_save(&g_cfg);

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

        if (g_font) DeleteObject(g_font);
        int fh = -MulDiv(g_cfg.font_size, 96, 72);
        g_font = CreateFontW(fh, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");

        /* Recreate all bars with new settings */
        bars_destroy_all();
        bars_create_all();
    }

    EnableWindow(parent, TRUE);
    DestroyWindow(hDlg);
    g_settings_orig_proc = NULL;
    SetForegroundWindow(parent);
}