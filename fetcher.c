#include "fetcher.h"
#include <winhttp.h>
#include <stdio.h>
#include <string.h>

#pragma comment(lib, "winhttp.lib")

static BOOL parse_url(const WCHAR *url,
                      WCHAR *host, DWORD host_len,
                      WCHAR *path, DWORD path_len,
                      INTERNET_PORT *port, BOOL *secure) {
    URL_COMPONENTS uc = {0};
    uc.dwStructSize     = sizeof(uc);
    uc.lpszHostName     = host;
    uc.dwHostNameLength = host_len;
    uc.lpszUrlPath      = path;
    uc.dwUrlPathLength  = path_len;

    if (!WinHttpCrackUrl(url, 0, 0, &uc))
        return FALSE;

    *port   = uc.nPort;
    *secure = (uc.nScheme == INTERNET_SCHEME_HTTPS);
    return TRUE;
}

DWORD WINAPI fetcher_thread(LPVOID param) {
    FetchContext *ctx = (FetchContext *)param;
    ctx->success = FALSE;
    ctx->result[0] = '\0';

    WCHAR host[256] = {0};
    WCHAR path[1024] = {0};
    INTERNET_PORT port = 80;
    BOOL secure = FALSE;

    if (!parse_url(ctx->url, host, 256, path, 1024, &port, &secure))
        goto done;

    HINTERNET hSession = WinHttpOpen(L"TaskPin/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) goto done;

    /* 超时 4 秒 */
    WinHttpSetTimeouts(hSession, 4000, 4000, 4000, 4000);

    HINTERNET hConnect = WinHttpConnect(hSession, host, port, 0);
    if (!hConnect) { WinHttpCloseHandle(hSession); goto done; }

    DWORD flags = secure ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", path,
        NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hRequest) { WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); goto done; }

    /* Ensure headers end with \r\n for WinHTTP */
    WCHAR hdr_buf[1024];
    WCHAR *hdr = WINHTTP_NO_ADDITIONAL_HEADERS;
    DWORD hdr_len = 0;
    if (ctx->headers[0]) {
        lstrcpynW(hdr_buf, ctx->headers, 1020);
        int len = lstrlenW(hdr_buf);
        /* Trim trailing whitespace */
        while (len > 0 && (hdr_buf[len-1] == L'\r' || hdr_buf[len-1] == L'\n' || hdr_buf[len-1] == L' '))
            len--;
        hdr_buf[len] = L'\r'; hdr_buf[len+1] = L'\n'; hdr_buf[len+2] = L'\0';
        hdr = hdr_buf;
        hdr_len = (DWORD)-1;
    }
    if (!WinHttpSendRequest(hRequest, hdr, hdr_len,
            WINHTTP_NO_REQUEST_DATA, 0, 0, 0))
        goto cleanup;

    if (!WinHttpReceiveResponse(hRequest, NULL))
        goto cleanup;

    /* 读取响应体 */
    DWORD total = 0;
    DWORD avail = 0;
    while (WinHttpQueryDataAvailable(hRequest, &avail) && avail > 0) {
        if (total + avail >= FETCH_BUF_SIZE - 1)
            avail = FETCH_BUF_SIZE - 1 - total;
        DWORD read = 0;
        WinHttpReadData(hRequest, ctx->result + total, avail, &read);
        total += read;
        if (total >= FETCH_BUF_SIZE - 1) break;
    }
    ctx->result[total] = '\0';
    ctx->success = TRUE;

cleanup:
    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);

done:
    PostMessageW(ctx->hwnd, WM_FETCH_DONE, 0, (LPARAM)ctx);
    return 0;
}