#include "ui.h"

/* Global variable definitions */
TaskPinConfig g_cfg;
HFONT g_font;
HWND g_main_hwnd = NULL;
HWND g_listview  = NULL;
HINSTANCE g_hinst;

BarInstance g_bars[MAX_BARS];
int g_bar_count = 0;

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

    bars_create_all();

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