#ifndef TASKPIN_WEBSOCKET_H
#define TASKPIN_WEBSOCKET_H

#include <windows.h>
#include <winhttp.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WS_MAX_CONNS     16
#define WS_QUEUE_SIZE    32
#define WS_MSG_MAX_LEN   (64 * 1024)
#define WS_RECONNECT_MAX 30000

typedef struct {
    char *data;
    int   len;
} WSMessage;

typedef struct WSConnection {
    HINTERNET hSession;
    HINTERNET hConnect;
    HINTERNET hRequest;
    HINTERNET hWebSocket;

    HANDLE    recv_thread;
    volatile BOOL connected;
    volatile BOOL closing;

    BOOL      reconnect;
    int       reconnect_delay;
    WCHAR     url[2048];
    WCHAR     headers[2048];

    WSMessage queue[WS_QUEUE_SIZE];
    int       queue_head;
    int       queue_tail;
    int       queue_count;
    CRITICAL_SECTION queue_cs;

    WCHAR     owner_path[MAX_PATH];
} WSConnection;

void ws_init(void);
void ws_shutdown(void);
void ws_close_by_script(const WCHAR *lua_path);

WSConnection *ws_connect(const WCHAR *url, const WCHAR *headers, BOOL reconnect);
void ws_close(WSConnection *ws);
int  ws_send(WSConnection *ws, const char *data, int len);
int  ws_recv(WSConnection *ws, char **out_data, int *out_len);
BOOL ws_is_connected(WSConnection *ws);

#ifdef __cplusplus
}
#endif

#endif
