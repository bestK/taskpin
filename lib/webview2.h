#ifndef TASKPIN_WEBVIEW2_H
#define TASKPIN_WEBVIEW2_H

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WebView WebView;

BOOL webview_available(void);
WebView *webview_create(HWND parent, int x, int y, int w, int h, const char *url);
void webview_resize(WebView *wv, int x, int y, int w, int h);
void webview_navigate(WebView *wv, const char *url);
void webview_eval(WebView *wv, const char *js);
void webview_destroy(WebView *wv);
BOOL webview_is_dragging(void);
void webview_hide_all(void);
void webview_show_all(void);

/* JS → Native message callback (for non-Lua custom messages) */
typedef void (*WebViewMessageCallback)(const char *msg, void *userdata);
void webview_set_message_handler(WebView *wv, WebViewMessageCallback cb, void *userdata);

#ifdef __cplusplus
}
#endif

#endif
