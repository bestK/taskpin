#ifndef TASKPIN_HTTPUTIL_H
#define TASKPIN_HTTPUTIL_H

#include <windows.h>

/* Synchronous HTTP request. Returns malloc'd response body (caller frees), or NULL on error.
   url: full URL (http:// or https://)
   method: L"GET" or L"POST"
   body: request body for POST (NULL for GET)
   headers: additional headers string "Key: Value\r\n..." (NULL for none)
   out_len: if non-NULL, receives response length
   max_size: max response bytes to read (0 = default 256KB) */
char *http_request_sync(const WCHAR *url, const WCHAR *method,
                        const char *body, const WCHAR *headers,
                        int *out_len, int max_size);

/* Convenience: GET with no body/headers */
char *http_get_sync(const WCHAR *url, int *out_len);

#endif