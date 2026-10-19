/*
 * tp_http.h — internal platform ABI for the blocking HTTP used by http.*().
 *
 * The contract is deliberately the same on every platform so the Lua layer
 * never changes: a synchronous call that returns a heap buffer the caller
 * frees, or NULL on failure. This mirrors lib/httputil.c's http_request_sync.
 *
 * Implementations:
 *   tp_http_win.c  WinHTTP, ported from lib/httputil.c + lib/fetcher.c
 *   tp_http_mac.m  NSURLSession (semaphore), TODO — macOS phase
 */

#ifndef TP_HTTP_H
#define TP_HTTP_H

#ifdef __cplusplus
extern "C" {
#endif

/* Response body cap when max_size <= 0 (lib/httputil.c DEFAULT_MAX_SIZE). */
#define TP_HTTP_DEFAULT_MAX_SIZE (256 * 1024)

/* Timeouts in milliseconds, applied to resolve/connect/send/receive.
 * lib/httputil.c uses 8000 for all four. */
#define TP_HTTP_TIMEOUT_MS 8000

/*
 * Perform one blocking request.
 *
 *   url      UTF-8, required.
 *   method   UTF-8, required ("GET" / "POST" / "PUT" / "DELETE").
 *   body     UTF-8 request body, or NULL.
 *   headers  UTF-8 extra headers, CRLF separated, or NULL. When a body is
 *            supplied and headers is NULL the implementation must send
 *            "Content-Type: application/x-www-form-urlencoded", matching
 *            lib/httputil.c.
 *   out_len  optional; receives the body length in bytes.
 *   max_size response cap; <= 0 selects TP_HTTP_DEFAULT_MAX_SIZE.
 *
 * Returns a NUL-terminated malloc'd buffer the caller must free(), or NULL.
 */
char *tp_http_request_sync(const char *url, const char *method,
                           const char *body, const char *headers,
                           int *out_len, int max_size);

#ifdef __cplusplus
}
#endif

#endif /* TP_HTTP_H */
