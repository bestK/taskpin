#include "update.h"
#include "httputil.h"
#include "json.h"
#include <shellapi.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static BOOL g_china = FALSE;

static BOOL is_in_china(void) {
    char *resp = http_get_sync(L"https://api.ip.sb/geoip", NULL);
    if (!resp) return FALSE;
    BOOL cn = (strstr(resp, "\"country_code\":\"CN\"") != NULL);
    free(resp);
    return cn;
}

/* Wrap GitHub URL with gh-proxy if in China */
static void gh_url(const WCHAR *path, WCHAR *out, int out_size) {
    if (g_china) {
        wsprintfW(out, L"https://gh-proxy.com/https://github.com/%s", path);
    } else {
        wsprintfW(out, L"https://github.com/%s", path);
    }
}

static char *gh_api_get(const WCHAR *api_path) {
    WCHAR url[512];
    if (g_china) {
        wsprintfW(url, L"https://gh-proxy.com/https://api.github.com%s", api_path);
    } else {
        wsprintfW(url, L"https://api.github.com%s", api_path);
    }
    return http_get_sync(url, NULL);
}

static BOOL download_file(const WCHAR *url, const WCHAR *dest) {
    int len = 0;
    char *data = http_request_sync(url, L"GET", NULL, NULL, &len, 8 * 1024 * 1024);
    if (!data || len <= 0) { free(data); return FALSE; }

    HANDLE hf = CreateFileW(dest, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (hf == INVALID_HANDLE_VALUE) { free(data); return FALSE; }
    DWORD written;
    WriteFile(hf, data, (DWORD)len, &written, NULL);
    CloseHandle(hf);
    free(data);
    return (written == (DWORD)len);
}

static void do_silent_update(void) {
    /* Determine architecture suffix */
    const WCHAR *arch_suffix;
#ifdef _WIN64
    arch_suffix = L"x64";
#else
    arch_suffix = L"x86";
#endif

    WCHAR dl_path[256];
    wsprintfW(dl_path, L"bestK/taskpin/releases/latest/download/taskpin-%s.exe", arch_suffix);

    WCHAR base[512];
    gh_url(dl_path, base, 512);

    /* Download to temp */
    WCHAR tmp_dir[MAX_PATH], tmp_exe[MAX_PATH], tmp_bat[MAX_PATH];
    GetTempPathW(MAX_PATH, tmp_dir);
    wsprintfW(tmp_exe, L"%staskpin_update.exe", tmp_dir);
    wsprintfW(tmp_bat, L"%staskpin_update.bat", tmp_dir);

    if (!download_file(base, tmp_exe)) {
        MessageBoxW(NULL, L"Download failed. Opening browser for manual download.",
            L"TaskPin Update", MB_OK | MB_ICONWARNING);
        WCHAR zip_path[256];
        wsprintfW(zip_path, L"bestK/taskpin/releases/latest/download/taskpin-%s.zip", arch_suffix);
        WCHAR zip_url[512];
        gh_url(zip_path, zip_url, 512);
        ShellExecuteW(NULL, L"open", zip_url, NULL, NULL, SW_SHOWNORMAL);
        return;
    }

    /* Get current exe path */
    WCHAR cur_exe[MAX_PATH];
    GetModuleFileNameW(NULL, cur_exe, MAX_PATH);

    /* Write bat script: wait, replace, restart, cleanup */
    HANDLE hf = CreateFileW(tmp_bat, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (hf == INVALID_HANDLE_VALUE) return;

    char bat[2048];
    char cur8[MAX_PATH], tmp8[MAX_PATH], bat8[MAX_PATH];
    WideCharToMultiByte(CP_ACP, 0, cur_exe, -1, cur8, MAX_PATH, NULL, NULL);
    WideCharToMultiByte(CP_ACP, 0, tmp_exe, -1, tmp8, MAX_PATH, NULL, NULL);
    WideCharToMultiByte(CP_ACP, 0, tmp_bat, -1, bat8, MAX_PATH, NULL, NULL);

    snprintf(bat, sizeof(bat),
        "@echo off\r\n"
        "timeout /t 2 /nobreak >nul\r\n"
        "copy /y \"%s\" \"%s\" >nul\r\n"
        "start \"\" \"%s\"\r\n"
        "del \"%s\"\r\n"
        "del \"%%~f0\"\r\n",
        tmp8, cur8, cur8, tmp8);

    DWORD wr;
    WriteFile(hf, bat, (DWORD)strlen(bat), &wr, NULL);
    CloseHandle(hf);

    /* Launch bat hidden and exit */
    STARTUPINFOW si = {0};
    PROCESS_INFORMATION pi = {0};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    WCHAR cmd[MAX_PATH + 16];
    wsprintfW(cmd, L"cmd /c \"%s\"", tmp_bat);
    if (CreateProcessW(NULL, cmd, NULL, NULL, FALSE,
            CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        ExitProcess(0);
    }
}

DWORD WINAPI check_update_thread(LPVOID param) {
    (void)param;
    Sleep(3000);

    g_china = is_in_china();

    for (;;) {
        WCHAR ver_url[512];
        gh_url(L"bestK/taskpin/raw/master/version.txt", ver_url, 512);
        char *resp = http_get_sync(ver_url, NULL);
        if (!resp) goto next;

        /* Trim whitespace */
        char *tag = resp;
        while (*tag == ' ' || *tag == '\r' || *tag == '\n') tag++;
        char *end = tag + strlen(tag) - 1;
        while (end > tag && (*end == ' ' || *end == '\r' || *end == '\n')) *end-- = '\0';

        if (strcmp(tag, TASKPIN_VERSION) > 0) {
            WCHAR msg[512];
            WCHAR wtag[64];
            MultiByteToWideChar(CP_UTF8, 0, tag, -1, wtag, 64);
            wsprintfW(msg, L"New version v%s available (current: v" L"" TASKPIN_VERSION L")\n\nUpdate now?", wtag);

            if (MessageBoxW(NULL, msg, L"TaskPin Update", MB_YESNO | MB_ICONINFORMATION) == IDYES) {
                free(resp);
                do_silent_update();
                return 0; /* ExitProcess called inside */
            }
            /* User declined — stop checking */
            free(resp);
            return 0;
        }

        free(resp);
next:
        /* No update found — wait 30 minutes and check again */
        Sleep(30 * 60 * 1000);
    }
}