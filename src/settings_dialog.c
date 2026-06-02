#include "ui.h"
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

    y += 28;
    CreateWindowExW(0, L"STATIC", L"Log level:",
        WS_CHILD | WS_VISIBLE, 10, y + 2, 70, 20, hDlg, NULL, g_hinst, NULL);
    HWND s_eLogLevel = CreateWindowExW(0, L"COMBOBOX", NULL,
        WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
        80, y, 100, 120, hDlg, (HMENU)5062, g_hinst, NULL);
    SendMessageW(s_eLogLevel, WM_SETFONT, (WPARAM)g_font, TRUE);
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)L"Off");
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)L"Error");
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)L"Info");
    SendMessageW(s_eLogLevel, CB_ADDSTRING, 0, (LPARAM)L"Debug");
    SendMessageW(s_eLogLevel, CB_SETCURSEL, g_cfg.log_level, 0);

    y += 30;
    CreateWindowExW(0, L"BUTTON", L"OK",
        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        90, y, 70, 28, hDlg, (HMENU)IDOK, g_hinst, NULL);
    CreateWindowExW(0, L"BUTTON", L"Cancel",
        WS_CHILD | WS_VISIBLE,
        170, y, 70, 28, hDlg, (HMENU)IDCANCEL, g_hinst, NULL);

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