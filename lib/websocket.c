#include "websocket.h"
#include "logger.h"
#include <winhttp.h>
#include <stdlib.h>
#include <string.h>

#define WS_LOG(fmt, ...) logger_write(LOG_ERROR, fmt, ##__VA_ARGS__)

static WSConnection *g_ws_conns[WS_MAX_CONNS];
static int g_ws_count = 0;
static CRITICAL_SECTION g_ws_cs;

void ws_init(void) {
    InitializeCriticalSection(&g_ws_cs);
    g_ws_count = 0;
    memset(g_ws_conns, 0, sizeof(g_ws_conns));
}

void ws_shutdown(void) {
    EnterCriticalSection(&g_ws_cs);
    for (int i = 0; i < g_ws_count; i++) {
        if (g_ws_conns[i]) ws_close(g_ws_conns[i]);
    }
    g_ws_count = 0;
    LeaveCriticalSection(&g_ws_cs);
    DeleteCriticalSection(&g_ws_cs);
}

static void registry_add(WSConnection *ws) {
    EnterCriticalSection(&g_ws_cs);
    if (g_ws_count < WS_MAX_CONNS) {
        g_ws_conns[g_ws_count++] = ws;
    }
    LeaveCriticalSection(&g_ws_cs);
}

static void registry_remove(WSConnection *ws) {
    EnterCriticalSection(&g_ws_cs);
    for (int i = 0; i < g_ws_count; i++) {
        if (g_ws_conns[i] == ws) {
            g_ws_conns[i] = g_ws_conns[--g_ws_count];
            g_ws_conns[g_ws_count] = NULL;
            break;
        }
    }
    LeaveCriticalSection(&g_ws_cs);
}

void ws_close_by_script(const WCHAR *lua_path) {
    if (!lua_path || !lua_path[0]) return;
    EnterCriticalSection(&g_ws_cs);
    for (int i = g_ws_count - 1; i >= 0; i--) {
        if (g_ws_conns[i] && lstrcmpiW(g_ws_conns[i]->owner_path, lua_path) == 0) {
            WSConnection *ws = g_ws_conns[i];
            g_ws_conns[i] = g_ws_conns[--g_ws_count];
            g_ws_conns[g_ws_count] = NULL;
            LeaveCriticalSection(&g_ws_cs);
            ws_close(ws);
            EnterCriticalSection(&g_ws_cs);
        }
    }
    LeaveCriticalSection(&g_ws_cs);
}

/* --- Message Queue --- */

static void queue_push(WSConnection *ws, const char *data, int len) {
    EnterCriticalSection(&ws->queue_cs);
    if (ws->queue_count >= WS_QUEUE_SIZE) {
        /* Drop oldest */
        free(ws->queue[ws->queue_head].data);
        ws->queue[ws->queue_head].data = NULL;
        ws->queue_head = (ws->queue_head + 1) % WS_QUEUE_SIZE;
        ws->queue_count--;
    }
    int idx = ws->queue_tail;
    ws->queue[idx].data = (char *)malloc(len + 1);
    if (ws->queue[idx].data) {
        memcpy(ws->queue[idx].data, data, len);
        ws->queue[idx].data[len] = '\0';
        ws->queue[idx].len = len;
        ws->queue_tail = (ws->queue_tail + 1) % WS_QUEUE_SIZE;
        ws->queue_count++;
    }
    LeaveCriticalSection(&ws->queue_cs);
}

int ws_recv(WSConnection *ws, char **out_data, int *out_len) {
    if (!ws) return 0;
    EnterCriticalSection(&ws->queue_cs);
    if (ws->queue_count == 0) {
        LeaveCriticalSection(&ws->queue_cs);
        *out_data = NULL;
        *out_len = 0;
        return 0;
    }
    int idx = ws->queue_head;
    *out_data = ws->queue[idx].data;
    *out_len = ws->queue[idx].len;
    ws->queue[idx].data = NULL;
    ws->queue_head = (ws->queue_head + 1) % WS_QUEUE_SIZE;
    ws->queue_count--;
    LeaveCriticalSection(&ws->queue_cs);
    return 1;
}

static void queue_clear(WSConnection *ws) {
    EnterCriticalSection(&ws->queue_cs);
    for (int i = 0; i < WS_QUEUE_SIZE; i++) {
        free(ws->queue[i].data);
        ws->queue[i].data = NULL;
    }
    ws->queue_head = ws->queue_tail = ws->queue_count = 0;
    LeaveCriticalSection(&ws->queue_cs);
}

/* --- WinHTTP WebSocket Connection --- */

static BOOL ws_do_connect(WSConnection *ws) {
    WCHAR host[256] = {0}, path[2048] = {0};

    /* WinHttpCrackUrl doesn't understand ws:// / wss:// — convert to http(s):// */
    WCHAR http_url[2048];
    lstrcpynW(http_url, ws->url, 2048);
    if (_wcsnicmp(http_url, L"wss://", 6) == 0) {
        lstrcpyW(http_url, L"https://");
        lstrcatW(http_url, ws->url + 6);
    } else if (_wcsnicmp(http_url, L"ws://", 5) == 0) {
        lstrcpyW(http_url, L"http://");
        lstrcatW(http_url, ws->url + 5);
    }

    URL_COMPONENTS uc = {0};
    uc.dwStructSize = sizeof(uc);
    uc.lpszHostName = host; uc.dwHostNameLength = 256;
    uc.lpszUrlPath = path; uc.dwUrlPathLength = 2048;
    if (!WinHttpCrackUrl(http_url, 0, 0, &uc)) {
        WS_LOG("ws: crack url failed");
        return FALSE;
    }

    /* Use IE proxy settings like httputil.c */
    WINHTTP_CURRENT_USER_IE_PROXY_CONFIG ie_cfg = {0};
    if (WinHttpGetIEProxyConfigForCurrentUser(&ie_cfg) && ie_cfg.lpszProxy) {
        ws->hSession = WinHttpOpen(L"TaskPin/1.0",
            WINHTTP_ACCESS_TYPE_NAMED_PROXY, ie_cfg.lpszProxy, ie_cfg.lpszProxyBypass, 0);
        if (ie_cfg.lpszProxy) GlobalFree(ie_cfg.lpszProxy);
        if (ie_cfg.lpszProxyBypass) GlobalFree(ie_cfg.lpszProxyBypass);
        if (ie_cfg.lpszAutoConfigUrl) GlobalFree(ie_cfg.lpszAutoConfigUrl);
    } else {
        ws->hSession = WinHttpOpen(L"TaskPin/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    }
    if (!ws->hSession) { WS_LOG("ws: open session failed"); return FALSE; }

    WinHttpSetTimeouts(ws->hSession, 10000, 10000, 10000, 10000);

    ws->hConnect = WinHttpConnect(ws->hSession, host, uc.nPort, 0);
    if (!ws->hConnect) { WS_LOG("ws: connect failed"); goto fail; }

    DWORD flags = (uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
    ws->hRequest = WinHttpOpenRequest(ws->hConnect, L"GET", path,
        NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!ws->hRequest) { WS_LOG("ws: open request failed"); goto fail; }

    if (!WinHttpSetOption(ws->hRequest, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, NULL, 0)) {
        WS_LOG("ws: set upgrade option failed");
        goto fail;
    }

    WCHAR *hdr_ptr = ws->headers[0] ? ws->headers : WINHTTP_NO_ADDITIONAL_HEADERS;
    DWORD hdr_len = ws->headers[0] ? (DWORD)-1 : 0;

    if (!WinHttpSendRequest(ws->hRequest, hdr_ptr, hdr_len, NULL, 0, 0, 0)) {
        WS_LOG("ws: send request failed (err=%lu)", GetLastError());
        goto fail;
    }
    if (!WinHttpReceiveResponse(ws->hRequest, NULL)) {
        WS_LOG("ws: receive response failed (err=%lu)", GetLastError());
        goto fail;
    }

    ws->hWebSocket = WinHttpWebSocketCompleteUpgrade(ws->hRequest, 0);
    if (!ws->hWebSocket) {
        WS_LOG("ws: upgrade failed (err=%lu)", GetLastError());
        goto fail;
    }

    WinHttpCloseHandle(ws->hRequest);
    ws->hRequest = NULL;
    ws->connected = TRUE;
    ws->reconnect_delay = 1000;
    return TRUE;

fail:
    if (ws->hRequest) { WinHttpCloseHandle(ws->hRequest); ws->hRequest = NULL; }
    if (ws->hConnect) { WinHttpCloseHandle(ws->hConnect); ws->hConnect = NULL; }
    if (ws->hSession) { WinHttpCloseHandle(ws->hSession); ws->hSession = NULL; }
    return FALSE;
}

static void ws_disconnect(WSConnection *ws) {
    ws->connected = FALSE;
    if (ws->hWebSocket) {
        WinHttpWebSocketClose(ws->hWebSocket,
            WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, NULL, 0);
        WinHttpCloseHandle(ws->hWebSocket);
        ws->hWebSocket = NULL;
    }
    if (ws->hConnect) { WinHttpCloseHandle(ws->hConnect); ws->hConnect = NULL; }
    if (ws->hSession) { WinHttpCloseHandle(ws->hSession); ws->hSession = NULL; }
}

static DWORD WINAPI ws_recv_thread(LPVOID param) {
    WSConnection *ws = (WSConnection *)param;
    char *buf = (char *)malloc(WS_MSG_MAX_LEN);
    if (!buf) return 1;

    while (!ws->closing) {
        if (!ws->connected) {
            if (!ws->reconnect || ws->closing) break;
            /* Interruptible sleep — check closing every 100ms */
            int slept = 0;
            while (slept < ws->reconnect_delay && !ws->closing) {
                Sleep(100);
                slept += 100;
            }
            if (ws->closing) break;
            if (!ws_do_connect(ws)) {
                if (ws->reconnect_delay < WS_RECONNECT_MAX)
                    ws->reconnect_delay = min(ws->reconnect_delay * 2, WS_RECONNECT_MAX);
                continue;
            }
        }

        DWORD bytes_read = 0;
        WINHTTP_WEB_SOCKET_BUFFER_TYPE buf_type;
        int total = 0;

        do {
            DWORD err = WinHttpWebSocketReceive(ws->hWebSocket,
                buf + total, WS_MSG_MAX_LEN - total - 1, &bytes_read, &buf_type);
            if (err != ERROR_SUCCESS) {
                ws_disconnect(ws);
                break;
            }
            total += bytes_read;
            if (buf_type == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE) {
                ws_disconnect(ws);
                break;
            }
        } while (buf_type == WINHTTP_WEB_SOCKET_UTF8_FRAGMENT_BUFFER_TYPE ||
                 buf_type == WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE);

        if (total > 0 && ws->connected) {
            buf[total] = '\0';
            queue_push(ws, buf, total);
        }
    }

    free(buf);
    return 0;
}

/* --- Public API --- */

WSConnection *ws_connect(const WCHAR *url, const WCHAR *headers, BOOL reconnect) {
    if (!url || !url[0]) return NULL;

    WSConnection *ws = (WSConnection *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(WSConnection));
    if (!ws) return NULL;

    InitializeCriticalSection(&ws->queue_cs);
    lstrcpynW(ws->url, url, 2048);
    if (headers) lstrcpynW(ws->headers, headers, 2048);
    ws->reconnect = reconnect;
    ws->reconnect_delay = 1000;
    ws->closing = FALSE;

    if (!ws_do_connect(ws)) {
        if (!reconnect) {
            DeleteCriticalSection(&ws->queue_cs);
            HeapFree(GetProcessHeap(), 0, ws);
            return NULL;
        }
    }

    ws->recv_thread = CreateThread(NULL, 0, ws_recv_thread, ws, 0, NULL);
    if (!ws->recv_thread) {
        ws_disconnect(ws);
        DeleteCriticalSection(&ws->queue_cs);
        HeapFree(GetProcessHeap(), 0, ws);
        return NULL;
    }

    registry_add(ws);
    return ws;
}

void ws_close(WSConnection *ws) {
    if (!ws) return;
    ws->closing = TRUE;
    ws->reconnect = FALSE;
    ws_disconnect(ws);

    if (ws->recv_thread) {
        WaitForSingleObject(ws->recv_thread, 5000);
        CloseHandle(ws->recv_thread);
        ws->recv_thread = NULL;
    }

    registry_remove(ws);
    queue_clear(ws);
    DeleteCriticalSection(&ws->queue_cs);
    HeapFree(GetProcessHeap(), 0, ws);
}

int ws_send(WSConnection *ws, const char *data, int len) {
    if (!ws || !ws->connected || !ws->hWebSocket) return -1;
    if (!data) return -1;
    if (len <= 0) len = (int)strlen(data);
    DWORD err = WinHttpWebSocketSend(ws->hWebSocket,
        WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE,
        (PVOID)data, (DWORD)len);
    return (err == ERROR_SUCCESS) ? len : -1;
}

BOOL ws_is_connected(WSConnection *ws) {
    return ws ? ws->connected : FALSE;
}
