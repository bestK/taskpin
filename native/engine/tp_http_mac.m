/*
 * tp_http_mac.m — macOS implementation of tp_http_request_sync.
 *
 * STATUS: NOT IMPLEMENTED. This is a Phase 8 (macOS) deliverable.
 *
 * The signatures are final so the ABI and the Lua layer above them do not
 * change when this lands; only the body is missing. CMake compiles this file
 * on Apple targets only.
 *
 * TODO (macOS phase):
 *   - NSURLSession with a synchronous semaphore, matching the blocking
 *     contract WinHTTP has in tp_http_win.c. The plan calls for exactly
 *     this: "tp_http_mac.m 用 NSURLSession 同步（信号量），与 WinHTTP 的
 *     阻塞契约一致".
 *   - Apply the caller's extra headers verbatim (CRLF separated), and when a
 *     body is present with no headers send
 *     "Content-Type: application/x-www-form-urlencoded".
 *   - Cap the body at max_size (default TP_HTTP_DEFAULT_MAX_SIZE) and apply
 *     TP_HTTP_TIMEOUT_MS to the request.
 *   - Return a NUL-terminated malloc'd buffer the caller frees, or NULL.
 *
 * Until then the build refuses to produce a silently-broken macOS engine:
 * define TP_ALLOW_UNIMPLEMENTED_MAC to opt in to the failing stubs.
 */

#include "tp_http.h"

#if !defined(__APPLE__)
/* Compiled on a non-Apple target by mistake; CMake should prevent this. */
#error "tp_http_mac.m is macOS-only; native/engine/CMakeLists.txt must not compile it elsewhere."
#endif

#if !defined(TP_ALLOW_UNIMPLEMENTED_MAC)
#error "tp_http_mac.m is not implemented yet (Phase 8). Define TP_ALLOW_UNIMPLEMENTED_MAC to build the failing stubs."
#endif

#include <stdio.h>
#include <stdlib.h>

char *tp_http_request_sync(const char *url, const char *method,
                           const char *body, const char *headers,
                           int *out_len, int max_size) {
    (void)url;
    (void)method;
    (void)body;
    (void)headers;
    (void)max_size;

    /* TODO: implement with NSURLSession + dispatch_semaphore (Phase 8). */
    fprintf(stderr, "[TaskPin] tp_http_request_sync: macOS implementation pending\n");
    if (out_len) *out_len = 0;
    return NULL;
}
