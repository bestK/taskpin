#ifndef TASKPIN_HTTPUTIL_H
#define TASKPIN_HTTPUTIL_H

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

char *http_request_sync(const WCHAR *url, const WCHAR *method,
                        const char *body, const WCHAR *headers,
                        int *out_len, int max_size);

char *http_get_sync(const WCHAR *url, int *out_len);

#ifdef __cplusplus
}
#endif

#endif