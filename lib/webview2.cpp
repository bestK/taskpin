#include "webview2.h"
#include "webview2/WebView2.h"
#include "i18n.h"
#include "cJSON.h"
#include "scripting.h"
#include <shlwapi.h>
#include <shlobj.h>
#include <shellapi.h>
#include <commctrl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef HRESULT (STDMETHODCALLTYPE *CreateWebView2EnvironmentFn)(
    PCWSTR browserExecutableFolder,
    PCWSTR userDataFolder,
    ICoreWebView2EnvironmentOptions *opts,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *handler);

static CreateWebView2EnvironmentFn s_create_env = nullptr;
static BOOL s_init_tried = FALSE;
static BOOL s_available = FALSE;

struct WebView {
    ICoreWebView2 *webview;
    ICoreWebView2Controller *controller;
    HWND parent;
    BOOL ready;
    WCHAR pending_url[2048];
    WebViewMessageCallback msg_cb;
    void *msg_userdata;
    RECT desired_bounds;
    HWND webview_hwnd;
};

/* Track all active webviews for visibility toggle during drag */
#define MAX_WEBVIEWS 16
static WebView *s_all_webviews[MAX_WEBVIEWS];
static int s_webview_count = 0;


extern "C" void webview_hide_all(void) {
    const WCHAR *hint = tr("webview.drag_hint");
    for (int i = 0; i < s_webview_count; i++) {
        if (s_all_webviews[i] && s_all_webviews[i]->webview && s_all_webviews[i]->ready) {
            WCHAR js[2048];
            wsprintfW(js,
                L"(function(){"
                L"if(document.getElementById('__tp_drag'))return;"
                L"var d=document.createElement('div');d.id='__tp_drag';"
                L"d.style.cssText='position:fixed;top:0;left:0;width:100vw;height:100vh;background:rgba(30,30,30,0.85);z-index:999999;display:flex;align-items:center;justify-content:center;cursor:grab;user-select:none;';"
                L"d.innerHTML='<span style=\"color:#aaa;font:14px sans-serif;pointer-events:none\">%s</span>';"
                L"var sx,sy,wx,wy,moving=false;"
                L"d.onmousedown=function(e){sx=e.screenX;sy=e.screenY;wx=window.screenX;wy=window.screenY;moving=true;d.style.cursor=\"grabbing\";};"
                L"d.onmousemove=function(e){if(!moving)return;var dx=e.screenX-sx,dy=e.screenY-sy;window.chrome.webview.postMessage('__taskpin_move__:'+(wx+dx)+':'+(wy+dy));};"
                L"d.onmouseup=function(){moving=false;d.style.cursor=\"grab\";};"
                L"d.onwheel=function(e){e.preventDefault();var delta=e.deltaY>0?-20:20;window.chrome.webview.postMessage('__taskpin_resize__:'+delta);};"
                L"document.body.appendChild(d);"
                L"})()", hint);
            s_all_webviews[i]->webview->ExecuteScript(js, nullptr);
        }
    }
}

extern "C" void webview_show_all(void) {
    for (int i = 0; i < s_webview_count; i++) {
        if (s_all_webviews[i] && s_all_webviews[i]->webview && s_all_webviews[i]->ready) {
            s_all_webviews[i]->webview->ExecuteScript(
                L"(function(){var d=document.getElementById('__tp_drag');if(d)d.remove();})()", nullptr);
        }
    }
}

extern "C" BOOL webview_is_dragging(void) {
    return FALSE;
}

static void ensure_init() {
    if (s_init_tried) return;
    s_init_tried = TRUE;

    /* 1. Try loading from exe directory (user manually placed it) */
    WCHAR exe_dir[MAX_PATH];
    GetModuleFileNameW(NULL, exe_dir, MAX_PATH);
    PathRemoveFileSpecW(exe_dir);
    WCHAR local_path[MAX_PATH];
    wsprintfW(local_path, L"%s\\WebView2Loader.dll", exe_dir);
    HMODULE hMod = LoadLibraryW(local_path);

    /* 2. Try system PATH */
    if (!hMod) hMod = LoadLibraryW(L"WebView2Loader.dll");

    /* 3. Try EdgeWebView Runtime location from registry */
    if (!hMod) {
        WCHAR edge_path[MAX_PATH] = {0};
        HKEY hk;
        DWORD sz;
#ifdef _WIN64
        const WCHAR *reg_paths[] = {
            L"SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
            L"SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
        };
#else
        const WCHAR *reg_paths[] = {
            L"SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
            L"SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
        };
#endif
        for (int r = 0; r < 2 && !edge_path[0]; r++) {
            sz = MAX_PATH * sizeof(WCHAR);
            if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, reg_paths[r], 0, KEY_READ, &hk) == ERROR_SUCCESS) {
                RegQueryValueExW(hk, L"location", NULL, NULL, (BYTE *)edge_path, &sz);
                RegCloseKey(hk);
            }
        }
        if (edge_path[0]) {
            /* Find version subfolder and look for WebView2Loader.dll */
            WCHAR search[MAX_PATH];
            wsprintfW(search, L"%s\\*", edge_path);
            WIN32_FIND_DATAW fd;
            HANDLE hFind = FindFirstFileW(search, &fd);
            if (hFind != INVALID_HANDLE_VALUE) {
                do {
                    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && fd.cFileName[0] != L'.') {
                        WCHAR try_path[MAX_PATH];
                        wsprintfW(try_path, L"%s\\%s\\WebView2Loader.dll", edge_path, fd.cFileName);
                        hMod = LoadLibraryW(try_path);
                        if (hMod) break;
                    }
                } while (FindNextFileW(hFind, &fd));
                FindClose(hFind);
            }
        }
    }

    /* 4. Try Edge browser installation */
    if (!hMod) {
        WCHAR pf[MAX_PATH];
#ifdef _WIN64
        GetEnvironmentVariableW(L"ProgramFiles", pf, MAX_PATH);
#else
        GetEnvironmentVariableW(L"ProgramFiles(x86)", pf, MAX_PATH);
#endif
        WCHAR search[MAX_PATH];
        wsprintfW(search, L"%s\\Microsoft\\Edge\\Application\\*", pf);
        WIN32_FIND_DATAW fd;
        HANDLE hFind = FindFirstFileW(search, &fd);
        if (hFind != INVALID_HANDLE_VALUE) {
            do {
                if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && fd.cFileName[0] >= L'0' && fd.cFileName[0] <= L'9') {
                    WCHAR try_path[MAX_PATH];
                    wsprintfW(try_path, L"%s\\Microsoft\\Edge\\Application\\%s\\WebView2Loader.dll", pf, fd.cFileName);
                    hMod = LoadLibraryW(try_path);
                    if (hMod) break;
                }
            } while (FindNextFileW(hFind, &fd));
            FindClose(hFind);
        }
    }

    if (!hMod) return;

    s_create_env = (CreateWebView2EnvironmentFn)GetProcAddress(hMod,
        "CreateCoreWebView2EnvironmentWithOptions");
    if (s_create_env) s_available = TRUE;
}

extern "C" BOOL webview_available(void) {
    ensure_init();
    return s_available;
}

/* COM callback: environment created → create controller */
class EnvHandler : public ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler {
    ULONG m_ref;
    WebView *m_wv;
public:
    EnvHandler(WebView *wv) : m_ref(1), m_wv(wv) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) {
        if (riid == IID_IUnknown || riid == IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler) {
            *ppv = this; AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() { return ++m_ref; }
    ULONG STDMETHODCALLTYPE Release() { if (--m_ref == 0) { delete this; return 0; } return m_ref; }
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT hr, ICoreWebView2Environment *env) {
        if (FAILED(hr) || !env) return hr;
        class CtrlHandler : public ICoreWebView2CreateCoreWebView2ControllerCompletedHandler {
            ULONG m_ref;
            WebView *m_wv;
        public:
            CtrlHandler(WebView *wv) : m_ref(1), m_wv(wv) {}
            HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) {
                if (riid == IID_IUnknown || riid == IID_ICoreWebView2CreateCoreWebView2ControllerCompletedHandler) {
                    *ppv = this; AddRef(); return S_OK;
                }
                *ppv = nullptr; return E_NOINTERFACE;
            }
            ULONG STDMETHODCALLTYPE AddRef() { return ++m_ref; }
            ULONG STDMETHODCALLTYPE Release() { if (--m_ref == 0) { delete this; return 0; } return m_ref; }
            HRESULT STDMETHODCALLTYPE Invoke(HRESULT hr, ICoreWebView2Controller *ctrl) {
                if (FAILED(hr) || !ctrl) return hr;
                m_wv->controller = ctrl;
                ctrl->AddRef();
                ctrl->get_CoreWebView2(&m_wv->webview);
                ctrl->put_Bounds(m_wv->desired_bounds);
                ctrl->put_IsVisible(TRUE);
                m_wv->ready = TRUE;
                if (m_wv->pending_url[0]) {
                    m_wv->webview->Navigate(m_wv->pending_url);
                    m_wv->pending_url[0] = L'\0';
                }
                /* Inject taskpin JS bridge — deep Proxy for taskpin.xxx.yyy() → Lua call */
                m_wv->webview->AddScriptToExecuteOnDocumentCreated(
                    L"(function(){"
                    L"var _cbs={},_id=0;"
                    L"window.__tp_resolve=function(id,val){if(_cbs[id]){_cbs[id](val);delete _cbs[id];}};"
                    L"function makeProxy(path){"
                    L"return new Proxy(function(){},{"
                    L"get:function(_,key){return makeProxy(path?path+'.'+key:key);},"
                    L"apply:function(_,__,args){"
                    L"var id=++_id;"
                    L"return new Promise(function(resolve){"
                    L"_cbs[id]=resolve;"
                    L"window.chrome.webview.postMessage(JSON.stringify({id:id,action:path,args:args}));"
                    L"});}"
                    L"});"
                    L"}"
                    L"window.taskpin=makeProxy('');"
                    L"})();",
                    nullptr);
                /* Set transparent background */
                ICoreWebView2Controller2 *ctrl2 = nullptr;
                if (SUCCEEDED(ctrl->QueryInterface(IID_ICoreWebView2Controller2, (void**)&ctrl2))) {
                    COREWEBVIEW2_COLOR bg = {0, 0, 0, 0};
                    ctrl2->put_DefaultBackgroundColor(bg);
                    ctrl2->Release();
                }
                /* Subclass all webview child windows for Shift+drag passthrough */
                /* (kept for future use, currently visibility-based approach) */
                /* Register JS→Native message handler */
                {
                    class MsgHandler : public ICoreWebView2WebMessageReceivedEventHandler {
                        ULONG m_ref;
                        WebView *m_wv;
                    public:
                        MsgHandler(WebView *wv) : m_ref(1), m_wv(wv) {}
                        HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) {
                            if (riid == IID_IUnknown || riid == IID_ICoreWebView2WebMessageReceivedEventHandler) {
                                *ppv = this; AddRef(); return S_OK;
                            }
                            *ppv = nullptr; return E_NOINTERFACE;
                        }
                        ULONG STDMETHODCALLTYPE AddRef() { return ++m_ref; }
                        ULONG STDMETHODCALLTYPE Release() { if (--m_ref == 0) { delete this; return 0; } return m_ref; }
                        HRESULT STDMETHODCALLTYPE Invoke(ICoreWebView2 *sender, ICoreWebView2WebMessageReceivedEventArgs *args) {
                            (void)sender;
                            LPWSTR msg = nullptr;
                            args->TryGetWebMessageAsString(&msg);
                            if (msg) {
                                /* Internal drag/resize messages (from overlay) */
                                if (wcsncmp(msg, L"__taskpin_move__:", 17) == 0) {
                                    int ax = 0, ay = 0;
                                    swscanf(msg + 17, L"%d:%d", &ax, &ay);
                                    SetWindowPos(m_wv->parent, NULL, ax, ay, 0, 0,
                                        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
                                } else if (wcsncmp(msg, L"__taskpin_resize__:", 19) == 0) {
                                    int delta = 0;
                                    swscanf(msg + 19, L"%d", &delta);
                                    RECT wr; GetWindowRect(m_wv->parent, &wr);
                                    int w = wr.right - wr.left + delta;
                                    int h = wr.bottom - wr.top + delta;
                                    if (w < 200) w = 200;
                                    if (h < 150) h = 150;
                                    SetWindowPos(m_wv->parent, NULL, 0, 0, w, h,
                                        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
                                    if (m_wv->controller) {
                                        RECT bounds = {0, 0, w, h};
                                        m_wv->controller->put_Bounds(bounds);
                                    }
                                } else if (msg[0] == L'{') {
                                    /* JSON proxy: {"id":N,"action":"sys.xxx","args":[...]} → Lua call */
                                    char utf8[4096];
                                    WideCharToMultiByte(CP_UTF8, 0, msg, -1, utf8, 4096, NULL, NULL);
                                    cJSON *root = cJSON_Parse(utf8);
                                    if (root) {
                                        int id = (int)cJSON_GetNumberValue(cJSON_GetObjectItem(root, "id"));
                                        const char *action = cJSON_GetStringValue(cJSON_GetObjectItem(root, "action"));
                                        cJSON *args = cJSON_GetObjectItem(root, "args");

                                        char *result = nullptr;
                                        if (action) {
                                            /* Build Lua expression: action(arg1, arg2, ...) */
                                            char expr[4096];
                                            int pos = snprintf(expr, sizeof(expr), "%s(", action);
                                            int argc = cJSON_GetArraySize(args);
                                            for (int a = 0; a < argc && pos < 3900; a++) {
                                                if (a > 0) pos += snprintf(expr + pos, sizeof(expr) - pos, ",");
                                                cJSON *arg = cJSON_GetArrayItem(args, a);
                                                if (cJSON_IsString(arg)) {
                                                    char *escaped = cJSON_PrintUnformatted(arg);
                                                    pos += snprintf(expr + pos, sizeof(expr) - pos, "%s", escaped);
                                                    cJSON_free(escaped);
                                                } else if (cJSON_IsNumber(arg)) {
                                                    pos += snprintf(expr + pos, sizeof(expr) - pos, "%g", arg->valuedouble);
                                                } else if (cJSON_IsBool(arg)) {
                                                    pos += snprintf(expr + pos, sizeof(expr) - pos, "%s", cJSON_IsTrue(arg) ? "true" : "false");
                                                } else if (cJSON_IsNull(arg)) {
                                                    pos += snprintf(expr + pos, sizeof(expr) - pos, "nil");
                                                } else {
                                                    char *json_str = cJSON_PrintUnformatted(arg);
                                                    pos += snprintf(expr + pos, sizeof(expr) - pos, "json.decode('%s')", json_str);
                                                    cJSON_free(json_str);
                                                }
                                            }
                                            snprintf(expr + pos, sizeof(expr) - pos, ")");
                                            result = script_eval_expr(expr);
                                        }

                                        /* Resolve Promise */
                                        if (id > 0 && m_wv->webview) {
                                            char js[4096];
                                            snprintf(js, sizeof(js), "window.__tp_resolve(%d,%s)", id, result ? result : "null");
                                            WCHAR wjs[4096];
                                            MultiByteToWideChar(CP_UTF8, 0, js, -1, wjs, 4096);
                                            m_wv->webview->ExecuteScript(wjs, nullptr);
                                        }
                                        if (result) free(result);
                                        cJSON_Delete(root);
                                    }
                                } else if (m_wv->msg_cb) {
                                    char utf8[4096];
                                    WideCharToMultiByte(CP_UTF8, 0, msg, -1, utf8, 4096, NULL, NULL);
                                    m_wv->msg_cb(utf8, m_wv->msg_userdata);
                                }
                                CoTaskMemFree(msg);
                            }
                            return S_OK;
                        }
                    };
                    EventRegistrationToken token;
                    m_wv->webview->add_WebMessageReceived(new MsgHandler(m_wv), &token);
                }
                return S_OK;
            }
        };
        env->CreateCoreWebView2Controller(m_wv->parent, new CtrlHandler(m_wv));
        return S_OK;
    }
};

extern "C" WebView *webview_create(HWND parent, int x, int y, int w, int h, const char *url) {
    ensure_init();
    if (!s_available || !s_create_env) return nullptr;

    WebView *wv = (WebView *)calloc(1, sizeof(WebView));
    if (!wv) return nullptr;
    wv->parent = parent;
    wv->desired_bounds = { x, y, x + w, y + h };

    if (url) {
        /* Resolve relative file:// paths to absolute */
        if (strncmp(url, "file:///", 8) == 0 && url[8] != '/' && url[9] != ':') {
            /* Relative path after file:/// — prepend exe directory */
            WCHAR exe_dir[MAX_PATH];
            GetModuleFileNameW(NULL, exe_dir, MAX_PATH);
            PathRemoveFileSpecW(exe_dir);
            char exe_dir_utf8[MAX_PATH * 3];
            WideCharToMultiByte(CP_UTF8, 0, exe_dir, -1, exe_dir_utf8, sizeof(exe_dir_utf8), NULL, NULL);
            /* Replace backslashes */
            for (char *p = exe_dir_utf8; *p; p++) if (*p == '\\') *p = '/';
            char abs_url[4096];
            snprintf(abs_url, sizeof(abs_url), "file:///%s/%s", exe_dir_utf8, url + 8);
            MultiByteToWideChar(CP_UTF8, 0, abs_url, -1, wv->pending_url, 2048);
        } else {
            MultiByteToWideChar(CP_UTF8, 0, url, -1, wv->pending_url, 2048);
        }
    }

    /* User data folder in AppData */
    WCHAR udf[MAX_PATH];
    SHGetFolderPathW(NULL, CSIDL_APPDATA, NULL, 0, udf);
    PathAppendW(udf, L"TaskPin\\webview2");

    HRESULT hr = s_create_env(nullptr, udf, nullptr, new EnvHandler(wv));
    if (FAILED(hr)) {
        OutputDebugStringW(L"[TaskPin] WebView2 CreateEnvironment failed\n");
        free(wv);
        return nullptr;
    }

    /* Register in global list for hide/show during drag */
    if (s_webview_count < MAX_WEBVIEWS)
        s_all_webviews[s_webview_count++] = wv;

    return wv;
}

extern "C" void webview_resize(WebView *wv, int x, int y, int w, int h) {
    if (!wv) return;
    wv->desired_bounds = { x, y, x + w, y + h };
    if (wv->controller)
        wv->controller->put_Bounds(wv->desired_bounds);
}

extern "C" void webview_navigate(WebView *wv, const char *url) {
    if (!wv || !url) return;
    WCHAR wurl[2048];
    MultiByteToWideChar(CP_UTF8, 0, url, -1, wurl, 2048);
    if (wv->ready && wv->webview) {
        wv->webview->Navigate(wurl);
    } else {
        lstrcpynW(wv->pending_url, wurl, 2048);
    }
}

extern "C" void webview_destroy(WebView *wv) {
    if (!wv) return;
    if (wv->controller) {
        wv->controller->Close();
        wv->controller->Release();
    }
    if (wv->webview) wv->webview->Release();
    /* Remove from global list */
    for (int i = 0; i < s_webview_count; i++) {
        if (s_all_webviews[i] == wv) {
            s_all_webviews[i] = s_all_webviews[--s_webview_count];
            break;
        }
    }
    free(wv);
}

extern "C" void webview_eval(WebView *wv, const char *js) {
    if (!wv || !wv->webview || !wv->ready || !js) return;
    WCHAR wjs[8192];
    MultiByteToWideChar(CP_UTF8, 0, js, -1, wjs, 8192);
    wv->webview->ExecuteScript(wjs, nullptr);
}

extern "C" void webview_set_message_handler(WebView *wv, WebViewMessageCallback cb, void *userdata) {
    if (!wv) return;
    wv->msg_cb = cb;
    wv->msg_userdata = userdata;
}
