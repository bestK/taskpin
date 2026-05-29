#include "httputil.h"
#include <winhttp.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_MAX_SIZE (256 * 1024)

static HINTERNET g_http_session = NULL;

static HINTERNET get_session(void) {
    if (g_http_session) return g_http_session;
    WINHTTP_CURRENT_USER_IE_PROXY_CONFIG ie_cfg = {0};
    if (WinHttpGetIEProxyConfigForCurrentUser(&ie_cfg) && ie_cfg.lpszProxy) {
        g_http_session = WinHttpOpen(L"TaskPin/1.0",
            WINHTTP_ACCESS_TYPE_NAMED_PROXY, ie_cfg.lpszProxy, ie_cfg.lpszProxyBypass, 0);
        if (ie_cfg.lpszProxy) GlobalFree(ie_cfg.lpszProxy);
        if (ie_cfg.lpszProxyBypass) GlobalFree(ie_cfg.lpszProxyBypass);
        if (ie_cfg.lpszAutoConfigUrl) GlobalFree(ie_cfg.lpszAutoConfigUrl);
    } else {
        g_http_session = WinHttpOpen(L"TaskPin/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    }
    if (g_http_session)
        WinHttpSetTimeouts(g_http_session, 8000, 8000, 8000, 8000);
    return g_http_session;
}

char *http_request_sync(const WCHAR *url, const WCHAR *method,
                        const char *body, const WCHAR *headers,
                        int *out_len, int max_size) {
    if (!url || !method) return NULL;
    if (max_size <= 0) max_size = DEFAULT_MAX_SIZE;

    /* Parse URL */
    WCHAR host[256] = {0}, path[2048] = {0};
    URL_COMPONENTS uc = {0};
    uc.dwStructSize = sizeof(uc);
    uc.lpszHostName = host; uc.dwHostNameLength = 256;
    uc.lpszUrlPath = path; uc.dwUrlPathLength = 2048;
    if (!WinHttpCrackUrl(url, 0, 0, &uc)) return NULL;

    HINTERNET hSession = get_session();
    if (!hSession) return NULL;

    HINTERNET hConn = WinHttpConnect(hSession, host, uc.nPort, 0);
    if (!hConn) return NULL;

    DWORD flags = (uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hReq = WinHttpOpenRequest(hConn, method, path,
        NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hReq) { WinHttpCloseHandle(hConn); return NULL; }

    /* Prepare headers and body */
    DWORD body_len = body ? (DWORD)strlen(body) : 0;
    WCHAR hdr_buf[2048] = {0};
    if (body && !headers) {
        lstrcpyW(hdr_buf, L"Content-Type: application/x-www-form-urlencoded\r\n");
    }
    if (headers) {
        lstrcatW(hdr_buf, headers);
        int hlen = lstrlenW(hdr_buf);
        if (hlen > 0 && hdr_buf[hlen-1] != L'\n') {
            lstrcatW(hdr_buf, L"\r\n");
        }
    }
    WCHAR *hdr_ptr = hdr_buf[0] ? hdr_buf : WINHTTP_NO_ADDITIONAL_HEADERS;
    DWORD hdr_len = hdr_buf[0] ? (DWORD)-1 : 0;

    if (!WinHttpSendRequest(hReq, hdr_ptr, hdr_len,
            (LPVOID)body, body_len, body_len, 0)) {
        WinHttpCloseHandle(hReq); WinHttpCloseHandle(hConn);
        return NULL;
    }
    if (!WinHttpReceiveResponse(hReq, NULL)) {
        WinHttpCloseHandle(hReq); WinHttpCloseHandle(hConn);
        return NULL;
    }

    /* Read response */
    char *buf = (char *)calloc(1, max_size);
    if (!buf) { WinHttpCloseHandle(hReq); WinHttpCloseHandle(hConn); return NULL; }
    DWORD total = 0, avail, rd;
    while (WinHttpQueryDataAvailable(hReq, &avail) && avail > 0) {
        if ((int)(total + avail) >= max_size - 1) avail = max_size - 1 - total;
        WinHttpReadData(hReq, buf + total, avail, &rd);
        total += rd;
        if ((int)total >= max_size - 1) break;
    }
    buf[total] = '\0';

    WinHttpCloseHandle(hReq);
    WinHttpCloseHandle(hConn);

    if (out_len) *out_len = (int)total;
    return buf;
}

char *http_get_sync(const WCHAR *url, int *out_len) {
    return http_request_sync(url, L"GET", NULL, NULL, out_len, 0);
}