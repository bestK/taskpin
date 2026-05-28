#include "update.h"
#include "httputil.h"
#include "json.h"
#include <shellapi.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static BOOL is_in_china(void) {
    char *resp = http_get_sync(L"https://api.ip.sb/geoip", NULL);
    if (!resp) return FALSE;
    BOOL cn = (strstr(resp, "\"country_code\":\"CN\"") != NULL);
    free(resp);
    return cn;
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

static void do_silent_update(BOOL china) {
    /* Build download URL */
    const WCHAR *base = china
        ? L"https://gh-proxy.com/https://github.com/bestK/taskpin/releases/latest/download/taskpin.exe"
        : L"https://github.com/bestK/taskpin/releases/latest/download/taskpin.exe";

    /* Download to temp */
    WCHAR tmp_dir[MAX_PATH], tmp_exe[MAX_PATH], tmp_bat[MAX_PATH];
    GetTempPathW(MAX_PATH, tmp_dir);
    wsprintfW(tmp_exe, L"%staskpin_update.exe", tmp_dir);
    wsprintfW(tmp_bat, L"%staskpin_update.bat", tmp_dir);

    if (!download_file(base, tmp_exe)) {
        MessageBoxW(NULL, L"Download failed. Opening browser for manual download.",
            L"TaskPin Update", MB_OK | MB_ICONWARNING);
        ShellExecuteW(NULL, L"open",
            china ? L"https://gh-proxy.com/https://github.com/bestK/taskpin/releases/latest/download/taskpin-x64.zip"
                  : L"https://github.com/bestK/taskpin/releases/latest/download/taskpin-x64.zip",
            NULL, NULL, SW_SHOWNORMAL);
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

    char *resp = http_get_sync(L"https://api.github.com/repos/bestK/taskpin/releases/latest", NULL);
    if (!resp) return 0;

    JsonNode *root = json_parse(resp);
    if (!root) { free(resp); return 0; }

    JsonNode *tag_node = json_path_query(root, "$.tag_name");
    if (!tag_node || tag_node->type != JSON_STRING || !tag_node->str_val) {
        json_free(root); free(resp); return 0;
    }

    const char *tag = tag_node->str_val;
    if (*tag == 'v') tag++;

    if (strcmp(tag, TASKPIN_VERSION) > 0) {
        BOOL china = is_in_china();

        /* Get release description */
        char body_text[1024] = {0};
        JsonNode *body_node = json_path_query(root, "$.body");
        if (body_node && body_node->type == JSON_STRING && body_node->str_val) {
            strncpy(body_text, body_node->str_val, 800);
        }

        WCHAR msg[2048];
        WCHAR wtag[64], wbody[1024];
        MultiByteToWideChar(CP_UTF8, 0, tag, -1, wtag, 64);
        MultiByteToWideChar(CP_UTF8, 0, body_text, -1, wbody, 1024);
        wsprintfW(msg, L"New version v%s available\n\n%s\n\nUpdate now?", wtag, wbody);

        if (MessageBoxW(NULL, msg, L"TaskPin Update", MB_YESNO | MB_ICONINFORMATION) == IDYES) {
            do_silent_update(china);
        } else {
            /* User declined — no action */
        }
    }

    json_free(root);
    free(resp);
    return 0;
}