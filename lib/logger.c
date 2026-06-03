#include "logger.h"
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>

int g_log_level = LOG_OFF;

void logger_init(int level) {
    g_log_level = level;
}

void logger_write_impl(int level, const char *file, int line, const char *func, const char *fmt, ...) {
    if (level > g_log_level) return;

    WCHAR log_path[MAX_PATH];
    GetModuleFileNameW(NULL, log_path, MAX_PATH);
    WCHAR *slash = wcsrchr(log_path, L'\\');
    if (slash) *(slash + 1) = L'\0';
    lstrcatW(log_path, L"taskpin.log");

    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (GetFileAttributesExW(log_path, GetFileExInfoStandard, &fad)) {
        if (fad.nFileSizeLow > 65536) DeleteFileW(log_path);
    }

    FILE *f = _wfopen(log_path, L"a");
    if (!f) return;

    SYSTEMTIME st;
    GetLocalTime(&st);

    const char *tag = "?";
    if (level == LOG_ERROR) tag = "ERR";
    else if (level == LOG_INFO) tag = "INF";
    else if (level == LOG_DEBUG) tag = "DBG";

    /* Extract filename from path */
    const char *basename = file;
    const char *p = file;
    while (*p) { if (*p == '\\' || *p == '/') basename = p + 1; p++; }

    if (func && func[0])
        fprintf(f, "[%04d-%02d-%02d %02d:%02d:%02d][%s][%s:%d %s] ",
            st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
            tag, basename, line, func);
    else
        fprintf(f, "[%04d-%02d-%02d %02d:%02d:%02d][%s][%s:%d] ",
            st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
            tag, basename, line);

    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);

    fprintf(f, "\n");
    fclose(f);
}
