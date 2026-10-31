/*
 * tp_http_mac.m — macOS implementation of tp_http_request_sync.
 *
 * STATUS: IMPLEMENTED (Phase 8).
 *
 * NSURLSession driven synchronously with a dispatch_semaphore, matching the
 * blocking contract WinHTTP has in tp_http_win.c: the call returns the body,
 * or NULL on failure, and never exposes a callback to the Lua layer.
 *
 * Notes on the mapping:
 *   - The request timeout is TP_HTTP_TIMEOUT_MS. The semaphore waits a little
 *     longer so NSURLSession's own timeout fires first and reports a clean
 *     error; the wait is only a backstop against a wedged session.
 *   - Caller headers arrive CRLF separated. They are split on newlines, each
 *     "Name: Value" line is applied verbatim, and (matching WinHTTP) a body
 *     with no headers at all gets application/x-www-form-urlencoded.
 *   - The body is capped at max_size (TP_HTTP_DEFAULT_MAX_SIZE when <= 0) and
 *     the returned buffer is malloc'd and NUL-terminated; the caller frees it.
 *   - HTTP error statuses are not failures: like WinHTTP, the response body is
 *     returned regardless of status code. Only transport failures yield NULL.
 *   - System proxy settings are honoured automatically by NSURLSession.
 *
 * The function is called from a Dart isolate thread, not the main thread, so
 * the autorelease pool is explicit and nothing here assumes a run loop.
 */

#include "tp_http.h"

#if !defined(__APPLE__)
/* Compiled on a non-Apple target by mistake; CMake should prevent this. */
#error "tp_http_mac.m is macOS-only; native/engine/CMakeLists.txt must not compile it elsewhere."
#endif

#import <Foundation/Foundation.h>

#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>

char *tp_http_request_sync(const char *url, const char *method,
                           const char *body, const char *headers,
                           int *out_len, int max_size) {
    if (!url || !method) return NULL;
    if (max_size <= 0) max_size = TP_HTTP_DEFAULT_MAX_SIZE;

    char *result = NULL;

    @autoreleasepool {
        NSString *urlString = [NSString stringWithUTF8String:url];
        NSString *methodString = [NSString stringWithUTF8String:method];
        NSURL *nsurl = urlString ? [NSURL URLWithString:urlString] : nil;
        if (!urlString || !methodString || !nsurl || !nsurl.scheme) return NULL;

        NSMutableURLRequest *request = [NSMutableURLRequest
            requestWithURL:nsurl
               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
           timeoutInterval:(NSTimeInterval)TP_HTTP_TIMEOUT_MS / 1000.0];
        request.HTTPMethod = methodString;

        /* Extra headers, verbatim. Split on any newline so both CRLF and LF
         * work; a line without a colon is ignored rather than sent malformed. */
        if (headers && headers[0]) {
            NSString *block = [NSString stringWithUTF8String:headers];
            NSArray<NSString *> *lines =
                [block componentsSeparatedByCharactersInSet:
                           [NSCharacterSet newlineCharacterSet]];
            for (NSString *line in lines) {
                NSRange colon = [line rangeOfString:@":"];
                if (colon.location == NSNotFound) continue;
                NSString *name = [[line substringToIndex:colon.location]
                    stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
                NSString *value = [[line substringFromIndex:colon.location + 1]
                    stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
                if (name.length > 0) {
                    [request setValue:value forHTTPHeaderField:name];
                }
            }
        } else if (body) {
            /* Same default as WinHTTP and lib/httputil.c. */
            [request setValue:@"application/x-www-form-urlencoded"
                forHTTPHeaderField:@"Content-Type"];
        }

        if (body) {
            request.HTTPBody = [NSData dataWithBytes:body length:strlen(body)];
        }

        NSURLSessionConfiguration *config =
            [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = (NSTimeInterval)TP_HTTP_TIMEOUT_MS / 1000.0;
        config.timeoutIntervalForResource = (NSTimeInterval)TP_HTTP_TIMEOUT_MS / 1000.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

        NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

        __block NSData *responseData = nil;
        __block NSError *responseError = nil;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);

        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response,
                                NSError *error) {
                (void)response;
                responseData = [data copy];
                responseError = error;
                dispatch_semaphore_signal(done);
            }];
        [task resume];

        /* Backstop: the request's own timeout should always fire first. */
        dispatch_time_t deadline = dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(TP_HTTP_TIMEOUT_MS + 2000) * NSEC_PER_MSEC);
        if (dispatch_semaphore_wait(done, deadline) != 0) {
            [task cancel];
            [session invalidateAndCancel];
            return NULL;
        }

        [session finishTasksAndInvalidate];

        if (responseError || !responseData) return NULL;

        NSUInteger len = responseData.length;
        if (len > (NSUInteger)(max_size - 1)) len = (NSUInteger)(max_size - 1);

        char *buf = (char *)malloc((size_t)len + 1);
        if (!buf) return NULL;
        if (len > 0) memcpy(buf, responseData.bytes, (size_t)len);
        buf[len] = '\0';

        if (out_len) *out_len = (int)len;
        result = buf;
    }

    return result;
}
