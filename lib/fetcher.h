#ifndef TASKPIN_FETCHER_H
#define TASKPIN_FETCHER_H

#include <windows.h>

#define FETCH_BUF_SIZE 2048
#define WM_FETCH_DONE  (WM_USER + 100)
#define WM_LUA_DONE    (WM_USER + 101)

typedef struct {
    HWND  hwnd;
    WCHAR url[1024];
    WCHAR headers[1024];  /* custom headers, \r\n separated */
    char  result[FETCH_BUF_SIZE];
    BOOL  success;
} FetchContext;

DWORD WINAPI fetcher_thread(LPVOID param);

#endif