#include "ui.h"
#include "logger.h"
#include <objbase.h>
#include <dbghelp.h>

/* Crash handler: dump stack trace to taskpin.log and show message */
static LONG WINAPI crash_handler(EXCEPTION_POINTERS *ep) {
    WCHAR log_path[MAX_PATH];
    GetModuleFileNameW(NULL, log_path, MAX_PATH);
    WCHAR *slash = wcsrchr(log_path, L'\\');
    if (slash) *(slash + 1) = L'\0';
    lstrcatW(log_path, L"crash.log");

    FILE *f = _wfopen(log_path, L"a");
    if (f) {
        SYSTEMTIME st;
        GetLocalTime(&st);
        fprintf(f, "\n=== CRASH %04d-%02d-%02d %02d:%02d:%02d ===\n",
            st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
        fprintf(f, "Exception: 0x%08X at address 0x%p\n",
            (unsigned)ep->ExceptionRecord->ExceptionCode,
            ep->ExceptionRecord->ExceptionAddress);

        HANDLE proc = GetCurrentProcess();
        HANDLE thread = GetCurrentThread();
        SymInitialize(proc, NULL, TRUE);

        CONTEXT *ctx = ep->ContextRecord;
        STACKFRAME64 frame = {0};
        frame.AddrPC.Mode = AddrModeFlat;
        frame.AddrFrame.Mode = AddrModeFlat;
        frame.AddrStack.Mode = AddrModeFlat;
#ifdef _M_X64
        DWORD machine = IMAGE_FILE_MACHINE_AMD64;
        frame.AddrPC.Offset = ctx->Rip;
        frame.AddrFrame.Offset = ctx->Rbp;
        frame.AddrStack.Offset = ctx->Rsp;
#else
        DWORD machine = IMAGE_FILE_MACHINE_I386;
        frame.AddrPC.Offset = ctx->Eip;
        frame.AddrFrame.Offset = ctx->Ebp;
        frame.AddrStack.Offset = ctx->Esp;
#endif
        fprintf(f, "Stack trace:\n");
        for (int i = 0; i < 32; i++) {
            if (!StackWalk64(machine, proc, thread, &frame, ctx, NULL,
                    SymFunctionTableAccess64, SymGetModuleBase64, NULL))
                break;
            if (frame.AddrPC.Offset == 0) break;

            char buf[sizeof(SYMBOL_INFO) + 256];
            SYMBOL_INFO *sym = (SYMBOL_INFO *)buf;
            sym->SizeOfStruct = sizeof(SYMBOL_INFO);
            sym->MaxNameLen = 255;
            DWORD64 disp = 0;
            if (SymFromAddr(proc, frame.AddrPC.Offset, &disp, sym)) {
                fprintf(f, "  [%d] %s + 0x%llx\n", i, sym->Name, (unsigned long long)disp);
            } else {
                fprintf(f, "  [%d] 0x%p\n", i, (void *)frame.AddrPC.Offset);
            }
        }
        SymCleanup(proc);
        fclose(f);
    }

    MessageBoxW(NULL, L"TaskPin crashed. See crash.log for details.",
        L"TaskPin - Fatal Error", MB_ICONERROR | MB_OK);
    return EXCEPTION_EXECUTE_HANDLER;
}

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
    SetUnhandledExceptionFilter(crash_handler);
    g_hinst = hInst;

    /* Logger: init early for --event mode, reinit after config_load */
    logger_init(LOG_OFF);

    /* Register taskpin:// URL scheme */
    {
        WCHAR exe_path[MAX_PATH];
        GetModuleFileNameW(NULL, exe_path, MAX_PATH);
        WCHAR cmd_val[MAX_PATH + 16];
        wsprintfW(cmd_val, L"\"%s\" \"%%1\"", exe_path);
        HKEY hk;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\taskpin",
                0, NULL, 0, KEY_WRITE, NULL, &hk, NULL) == ERROR_SUCCESS) {
            const WCHAR *desc = L"URL:TaskPin Protocol";
            RegSetValueExW(hk, NULL, 0, REG_SZ, (BYTE *)desc, (lstrlenW(desc) + 1) * sizeof(WCHAR));
            RegSetValueExW(hk, L"URL Protocol", 0, REG_SZ, (BYTE *)L"", sizeof(WCHAR));
            HKEY hk_cmd;
            if (RegCreateKeyExW(hk, L"shell\\open\\command",
                    0, NULL, 0, KEY_WRITE, NULL, &hk_cmd, NULL) == ERROR_SUCCESS) {
                RegSetValueExW(hk_cmd, NULL, 0, REG_SZ, (BYTE *)cmd_val, (lstrlenW(cmd_val) + 1) * sizeof(WCHAR));
                RegCloseKey(hk_cmd);
            }
            RegCloseKey(hk);
        }
    }

    /* Handle taskpin:// URL invocation */
    int argc;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    WCHAR import_url[1024] = {0};
    if (argv) {
        for (int i = 1; i < argc; i++) {
            if (wcsncmp(argv[i], L"taskpin://install/", 18) == 0) {
                lstrcpynW(import_url, argv[i] + 18, 1024);
                break;
            }
        }
    }

    /* If we have an import URL and another instance is running, forward via IPC */
    if (import_url[0]) {
        HWND hTaskbar = FindWindowW(L"Shell_TrayWnd", NULL);
        HWND target = NULL;
        if (hTaskbar)
            target = FindWindowExW(hTaskbar, NULL, L"TaskPinBarClass", NULL);
        if (!target)
            target = FindWindowW(L"TaskPinBarClass", NULL);
        if (target) {
            COPYDATASTRUCT cds;
            cds.dwData = 0x5451; /* COPYDATA_IMPORT_ID */
            cds.cbData = (DWORD)((lstrlenW(import_url) + 1) * sizeof(WCHAR));
            cds.lpData = import_url;
            SendMessageW(target, WM_COPYDATA, 0, (LPARAM)&cds);
            if (argv) LocalFree(argv);
            return 0;
        }
    }

    /* Handle --source/--event/--params: send to running instance and exit */
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
        i18n_init();
        MessageBoxW(NULL, tr("app.already_running"), L"TaskPin", MB_ICONINFORMATION | MB_OK);
        return 0;
    }

    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_LISTVIEW_CLASSES | ICC_TREEVIEW_CLASSES };
    InitCommonControlsEx(&icc);

    config_load(&g_cfg);
    i18n_init();
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

    /* Handle pending URL import (first-launch case) */
    if (import_url[0]) {
        import_script_from_url(import_url);
    }

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