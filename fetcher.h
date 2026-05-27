#ifndef TASKPIN_FETCHER_H
#define TASKPIN_FETCHER_H

#include <windows.h>

#define FETCH_BUF_SIZE 2048
#define WM_FETCH_DONE  (WM_USER + 100)

typedef struct {
    HWND  hwnd;
    WCHAR url[1024];
    char  result[FETCH_BUF_SIZE];
    BOOL  success;
} FetchContext;

DWORD WINAPI fetcher_thread(LPVOID param);

#endif