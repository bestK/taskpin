#include "ui.h"

/* Global variable definitions */
TaskPinConfig g_cfg;
HFONT g_font;
HWND g_main_hwnd = NULL;
HINSTANCE g_hinst;

BarInstance g_bars[MAX_BARS];
int g_bar_count = 0;

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, LPWSTR cmdLine, int nShow) {
    (void)hPrev; (void)cmdLine; (void)nShow;
    g_hinst = hInst;

    /* TEMP: distinct mutex so we can launch beside an elevated old instance. */
    HANDLE hMutex = CreateMutexW(NULL, TRUE, L"Global\\TaskPin_SingleInstance_UITest");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (hMutex) CloseHandle(hMutex);
        return 0;
    }

    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_LISTVIEW_CLASSES | ICC_TREEVIEW_CLASSES };
    InitCommonControlsEx(&icc);

    config_load(&g_cfg);
    i18n_init();
    script_init();
    script_dialog_init(hInst);

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

    bars_create_all();
    modern_ui_show();

    HANDLE hUpd = CreateThread(NULL, 0, check_update_thread, NULL, 0, NULL);
    if (hUpd) CloseHandle(hUpd);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    modern_ui_shutdown();
    script_shutdown();
    return (int)msg.wParam;
}
