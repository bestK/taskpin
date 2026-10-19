/*
 * tp_json.c — a small, platform-neutral JSON decoder used by json.decode().
 *
 * WHY THIS EXISTS RATHER THAN lib/json.c:
 * lib/json.c is the tree-based parser the Windows build uses, but it does
 * `#include <windows.h>` at the top of json.h, so it cannot be compiled into
 * a platform-neutral engine. This file is deliberately dependency-free
 * (only <stdlib.h>, <string.h>, <stdio.h>) so native/engine stays buildable
 * under MinGW gcc, MSVC and Apple clang.
 *
 * Semantics are preserved from the macOS bridge (src/clua_bridge/taskpin_lua.c
 * `push_json_value`), which is the UTF-8 behaviour scripts are written
 * against: a valid document produces a value, anything else produces nil.
 *
 * NOTE: this decoder intentionally does not handle \uXXXX escapes (the mac
 * bridge does not either). Scripts that need them should be revisited when
 * lib/json.c's tree parser is ported in a later phase.
 */

#include <stdlib.h>
#include <string.h>

#define TASKPIN_ENGINE_INTERNAL
#include "taskpin_engine.h"

#include "lua.h"
#include "lauxlib.h"

static void tp_json_value(lua_State *L, const char **p);

static void tp_skip_ws(const char **p) {
    while (**p == ' ' || **p == '\t' || **p == '\n' || **p == '\r') (*p)++;
}

static void tp_json_string(lua_State *L, const char **p) {
    (*p)++; /* skip opening quote */
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    while (**p && **p != '"') {
        if (**p == '\\') {
            (*p)++;
            switch (**p) {
            case '"':  luaL_addchar(&buf, '"');  break;
            case '\\': luaL_addchar(&buf, '\\'); break;
            case '/':  luaL_addchar(&buf, '/');  break;
            case 'n':  luaL_addchar(&buf, '\n'); break;
            case 't':  luaL_addchar(&buf, '\t'); break;
            case 'r':  luaL_addchar(&buf, '\r'); break;
            case 'b':  luaL_addchar(&buf, '\b'); break;
            case 'f':  luaL_addchar(&buf, '\f'); break;
            default:   luaL_addchar(&buf, **p);  break;
            }
        } else {
            luaL_addchar(&buf, **p);
        }
        (*p)++;
    }
    if (**p == '"') (*p)++;
    luaL_pushresult(&buf);
}

static void tp_json_object(lua_State *L, const char **p) {
    (*p)++; /* skip '{' */
    lua_createtable(L, 0, 0);
    tp_skip_ws(p);
    if (**p != '}') {
        for (;;) {
            tp_skip_ws(p);
            if (**p != '"') break;
            tp_json_string(L, p);
            tp_skip_ws(p);
            if (**p == ':') (*p)++;
            tp_json_value(L, p);
            lua_settable(L, -3);
            tp_skip_ws(p);
            if (**p == ',') (*p)++;
            else break;
        }
    }
    if (**p == '}') (*p)++;
}

static void tp_json_array(lua_State *L, const char **p) {
    (*p)++; /* skip '[' */
    lua_createtable(L, 0, 0);
    int idx = 1;
    tp_skip_ws(p);
    if (**p != ']') {
        for (;;) {
            tp_json_value(L, p);
            lua_rawseti(L, -2, idx++);
            tp_skip_ws(p);
            if (**p == ',') (*p)++;
            else break;
        }
    }
    if (**p == ']') (*p)++;
}

static void tp_json_value(lua_State *L, const char **p) {
    tp_skip_ws(p);
    if (**p == '"') {
        tp_json_string(L, p);
    } else if (**p == '{') {
        tp_json_object(L, p);
    } else if (**p == '[') {
        tp_json_array(L, p);
    } else if (strncmp(*p, "true", 4) == 0) {
        lua_pushboolean(L, 1);
        *p += 4;
    } else if (strncmp(*p, "false", 5) == 0) {
        lua_pushboolean(L, 0);
        *p += 5;
    } else if (strncmp(*p, "null", 4) == 0) {
        lua_pushnil(L);
        *p += 4;
    } else {
        char *end = NULL;
        double num = strtod(*p, &end);
        lua_pushnumber(L, num);
        *p = (end && end != *p) ? end : *p + 1;
    }
}

int tp_json_to_lua(lua_State *L, const char *json) {
    if (!json) {
        lua_pushnil(L);
        return 0;
    }

    const char *start = json;
    tp_skip_ws(&start);

    /* Reject anything that cannot begin a JSON value, mirroring the mac
     * bridge's guard so json.decode() returns nil rather than garbage. */
    if (*start != '{' && *start != '[' && *start != '"'
        && strncmp(start, "true", 4) != 0
        && strncmp(start, "false", 5) != 0
        && strncmp(start, "null", 4) != 0
        && (*start < '0' || *start > '9') && *start != '-') {
        lua_pushnil(L);
        return 0;
    }

    const char *p = json;
    tp_json_value(L, &p);
    return 1;
}
