#include "scripting.h"
#include "sysinfo.h"
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

#include "httputil.h"

static int http_request(lua_State *ls, const WCHAR *method) {
    const char *url_str = luaL_checkstring(ls, 1);
    const char *body = NULL;
    const char *extra_headers = NULL;
    if (lua_gettop(ls) >= 2 && !lua_isnil(ls, 2))
        body = luaL_checkstring(ls, 2);
    if (lua_gettop(ls) >= 3 && !lua_isnil(ls, 3))
        extra_headers = luaL_checkstring(ls, 3);

    WCHAR wurl[2048];
    MultiByteToWideChar(CP_UTF8, 0, url_str, -1, wurl, 2048);

    WCHAR wheaders[2048] = {0};
    if (extra_headers) {
        MultiByteToWideChar(CP_UTF8, 0, extra_headers, -1, wheaders, 2048);
    }

    char *resp = http_request_sync(wurl, method, body,
        wheaders[0] ? wheaders : NULL, NULL, 0);
    if (resp) {
        lua_pushstring(ls, resp);
        free(resp);
    } else {
        lua_pushnil(ls);
    }
    return 1;
}

static int l_http_get(lua_State *ls) { return http_request(ls, L"GET"); }
static int l_http_post(lua_State *ls) { return http_request(ls, L"POST"); }
static int l_http_put(lua_State *ls) { return http_request(ls, L"PUT"); }
static int l_http_delete(lua_State *ls) { return http_request(ls, L"DELETE"); }

/* ─── init / shutdown ─── */

/* ─── font() span system for rich text ─── */

#define SPAN_MT "TaskPin.Span"

/* A span list is a Lua table: { {text=..., color=..., size=...}, ... } */

static COLORREF parse_color_str(const char *s) {
    if (!s || !s[0]) return 0xFFFFFFFF;
    if (s[0] == '#') s++;
    unsigned int r = 0, g = 0, b = 0;
    int len = (int)strlen(s);
    if (len == 3) {
        sscanf(s, "%1x%1x%1x", &r, &g, &b);
        r *= 17; g *= 17; b *= 17;
    } else if (len == 6) {
        sscanf(s, "%2x%2x%2x", &r, &g, &b);
    }
    return RGB(r, g, b);
}

/* font(text, color, size) -> span table */
static int l_font(lua_State *ls) {
    const char *text = luaL_checkstring(ls, 1);
    const char *color_str = NULL;
    int font_size = 0;
    const char *align_str = NULL;

    if (lua_gettop(ls) >= 2 && !lua_isnil(ls, 2))
        color_str = lua_tostring(ls, 2);
    if (lua_gettop(ls) >= 3 && !lua_isnil(ls, 3))
        font_size = (int)lua_tointeger(ls, 3);
    if (lua_gettop(ls) >= 4 && !lua_isnil(ls, 4))
        align_str = lua_tostring(ls, 4);

    /* Create a span table: {text, color, size, align, __is_span=true} */
    lua_newtable(ls);

    lua_pushstring(ls, text);
    lua_setfield(ls, -2, "text");

    if (color_str) {
        lua_pushstring(ls, color_str);
        lua_setfield(ls, -2, "color");
    }

    if (font_size > 0) {
        lua_pushinteger(ls, font_size);
        lua_setfield(ls, -2, "size");
    }

    if (align_str) {
        lua_pushstring(ls, align_str);
        lua_setfield(ls, -2, "align");
    }

    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_span");

    /* Set the span metatable for __concat support */
    luaL_getmetatable(ls, SPAN_MT);
    lua_setmetatable(ls, -2);

    return 1;
}

/* Helper: check if value at idx is a span or span list */
static BOOL is_span(lua_State *ls, int idx) {
    if (!lua_istable(ls, idx)) return FALSE;
    lua_getfield(ls, idx, "__is_span");
    BOOL r = lua_toboolean(ls, -1);
    lua_pop(ls, 1);
    if (r) return TRUE;
    /* Check if it's a span list (array of spans) */
    lua_getfield(ls, idx, "__is_spanlist");
    r = lua_toboolean(ls, -1);
    lua_pop(ls, 1);
    return r;
}

/* Append span(s) from src into dest list table (at top of stack) */
static void append_spans(lua_State *ls, int src_idx, int dest_idx) {
    int abs_src = (src_idx > 0) ? src_idx : lua_gettop(ls) + src_idx + 1;
    int abs_dest = (dest_idx > 0) ? dest_idx : lua_gettop(ls) + dest_idx + 1;

    lua_getfield(ls, abs_src, "__is_spanlist");
    BOOL is_list = lua_toboolean(ls, -1);
    lua_pop(ls, 1);

    if (is_list) {
        int len = (int)lua_rawlen(ls, abs_src);
        int dest_len = (int)lua_rawlen(ls, abs_dest);
        for (int i = 1; i <= len; i++) {
            lua_rawgeti(ls, abs_src, i);
            lua_rawseti(ls, abs_dest, dest_len + i);
        }
    } else {
        int dest_len = (int)lua_rawlen(ls, abs_dest);
        lua_pushvalue(ls, abs_src);
        lua_rawseti(ls, abs_dest, dest_len + 1);
    }
}

/* __concat metamethod: span .. span -> spanlist */
static int l_span_concat(lua_State *ls) {
    /* Create a new span list */
    lua_newtable(ls);
    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_spanlist");

    /* Set metatable on result too */
    luaL_getmetatable(ls, SPAN_MT);
    lua_setmetatable(ls, -2);

    int result_idx = lua_gettop(ls);

    /* Append left operand */
    if (lua_isstring(ls, 1)) {
        /* Plain string on left: wrap as default span */
        lua_newtable(ls);
        lua_pushvalue(ls, 1);
        lua_setfield(ls, -2, "text");
        lua_pushboolean(ls, 1);
        lua_setfield(ls, -2, "__is_span");
        lua_rawseti(ls, result_idx, 1);
    } else if (lua_istable(ls, 1)) {
        append_spans(ls, 1, result_idx);
    }

    /* Append right operand */
    if (lua_isstring(ls, 2)) {
        lua_newtable(ls);
        lua_pushvalue(ls, 2);
        lua_setfield(ls, -2, "text");
        lua_pushboolean(ls, 1);
        lua_setfield(ls, -2, "__is_span");
        int n = (int)lua_rawlen(ls, result_idx);
        lua_rawseti(ls, result_idx, n + 1);
    } else if (lua_istable(ls, 2)) {
        append_spans(ls, 2, result_idx);
    }

    return 1;
}

static void register_font_api(lua_State *ls) {
    /* Create span metatable */
    luaL_newmetatable(ls, SPAN_MT);
    lua_pushcfunction(ls, l_span_concat);
    lua_setfield(ls, -2, "__concat");
    lua_pop(ls, 1);

    /* Register global font() */
    lua_pushcfunction(ls, l_font);
    lua_setglobal(ls, "font");
}

static int parse_align_str(const char *s) {
    if (!s) return SPAN_ALIGN_LEFT;
    if (strcmp(s, "right") == 0) return SPAN_ALIGN_RIGHT;
    if (strcmp(s, "center") == 0) return SPAN_ALIGN_CENTER;
    return SPAN_ALIGN_LEFT;
}

/* Parse return value from Lua into ScriptResult rich spans */
static void parse_rich_result(lua_State *ls, int idx, DisplayContent *rich) {
    rich->count = 0;
    if (!lua_istable(ls, idx)) return;

    /* Check if it's a single span or a span list */
    lua_getfield(ls, idx, "__is_span");
    BOOL single = lua_toboolean(ls, -1);
    lua_pop(ls, 1);

    if (single) {
        lua_getfield(ls, idx, "text");
        const char *t = lua_tostring(ls, -1);
        if (t) {
            DisplaySpan *sp = &rich->spans[0];
            MultiByteToWideChar(CP_UTF8, 0, t, -1, sp->text, SPAN_TEXT_LEN);
            sp->color = 0xFFFFFFFF;
            sp->font_size = 0;
            sp->align = SPAN_ALIGN_LEFT;
            sp->newline = FALSE;
            if (wcscmp(sp->text, L"\n") == 0) { sp->text[0] = 0; sp->newline = TRUE; }
            lua_pop(ls, 1);
            lua_getfield(ls, idx, "color");
            const char *c = lua_tostring(ls, -1);
            if (c) sp->color = parse_color_str(c);
            lua_pop(ls, 1);
            lua_getfield(ls, idx, "size");
            if (!lua_isnil(ls, -1)) sp->font_size = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, idx, "align");
            const char *a = lua_tostring(ls, -1);
            sp->align = parse_align_str(a);
            lua_pop(ls, 1);
            rich->count = 1;
        } else {
            lua_pop(ls, 1);
        }
        return;
    }

    /* It's a span list */
    int len = (int)lua_rawlen(ls, idx);
    if (len > MAX_SPANS) len = MAX_SPANS;
    for (int i = 1; i <= len; i++) {
        lua_rawgeti(ls, idx, i);
        if (lua_istable(ls, -1)) {
            DisplaySpan *sp = &rich->spans[rich->count];
            sp->color = 0xFFFFFFFF;
            sp->font_size = 0;
            sp->align = SPAN_ALIGN_LEFT;
            sp->newline = FALSE;

            lua_getfield(ls, -1, "text");
            const char *t = lua_tostring(ls, -1);
            if (t) {
                MultiByteToWideChar(CP_UTF8, 0, t, -1, sp->text, SPAN_TEXT_LEN);
                if (wcscmp(sp->text, L"\n") == 0) { sp->text[0] = 0; sp->newline = TRUE; }
            } else {
                sp->text[0] = 0;
            }
            lua_pop(ls, 1);

            lua_getfield(ls, -1, "color");
            const char *c = lua_tostring(ls, -1);
            if (c) sp->color = parse_color_str(c);
            lua_pop(ls, 1);

            lua_getfield(ls, -1, "size");
            if (!lua_isnil(ls, -1)) sp->font_size = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);

            lua_getfield(ls, -1, "align");
            const char *al = lua_tostring(ls, -1);
            sp->align = parse_align_str(al);
            lua_pop(ls, 1);

            rich->count++;
        }
        lua_pop(ls, 1);
    }
}

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
    lua_pushcfunction(L, l_http_put);
    lua_setfield(L, -2, "put");
    lua_pushcfunction(L, l_http_delete);
    lua_setfield(L, -2, "delete");
    lua_setglobal(L, "http");

    /* Register font() rich text API */
    register_font_api(L);

    /* Register sys.* system info API */
    sysinfo_register_lua(L);
}

void script_shutdown(void) {
    if (L) { lua_close(L); L = NULL; }
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

    /* Check if 1st return is a rich span/spanlist */
    result->rich.count = 0;
    if (nresults >= 1 && lua_istable(L, 1) && is_span(L, 1)) {
        parse_rich_result(L, 1, &result->rich);
        /* Build plain display as fallback */
        result->display[0] = L'\0';
        for (int i = 0; i < result->rich.count; i++) {
            lstrcatW(result->display, result->rich.spans[i].text);
        }
    } else if (nresults >= 1) {
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
    return (result->display[0] != L'\0' || result->rich.count > 0);
}

/* ─── execute Lua file ─── */

static void resolve_lua_path(const WCHAR *lua_path, WCHAR *full_path) {
    if (lua_path[0] != L'\\' && lua_path[0] != L'/' &&
        !(lua_path[0] && lua_path[1] == L':')) {
        GetModuleFileNameW(NULL, full_path, MAX_PATH);
        WCHAR *slash = wcsrchr(full_path, L'\\');
        if (slash) *(slash + 1) = L'\0';
        lstrcatW(full_path, lua_path);
    } else {
        lstrcpynW(full_path, lua_path, MAX_PATH);
    }
}

BOOL script_exec_file(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                      ScriptResult *result) {
    if (!L || !lua_path || !lua_path[0] || !result) return FALSE;

    result->display[0] = L'\0';
    result->clickable = FALSE;
    result->click_url[0] = L'\0';

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    /* Inject args table */
    lua_newtable(L);
    for (int i = 0; i < param_count; i++) {
        if (params[i].key[0]) {
            char k8[CFG_MAX_PARAM_KEY], v8[CFG_MAX_PARAM_VAL];
            WideCharToMultiByte(CP_UTF8, 0, params[i].key, -1, k8, sizeof(k8), NULL, NULL);
            WideCharToMultiByte(CP_UTF8, 0, params[i].value, -1, v8, sizeof(v8), NULL, NULL);
            lua_pushstring(L, v8);
            lua_setfield(L, -2, k8);
        }
    }
    lua_setglobal(L, "args");

    char path8[512];
    WideCharToMultiByte(CP_UTF8, 0, full_path, -1, path8, 512, NULL, NULL);

    if (luaL_dofile(L, path8) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        if (err) MultiByteToWideChar(CP_UTF8, 0, err, -1, result->display, 2048);
        else lstrcpyW(result->display, L"[lua error]");
        lua_settop(L, 0);
        return TRUE;
    }

    int nresults = lua_gettop(L);
    result->rich.count = 0;
    if (nresults >= 1 && lua_istable(L, 1) && is_span(L, 1)) {
        parse_rich_result(L, 1, &result->rich);
        result->display[0] = L'\0';
        for (int i = 0; i < result->rich.count; i++) {
            lstrcatW(result->display, result->rich.spans[i].text);
        }
    } else if (nresults >= 1) {
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
    return (result->display[0] != L'\0' || result->rich.count > 0);
}

/* ─── parse @param declarations ─── */

int script_parse_params(const WCHAR *lua_path, ScriptParamDecl *decls, int max_decls) {
    if (!lua_path || !lua_path[0]) return 0;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return 0;

    int count = 0;
    char line[512];
    while (fgets(line, sizeof(line), f) && count < max_decls) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@param", 6) != 0) continue;
        p += 6;
        while (*p == ' ') p++;

        char *start = p;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
        int klen = (int)(p - start);
        if (klen <= 0 || klen >= 64) continue;
        memcpy(decls[count].key, start, klen);
        decls[count].key[klen] = '\0';

        while (*p == ' ' || *p == '\t') p++;
        start = p;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
        int tlen = (int)(p - start);
        if (tlen >= 16) tlen = 15;
        memcpy(decls[count].type, start, tlen);
        decls[count].type[tlen] = '\0';

        while (*p == ' ' || *p == '\t') p++;
        start = p;
        int llen = (int)strlen(start);
        while (llen > 0 && (start[llen-1] == '\n' || start[llen-1] == '\r')) llen--;
        if (llen >= 128) llen = 127;
        memcpy(decls[count].label, start, llen);
        decls[count].label[llen] = '\0';

        count++;
    }
    fclose(f);
    return count;
}