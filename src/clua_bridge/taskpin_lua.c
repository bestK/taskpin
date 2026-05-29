#include "taskpin_lua.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static lua_State *g_L = NULL;

// MARK: - Span concat metatable

#define SPAN_MT "TaskPin.Span"

static int l_span_concat(lua_State *L) {
    lua_createtable(L, 0, 0);
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_spanlist");
    luaL_getmetatable(L, SPAN_MT); lua_setmetatable(L, -2);
    int result = lua_gettop(L);

    for (int side = 1; side <= 2; side++) {
        if (lua_istable(L, side)) {
            lua_getfield(L, side, "__is_spanlist");
            int is_list = lua_toboolean(L, -1);
            lua_pop(L, 1);
            if (is_list) {
                int len = (int)lua_rawlen(L, side);
                int dlen = (int)lua_rawlen(L, result);
                for (int i = 1; i <= len; i++) {
                    lua_rawgeti(L, side, i);
                    lua_rawseti(L, result, dlen + i);
                }
            } else {
                int dlen = (int)lua_rawlen(L, result);
                lua_pushvalue(L, side);
                lua_rawseti(L, result, dlen + 1);
            }
        } else if (lua_isstring(L, side)) {
            lua_createtable(L, 0, 0);
            lua_pushvalue(L, side); lua_setfield(L, -2, "text");
            lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span");
            int dlen = (int)lua_rawlen(L, result);
            lua_rawseti(L, result, dlen + 1);
        }
    }
    return 1;
}

// MARK: - font(text, color, size, align)

static int l_font(lua_State *L) {
    lua_createtable(L, 0, 0);
    if (lua_isstring(L, 1)) { lua_pushvalue(L, 1); lua_setfield(L, -2, "text"); }
    if (lua_gettop(L) >= 3 && !lua_isnoneornil(L, 2)) { lua_pushvalue(L, 2); lua_setfield(L, -2, "color"); }
    if (lua_gettop(L) >= 4 && !lua_isnoneornil(L, 3)) { lua_pushvalue(L, 3); lua_setfield(L, -2, "size"); }
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span");
    luaL_getmetatable(L, SPAN_MT); lua_setmetatable(L, -2);
    return 1;
}

// MARK: - icon(source, w, h)

static int l_icon(lua_State *L) {
    lua_createtable(L, 0, 0);
    if (lua_isstring(L, 1)) { lua_pushvalue(L, 1); lua_setfield(L, -2, "img_source"); }
    lua_pushinteger(L, lua_gettop(L) >= 2 ? lua_tointeger(L, 2) : 16); lua_setfield(L, -2, "img_w");
    lua_pushinteger(L, lua_gettop(L) >= 3 ? lua_tointeger(L, 3) : 16); lua_setfield(L, -2, "img_h");
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_image");
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span");
    luaL_getmetatable(L, SPAN_MT); lua_setmetatable(L, -2);
    return 1;
}

// MARK: - dialog(spec)

static int l_dialog(lua_State *L) {
    if (lua_istable(L, 1)) { lua_pushboolean(L, 1); lua_setfield(L, 1, "_dialog"); }
    lua_pushvalue(L, 1);
    return 1;
}

// MARK: - log(...)

static int l_log(lua_State *L) {
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++) {
        size_t len;
        const char *s = luaL_tolstring(L, i, &len);
        if (s) fprintf(stderr, "%s%s", s, i < n ? "\t" : "");
        lua_pop(L, 1);
    }
    fprintf(stderr, "\n");
    return 0;
}

// MARK: - json.decode (minimal)

static void push_json_value(lua_State *L, const char **p);

static void skip_ws(const char **p) { while (**p == ' ' || **p == '\t' || **p == '\n' || **p == '\r') (*p)++; }

static void push_json_string(lua_State *L, const char **p) {
    (*p)++; // skip "
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    while (**p && **p != '"') {
        if (**p == '\\') {
            (*p)++;
            switch (**p) {
                case '"': luaL_addchar(&buf, '"'); break;
                case '\\': luaL_addchar(&buf, '\\'); break;
                case '/': luaL_addchar(&buf, '/'); break;
                case 'n': luaL_addchar(&buf, '\n'); break;
                case 't': luaL_addchar(&buf, '\t'); break;
                case 'r': luaL_addchar(&buf, '\r'); break;
                default: luaL_addchar(&buf, **p); break;
            }
        } else {
            luaL_addchar(&buf, **p);
        }
        (*p)++;
    }
    if (**p == '"') (*p)++;
    luaL_pushresult(&buf);
}

static void push_json_value(lua_State *L, const char **p) {
    skip_ws(p);
    if (**p == '"') {
        push_json_string(L, p);
    } else if (**p == '{') {
        (*p)++;
        lua_createtable(L, 0, 0);
        skip_ws(p);
        if (**p != '}') {
            while (1) {
                skip_ws(p);
                if (**p != '"') break;
                push_json_string(L, p);
                skip_ws(p);
                if (**p == ':') (*p)++;
                push_json_value(L, p);
                lua_settable(L, -3);
                skip_ws(p);
                if (**p == ',') (*p)++; else break;
            }
        }
        if (**p == '}') (*p)++;
    } else if (**p == '[') {
        (*p)++;
        lua_createtable(L, 0, 0);
        int idx = 1;
        skip_ws(p);
        if (**p != ']') {
            while (1) {
                push_json_value(L, p);
                lua_rawseti(L, -2, idx++);
                skip_ws(p);
                if (**p == ',') (*p)++; else break;
            }
        }
        if (**p == ']') (*p)++;
    } else if (strncmp(*p, "true", 4) == 0) {
        lua_pushboolean(L, 1); *p += 4;
    } else if (strncmp(*p, "false", 5) == 0) {
        lua_pushboolean(L, 0); *p += 5;
    } else if (strncmp(*p, "null", 4) == 0) {
        lua_pushnil(L); *p += 4;
    } else {
        char *end;
        double num = strtod(*p, &end);
        lua_pushnumber(L, num);
        *p = end;
    }
}

static int l_json_decode(lua_State *L) {
    const char *str = luaL_checkstring(L, 1);
    push_json_value(L, &str);
    return 1;
}

// MARK: - http.get (using curl)

static int l_http_get(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "curl -sL '%s'", url);
    FILE *fp = popen(cmd, "r");
    if (!fp) { lua_pushnil(L); return 1; }
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    char chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
        luaL_addlstring(&buf, chunk, n);
    }
    pclose(fp);
    luaL_pushresult(&buf);
    return 1;
}

static int l_http_post(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    const char *body = lua_gettop(L) >= 2 ? lua_tostring(L, 2) : NULL;
    const char *headers = lua_gettop(L) >= 3 ? lua_tostring(L, 3) : NULL;
    char cmd[4096];
    if (body && headers) {
        snprintf(cmd, sizeof(cmd), "curl -sL -X POST -H '%s' -d '%s' '%s'", headers, body, url);
    } else if (body) {
        snprintf(cmd, sizeof(cmd), "curl -sL -X POST -d '%s' '%s'", body, url);
    } else {
        snprintf(cmd, sizeof(cmd), "curl -sL -X POST '%s'", url);
    }
    FILE *fp = popen(cmd, "r");
    if (!fp) { lua_pushnil(L); return 1; }
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    char chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
        luaL_addlstring(&buf, chunk, n);
    }
    pclose(fp);
    luaL_pushresult(&buf);
    return 1;
}

// MARK: - sys.cpu / sys.memory

#ifdef __APPLE__
#include <mach/mach.h>
#include <sys/sysctl.h>

static int l_sys_cpu(lua_State *L) {
    // Simplified: return load average * 100 / ncpu
    double load[1];
    getloadavg(load, 1);
    int ncpu = 1;
    size_t sz = sizeof(ncpu);
    sysctlbyname("hw.ncpu", &ncpu, &sz, NULL, 0);
    int pct = (int)(load[0] * 100.0 / ncpu);
    if (pct > 100) pct = 100;
    lua_pushinteger(L, pct);
    return 1;
}

static int l_sys_memory(lua_State *L) {
    int64_t total = 0;
    size_t sz = sizeof(total);
    sysctlbyname("hw.memsize", &total, &sz, NULL, 0);

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count);
    int64_t used = ((int64_t)vm.active_count + vm.wire_count) * vm_page_size;

    lua_createtable(L, 0, 3);
    lua_pushinteger(L, total / (1024*1024)); lua_setfield(L, -2, "total_mb");
    lua_pushinteger(L, used / (1024*1024)); lua_setfield(L, -2, "used_mb");
    lua_pushinteger(L, (int)(used * 100 / total)); lua_setfield(L, -2, "percent");
    return 1;
}
#endif

// MARK: - Init / Execute

void tp_lua_init(void) {
    if (g_L) return;
    g_L = luaL_newstate();
    luaL_openlibs(g_L);

    // Span metatable
    luaL_newmetatable(g_L, SPAN_MT);
    lua_pushcfunction(g_L, l_span_concat); lua_setfield(g_L, -2, "__concat");
    lua_pop(g_L, 1);

    // Globals
    lua_pushcfunction(g_L, l_font); lua_setglobal(g_L, "font");
    lua_pushcfunction(g_L, l_icon); lua_setglobal(g_L, "icon");
    lua_pushcfunction(g_L, l_dialog); lua_setglobal(g_L, "dialog");
    lua_pushcfunction(g_L, l_log); lua_setglobal(g_L, "log");

    // json
    lua_createtable(g_L, 0, 0);
    lua_pushcfunction(g_L, l_json_decode); lua_setfield(g_L, -2, "decode");
    lua_setglobal(g_L, "json");

    // http
    lua_createtable(g_L, 0, 0);
    lua_pushcfunction(g_L, l_http_get); lua_setfield(g_L, -2, "get");
    lua_pushcfunction(g_L, l_http_post); lua_setfield(g_L, -2, "post");
    lua_setglobal(g_L, "http");

    // sys
    lua_createtable(g_L, 0, 0);
#ifdef __APPLE__
    lua_pushcfunction(g_L, l_sys_cpu); lua_setfield(g_L, -2, "cpu");
    lua_pushcfunction(g_L, l_sys_memory); lua_setfield(g_L, -2, "memory");
#endif
    lua_setglobal(g_L, "sys");
}

void tp_lua_shutdown(void) {
    if (g_L) { lua_close(g_L); g_L = NULL; }
}

int tp_lua_execute(const char *filepath, const char *args_json) {
    if (!g_L || !filepath) return -1;

    // Inject args
    lua_createtable(g_L, 0, 0);
    if (args_json && args_json[0]) {
        const char *p = args_json;
        push_json_value(g_L, &p);
        if (lua_istable(g_L, -1)) {
            lua_remove(g_L, -2); // remove empty table
        } else {
            lua_pop(g_L, 1);
        }
    }
    lua_setglobal(g_L, "args");

    if (luaL_loadfile(g_L, filepath) != LUA_OK || lua_pcall(g_L, 0, LUA_MULTRET, 0) != LUA_OK) {
        fprintf(stderr, "[TaskPin] %s\n", lua_tostring(g_L, -1));
        lua_settop(g_L, 0);
        return -1;
    }
    return lua_gettop(g_L);
}

const char *tp_lua_get_error(void) {
    if (!g_L) return NULL;
    if (lua_isstring(g_L, -1)) return lua_tostring(g_L, -1);
    return NULL;
}

int tp_lua_get_nresults(void) {
    return g_L ? lua_gettop(g_L) : 0;
}

void tp_lua_clear_stack(void) {
    if (g_L) lua_settop(g_L, 0);
}

// MARK: - Result extraction

int tp_lua_is_span(int idx) {
    if (!g_L || !lua_istable(g_L, idx)) return 0;
    lua_getfield(g_L, idx, "__is_span");
    int r = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    if (r) return 1;
    lua_getfield(g_L, idx, "__is_spanlist");
    r = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    return r;
}

int tp_lua_is_dialog(int idx) {
    if (!g_L || !lua_istable(g_L, idx)) return 0;
    lua_getfield(g_L, idx, "_dialog");
    int r = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    return r;
}

int tp_lua_get_bool(int idx) {
    return g_L ? lua_toboolean(g_L, idx) : 0;
}

const char *tp_lua_get_string(int idx) {
    return (g_L && lua_isstring(g_L, idx)) ? lua_tostring(g_L, idx) : NULL;
}

int tp_lua_span_count(int idx) {
    if (!g_L || !lua_istable(g_L, idx)) return 0;
    lua_getfield(g_L, idx, "__is_spanlist");
    int is_list = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    if (is_list) return (int)lua_rawlen(g_L, idx);
    return 1;
}

TPSpan tp_lua_get_span(int list_idx, int span_idx) {
    TPSpan span = {0};
    if (!g_L) return span;

    int target;
    lua_getfield(g_L, list_idx, "__is_spanlist");
    int is_list = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    if (is_list) {
        lua_rawgeti(g_L, list_idx, span_idx + 1);
        target = lua_gettop(g_L);
    } else {
        target = list_idx;
    }

    lua_getfield(g_L, target, "__is_image");
    span.is_image = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    if (span.is_image) {
        lua_getfield(g_L, target, "img_source");
        if (lua_isstring(g_L, -1)) strncpy(span.text, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "img_w");
        span.img_w = lua_isnil(g_L, -1) ? 16 : (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "img_h");
        span.img_h = lua_isnil(g_L, -1) ? 16 : (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);
    } else {
        lua_getfield(g_L, target, "text");
        if (lua_isstring(g_L, -1)) strncpy(span.text, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "color");
        if (lua_isstring(g_L, -1)) strncpy(span.color, lua_tostring(g_L, -1), 15);
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "size");
        span.font_size = lua_isnil(g_L, -1) ? 0 : (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);
    }

    if (is_list) lua_pop(g_L, 1);
    return span;
}

// MARK: - Dialog extraction

TPDialogSpec tp_lua_get_dialog(int idx) {
    TPDialogSpec spec = {0};
    if (!g_L || !lua_istable(g_L, idx)) return spec;

    spec.width = 400; spec.height = 300; spec.opacity = 255;

    lua_getfield(g_L, idx, "title");
    if (lua_isstring(g_L, -1)) strncpy(spec.title, lua_tostring(g_L, -1), 127);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "width");
    if (!lua_isnil(g_L, -1)) spec.width = (int)lua_tointeger(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "height");
    if (!lua_isnil(g_L, -1)) spec.height = (int)lua_tointeger(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "refresh");
    if (!lua_isnil(g_L, -1)) spec.refresh = (int)lua_tointeger(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "borderless");
    spec.borderless = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "clickthrough");
    spec.clickthrough = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "opacity");
    if (!lua_isnil(g_L, -1)) spec.opacity = (int)lua_tointeger(g_L, -1);
    else spec.opacity = 255;
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "content");
    if (!lua_istable(g_L, -1)) { lua_pop(g_L, 1); return spec; }

    int content_idx = lua_gettop(g_L);
    int n = (int)lua_rawlen(g_L, content_idx);
    if (n > 8) n = 8;

    for (int i = 1; i <= n; i++) {
        lua_rawgeti(g_L, content_idx, i);
        if (!lua_istable(g_L, -1)) { lua_pop(g_L, 1); continue; }

        TPDialogItem *item = &spec.items[spec.item_count];
        memset(item, 0, sizeof(TPDialogItem));

        lua_getfield(g_L, -1, "type");
        if (lua_isstring(g_L, -1)) strncpy(item->type, lua_tostring(g_L, -1), 15);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "value");
        if (lua_isstring(g_L, -1)) strncpy(item->value, lua_tostring(g_L, -1), 255);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "color");
        if (lua_isstring(g_L, -1)) strncpy(item->color, lua_tostring(g_L, -1), 15);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "size");
        if (!lua_isnil(g_L, -1)) item->font_size = (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "bold");
        item->bold = lua_toboolean(g_L, -1);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "image");
        if (lua_isstring(g_L, -1)) strncpy(item->image, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "image_width");
        if (!lua_isnil(g_L, -1)) item->image_width = (int)lua_tointeger(g_L, -1);
        else item->image_width = 16;
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "image_height");
        if (!lua_isnil(g_L, -1)) item->image_height = (int)lua_tointeger(g_L, -1);
        else item->image_height = 16;
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "url");
        if (lua_isstring(g_L, -1)) strncpy(item->url, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "cmd");
        if (lua_isstring(g_L, -1)) strncpy(item->cmd, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);

        // Parse table columns/rows
        if (strcmp(item->type, "table") == 0) {
            lua_getfield(g_L, -1, "columns");
            if (lua_istable(g_L, -1)) {
                int nc = (int)lua_rawlen(g_L, -1);
                if (nc > 6) nc = 6;
                item->col_count = nc;
                for (int c = 1; c <= nc; c++) {
                    lua_rawgeti(g_L, -1, c);
                    if (lua_isstring(g_L, -1)) strncpy(item->columns[c-1], lua_tostring(g_L, -1), 63);
                    lua_pop(g_L, 1);
                }
            }
            lua_pop(g_L, 1);

            lua_getfield(g_L, -1, "rows");
            if (lua_istable(g_L, -1)) {
                int nr = (int)lua_rawlen(g_L, -1);
                if (nr > 24) nr = 24;
                item->row_count = nr;
                for (int r = 1; r <= nr; r++) {
                    lua_rawgeti(g_L, -1, r);
                    if (lua_istable(g_L, -1)) {
                        int rc = (int)lua_rawlen(g_L, -1);
                        if (rc > item->col_count) rc = item->col_count;
                        for (int c = 1; c <= rc; c++) {
                            lua_rawgeti(g_L, -1, c);
                            if (lua_isstring(g_L, -1)) strncpy(item->cells[r-1][c-1], lua_tostring(g_L, -1), 63);
                            lua_pop(g_L, 1);
                        }
                        lua_getfield(g_L, -1, "url");
                        if (lua_isstring(g_L, -1)) strncpy(item->row_urls[r-1], lua_tostring(g_L, -1), 255);
                        lua_pop(g_L, 1);
                    }
                    lua_pop(g_L, 1);
                }
            }
            lua_pop(g_L, 1);
        }

        spec.item_count++;
        lua_pop(g_L, 1);
    }
    lua_pop(g_L, 1); // content table
    return spec;
}
