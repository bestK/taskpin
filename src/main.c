#include "ui.h"

/* Global variable definitions */
TaskPinConfig g_cfg;
WCHAR g_display[FETCH_BUF_SIZE];
DisplayContent g_display_rich = {0};
HFONT g_font;
BOOL  g_fetching = FALSE;
char  g_last_response[FETCH_BUF_SIZE];
ScriptResult g_script_result = {0};
int   g_scroll_offset = 0;
int   g_text_width = 0;

HWND g_bar_hwnd  = NULL;
HWND g_main_hwnd = NULL;
HWND g_listview  = NULL;
HINSTANCE g_hinst;

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, LPWSTR cmdLine, int nShow) {
    (void)hPrev; (void)cmdLine; (void)nShow;
    g_hinst = hInst;

    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_LISTVIEW_CLASSES | ICC_TREEVIEW_CLASSES };
    InitCommonControlsEx(&icc);

    config_load(&g_cfg);
    script_init();

    HICON hIcon = LoadIconW(hInst, L"IDI_APPICON");

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

    wc.lpfnWndProc   = main_wnd_proc;
    wc.lpszClassName = L"TaskPinMainClass";
    wc.style         = 0;
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    RegisterClassExW(&wc);

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