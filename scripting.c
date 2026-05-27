#include "scripting.h"
#include "lua/lua.h"
#include "lua/lauxlib.h"
#include "lua/lualib.h"
#include "json.h"
#include <winhttp.h>
#include <stdio.h>
#include <string.h>

static lua_State *L = NULL;

/* ─── built-in json.decode for Lua ─── */

static void push_json_node(lua_State *ls, JsonNode *node);

static void push_json_node(lua_State *ls, JsonNode *node) {
    if (!node) { lua_pushnil(ls); return; }
    switch (node->type) {
    case JSON_NULL:   lua_pushnil(ls); break;
    case JSON_BOOL:   lua_pushboolean(ls, node->bool_val); break;
    case JSON_NUMBER: lua_pushnumber(ls, node->num_val); break;
    case JSON_STRING: lua_pushstring(ls, node->str_val ? node->str_val : ""); break;
    case JSON_OBJECT: {
        lua_newtable(ls);
        for (JsonNode *c = node->children; c; c = c->next) {
            if (c->key) {
                lua_pushstring(ls, c->key);
                push_json_node(ls, c);
                lua_settable(ls, -3);
            }
        }
        break;
    }
    case JSON_ARRAY: {
        lua_newtable(ls);
        int idx = 1;
        for (JsonNode *c = node->children; c; c = c->next, idx++) {
            lua_pushinteger(ls, idx);
            push_json_node(ls, c);
            lua_settable(ls, -3);
        }
        break;
    }
    }
}

static int l_json_decode(lua_State *ls) {
    const char *str = luaL_checkstring(ls, 1);
    JsonNode *root = json_parse(str);
    if (!root) { lua_pushnil(ls); return 1; }
    push_json_node(ls, root);
    json_free(root);
    return 1;
}

/* ─── built-in http.get / http.post for Lua ─── */

#include <winhttp.h>

static HINTERNET g_http_session = NULL;

static void http_ensure_session(void) {
    if (!g_http_session) {
        g_http_session = WinHttpOpen(L"TaskPin/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        if (g_http_session)
            WinHttpSetTimeouts(g_http_session, 8000, 8000, 8000, 8000);
    }
}

static int http_request(lua_State *ls, const WCHAR *method) {
    const char *url_str = luaL_checkstring(ls, 1);
    const char *body = NULL;
    if (lua_gettop(ls) >= 2 && !lua_isnil(ls, 2))
        body = luaL_checkstring(ls, 2);

    WCHAR wurl[2048];
    MultiByteToWideChar(CP_UTF8, 0, url_str, -1, wurl, 2048);

    http_ensure_session();
    if (!g_http_session) { lua_pushnil(ls); return 1; }

    /* Parse URL */
    WCHAR host[256] = {0}, path[1024] = {0};
    URL_COMPONENTS uc = {0};
    uc.dwStructSize = sizeof(uc);
    uc.lpszHostName = host; uc.dwHostNameLength = 256;
    uc.lpszUrlPath = path; uc.dwUrlPathLength = 1024;
    if (!WinHttpCrackUrl(wurl, 0, 0, &uc)) { lua_pushnil(ls); return 1; }

    HINTERNET hConn = WinHttpConnect(g_http_session, host, uc.nPort, 0);
    if (!hConn) { lua_pushnil(ls); return 1; }

    DWORD flags = (uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hReq = WinHttpOpenRequest(hConn, method, path,
        NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hReq) { WinHttpCloseHandle(hConn); lua_pushnil(ls); return 1; }

    /* Send */
    DWORD body_len = body ? (DWORD)strlen(body) : 0;
    WCHAR *headers = NULL;
    if (body) headers = L"Content-Type: application/x-www-form-urlencoded\r\n";
    if (!WinHttpSendRequest(hReq, headers, headers ? (DWORD)-1 : 0,
            (LPVOID)body, body_len, body_len, 0)) {
        WinHttpCloseHandle(hReq); WinHttpCloseHandle(hConn);
        lua_pushnil(ls); return 1;
    }
    if (!WinHttpReceiveResponse(hReq, NULL)) {
        WinHttpCloseHandle(hReq); WinHttpCloseHandle(hConn);
        lua_pushnil(ls); return 1;
    }

    /* Read response */
    char buf[8192] = {0};
    DWORD total = 0, avail, rd;
    while (WinHttpQueryDataAvailable(hReq, &avail) && avail > 0) {
        if (total + avail >= sizeof(buf) - 1) avail = sizeof(buf) - 1 - total;
        WinHttpReadData(hReq, buf + total, avail, &rd);
        total += rd;
        if (total >= sizeof(buf) - 1) break;
    }
    buf[total] = '\0';

    WinHttpCloseHandle(hReq);
    WinHttpCloseHandle(hConn);

    lua_pushstring(ls, buf);
    return 1;
}

static int l_http_get(lua_State *ls) { return http_request(ls, L"GET"); }
static int l_http_post(lua_State *ls) { return http_request(ls, L"POST"); }

/* ─── init / shutdown ─── */

void script_init(void) {
    L = luaL_newstate();
    if (!L) return;
    luaL_openlibs(L);

    /* Register json.decode */
    lua_newtable(L);
    lua_pushcfunction(L, l_json_decode);
    lua_setfield(L, -2, "decode");
    lua_setglobal(L, "json");

    /* Register http.get / http.post */
    lua_newtable(L);
    lua_pushcfunction(L, l_http_get);
    lua_setfield(L, -2, "get");
    lua_pushcfunction(L, l_http_post);
    lua_setfield(L, -2, "post");
    lua_setglobal(L, "http");
}

void script_shutdown(void) {
    if (L) { lua_close(L); L = NULL; }
    if (g_http_session) { WinHttpCloseHandle(g_http_session); g_http_session = NULL; }
}

/* ─── execute template code ─── */

BOOL script_exec(const char *lua_code, const char *response_raw, ScriptResult *result) {
    if (!L || !lua_code || !lua_code[0] || !result) return FALSE;

    result->display[0] = L'\0';
    result->clickable = FALSE;
    result->click_url[0] = L'\0';

    /* Set global `response` */
    lua_pushstring(L, response_raw ? response_raw : "");
    lua_setglobal(L, "response");

    /* Wrap code so multiple return values work */
    char wrapped[4096];
    snprintf(wrapped, sizeof(wrapped),
        "return (function()\n%s\nend)()", lua_code);

    if (luaL_dostring(L, wrapped) != LUA_OK) {
        lua_pop(L, 1);
        return FALSE;
    }

    /* Read up to 3 return values from stack */
    int nresults = lua_gettop(L);

    /* 1st: display text (required) */
    if (nresults >= 1) {
        const char *s = lua_tostring(L, 1);
        if (s) MultiByteToWideChar(CP_UTF8, 0, s, -1, result->display, 2048);
    }
    /* 2nd: clickable (boolean) */
    if (nresults >= 2) {
        result->clickable = lua_toboolean(L, 2);
    }
    /* 3rd: click URL */
    if (nresults >= 3) {
        const char *url = lua_tostring(L, 3);
        if (url) MultiByteToWideChar(CP_UTF8, 0, url, -1, result->click_url, 1024);
    }

    lua_settop(L, 0);
    return (result->display[0] != L'\0');
}

/* ─── execute Lua file ─── */

BOOL script_exec_file(const WCHAR *lua_path, ScriptResult *result) {
    if (!L || !lua_path || !lua_path[0] || !result) return FALSE;

    result->display[0] = L'\0';
    result->clickable = FALSE;
    result->click_url[0] = L'\0';

    /* Resolve relative path (relative to exe directory) */
    WCHAR full_path[MAX_PATH];
    if (lua_path[0] != L'\\' && lua_path[0] != L'/' &&
        !(lua_path[0] && lua_path[1] == L':')) {
        /* Relative path — prepend exe directory */
        GetModuleFileNameW(NULL, full_path, MAX_PATH);
        WCHAR *slash = wcsrchr(full_path, L'\\');
        if (slash) *(slash + 1) = L'\0';
        lstrcatW(full_path, lua_path);
    } else {
        lstrcpynW(full_path, lua_path, MAX_PATH);
    }

    char path8[512];
    WideCharToMultiByte(CP_UTF8, 0, full_path, -1, path8, 512, NULL, NULL);

    if (luaL_dofile(L, path8) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        if (err) MultiByteToWideChar(CP_UTF8, 0, err, -1, result->display, 2048);
        else lstrcpyW(result->display, L"[lua error]");
        lua_settop(L, 0);
        return TRUE; /* return TRUE so error shows in taskbar */
    }

    int nresults = lua_gettop(L);
    if (nresults >= 1) {
        const char *s = lua_tostring(L, 1);
        if (s) MultiByteToWideChar(CP_UTF8, 0, s, -1, result->display, 2048);
    }
    if (nresults >= 2) {
        result->clickable = lua_toboolean(L, 2);
    }
    if (nresults >= 3) {
        const char *url = lua_tostring(L, 3);
        if (url) MultiByteToWideChar(CP_UTF8, 0, url, -1, result->click_url, 1024);
    }

    lua_settop(L, 0);
    return (result->display[0] != L'\0');
}