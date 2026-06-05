#include "ui.h"
#include "update.h"

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

        ListView_SetItemText(g_listview, i, 4, g_cfg.items[i].pinned ? L"Y" : L"");

        WCHAR xy[32];
        wsprintfW(xy, L"%d,%d", g_cfg.items[i].bar_x, g_cfg.items[i].bar_y);
        ListView_SetItemText(g_listview, i, 5, xy);

        WCHAR bw[16];
        wsprintfW(bw, L"%d", g_cfg.items[i].bar_width);
        ListView_SetItemText(g_listview, i, 6, bw);

        WCHAR bg[16];
        wsprintfW(bg, L"%08X", (unsigned int)g_cfg.items[i].bar_bg_color);
        ListView_SetItemText(g_listview, i, 7, bg);
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
        col.pszText = (LPWSTR)tr("main.col_name"); col.cx = 100;
        ListView_InsertColumn(g_listview, 0, &col);
        col.pszText = (LPWSTR)tr("main.col_type"); col.cx = 50;
        ListView_InsertColumn(g_listview, 1, &col);
        col.pszText = (LPWSTR)tr("main.col_source"); col.cx = 250;
        ListView_InsertColumn(g_listview, 2, &col);
        col.pszText = (LPWSTR)tr("main.col_interval"); col.cx = 60;
        ListView_InsertColumn(g_listview, 3, &col);
        col.pszText = (LPWSTR)tr("main.col_pin"); col.cx = 30;
        ListView_InsertColumn(g_listview, 4, &col);
        col.pszText = (LPWSTR)tr("main.col_xy"); col.cx = 60;
        ListView_InsertColumn(g_listview, 5, &col);
        col.pszText = (LPWSTR)tr("main.col_width"); col.cx = 35;
        ListView_InsertColumn(g_listview, 6, &col);
        col.pszText = (LPWSTR)tr("main.col_bg"); col.cx = 65;
        ListView_InsertColumn(g_listview, 7, &col);

        SendMessageW(g_listview, WM_SETFONT, (WPARAM)g_font, TRUE);

        CreateWindowExW(0, L"BUTTON", tr("main.add"),
            WS_CHILD | WS_VISIBLE, 10, 268, 70, 28, hwnd, (HMENU)IDB_ADD, g_hinst, NULL);
        CreateWindowExW(0, L"BUTTON", tr("main.delete"),
            WS_CHILD | WS_VISIBLE, 90, 268, 70, 28, hwnd, (HMENU)IDB_DEL, g_hinst, NULL);
        CreateWindowExW(0, L"BUTTON", tr("main.pin"),
            WS_CHILD | WS_VISIBLE, 170, 268, 90, 28, hwnd, (HMENU)IDB_SELECT, g_hinst, NULL);
        CreateWindowExW(0, L"BUTTON", tr("main.settings"),
            WS_CHILD | WS_VISIBLE, 270, 268, 80, 28, hwnd, (HMENU)IDB_SETTINGS, g_hinst, NULL);
        CreateWindowExW(0, L"BUTTON", tr("main.market"),
            WS_CHILD | WS_VISIBLE, 360, 268, 70, 28, hwnd, (HMENU)IDB_MARKET, g_hinst, NULL);

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
        if (nm->hwndFrom == g_listview && nm->code == LVN_ITEMCHANGED) {
            int sel = ListView_GetNextItem(g_listview, -1, LVNI_SELECTED);
            HWND hBtn = GetDlgItem(hwnd, IDB_SELECT);
            if (hBtn) {
                if (sel >= 0 && sel < g_cfg.count && g_cfg.items[sel].pinned)
                    SetWindowTextW(hBtn, tr("main.unpin"));
                else
                    SetWindowTextW(hBtn, tr("main.pin"));
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
            check_update_manual();
            break;
        case IDB_SETTINGS:
            show_settings_dialog(hwnd);
            break;
        case IDB_MARKET:
            show_market_dialog(hwnd);
            break;
        case IDB_DEL: {
            int sel = ListView_GetNextItem(g_listview, -1, LVNI_SELECTED);
            if (sel >= 0 && sel < g_cfg.count) {
                BOOL was_pinned = g_cfg.items[sel].pinned;
                for (int i = sel; i < g_cfg.count - 1; i++)
                    g_cfg.items[i] = g_cfg.items[i + 1];
                g_cfg.count--;
                config_save(&g_cfg);
                listview_populate();
                if (was_pinned) {
                    bars_destroy_all();
                    bars_create_all();
                }
            }
            break;
        }
        case IDB_SELECT: {
            int sel = ListView_GetNextItem(g_listview, -1, LVNI_SELECTED);
            if (sel >= 0 && sel < g_cfg.count) {
                g_cfg.items[sel].pinned = !g_cfg.items[sel].pinned;
                config_save(&g_cfg);
                listview_populate();
                bars_destroy_all();
                bars_create_all();
            } else {
                MessageBoxW(hwnd, tr("main.select_item_first"), L"TaskPin", MB_OK | MB_ICONINFORMATION);
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

    case WM_CONTEXTMENU: {
        HWND hCtrl = (HWND)wp;
        if (GetDlgCtrlID(hCtrl) == 4099) {
            ShellExecuteW(NULL, L"open", L"https://github.com/bestK/taskpin", NULL, NULL, SW_SHOWNORMAL);
            return 0;
        }
        break;
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
    g_main_hwnd = CreateWindowExW(0, L"TaskPinMainClass", tr("main.window_title"),
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 640, 340,
        NULL, NULL, g_hinst, NULL);
    ShowWindow(g_main_hwnd, SW_SHOW);
    UpdateWindow(g_main_hwnd);
}