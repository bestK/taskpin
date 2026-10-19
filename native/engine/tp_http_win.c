/*
 * tp_http_win.c — WinHTTP implementation of tp_http_request_sync.
 *
 * Ported from lib/httputil.c (http_request_sync) with the URL parsing and
 * header handling that lib/fetcher.c also carries, so the two Windows HTTP
 * paths collapse into one.
 *
 * Deliberately MSVC-clean C: no VLAs, no GNU extensions, no // comments in
 * the Win32 glue that has to compile under both MinGW and MSVC.
 *
 * Note: UNICODE is NOT defined for this engine (the ABI is UTF-8), so the
 * explicit *W functions are used throughout rather than the TCHAR macros.
 */

#include "tp_http.h"

#include <windows.h>
#include <winhttp.h>

#include <stdlib.h>
#include <string.h>

#define TP_WIN_URL_MAX    2048
#define TP_WIN_HOST_MAX   256
#define TP_WIN_HEADER_MAX 2048

/* One shared session per process, with the current user's IE proxy config
 * applied, exactly as lib/httputil.c's get_session does. */
static HINTERNET tp_http_session = NULL;

static HINTERNET tp_win_session(void) {
    if (tp_http_session) return tp_http_session;

    WINHTTP_CURRENT_USER_IE_PROXY_CONFIG ie_cfg;
    memset(&ie_cfg, 0, sizeof(ie_cfg));

    if (WinHttpGetIEProxyConfigForCurrentUser(&ie_cfg) && ie_cfg.lpszProxy) {
        tp_http_session = WinHttpOpen(L"TaskPin/1.0",
            WINHTTP_ACCESS_TYPE_NAMED_PROXY,
            ie_cfg.lpszProxy, ie_cfg.lpszProxyBypass, 0);
    } else {
        tp_http_session = WinHttpOpen(L"TaskPin/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    }

    if (ie_cfg.lpszProxy) GlobalFree(ie_cfg.lpszProxy);
    if (ie_cfg.lpszProxyBypass) GlobalFree(ie_cfg.lpszProxyBypass);
    if (ie_cfg.lpszAutoConfigUrl) GlobalFree(ie_cfg.lpszAutoConfigUrl);

    if (tp_http_session) {
        WinHttpSetTimeouts(tp_http_session, TP_HTTP_TIMEOUT_MS, TP_HTTP_TIMEOUT_MS,
                           TP_HTTP_TIMEOUT_MS, TP_HTTP_TIMEOUT_MS);
    }
    return tp_http_session;
}

static WCHAR *tp_utf8_to_wide(const char *s, WCHAR *buf, int cap) {
    if (!s) return NULL;
    buf[0] = 0;
    MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, cap);
    return buf;
}

char *tp_http_request_sync(const char *url, const char *method,
                           const char *body, const char *headers,
                           int *out_len, int max_size) {
    if (!url || !method) return NULL;
    if (max_size <= 0) max_size = TP_HTTP_DEFAULT_MAX_SIZE;

    WCHAR wurl[TP_WIN_URL_MAX];
    WCHAR wmethod[16];
    WCHAR whost[TP_WIN_HOST_MAX];
    WCHAR wpath[TP_WIN_URL_MAX];
    WCHAR wheaders[TP_WIN_HEADER_MAX];
    WCHAR hdr_buf[TP_WIN_HEADER_MAX];

    if (!tp_utf8_to_wide(url, wurl, TP_WIN_URL_MAX)) return NULL;
    if (!tp_utf8_to_wide(method, wmethod, 16)) return NULL;

    whost[0] = 0;
    wpath[0] = 0;

    URL_COMPONENTS uc;
    memset(&uc, 0, sizeof(uc));
    uc.dwStructSize = sizeof(uc);
    uc.lpszHostName = whost;
    uc.dwHostNameLength = TP_WIN_HOST_MAX;
    uc.lpszUrlPath = wpath;
    uc.dwUrlPathLength = TP_WIN_URL_MAX;
    if (!WinHttpCrackUrl(wurl, 0, 0, &uc)) return NULL;

    HINTERNET hSession = tp_win_session();
    if (!hSession) return NULL;

    HINTERNET hConn = WinHttpConnect(hSession, whost, uc.nPort, 0);
    if (!hConn) return NULL;

    DWORD flags = (uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hReq = WinHttpOpenRequest(hConn, wmethod, wpath,
        NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hReq) {
        WinHttpCloseHandle(hConn);
        return NULL;
    }

    /* Headers. lib/httputil.c sends a form content type when there is a body
     * and the caller supplied no headers, then appends any caller headers
     * with a CRLF terminator if missing. */
    DWORD body_len = body ? (DWORD)strlen(body) : 0;
    hdr_buf[0] = 0;
    if (body && !headers) {
        wcscpy(hdr_buf, L"Content-Type: application/x-www-form-urlencoded\r\n");
    }
    if (headers && tp_utf8_to_wide(headers, wheaders, TP_WIN_HEADER_MAX) && wheaders[0]) {
        wcsncat(hdr_buf, wheaders,
                TP_WIN_HEADER_MAX - wcslen(hdr_buf) - 1);
        int hlen = (int)wcslen(hdr_buf);
        if (hlen > 0 && hdr_buf[hlen - 1] != L'\n' &&
            hlen + 2 < TP_WIN_HEADER_MAX) {
            hdr_buf[hlen] = L'\r';
            hdr_buf[hlen + 1] = L'\n';
            hdr_buf[hlen + 2] = 0;
        }
    }

    WCHAR *hdr_ptr = hdr_buf[0] ? hdr_buf : WINHTTP_NO_ADDITIONAL_HEADERS;
    DWORD hdr_len = hdr_buf[0] ? (DWORD)-1 : 0;

    if (!WinHttpSendRequest(hReq, hdr_ptr, hdr_len,
                            (LPVOID)body, body_len, body_len, 0)) {
        WinHttpCloseHandle(hReq);
        WinHttpCloseHandle(hConn);
        return NULL;
    }
    if (!WinHttpReceiveResponse(hReq, NULL)) {
        WinHttpCloseHandle(hReq);
        WinHttpCloseHandle(hConn);
        return NULL;
    }

    char *buf = (char *)calloc(1, (size_t)max_size);
    if (!buf) {
        WinHttpCloseHandle(hReq);
        WinHttpCloseHandle(hConn);
        return NULL;
    }

    DWORD total = 0;
    for (;;) {
        DWORD avail = 0;
        if (!WinHttpQueryDataAvailable(hReq, &avail) || avail == 0) break;
        if ((int)(total + avail) >= max_size - 1) avail = (DWORD)(max_size - 1 - (int)total);
        DWORD rd = 0;
        if (!WinHttpReadData(hReq, buf + total, avail, &rd)) break;
        total += rd;
        if ((int)total >= max_size - 1) break;
    }
    buf[total] = '\0';

    WinHttpCloseHandle(hReq);
    WinHttpCloseHandle(hConn);

    if (out_len) *out_len = (int)total;
    return buf;
}
