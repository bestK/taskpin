#include "ui.h"
#include "logger.h"
#include <objbase.h>

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

    /* Logger: init early for --event mode, reinit after config_load */
    logger_init(LOG_OFF);

    /* Handle --source/--event/--params: send to running instance and exit */
    int argc;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv && argc >= 3) {
        const char *src = NULL, *evt = NULL, *params = NULL;
        char src_buf[EVENT_SOURCE_LEN] = {0};
        char evt_buf[EVENT_NAME_LEN] = {0};
        char params_buf[EVENT_JSON_LEN] = {0};
        for (int i = 1; i < argc; i++) {
            if (wcscmp(argv[i], L"--source") == 0 && i + 1 < argc) {
                WideCharToMultiByte(CP_UTF8, 0, argv[++i], -1, src_buf, sizeof(src_buf), NULL, NULL);
                src = src_buf;
            } else if (wcscmp(argv[i], L"--event") == 0 && i + 1 < argc) {
                WideCharToMultiByte(CP_UTF8, 0, argv[++i], -1, evt_buf, sizeof(evt_buf), NULL, NULL);
                evt = evt_buf;
            } else if (wcscmp(argv[i], L"--params") == 0 && i + 1 < argc) {
                /* Extract params from raw cmdline to avoid quote mangling */
                LPWSTR raw = GetCommandLineW();
                LPWSTR p = wcsstr(raw, L"--params");
                if (p) {
                    p += 8; /* skip "--params" */
                    while (*p == L' ') p++;
                    /* Strip surrounding quotes and unescape \" → " */
                    WCHAR clean[EVENT_JSON_LEN];
                    int ci = 0;
                    BOOL in_quote = FALSE;
                    for (int k = 0; p[k] && ci < EVENT_JSON_LEN - 1; k++) {
                        if (p[k] == L'"' && (k == 0 || p[k-1] != L'\\')) {
                            in_quote = !in_quote;
                            continue;
                        }
                        if (p[k] == L'\\' && p[k+1] == L'"') {
                            clean[ci++] = L'"';
                            k++;
                            continue;
                        }
                        clean[ci++] = p[k];
                    }
                    clean[ci] = L'\0';
                    WideCharToMultiByte(CP_UTF8, 0, clean, -1, params_buf, sizeof(params_buf), NULL, NULL);
                    params = params_buf;
                }
                break;
            }
        }
        if (src && evt) {
            BOOL wait_mode = FALSE;
            for (int i = 1; i < argc; i++) {
                if (wcscmp(argv[i], L"--wait") == 0) { wait_mode = TRUE; break; }
            }
            if (wait_mode) {
                /* Read stdin as params if no --params provided */
                if (!params) {
                    HANDLE hStdin = GetStdHandle(STD_INPUT_HANDLE);
                    DWORD avail = 0;
                    if (PeekNamedPipe(hStdin, NULL, 0, NULL, &avail, NULL) && avail > 0) {
                        static char stdin_buf[EVENT_JSON_LEN];
                        DWORD rd = 0;
                        ReadFile(hStdin, stdin_buf, sizeof(stdin_buf) - 1, &rd, NULL);
                        stdin_buf[rd] = '\0';
                        params = stdin_buf;
                    }
                }

                /* Generate unique response file path */
                char resp_path[MAX_PATH];
                char *tmp = getenv("TEMP");
                if (!tmp) tmp = getenv("TMP");
                if (!tmp) tmp = ".";
                GUID guid;
                CoCreateGuid(&guid);
                snprintf(resp_path, MAX_PATH,
                    "%s\\taskpin_%08lx%04x%04x%02x%02x%02x%02x%02x%02x%02x%02x",
                    tmp, guid.Data1, guid.Data2, guid.Data3,
                    guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3],
                    guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
                DeleteFileA(resp_path);
                /* Merge response_file into params JSON */
                char merged[EVENT_JSON_LEN];
                if (params && params[0]) {
                    /* Insert into existing JSON object: {"response_file":"...", ...rest} */
                    snprintf(merged, sizeof(merged),
                        "{\"response_file\":\"%s\",%s", resp_path, params + 1);
                } else {
                    snprintf(merged, sizeof(merged),
                        "{\"response_file\":\"%s\"}", resp_path);
                }
                /* Escape backslashes in path for JSON */
                char escaped[EVENT_JSON_LEN];
                int ei = 0;
                for (int k = 0; merged[k] && ei < EVENT_JSON_LEN - 1; k++) {
                    if (merged[k] == '\\') { escaped[ei++] = '\\'; escaped[ei++] = '\\'; }
                    else escaped[ei++] = merged[k];
                }
                escaped[ei] = '\0';
                event_send_ipc(src, evt, escaped);
                /* Poll for response file */
                for (int t = 0; t < 240; t++) {
                    Sleep(500);
                    FILE *df = fopen(resp_path, "r");
                    if (df) {
                        char buf[2048] = {0};
                        size_t n = fread(buf, 1, sizeof(buf) - 1, df);
                        fclose(df);
                        DeleteFileA(resp_path);
                        if (n > 0) {
                            fwrite(buf, 1, n, stdout);
                            fflush(stdout);
                        }
                        LocalFree(argv);
                        return 0;
                    }
                }
            } else {
                event_send_ipc(src, evt, params);
            }
            LocalFree(argv);
            return 0;
        }
    }
    if (argv) LocalFree(argv);

    HANDLE hMutex = CreateMutexW(NULL, TRUE, L"Global\\TaskPin_SingleInstance");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (hMutex) CloseHandle(hMutex);
        return 0;
    }

    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_LISTVIEW_CLASSES | ICC_TREEVIEW_CLASSES };
    InitCommonControlsEx(&icc);

    config_load(&g_cfg);
    logger_init(g_cfg.log_level);
    event_init();
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