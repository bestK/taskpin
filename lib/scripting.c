#include "scripting.h"
#include "sysinfo.h"
#include "image.h"
#include "event.h"
#include "logger.h"
#include "i18n.h"
#include "websocket.h"
#include "hotkey.h"
#include "script_dialog.h"
#include "lua/lua.h"
#include "lua/lauxlib.h"
#include "lua/lualib.h"
#include "cJSON.h"
#include <winhttp.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

static lua_State *L = NULL;
static CRITICAL_SECTION g_lua_cs;

static void script_log_write(const char *msg) {
    if (!msg) return;
    WCHAR log_path[MAX_PATH];
    GetModuleFileNameW(NULL, log_path, MAX_PATH);
    WCHAR *slash = wcsrchr(log_path, L'\\');
    if (slash) *(slash + 1) = L'\0';
    lstrcatW(log_path, L"taskpin.log");

    /* Rotate: if file > 64KB, truncate */
    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (GetFileAttributesExW(log_path, GetFileExInfoStandard, &fad)) {
        if (fad.nFileSizeLow > 65536) {
            DeleteFileW(log_path);
        }
    }

    FILE *f = _wfopen(log_path, L"a");
    if (!f) return;
    SYSTEMTIME st;
    GetLocalTime(&st);
    fprintf(f, "[%04d-%02d-%02d %02d:%02d:%02d] %s\n",
        st.wYear, st.wMonth, st.wDay,
        st.wHour, st.wMinute, st.wSecond, msg);
    fclose(f);
}

/* ??? built-in json.decode for Lua ??? */

static void push_cjson_node(lua_State *ls, cJSON *item);

static void push_cjson_node(lua_State *ls, cJSON *item) {
    if (!item) { lua_pushnil(ls); return; }
    if (cJSON_IsNull(item)) {
        lua_pushnil(ls);
    } else if (cJSON_IsBool(item)) {
        lua_pushboolean(ls, item->valueint);
    } else if (cJSON_IsNumber(item)) {
        lua_pushnumber(ls, item->valuedouble);
    } else if (cJSON_IsString(item)) {
        lua_pushstring(ls, item->valuestring ? item->valuestring : "");
    } else if (cJSON_IsObject(item)) {
        lua_newtable(ls);
        cJSON *child = NULL;
        cJSON_ArrayForEach(child, item) {
            if (child->string) {
                lua_pushstring(ls, child->string);
                push_cjson_node(ls, child);
                lua_settable(ls, -3);
            }
        }
    } else if (cJSON_IsArray(item)) {
        lua_newtable(ls);
        int idx = 1;
        cJSON *child = NULL;
        cJSON_ArrayForEach(child, item) {
            lua_pushinteger(ls, idx);
            push_cjson_node(ls, child);
            lua_settable(ls, -3);
            idx++;
        }
    } else {
        lua_pushnil(ls);
    }
}

static int l_json_decode(lua_State *ls) {
    const char *str = luaL_checkstring(ls, 1);
    cJSON *root = cJSON_Parse(str);
    if (!root) { lua_pushnil(ls); return 1; }
    push_cjson_node(ls, root);
    cJSON_Delete(root);
    return 1;
}

/* ??? json.encode: Lua table ??JSON string ??? */

static cJSON *lua_to_cjson(lua_State *ls, int idx) {
    idx = lua_absindex(ls, idx);
    int t = lua_type(ls, idx);
    switch (t) {
    case LUA_TNIL:
        return cJSON_CreateNull();
    case LUA_TBOOLEAN:
        return cJSON_CreateBool(lua_toboolean(ls, idx));
    case LUA_TNUMBER:
        if (lua_isinteger(ls, idx))
            return cJSON_CreateNumber((double)lua_tointeger(ls, idx));
        else
            return cJSON_CreateNumber(lua_tonumber(ls, idx));
    case LUA_TSTRING:
        return cJSON_CreateString(lua_tostring(ls, idx));
    case LUA_TTABLE: {
        /* Detect array vs object: if key 1 exists, treat as array */
        lua_rawgeti(ls, idx, 1);
        BOOL is_array = !lua_isnil(ls, -1);
        lua_pop(ls, 1);
        if (is_array) {
            cJSON *arr = cJSON_CreateArray();
            int len = (int)lua_rawlen(ls, idx);
            for (int i = 1; i <= len; i++) {
                lua_rawgeti(ls, idx, i);
                cJSON *item = lua_to_cjson(ls, -1);
                lua_pop(ls, 1);
                if (item) cJSON_AddItemToArray(arr, item);
            }
            return arr;
        } else {
            cJSON *obj = cJSON_CreateObject();
            lua_pushnil(ls);
            while (lua_next(ls, idx) != 0) {
                if (lua_type(ls, -2) == LUA_TSTRING) {
                    const char *key = lua_tostring(ls, -2);
                    cJSON *val = lua_to_cjson(ls, -1);
                    if (val) cJSON_AddItemToObject(obj, key, val);
                }
                lua_pop(ls, 1);
            }
            return obj;
        }
    }
    default:
        return cJSON_CreateNull();
    }
}

static int l_json_encode(lua_State *ls) {
    BOOL pretty = lua_toboolean(ls, 2);
    cJSON *root = lua_to_cjson(ls, 1);
    if (!root) {
        lua_pushstring(ls, "null");
        return 1;
    }
    char *str = pretty ? cJSON_Print(root) : cJSON_PrintUnformatted(root);
    lua_pushstring(ls, str ? str : "null");
    if (str) cJSON_free(str);
    cJSON_Delete(root);
    return 1;
}

/* ??? built-in http.get / http.post for Lua ??? */

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

/* ??? log() for Lua ??? */

static void lua_log_with_level(lua_State *ls, int level) {
    int n = lua_gettop(ls);
    luaL_Buffer buf;
    luaL_buffinit(ls, &buf);
    for (int i = 1; i <= n; i++) {
        const char *s = luaL_tolstring(ls, i, NULL);
        if (s) luaL_addstring(&buf, s);
        lua_pop(ls, 1);
        if (i < n) luaL_addchar(&buf, '\t');
    }
    luaL_pushresult(&buf);
    const char *msg = lua_tostring(ls, -1);

    /* Get caller info from lua debug */
    lua_Debug ar;
    const char *src = "?";
    int line = 0;
    if (lua_getstack(ls, 1, &ar)) {
        lua_getinfo(ls, "Sl", &ar);
        if (ar.source && ar.source[0] == '@') src = ar.source + 1;
        else if (ar.source) src = ar.source;
        line = ar.currentline;
    }
    /* Extract basename */
    const char *basename = src;
    const char *p = src;
    while (*p) { if (*p == '\\' || *p == '/') basename = p + 1; p++; }

    logger_write_impl(level, basename, line, NULL, "%s", msg);
    lua_pop(ls, 1);
}

static int l_log_info(lua_State *ls) { lua_log_with_level(ls, LOG_INFO); return 0; }
static int l_log_debug(lua_State *ls) { lua_log_with_level(ls, LOG_DEBUG); return 0; }
static int l_log_error(lua_State *ls) { lua_log_with_level(ls, LOG_ERROR); return 0; }

static int l_log(lua_State *ls) { lua_remove(ls, 1); lua_log_with_level(ls, LOG_INFO); return 0; }

/* ??? init / shutdown ??? */

/* ??? font() span system for rich text ??? */

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

/* icon(source, width, height, align) -> span table with __is_image marker */
static int l_icon(lua_State *ls) {
    const char *source = luaL_checkstring(ls, 1);
    int img_w = 16, img_h = 16;
    const char *align_str = NULL;

    if (lua_gettop(ls) >= 2 && !lua_isnil(ls, 2))
        img_w = (int)lua_tointeger(ls, 2);
    if (lua_gettop(ls) >= 3 && !lua_isnil(ls, 3))
        img_h = (int)lua_tointeger(ls, 3);
    if (lua_gettop(ls) >= 4 && !lua_isnil(ls, 4))
        align_str = lua_tostring(ls, 4);

    lua_newtable(ls);

    lua_pushstring(ls, source);
    lua_setfield(ls, -2, "img_source");

    lua_pushinteger(ls, img_w);
    lua_setfield(ls, -2, "img_w");

    lua_pushinteger(ls, img_h);
    lua_setfield(ls, -2, "img_h");

    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_image");

    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_span");

    if (align_str) {
        lua_pushstring(ls, align_str);
        lua_setfield(ls, -2, "align");
    }

    /* Set the span metatable for __concat support */
    luaL_getmetatable(ls, SPAN_MT);
    lua_setmetatable(ls, -2);

    return 1;
}

/* button(text, cmd, bg, color, size) -> span table with __is_button marker */
static int l_button(lua_State *ls) {
    const char *text = luaL_checkstring(ls, 1);
    const char *cmd = NULL;
    const char *bg_str = NULL;
    const char *color_str = NULL;
    int font_size = 0;

    if (lua_gettop(ls) >= 2 && !lua_isnil(ls, 2))
        cmd = lua_tostring(ls, 2);
    if (lua_gettop(ls) >= 3 && !lua_isnil(ls, 3))
        bg_str = lua_tostring(ls, 3);
    if (lua_gettop(ls) >= 4 && !lua_isnil(ls, 4))
        color_str = lua_tostring(ls, 4);
    if (lua_gettop(ls) >= 5 && !lua_isnil(ls, 5))
        font_size = (int)lua_tointeger(ls, 5);

    lua_newtable(ls);

    lua_pushstring(ls, text);
    lua_setfield(ls, -2, "text");

    if (cmd) {
        lua_pushstring(ls, cmd);
        lua_setfield(ls, -2, "cmd");
    }

    if (bg_str) {
        lua_pushstring(ls, bg_str);
        lua_setfield(ls, -2, "bg_color");
    }

    if (color_str) {
        lua_pushstring(ls, color_str);
        lua_setfield(ls, -2, "color");
    }

    if (font_size > 0) {
        lua_pushinteger(ls, font_size);
        lua_setfield(ls, -2, "size");
    }

    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_button");

    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_span");

    luaL_getmetatable(ls, SPAN_MT);
    lua_setmetatable(ls, -2);

    return 1;
}

/* input(name, placeholder, width, height, bg, color, border) -> span */
static int l_input(lua_State *ls) {
    const char *name = luaL_checkstring(ls, 1);
    const char *placeholder = "";
    if (lua_gettop(ls) >= 2 && !lua_isnil(ls, 2))
        placeholder = lua_tostring(ls, 2);

    lua_newtable(ls);

    lua_pushstring(ls, name);
    lua_setfield(ls, -2, "name");

    lua_pushstring(ls, placeholder);
    lua_setfield(ls, -2, "placeholder");

    if (lua_gettop(ls) >= 3 && !lua_isnil(ls, 3)) {
        lua_pushinteger(ls, lua_tointeger(ls, 3));
        lua_setfield(ls, -2, "width");
    }
    if (lua_gettop(ls) >= 4 && !lua_isnil(ls, 4)) {
        lua_pushinteger(ls, lua_tointeger(ls, 4));
        lua_setfield(ls, -2, "height");
    }
    if (lua_gettop(ls) >= 5 && !lua_isnil(ls, 5)) {
        lua_pushstring(ls, lua_tostring(ls, 5));
        lua_setfield(ls, -2, "bg_color");
    }
    if (lua_gettop(ls) >= 6 && !lua_isnil(ls, 6)) {
        lua_pushstring(ls, lua_tostring(ls, 6));
        lua_setfield(ls, -2, "color");
    }
    if (lua_gettop(ls) >= 7 && !lua_isnil(ls, 7)) {
        lua_pushstring(ls, lua_tostring(ls, 7));
        lua_setfield(ls, -2, "border_color");
    }

    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_input");

    lua_pushboolean(ls, 1);
    lua_setfield(ls, -2, "__is_span");

    luaL_getmetatable(ls, SPAN_MT);
    lua_setmetatable(ls, -2);

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

    /* Register global icon() */
    lua_pushcfunction(ls, l_icon);
    lua_setglobal(ls, "icon");

    /* Register global button() */
    lua_pushcfunction(ls, l_button);
    lua_setglobal(ls, "button");

    /* Register global input() */
    lua_pushcfunction(ls, l_input);
    lua_setglobal(ls, "input");
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
        DisplaySpan *sp = &rich->spans[0];
        memset(sp, 0, sizeof(DisplaySpan));
        sp->color = 0xFFFFFFFF;

        /* Check if it's an image span */
        lua_getfield(ls, idx, "__is_image");
        BOOL is_img = lua_toboolean(ls, -1);
        lua_pop(ls, 1);

        if (is_img) {
            sp->is_image = TRUE;
            lua_getfield(ls, idx, "img_source");
            const char *src = lua_tostring(ls, -1);
            if (src) strncpy(sp->img_source, src, IMG_SOURCE_MAX - 1);
            lua_pop(ls, 1);
            lua_getfield(ls, idx, "img_w");
            if (!lua_isnil(ls, -1)) sp->img_w = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, idx, "img_h");
            if (!lua_isnil(ls, -1)) sp->img_h = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, idx, "align");
            const char *a = lua_tostring(ls, -1);
            sp->align = parse_align_str(a);
            lua_pop(ls, 1);
            rich->count = 1;
            return;
        }

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
            /* Button fields for single span */
            lua_getfield(ls, idx, "__is_button");
            if (lua_toboolean(ls, -1)) {
                sp->is_button = TRUE;
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "cmd");
                const char *bc = lua_tostring(ls, -1);
                if (bc) strncpy(sp->cmd, bc, 511);
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "response");
                const char *br = lua_tostring(ls, -1);
                if (br) strncpy(sp->response, br, 4095);
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "bg_color");
                const char *bg = lua_tostring(ls, -1);
                if (bg) sp->bg_color = parse_color_str(bg);
                else sp->bg_color = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "hover_bg");
                const char *hbg = lua_tostring(ls, -1);
                if (hbg) sp->hover_bg = parse_color_str(hbg);
                else sp->hover_bg = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "hover_color");
                const char *hc = lua_tostring(ls, -1);
                if (hc) sp->hover_color = parse_color_str(hc);
                else sp->hover_color = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "border_color");
                const char *brc = lua_tostring(ls, -1);
                if (brc) sp->border_color = parse_color_str(brc);
                else sp->border_color = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "margin");
                if (!lua_isnil(ls, -1)) sp->margin = (int)lua_tointeger(ls, -1);
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "patch_local");
                const char *pl = lua_tostring(ls, -1);
                if (pl) strncpy(sp->patch_local, pl, 511);
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "patch_global");
                const char *pg = lua_tostring(ls, -1);
                if (pg) strncpy(sp->patch_global, pg, 511);
                lua_pop(ls, 1);
            } else {
                lua_pop(ls, 1);
                lua_getfield(ls, idx, "__is_input");
                if (lua_toboolean(ls, -1)) {
                    sp->is_input = TRUE;
                    lua_pop(ls, 1);
                    lua_getfield(ls, idx, "name");
                    const char *nm = lua_tostring(ls, -1);
                    if (nm) strncpy(sp->prompt, nm, 255);
                    lua_pop(ls, 1);
                    lua_getfield(ls, idx, "placeholder");
                    const char *ph = lua_tostring(ls, -1);
                    if (ph) strncpy(sp->placeholder, ph, 255);
                    lua_pop(ls, 1);
                    lua_getfield(ls, idx, "width");
                    if (!lua_isnil(ls, -1)) sp->input_w = (int)lua_tointeger(ls, -1);
                    lua_pop(ls, 1);
                    lua_getfield(ls, idx, "height");
                    if (!lua_isnil(ls, -1)) sp->input_h = (int)lua_tointeger(ls, -1);
                    lua_pop(ls, 1);
                    lua_getfield(ls, idx, "bg_color");
                    const char *bg = lua_tostring(ls, -1);
                    if (bg) sp->bg_color = parse_color_str(bg);
                    lua_pop(ls, 1);
                    lua_getfield(ls, idx, "color");
                    const char *clr = lua_tostring(ls, -1);
                    if (clr) sp->color = parse_color_str(clr);
                    lua_pop(ls, 1);
                    lua_getfield(ls, idx, "border_color");
                    const char *bdr = lua_tostring(ls, -1);
                    if (bdr) sp->border_color = parse_color_str(bdr);
                    lua_pop(ls, 1);
                } else {
                    lua_pop(ls, 1);
                }
            }
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
            memset(sp, 0, sizeof(DisplaySpan));
            sp->color = 0xFFFFFFFF;
            sp->font_size = 0;
            sp->align = SPAN_ALIGN_LEFT;
            sp->newline = FALSE;

            /* Check if this span is an image */
            lua_getfield(ls, -1, "__is_image");
            BOOL is_img = lua_toboolean(ls, -1);
            lua_pop(ls, 1);

            if (is_img) {
                sp->is_image = TRUE;
                lua_getfield(ls, -1, "img_source");
                const char *src = lua_tostring(ls, -1);
                if (src) strncpy(sp->img_source, src, IMG_SOURCE_MAX - 1);
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "img_w");
                if (!lua_isnil(ls, -1)) sp->img_w = (int)lua_tointeger(ls, -1);
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "img_h");
                if (!lua_isnil(ls, -1)) sp->img_h = (int)lua_tointeger(ls, -1);
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "align");
                const char *al = lua_tostring(ls, -1);
                sp->align = parse_align_str(al);
                lua_pop(ls, 1);
                rich->count++;
                lua_pop(ls, 1);
                continue;
            }

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

            /* Button fields */
            lua_getfield(ls, -1, "__is_button");
            if (lua_toboolean(ls, -1)) {
                sp->is_button = TRUE;
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "cmd");
                const char *bc = lua_tostring(ls, -1);
                if (bc) strncpy(sp->cmd, bc, 511);
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "response");
                const char *br = lua_tostring(ls, -1);
                if (br) strncpy(sp->response, br, 4095);
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "bg_color");
                const char *bg = lua_tostring(ls, -1);
                if (bg) sp->bg_color = parse_color_str(bg);
                else sp->bg_color = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "hover_bg");
                const char *hbg = lua_tostring(ls, -1);
                if (hbg) sp->hover_bg = parse_color_str(hbg);
                else sp->hover_bg = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "hover_color");
                const char *hc = lua_tostring(ls, -1);
                if (hc) sp->hover_color = parse_color_str(hc);
                else sp->hover_color = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "border_color");
                const char *brc = lua_tostring(ls, -1);
                if (brc) sp->border_color = parse_color_str(brc);
                else sp->border_color = 0xFFFFFFFF;
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "margin");
                if (!lua_isnil(ls, -1)) sp->margin = (int)lua_tointeger(ls, -1);
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "patch_local");
                const char *pl = lua_tostring(ls, -1);
                if (pl) strncpy(sp->patch_local, pl, 511);
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "patch_global");
                const char *pg = lua_tostring(ls, -1);
                if (pg) strncpy(sp->patch_global, pg, 511);
                lua_pop(ls, 1);
            } else {
                lua_pop(ls, 1);
                lua_getfield(ls, -1, "__is_input");
                if (lua_toboolean(ls, -1)) {
                    sp->is_input = TRUE;
                    lua_pop(ls, 1);
                    lua_getfield(ls, -1, "name");
                    const char *nm = lua_tostring(ls, -1);
                    if (nm) strncpy(sp->prompt, nm, 255);
                    lua_pop(ls, 1);
                    lua_getfield(ls, -1, "placeholder");
                    const char *ph = lua_tostring(ls, -1);
                    if (ph) strncpy(sp->placeholder, ph, 255);
                    lua_pop(ls, 1);
                    lua_getfield(ls, -1, "width");
                    if (!lua_isnil(ls, -1)) sp->input_w = (int)lua_tointeger(ls, -1);
                    lua_pop(ls, 1);
                    lua_getfield(ls, -1, "height");
                    if (!lua_isnil(ls, -1)) sp->input_h = (int)lua_tointeger(ls, -1);
                    lua_pop(ls, 1);
                    lua_getfield(ls, -1, "bg_color");
                    const char *bg = lua_tostring(ls, -1);
                    if (bg) sp->bg_color = parse_color_str(bg);
                    lua_pop(ls, 1);
                    lua_getfield(ls, -1, "color");
                    const char *clr = lua_tostring(ls, -1);
                    if (clr) sp->color = parse_color_str(clr);
                    lua_pop(ls, 1);
                    lua_getfield(ls, -1, "border_color");
                    const char *bdr = lua_tostring(ls, -1);
                    if (bdr) sp->border_color = parse_color_str(bdr);
                    lua_pop(ls, 1);
                } else {
                    lua_pop(ls, 1);
                }
            }

            rich->count++;
        }
        lua_pop(ls, 1);
    }
}

/* ??? dialog() Lua function ??? */

static int l_dialog(lua_State *ls) {
    if (!lua_istable(ls, 1)) {
        lua_newtable(ls);
        return 1;
    }

    lua_getglobal(ls, "__dialog_open");
    BOOL dlg_open = lua_toboolean(ls, -1);
    lua_pop(ls, 1);

    if (dlg_open) {
        /* Dialog is open: if render function exists, call it to produce content */
        lua_getfield(ls, 1, "render");
        if (lua_isfunction(ls, -1)) {
            if (lua_pcall(ls, 0, 1, 0) == LUA_OK && lua_istable(ls, -1)) {
                lua_setfield(ls, 1, "content");
            } else {
                const char *err = lua_tostring(ls, -1);
                if (err) logger_write(LOG_ERROR, "render: %s", err);
                lua_pop(ls, 1);
            }
        } else {
            lua_pop(ls, 1);
        }
    } else {
        /* Dialog not open: strip content to skip C-side parsing */
        lua_pushnil(ls);
        lua_setfield(ls, 1, "content");
    }

    /* Clear render function before returning (not needed in spec) */
    lua_pushnil(ls);
    lua_setfield(ls, 1, "render");

    lua_pushboolean(ls, 1);
    lua_setfield(ls, 1, "_dialog");
    lua_pushvalue(ls, 1);
    return 1;
}

/* Parse a dialog spec table from Lua stack at idx */
static void parse_dialog_spec(lua_State *ls, int idx, DialogSpec *spec) {
    memset(spec, 0, sizeof(DialogSpec));
    spec->width = 400;
    spec->height = 300;

    if (!lua_istable(ls, idx)) return;

    lua_getfield(ls, idx, "title");
    const char *title = lua_tostring(ls, -1);
    if (title) MultiByteToWideChar(CP_UTF8, 0, title, -1, spec->title, 128);
    else lstrcpyW(spec->title, L"Dialog");
    lua_pop(ls, 1);

    spec->title_bg_color = 0xFFFFFFFF;
    spec->title_color = 0xFFFFFFFF;
    lua_getfield(ls, idx, "title_bg_color");
    const char *tbg = lua_tostring(ls, -1);
    if (tbg) spec->title_bg_color = parse_color_str(tbg);
    lua_pop(ls, 1);
    lua_getfield(ls, idx, "title_color");
    const char *tfg = lua_tostring(ls, -1);
    if (tfg) spec->title_color = parse_color_str(tfg);
    lua_pop(ls, 1);

    spec->icon[0] = '\0';
    lua_getfield(ls, idx, "icon");
    const char *ico = lua_tostring(ls, -1);
    if (ico) strncpy(spec->icon, ico, 511);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "width");
    if (!lua_isnil(ls, -1)) spec->width = (int)lua_tointeger(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "height");
    if (!lua_isnil(ls, -1)) spec->height = (int)lua_tointeger(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "refresh");
    if (!lua_isnil(ls, -1)) spec->refresh = (int)lua_tointeger(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "x");
    spec->x = lua_isnil(ls, -1) ? -1 : (int)lua_tointeger(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "y");
    spec->y = lua_isnil(ls, -1) ? -1 : (int)lua_tointeger(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "borderless");
    spec->borderless = lua_toboolean(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "clickthrough");
    spec->clickthrough = lua_toboolean(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "transparent_bg");
    spec->transparent_bg = lua_toboolean(ls, -1);
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "opacity");
    if (!lua_isnil(ls, -1)) {
        spec->opacity = (int)lua_tointeger(ls, -1);
        if (spec->opacity < 0) spec->opacity = 0;
        if (spec->opacity > 255) spec->opacity = 255;
    } else {
        spec->opacity = 255;
    }
    lua_pop(ls, 1);

    lua_getfield(ls, idx, "content");
    if (!lua_istable(ls, -1)) { lua_pop(ls, 1); return; }

    int content_idx = lua_gettop(ls);
    int n = (int)lua_rawlen(ls, content_idx);
    if (n > DIALOG_MAX_ITEMS) n = DIALOG_MAX_ITEMS;

    for (int i = 1; i <= n; i++) {
        lua_rawgeti(ls, content_idx, i);
        if (!lua_istable(ls, -1)) { lua_pop(ls, 1); continue; }

        DialogItem *item = &spec->items[spec->item_count];
        memset(item, 0, sizeof(DialogItem));
        item->color = 0xFFFFFFFF;
        item->bg_color = 0xFFFFFFFF;

        lua_getfield(ls, -1, "type");
        const char *type = lua_tostring(ls, -1);
        if (!type) { lua_pop(ls, 2); continue; }

        if (strcmp(type, "text") == 0) {
            item->type = DI_TEXT;
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "value");
            const char *val = lua_tostring(ls, -1);
            if (val) MultiByteToWideChar(CP_UTF8, 0, val, -1, item->text, 256);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "color");
            const char *c = lua_tostring(ls, -1);
            if (c) item->color = parse_color_str(c);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "size");
            if (!lua_isnil(ls, -1)) item->font_size = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "bold");
            item->bold = lua_toboolean(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "image");
            const char *ico = lua_tostring(ls, -1);
            if (ico) strncpy(item->img_source, ico, 511);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "image_width");
            item->width = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "image_height");
            item->height = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "align");
            const char *ta = lua_tostring(ls, -1);
            if (ta) {
                if (strcmp(ta, "center") == 0) item->align = ALIGN_CENTER;
                else if (strcmp(ta, "right") == 0) item->align = ALIGN_RIGHT;
            }
            lua_pop(ls, 1);
        } else if (strcmp(type, "hr") == 0) {
            item->type = DI_HR;
            lua_pop(ls, 1);
        } else if (strcmp(type, "table") == 0) {
            item->type = DI_TABLE;
            lua_pop(ls, 1);

            /* Parse columns */
            lua_getfield(ls, -1, "columns");
            if (lua_istable(ls, -1)) {
                int nc = (int)lua_rawlen(ls, -1);
                if (nc > DIALOG_MAX_COLS) nc = DIALOG_MAX_COLS;
                item->col_count = nc;
                for (int c = 1; c <= nc; c++) {
                    lua_rawgeti(ls, -1, c);
                    const char *cs = lua_tostring(ls, -1);
                    if (cs) MultiByteToWideChar(CP_UTF8, 0, cs, -1, item->columns[c-1], 64);
                    lua_pop(ls, 1);
                }
            }
            lua_pop(ls, 1);

            /* Parse col_widths */
            lua_getfield(ls, -1, "col_widths");
            if (lua_istable(ls, -1)) {
                int nw = (int)lua_rawlen(ls, -1);
                if (nw > item->col_count) nw = item->col_count;
                for (int c = 1; c <= nw; c++) {
                    lua_rawgeti(ls, -1, c);
                    item->col_widths[c-1] = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
                    lua_pop(ls, 1);
                }
            }
            lua_pop(ls, 1);

            /* Row height */
            lua_getfield(ls, -1, "height");
            if (!lua_isnil(ls, -1)) item->height = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);

            /* Word wrap */
            lua_getfield(ls, -1, "wrap");
            item->word_wrap = lua_toboolean(ls, -1);
            lua_pop(ls, 1);

            /* Parse rows */
            lua_getfield(ls, -1, "rows");
            if (lua_istable(ls, -1)) {
                int nr = (int)lua_rawlen(ls, -1);
                if (nr > DIALOG_MAX_ROWS) nr = DIALOG_MAX_ROWS;
                item->row_count = nr;
                for (int r = 1; r <= nr; r++) {
                    lua_rawgeti(ls, -1, r);
                    if (lua_istable(ls, -1)) {
                        int rc = (int)lua_rawlen(ls, -1);
                        if (rc > item->col_count) rc = item->col_count;
                        for (int c = 1; c <= rc; c++) {
                            lua_rawgeti(ls, -1, c);
                            const char *cv = lua_tostring(ls, -1);
                            if (cv) MultiByteToWideChar(CP_UTF8, 0, cv, -1, item->cells[r-1][c-1], 64);
                            lua_pop(ls, 1);
                        }
                        /* Check for url field in row table */
                        lua_getfield(ls, -1, "url");
                        const char *rurl = lua_tostring(ls, -1);
                        if (rurl) strncpy(item->row_urls[r-1], rurl, 255);
                        lua_pop(ls, 1);
                        lua_getfield(ls, -1, "cmd");
                        const char *rcmd = lua_tostring(ls, -1);
                        if (rcmd) strncpy(item->row_cmds[r-1], rcmd, 255);
                        lua_pop(ls, 1);
                        lua_getfield(ls, -1, "lua");
                        const char *rlua = lua_tostring(ls, -1);
                        if (rlua) strncpy(item->row_luas[r-1], rlua, 255);
                        lua_pop(ls, 1);
                        lua_getfield(ls, -1, "btn_text");
                        const char *rbt = lua_tostring(ls, -1);
                        if (rbt) MultiByteToWideChar(CP_UTF8, 0, rbt, -1, item->row_btn_text[r-1], 32);
                        lua_pop(ls, 1);
                    }
                    lua_pop(ls, 1);
                }
            }
            lua_pop(ls, 1);
        } else if (strcmp(type, "image") == 0) {
            item->type = DI_IMG;
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "source");
            const char *src = lua_tostring(ls, -1);
            if (src) strncpy(item->img_source, src, 511);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "width");
            item->width = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "height");
            item->height = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "src_x");
            item->src_x = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "src_y");
            item->src_y = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "src_w");
            item->src_w = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "src_h");
            item->src_h = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
        } else if (strcmp(type, "button") == 0) {
            item->type = DI_BUTTON;
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "value");
            const char *val = lua_tostring(ls, -1);
            if (val) MultiByteToWideChar(CP_UTF8, 0, val, -1, item->text, 256);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "url");
            const char *u = lua_tostring(ls, -1);
            if (u) strncpy(item->url, u, 511);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "cmd");
            const char *cmd = lua_tostring(ls, -1);
            if (cmd) strncpy(item->cmd, cmd, 511);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "lua");
            const char *lcode = lua_tostring(ls, -1);
            if (lcode) strncpy(item->lua_code, lcode, 511);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "color");
            const char *c = lua_tostring(ls, -1);
            if (c) item->color = parse_color_str(c);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "bg_color");
            const char *bg = lua_tostring(ls, -1);
            if (bg) item->bg_color = parse_color_str(bg);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "size");
            if (!lua_isnil(ls, -1)) item->font_size = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "width");
            if (!lua_isnil(ls, -1)) item->width = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "height");
            if (!lua_isnil(ls, -1)) item->height = (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "align");
            const char *align = lua_tostring(ls, -1);
            if (align) {
                if (strcmp(align, "center") == 0) item->align = ALIGN_CENTER;
                else if (strcmp(align, "right") == 0) item->align = ALIGN_RIGHT;
                else if (strcmp(align, "inline") == 0) item->align = ALIGN_INLINE;
            }
            lua_pop(ls, 1);
        } else if (strcmp(type, "webview") == 0) {
            item->type = DI_WEBVIEW;
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "url");
            const char *u = lua_tostring(ls, -1);
            if (u) strncpy(item->url, u, 511);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "width");
            item->width = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
            lua_getfield(ls, -1, "height");
            item->height = lua_isnil(ls, -1) ? 0 : (int)lua_tointeger(ls, -1);
            lua_pop(ls, 1);
        } else {
            lua_pop(ls, 1);
            lua_pop(ls, 1);
            continue;
        }

        spec->item_count++;
        lua_pop(ls, 1); /* pop content item table */
    }
    lua_pop(ls, 1); /* pop content table */
}

/* Check if value at idx is a dialog spec (has _dialog marker) */
static BOOL is_dialog_table(lua_State *ls, int idx) {
    if (!lua_istable(ls, idx)) return FALSE;
    lua_getfield(ls, idx, "_dialog");
    BOOL r = lua_toboolean(ls, -1);
    lua_pop(ls, 1);
    return r;
}

/* --- open_dialog / close_dialog Lua bindings --- */

static WCHAR g_current_lua_path[MAX_PATH];
extern TaskPinConfig g_cfg;

static int l_open_dialog(lua_State *ls) {
    if (lua_gettop(ls) >= 1 && lua_istable(ls, 1)) {
        DialogSpec spec;
        parse_dialog_spec(ls, 1, &spec);
        if (spec.refresh <= 0) spec.refresh = 1000;
        show_script_dialog(g_current_lua_path, NULL, 0, &spec);
    } else {
        int refresh = script_parse_refresh(g_current_lua_path);
        if (refresh <= 0) refresh = 1000;
        const ParamEntry *params = NULL;
        int param_count = 0;
        for (int i = 0; i < g_cfg.count; i++) {
            if (lstrcmpiW(g_cfg.items[i].lua_path, g_current_lua_path) == 0) {
                params = g_cfg.items[i].params;
                param_count = g_cfg.items[i].param_count;
                break;
            }
        }
        DialogSpec spec;
        memset(&spec, 0, sizeof(spec));
        spec.width = 400;
        spec.height = 300;
        spec.refresh = refresh;
        spec.opacity = 255;
        spec.x = -1;
        spec.y = -1;
        lstrcpyW(spec.title, L"Dialog");
        show_script_dialog(g_current_lua_path, params, param_count, &spec);
    }
    return 0;
}

static int l_close_dialog(lua_State *ls) {
    (void)ls;
    script_dialog_close_by_path(g_current_lua_path);
    return 0;
}

static int l_dialog_is_open(lua_State *ls) {
    (void)ls;
    lua_pushboolean(ls, script_dialog_is_open(g_current_lua_path));
    return 1;
}

/* --- set_bar_text / set_bar_lua --- */

extern void bar_update_display(const WCHAR *lua_path, const WCHAR *text, const DisplayContent *rich);

static int l_set_bar_text(lua_State *ls) {
    const char *text = luaL_checkstring(ls, 1);
    WCHAR wtext[2048];
    MultiByteToWideChar(CP_UTF8, 0, text, -1, wtext, 2048);
    bar_update_display(g_current_lua_path, wtext, NULL);
    lua_pushstring(ls, text);
    lua_setglobal(ls, "__bar_text");
    return 0;
}

static int l_set_bar_lua(lua_State *ls) {
    const char *code = luaL_checkstring(ls, 1);
    char wrapped[4096];
    snprintf(wrapped, sizeof(wrapped), "return %s", code);
    if (luaL_dostring(ls, wrapped) == LUA_OK) {
        int nresults = lua_gettop(ls);
        if (nresults >= 1 && lua_istable(ls, -1)) {
            DisplayContent rich;
            parse_rich_result(ls, -1, &rich);
            WCHAR plain[2048] = {0};
            for (int i = 0; i < rich.count; i++)
                lstrcatW(plain, rich.spans[i].text);
            bar_update_display(g_current_lua_path, plain, &rich);
        } else if (nresults >= 1) {
            const char *s = lua_tostring(ls, -1);
            if (s) {
                WCHAR wtext[2048];
                MultiByteToWideChar(CP_UTF8, 0, s, -1, wtext, 2048);
                bar_update_display(g_current_lua_path, wtext, NULL);
            }
        }
        lua_settop(ls, 0);
        lua_pushstring(ls, code);
        lua_setglobal(ls, "__bar_lua");
    } else {
        const char *err = lua_tostring(ls, -1);
        if (err) logger_write(LOG_ERROR, "set_bar_lua: %s", err);
        lua_pop(ls, 1);
    }
    return 0;
}

/* --- Animation Lua bindings (anim.*) --- */

#define ANIM_REGISTRY_KEY "taskpin_anim_starts"

static DWORD anim_get_start(lua_State *ls, const char *id) {
    lua_getfield(ls, LUA_REGISTRYINDEX, ANIM_REGISTRY_KEY);
    if (lua_isnil(ls, -1)) {
        lua_pop(ls, 1);
        lua_newtable(ls);
        lua_pushvalue(ls, -1);
        lua_setfield(ls, LUA_REGISTRYINDEX, ANIM_REGISTRY_KEY);
    }
    lua_getfield(ls, -1, id);
    DWORD start;
    if (lua_isnil(ls, -1)) {
        start = GetTickCount();
        lua_pop(ls, 1);
        lua_pushinteger(ls, (lua_Integer)start);
        lua_setfield(ls, -2, id);
    } else {
        start = (DWORD)lua_tointeger(ls, -1);
        lua_pop(ls, 1);
    }
    lua_pop(ls, 1);
    return start;
}

static double anim_clamp(double v, double lo, double hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static int l_anim_elapsed(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    DWORD start = anim_get_start(ls, id);
    lua_pushinteger(ls, (lua_Integer)(GetTickCount() - start));
    return 1;
}

static int l_anim_reset(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    lua_getfield(ls, LUA_REGISTRYINDEX, ANIM_REGISTRY_KEY);
    if (!lua_isnil(ls, -1)) {
        lua_pushnil(ls);
        lua_setfield(ls, -2, id);
    }
    lua_pop(ls, 1);
    return 0;
}

static int l_anim_blink(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int interval = luaL_optinteger(ls, 2, 500);
    if (interval <= 0) interval = 500;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    lua_pushboolean(ls, ((int)(elapsed / interval) % 2) == 0);
    return 1;
}

static int l_anim_progress(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int duration = luaL_optinteger(ls, 2, 1000);
    if (duration <= 0) duration = 1000;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double t = anim_clamp((double)elapsed / duration, 0.0, 1.0);
    lua_pushnumber(ls, t);
    return 1;
}

static int l_anim_loop(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int period = luaL_optinteger(ls, 2, 1000);
    if (period <= 0) period = 1000;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double t = (double)(elapsed % period) / period;
    lua_pushnumber(ls, t);
    return 1;
}

static int l_anim_ping_pong(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int period = luaL_optinteger(ls, 2, 1000);
    if (period <= 0) period = 1000;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    int cycle = period * 2;
    int pos = (int)(elapsed % cycle);
    double t;
    if (pos < period) t = (double)pos / period;
    else t = 1.0 - (double)(pos - period) / period;
    lua_pushnumber(ls, t);
    return 1;
}

static int l_anim_fade_in(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int duration = luaL_optinteger(ls, 2, 500);
    if (duration <= 0) duration = 500;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double t = anim_clamp((double)elapsed / duration, 0.0, 1.0);
    lua_pushinteger(ls, (lua_Integer)(t * 255));
    return 1;
}

static int l_anim_fade_out(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int duration = luaL_optinteger(ls, 2, 500);
    if (duration <= 0) duration = 500;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double t = anim_clamp((double)elapsed / duration, 0.0, 1.0);
    lua_pushinteger(ls, (lua_Integer)((1.0 - t) * 255));
    return 1;
}

static int l_anim_scale(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int duration = luaL_optinteger(ls, 2, 500);
    double from = luaL_optnumber(ls, 3, 0.0);
    double to = luaL_optnumber(ls, 4, 1.0);
    if (duration <= 0) duration = 500;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double t = anim_clamp((double)elapsed / duration, 0.0, 1.0);
    lua_pushnumber(ls, from + (to - from) * t);
    return 1;
}

static int l_anim_pulse(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int period = luaL_optinteger(ls, 2, 1000);
    double lo = luaL_optnumber(ls, 3, 0.0);
    double hi = luaL_optnumber(ls, 4, 1.0);
    if (period <= 0) period = 1000;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double angle = 3.14159265358979 * 2.0 * (double)(elapsed % period) / period;
    double cos_val = (1.0 - cos(angle)) / 2.0;
    lua_pushnumber(ls, lo + (hi - lo) * cos_val);
    return 1;
}

static int l_anim_fly(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int duration = luaL_optinteger(ls, 2, 500);
    int from_x = (int)luaL_optinteger(ls, 3, 0);
    int from_y = (int)luaL_optinteger(ls, 4, 0);
    int to_x = (int)luaL_optinteger(ls, 5, 0);
    int to_y = (int)luaL_optinteger(ls, 6, 0);
    if (duration <= 0) duration = 500;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double t = anim_clamp((double)elapsed / duration, 0.0, 1.0);
    /* ease-out for natural fly feel */
    double et = 1.0 - (1.0 - t) * (1.0 - t);
    lua_pushinteger(ls, (lua_Integer)(from_x + (to_x - from_x) * et));
    lua_pushinteger(ls, (lua_Integer)(from_y + (to_y - from_y) * et));
    return 2;
}

static int l_anim_color(lua_State *ls) {
    const char *id = luaL_checkstring(ls, 1);
    int duration = luaL_optinteger(ls, 2, 500);
    const char *from_s = luaL_optstring(ls, 3, "#000000");
    const char *to_s = luaL_optstring(ls, 4, "#ffffff");
    if (duration <= 0) duration = 500;
    DWORD elapsed = GetTickCount() - anim_get_start(ls, id);
    double t = anim_clamp((double)elapsed / duration, 0.0, 1.0);

    unsigned int fr = 0, fg = 0, fb = 0, tr = 0, tg = 0, tb = 0;
    if (from_s[0] == '#') from_s++;
    if (to_s[0] == '#') to_s++;
    sscanf(from_s, "%2x%2x%2x", &fr, &fg, &fb);
    sscanf(to_s, "%2x%2x%2x", &tr, &tg, &tb);

    int r = (int)(fr + (tr - fr) * t);
    int g = (int)(fg + (tg - fg) * t);
    int b = (int)(fb + (tb - fb) * t);
    char buf[8];
    snprintf(buf, sizeof(buf), "#%02x%02x%02x", r, g, b);
    lua_pushstring(ls, buf);
    return 1;
}

static int l_anim_ease_in(lua_State *ls) {
    double t = luaL_checknumber(ls, 1);
    t = anim_clamp(t, 0.0, 1.0);
    lua_pushnumber(ls, t * t);
    return 1;
}

static int l_anim_ease_out(lua_State *ls) {
    double t = luaL_checknumber(ls, 1);
    t = anim_clamp(t, 0.0, 1.0);
    lua_pushnumber(ls, 1.0 - (1.0 - t) * (1.0 - t));
    return 1;
}

static int l_anim_ease_in_out(lua_State *ls) {
    double t = luaL_checknumber(ls, 1);
    t = anim_clamp(t, 0.0, 1.0);
    if (t < 0.5) lua_pushnumber(ls, 2.0 * t * t);
    else lua_pushnumber(ls, 1.0 - 2.0 * (1.0 - t) * (1.0 - t));
    return 1;
}

static int l_anim_bounce(lua_State *ls) {
    double t = luaL_checknumber(ls, 1);
    t = anim_clamp(t, 0.0, 1.0);
    double n;
    if (t < 1.0 / 2.75) n = 7.5625 * t * t;
    else if (t < 2.0 / 2.75) { t -= 1.5 / 2.75; n = 7.5625 * t * t + 0.75; }
    else if (t < 2.5 / 2.75) { t -= 2.25 / 2.75; n = 7.5625 * t * t + 0.9375; }
    else { t -= 2.625 / 2.75; n = 7.5625 * t * t + 0.984375; }
    lua_pushnumber(ls, n);
    return 1;
}

static int l_anim_lerp(lua_State *ls) {
    double a = luaL_checknumber(ls, 1);
    double b = luaL_checknumber(ls, 2);
    double t = luaL_checknumber(ls, 3);
    t = anim_clamp(t, 0.0, 1.0);
    lua_pushnumber(ls, a + (b - a) * t);
    return 1;
}

static void register_anim_api(lua_State *ls) {
    lua_newtable(ls);
    lua_pushcfunction(ls, l_anim_elapsed);
    lua_setfield(ls, -2, "elapsed");
    lua_pushcfunction(ls, l_anim_reset);
    lua_setfield(ls, -2, "reset");
    lua_pushcfunction(ls, l_anim_blink);
    lua_setfield(ls, -2, "blink");
    lua_pushcfunction(ls, l_anim_progress);
    lua_setfield(ls, -2, "progress");
    lua_pushcfunction(ls, l_anim_loop);
    lua_setfield(ls, -2, "loop");
    lua_pushcfunction(ls, l_anim_ping_pong);
    lua_setfield(ls, -2, "ping_pong");
    lua_pushcfunction(ls, l_anim_fade_in);
    lua_setfield(ls, -2, "fade_in");
    lua_pushcfunction(ls, l_anim_fade_out);
    lua_setfield(ls, -2, "fade_out");
    lua_pushcfunction(ls, l_anim_scale);
    lua_setfield(ls, -2, "scale");
    lua_pushcfunction(ls, l_anim_pulse);
    lua_setfield(ls, -2, "pulse");
    lua_pushcfunction(ls, l_anim_fly);
    lua_setfield(ls, -2, "fly");
    lua_pushcfunction(ls, l_anim_color);
    lua_setfield(ls, -2, "color");
    lua_pushcfunction(ls, l_anim_ease_in);
    lua_setfield(ls, -2, "ease_in");
    lua_pushcfunction(ls, l_anim_ease_out);
    lua_setfield(ls, -2, "ease_out");
    lua_pushcfunction(ls, l_anim_ease_in_out);
    lua_setfield(ls, -2, "ease_in_out");
    lua_pushcfunction(ls, l_anim_bounce);
    lua_setfield(ls, -2, "bounce");
    lua_pushcfunction(ls, l_anim_lerp);
    lua_setfield(ls, -2, "lerp");
    lua_setglobal(ls, "animation");
}

/* --- WebSocket Lua bindings --- */

#define WS_META "WSConnection"

static WSConnection **ws_check(lua_State *ls) {
    return (WSConnection **)luaL_checkudata(ls, 1, WS_META);
}

static int l_ws_connect(lua_State *ls) {
    const char *url_str = luaL_checkstring(ls, 1);
    BOOL reconnect = TRUE;
    const char *extra_headers = NULL;

    if (lua_istable(ls, 2)) {
        lua_getfield(ls, 2, "reconnect");
        if (!lua_isnil(ls, -1)) reconnect = lua_toboolean(ls, -1);
        lua_pop(ls, 1);
        lua_getfield(ls, 2, "headers");
        if (lua_isstring(ls, -1)) extra_headers = lua_tostring(ls, -1);
        lua_pop(ls, 1);
    }

    WCHAR wurl[2048];
    MultiByteToWideChar(CP_UTF8, 0, url_str, -1, wurl, 2048);
    WCHAR wheaders[2048] = {0};
    if (extra_headers)
        MultiByteToWideChar(CP_UTF8, 0, extra_headers, -1, wheaders, 2048);

    WSConnection *ws = ws_connect(wurl, wheaders[0] ? wheaders : NULL, reconnect);
    if (!ws) { lua_pushnil(ls); return 1; }

    lstrcpynW(ws->owner_path, g_current_lua_path, MAX_PATH);

    WSConnection **ud = (WSConnection **)lua_newuserdata(ls, sizeof(WSConnection *));
    *ud = ws;
    luaL_getmetatable(ls, WS_META);
    lua_setmetatable(ls, -2);
    return 1;
}

static int l_ws_send(lua_State *ls) {
    WSConnection **ud = ws_check(ls);
    if (!*ud) { lua_pushboolean(ls, FALSE); return 1; }
    size_t len;
    const char *data = luaL_checklstring(ls, 2, &len);
    int r = ws_send(*ud, data, (int)len);
    lua_pushboolean(ls, r > 0);
    return 1;
}

static int l_ws_recv(lua_State *ls) {
    WSConnection **ud = ws_check(ls);
    if (!*ud) { lua_pushnil(ls); return 1; }
    char *data = NULL;
    int len = 0;
    if (ws_recv(*ud, &data, &len) && data) {
        lua_pushlstring(ls, data, len);
        free(data);
    } else {
        lua_pushnil(ls);
    }
    return 1;
}

static int l_ws_close(lua_State *ls) {
    WSConnection **ud = ws_check(ls);
    if (*ud) { ws_close(*ud); *ud = NULL; }
    return 0;
}

static int l_ws_is_connected(lua_State *ls) {
    WSConnection **ud = ws_check(ls);
    lua_pushboolean(ls, *ud ? ws_is_connected(*ud) : FALSE);
    return 1;
}

static int l_ws_set_reconnect(lua_State *ls) {
    WSConnection **ud = ws_check(ls);
    if (*ud) (*ud)->reconnect = lua_toboolean(ls, 2);
    return 0;
}

static int l_ws_gc(lua_State *ls) {
    WSConnection **ud = (WSConnection **)luaL_checkudata(ls, 1, WS_META);
    if (*ud) { ws_close(*ud); *ud = NULL; }
    return 0;
}

static void register_websocket_api(lua_State *ls) {
    luaL_newmetatable(ls, WS_META);
    lua_pushvalue(ls, -1);
    lua_setfield(ls, -2, "__index");

    lua_pushcfunction(ls, l_ws_send);
    lua_setfield(ls, -2, "send");
    lua_pushcfunction(ls, l_ws_recv);
    lua_setfield(ls, -2, "recv");
    lua_pushcfunction(ls, l_ws_close);
    lua_setfield(ls, -2, "close");
    lua_pushcfunction(ls, l_ws_is_connected);
    lua_setfield(ls, -2, "is_connected");
    lua_pushcfunction(ls, l_ws_set_reconnect);
    lua_setfield(ls, -2, "set_reconnect");
    lua_pushcfunction(ls, l_ws_gc);
    lua_setfield(ls, -2, "__gc");
    lua_pop(ls, 1);

    lua_newtable(ls);
    lua_pushcfunction(ls, l_ws_connect);
    lua_setfield(ls, -2, "connect");
    lua_setglobal(ls, "websocket");
}

char *script_eval_expr(const char *expr) {
    if (!L || !expr) return NULL;
    EnterCriticalSection(&g_lua_cs);

    char code[4096];
    snprintf(code, sizeof(code), "return json.encode(%s)", expr);

    if (luaL_dostring(L, code) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        char *result = err ? _strdup(err) : _strdup("null");
        lua_settop(L, 0);
        LeaveCriticalSection(&g_lua_cs);
        return result;
    }

    const char *val = lua_tostring(L, -1);
    char *result = val ? _strdup(val) : _strdup("null");
    lua_settop(L, 0);
    LeaveCriticalSection(&g_lua_cs);
    return result;
}

void script_init(void) {
    InitializeCriticalSection(&g_lua_cs);
    image_init();
    L = luaL_newstate();
    if (!L) return;
    luaL_openlibs(L);

    /* Register json.decode */
    lua_newtable(L);
    lua_pushcfunction(L, l_json_decode);
    lua_setfield(L, -2, "decode");
    lua_pushcfunction(L, l_json_encode);
    lua_setfield(L, -2, "encode");
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

    /* Register dialog() DSL API */
    lua_pushcfunction(L, l_dialog);
    lua_setglobal(L, "dialog");

    /* Register open_dialog() / close_dialog() / dialog_is_open() */
    lua_pushcfunction(L, l_open_dialog);
    lua_setglobal(L, "open_dialog");
    lua_pushcfunction(L, l_close_dialog);
    lua_setglobal(L, "close_dialog");
    lua_pushcfunction(L, l_dialog_is_open);
    lua_setglobal(L, "dialog_is_open");

    /* Register anim.* animation API */
    register_anim_api(L);

    /* Register log table: log.info(), log.debug(), log.error(), log() */
    lua_newtable(L);
    lua_pushcfunction(L, l_log_info);
    lua_setfield(L, -2, "info");
    lua_pushcfunction(L, l_log_debug);
    lua_setfield(L, -2, "debug");
    lua_pushcfunction(L, l_log_error);
    lua_setfield(L, -2, "error");
    /* Allow log(...) as shorthand for log.info(...) via __call */
    lua_newtable(L);
    lua_pushcfunction(L, l_log);
    lua_setfield(L, -2, "__call");
    lua_setmetatable(L, -2);
    lua_setglobal(L, "log");

    /* Register sys.* system info API */
    sysinfo_register_lua(L);

    /* Append set_bar_text/set_bar_lua to sys table */
    lua_getglobal(L, "sys");
    lua_pushcfunction(L, l_set_bar_text);
    lua_setfield(L, -2, "set_bar_text");
    lua_pushcfunction(L, l_set_bar_lua);
    lua_setfield(L, -2, "set_bar_lua");
    lua_pop(L, 1);

    /* Register websocket API */
    ws_init();
    hotkey_init();
    register_websocket_api(L);
}

void script_shutdown(void) {
    hotkey_shutdown();
    ws_shutdown();
    if (L) { lua_close(L); L = NULL; }
    image_shutdown();
    DeleteCriticalSection(&g_lua_cs);
}

BOOL script_try_lock(void) {
    return TryEnterCriticalSection(&g_lua_cs);
}

void script_unlock(void) {
    LeaveCriticalSection(&g_lua_cs);
}

void script_set_global_bool(const char *name, BOOL value) {
    if (!L) return;
    EnterCriticalSection(&g_lua_cs);
    lua_pushboolean(L, value);
    lua_setglobal(L, name);
    LeaveCriticalSection(&g_lua_cs);
}

void script_set_global_string(const char *name, const char *value) {
    if (!L) return;
    EnterCriticalSection(&g_lua_cs);
    lua_pushstring(L, value ? value : "");
    lua_setglobal(L, name);
    LeaveCriticalSection(&g_lua_cs);
}

void script_set_lua_path(const WCHAR *path) {
    if (path) lstrcpynW(g_current_lua_path, path, MAX_PATH);
}

/* ??? execute template code ??? */

BOOL script_exec(const char *lua_code, const char *response_raw, ScriptResult *result) {
    if (!L || !lua_code || !lua_code[0] || !result) return FALSE;

    EnterCriticalSection(&g_lua_cs);
    result->display[0] = L'\0';
    result->clickable = FALSE;
    result->click_action = CLICK_URL;
    result->click_url[0] = L'\0';

    /* Set global `response` */
    lua_pushstring(L, response_raw ? response_raw : "");
    lua_setglobal(L, "response");

    event_push_lua(L);

    /* Wrap code so multiple return values work */
    char wrapped[4096];
    snprintf(wrapped, sizeof(wrapped),
        "return (function()\n%s\nend)()", lua_code);

    if (luaL_dostring(L, wrapped) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        logger_write(LOG_ERROR, "lua: %s", err ? err : "(unknown error)");
        lua_pop(L, 1);
        LeaveCriticalSection(&g_lua_cs);
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
    /* 3rd: click URL or dialog spec */
    if (nresults >= 3) {
        if (is_dialog_table(L, 3)) {
            result->click_action = CLICK_DIALOG;
            parse_dialog_spec(L, 3, &result->dialog);
        } else {
            result->click_action = CLICK_URL;
            const char *url = lua_tostring(L, 3);
            if (url) MultiByteToWideChar(CP_UTF8, 0, url, -1, result->click_url, 1024);
        }
    }
    /* 4th return: tooltip text */
    result->tooltip[0] = L'\0';
    if (nresults >= 4) {
        const char *tip = lua_tostring(L, 4);
        if (tip) MultiByteToWideChar(CP_UTF8, 0, tip, -1, result->tooltip, 512);
    }

    lua_settop(L, 0);
    LeaveCriticalSection(&g_lua_cs);
    return (result->display[0] != L'\0' || result->rich.count > 0 ||
            result->clickable || result->click_action == CLICK_DIALOG);
}

/* ??? execute Lua file ??? */

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

static BOOL script_exec_file_ex(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                                ScriptResult *result, BOOL nonblock);

BOOL script_exec_file(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                      ScriptResult *result) {
    return script_exec_file_ex(lua_path, params, param_count, result, FALSE);
}

BOOL script_exec_file_try(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                          ScriptResult *result) {
    return script_exec_file_ex(lua_path, params, param_count, result, TRUE);
}

static BOOL script_exec_file_ex(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                                ScriptResult *result, BOOL nonblock) {
    if (!L || !lua_path || !lua_path[0] || !result) return FALSE;

    /* Version check */
    char required_ver[32] = {0};
    if (!script_check_require(lua_path, required_ver, sizeof(required_ver))) {
        WCHAR msg[256];
        WCHAR wreq[32];
        MultiByteToWideChar(CP_UTF8, 0, required_ver, -1, wreq, 32);
        wsprintfW(msg, tr("scripting.version_required"), wreq, L"" TASKPIN_VERSION);
        lstrcpynW(result->display, msg, 2048);
        result->clickable = FALSE;
        result->rich.count = 0;
        return TRUE;
    }

    if (nonblock) {
        if (!TryEnterCriticalSection(&g_lua_cs)) return FALSE;
    } else {
        EnterCriticalSection(&g_lua_cs);
    }
    result->display[0] = L'\0';
    result->clickable = FALSE;
    result->click_action = CLICK_URL;
    result->click_url[0] = L'\0';

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    lstrcpynW(g_current_lua_path, full_path, MAX_PATH);

    /* Inject __dialog_open so scripts/animation can short-circuit */
    lua_pushboolean(L, script_dialog_is_open(full_path));
    lua_setglobal(L, "__dialog_open");

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

    event_push_lua(L);

    /* Build selection table from __selection_* globals (set by hotkey handler) */
    lua_getglobal(L, "__selection_type");
    const char *sel_type = lua_tostring(L, -1);
    if (sel_type && strcmp(sel_type, "none") != 0) {
        lua_newtable(L);
        lua_pushstring(L, sel_type);
        lua_setfield(L, -2, "type");
        lua_getglobal(L, "__selection_text");
        lua_setfield(L, -2, "text");
        /* Parse files JSON array */
        lua_getglobal(L, "__selection_files");
        const char *fj = lua_tostring(L, -1);
        if (fj && fj[0] == '[') {
            luaL_dostring(L, "return json.decode(__selection_files)");
            lua_setfield(L, -3, "files");
        }
        lua_pop(L, 1);
        lua_getglobal(L, "__selection_image");
        lua_setfield(L, -2, "image");
        lua_setglobal(L, "selection");
        /* Clear after use */
        lua_pushnil(L); lua_setglobal(L, "__selection_type");
    } else {
        lua_pushnil(L); lua_setglobal(L, "selection");
    }
    lua_pop(L, 1);

    char path8[512];
    WideCharToMultiByte(CP_UTF8, 0, full_path, -1, path8, 512, NULL, NULL);

    if (luaL_dofile(L, path8) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        logger_write(LOG_ERROR, "lua: %s", err ? err : "(unknown error)");
        if (err) MultiByteToWideChar(CP_UTF8, 0, err, -1, result->display, 2048);
        else lstrcpyW(result->display, L"[lua error]");
        lua_settop(L, 0);
        LeaveCriticalSection(&g_lua_cs);
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
        if (is_dialog_table(L, 3)) {
            result->click_action = CLICK_DIALOG;
            parse_dialog_spec(L, 3, &result->dialog);
        } else {
            result->click_action = CLICK_URL;
            const char *url = lua_tostring(L, 3);
            if (url) MultiByteToWideChar(CP_UTF8, 0, url, -1, result->click_url, 1024);
        }
    }
    /* 4th return: tooltip text */
    result->tooltip[0] = L'\0';
    if (nresults >= 4) {
        const char *tip = lua_tostring(L, 4);
        if (tip) MultiByteToWideChar(CP_UTF8, 0, tip, -1, result->tooltip, 512);
    }

    lua_settop(L, 0);
    LeaveCriticalSection(&g_lua_cs);
    return (result->display[0] != L'\0' || result->rich.count > 0 ||
            result->clickable || result->click_action == CLICK_DIALOG);
}

/* ??? parse @param declarations ??? */

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

/* ??? parse @refresh declaration ??? */

int script_parse_refresh(const WCHAR *lua_path) {
    if (!lua_path || !lua_path[0]) return 0;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return 0;

    char line[512];
    int result = 0;
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@refresh", 8) != 0) continue;
        p += 8;
        while (*p == ' ' || *p == '\t') p++;
        result = atoi(p);
        break;
    }
    fclose(f);
    return result;
}

/* ??? parse @realtime declaration ??? */

BOOL script_parse_realtime(const WCHAR *lua_path) {
    if (!lua_path || !lua_path[0]) return FALSE;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return FALSE;

    char line[512];
    BOOL result = FALSE;
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@realtime", 9) == 0) { result = TRUE; break; }
    }
    fclose(f);
    return result;
}

/* ??? parse @hotkey declaration ??? */

void script_parse_hotkey(const WCHAR *lua_path, char *out, int out_size) {
    out[0] = '\0';
    if (!lua_path || !lua_path[0]) return;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return;

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@hotkey", 7) != 0) continue;
        p += 7;
        while (*p == ' ' || *p == '\t') p++;
        /* trim trailing whitespace */
        char *end = p + strlen(p) - 1;
        while (end > p && (*end == '\n' || *end == '\r' || *end == ' ')) *end-- = '\0';
        strncpy(out, p, out_size - 1);
        out[out_size - 1] = '\0';
        break;
    }
    fclose(f);
}

/* ??? parse @admin declaration ??? */

BOOL script_parse_admin(const WCHAR *lua_path) {
    if (!lua_path || !lua_path[0]) return FALSE;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return FALSE;

    char line[512];
    BOOL result = FALSE;
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@admin", 6) == 0) { result = TRUE; break; }
    }
    fclose(f);
    return result;
}

void script_parse_admin_desc(const WCHAR *lua_path, char *out_desc, int out_size) {
    out_desc[0] = '\0';
    if (!lua_path || !lua_path[0]) return;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return;

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@admin", 6) != 0) continue;
        p += 6;
        while (*p == ' ' || *p == '\t') p++;
        char *end = p + strlen(p) - 1;
        while (end > p && (*end == '\n' || *end == '\r' || *end == ' ')) *end-- = '\0';
        if (*p) strncpy(out_desc, p, out_size - 1);
        break;
    }
    fclose(f);
}

/* ??? parse @bar_width declaration ??? */

int script_parse_bar_width(const WCHAR *lua_path) {
    if (!lua_path || !lua_path[0]) return 0;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return 0;

    char line[512];
    int result = 0;
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@bar_width", 10) != 0) continue;
        p += 10;
        while (*p == ' ' || *p == '\t') p++;
        result = atoi(p);
        break;
    }
    fclose(f);
    return result;
}

/* ??? parse @name declaration ??? */

void script_parse_name(const WCHAR *lua_path, WCHAR *out, int out_size) {
    out[0] = L'\0';
    if (!lua_path || !lua_path[0]) return;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return;

    char line[512];
    char fallback[256] = {0};
    BOOL first_line = TRUE;
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        /* First line: extract "-- xxx.lua - Description" ??Description */
        if (first_line) {
            first_line = FALSE;
            char *dash = strstr(p, " - ");
            if (dash) {
                dash += 3;
                char *end = dash + strlen(dash) - 1;
                while (end > dash && (*end == '\n' || *end == '\r' || *end == ' ')) *end-- = '\0';
                strncpy(fallback, dash, sizeof(fallback) - 1);
            }
        }
        /* Explicit @name overrides */
        if (strncmp(p, "@name", 5) == 0) {
            p += 5;
            while (*p == ' ' || *p == '\t') p++;
            char *end = p + strlen(p) - 1;
            while (end > p && (*end == '\n' || *end == '\r' || *end == ' ')) *end-- = '\0';
            MultiByteToWideChar(CP_UTF8, 0, p, -1, out, out_size);
            fclose(f);
            return;
        }
    }
    fclose(f);
    if (fallback[0]) {
        MultiByteToWideChar(CP_UTF8, 0, fallback, -1, out, out_size);
    }
}

/* ??? parse @version declaration ??? */

void script_parse_version(const WCHAR *lua_path, char *out, int out_size) {
    out[0] = '\0';
    if (!lua_path || !lua_path[0]) return;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return;

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@version", 8) != 0) continue;
        p += 8;
        while (*p == ' ' || *p == '\t') p++;
        char *end = p + strlen(p) - 1;
        while (end > p && (*end == '\n' || *end == '\r' || *end == ' ')) *end-- = '\0';
        strncpy(out, p, out_size - 1);
        break;
    }
    fclose(f);
}

/* ??? parse @require declaration and check ??? */

static int version_compare(const char *a, const char *b) {
    int a1=0,a2=0,a3=0, b1=0,b2=0,b3=0;
    sscanf(a, "%d.%d.%d", &a1, &a2, &a3);
    sscanf(b, "%d.%d.%d", &b1, &b2, &b3);
    if (a1 != b1) return a1 - b1;
    if (a2 != b2) return a2 - b2;
    return a3 - b3;
}

BOOL script_check_require(const WCHAR *lua_path, char *required, int req_size) {
    if (!lua_path || !lua_path[0]) return TRUE;

    WCHAR full_path[MAX_PATH];
    resolve_lua_path(lua_path, full_path);

    FILE *f = _wfopen(full_path, L"r");
    if (!f) return TRUE;

    char line[512];
    char min_ver[32] = {0};
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@require", 8) != 0) continue;
        p += 8;
        while (*p == ' ' || *p == '\t') p++;
        /* trim trailing whitespace */
        char *end = p + strlen(p) - 1;
        while (end > p && (*end == '\n' || *end == '\r' || *end == ' ')) *end-- = '\0';
        strncpy(min_ver, p, 31);
        break;
    }
    fclose(f);

    if (!min_ver[0]) return TRUE;
    if (required) strncpy(required, min_ver, req_size - 1);
    return version_compare(TASKPIN_VERSION, min_ver) >= 0;
}
