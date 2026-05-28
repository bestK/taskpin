#include "ui.h"

void listview_populate(void) {
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

LRESULT CALLBACK main_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
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
        case 4099:
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

void show_main_window(void) {
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