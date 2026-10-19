/*
 * taskpin_lua.c — the TaskPin Lua API, ported from lib/scripting.c.
 *
 * lib/scripting.c is the authoritative implementation (see
 * docs/FLUTTER_REWRITE_PLAN.md). It stores text as WCHAR and converts with
 * MultiByteToWideChar; this port keeps the exact same logic but works in
 * UTF-8 end to end, so the ABI stays flat and platform-neutral.
 *
 * Semantics preserved deliberately and exactly (golden tests depend on it):
 *
 *   font(text, color, size, align)   color/size/align set only when the arg
 *                                    is present AND non-nil
 *   icon(source, w, h, align)        w/h default to 16
 *   span .. span                     -> span list (flattening nested lists)
 *   "plain" .. span                  -> plain string wrapped as a span
 *   dialog(spec)                     marks _dialog and returns the same table
 *   return display, clickable, click_url|dialog
 *   a span whose text is exactly "\n" becomes an empty span with newline=1
 *   parse_color_str: "#RGB" (x17), "#RRGGBB", bare hex; else default
 *   parse_align_str: "right" -> 1, "center" -> 2, else 0
 *   dialog defaults: 400x300, opacity 255, title "Dialog", 8 items max,
 *   6 cols x 24 rows max, unknown item types skipped
 *
 * Two item fields are additions over lib/scripting.c, both carried through
 * for the Flutter host rather than interpreted here:
 *   transparent_bg                   spec field, boolean
 *   { type = "webview", url, width, height }   item type (Phase 9 renders it)
 *
 * Two deliberate deviations from lib/scripting.c, both noted inline:
 *   - no global CRITICAL_SECTION: a TPEngine is owned by one isolate/thread
 *     (the plan's isolate model), so the lock would be dead weight.
 *   - errors go to result->error instead of result->display (the plan's
 *     stated improvement: a raw traceback must not render into the taskbar).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TASKPIN_ENGINE_INTERNAL
#include "taskpin_engine.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "tp_http.h"
#include "tp_sysinfo.h"

/* tp_json.c */
int tp_json_to_lua(lua_State *L, const char *json);

#define SPAN_MT "TaskPin.Span"

/* ─── helpers ─── */

static void copy_str(char *dst, size_t cap, const char *src) {
    if (!src) { dst[0] = '\0'; return; }
    size_t n = strlen(src);
    if (n >= cap) n = cap - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

/* lib/scripting.c parse_color_str: returns a COLORREF or "use default".
 * The neutral engine stores the "#RRGGBB" string verbatim and lets the
 * host parse it, but validity still has to be decided here so that a
 * bogus colour falls back to "" (default) exactly as before. */
static int valid_color_str(const char *s) {
    if (!s || !s[0]) return 0;
    if (s[0] == '#') s++;
    size_t len = strlen(s);
    if (len != 3 && len != 6) return 0;
    for (size_t i = 0; i < len; i++) {
        char c = s[i];
        int hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!hex) return 0;
    }
    return 1;
}

static void set_color_field(char *dst, size_t cap, const char *s) {
    if (valid_color_str(s)) copy_str(dst, cap, s);
    else dst[0] = '\0';
}

static int parse_align_str(const char *s) {
    if (!s) return TP_SPAN_ALIGN_LEFT;
    if (strcmp(s, "right") == 0) return TP_SPAN_ALIGN_RIGHT;
    if (strcmp(s, "center") == 0) return TP_SPAN_ALIGN_CENTER;
    return TP_SPAN_ALIGN_LEFT;
}

/* ─── log() ─── */

static int l_log(lua_State *L) {
    TPEngine *e = (TPEngine *)lua_touserdata(L, lua_upvalueindex(1));
    int n = lua_gettop(L);

    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    for (int i = 1; i <= n; i++) {
        const char *s = luaL_tolstring(L, i, NULL);
        if (s) luaL_addstring(&buf, s);
        lua_pop(L, 1);
        if (i < n) luaL_addchar(&buf, '\t');
    }
    luaL_pushresult(&buf);

    const char *msg = lua_tostring(L, -1);
    if (msg) tp_engine_log(e, msg);
    lua_pop(L, 1);
    return 0;
}

/* ─── json.decode ─── */

static int l_json_decode(lua_State *L) {
    const char *str = luaL_checkstring(L, 1);
    tp_json_to_lua(L, str);
    return 1;
}

/* ─── http.get / post / put / delete ─── */

static int http_request(lua_State *L, const char *method) {
    const char *url = luaL_checkstring(L, 1);
    const char *body = NULL;
    const char *extra_headers = NULL;

    if (lua_gettop(L) >= 2 && !lua_isnil(L, 2))
        body = luaL_checkstring(L, 2);
    if (lua_gettop(L) >= 3 && !lua_isnil(L, 3))
        extra_headers = luaL_checkstring(L, 3);

    char *resp = tp_http_request_sync(url, method, body, extra_headers, NULL, 0);
    if (resp) {
        lua_pushstring(L, resp);
        free(resp);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

static int l_http_get(lua_State *L)    { return http_request(L, "GET"); }
static int l_http_post(lua_State *L)   { return http_request(L, "POST"); }
static int l_http_put(lua_State *L)    { return http_request(L, "PUT"); }
static int l_http_delete(lua_State *L) { return http_request(L, "DELETE"); }

/* ─── font() / icon() span system ─── */

/* font(text, color, size, align) -> span table
 * NOTE: this is the fix for the macOS bridge's arity bug — lib/scripting.c
 * sets each field independently when the argument is present and non-nil,
 * so font("a", "#fff") keeps its colour. */
static int l_font(lua_State *L) {
    const char *text = luaL_checkstring(L, 1);
    const char *color_str = NULL;
    int font_size = 0;
    const char *align_str = NULL;

    if (lua_gettop(L) >= 2 && !lua_isnil(L, 2))
        color_str = lua_tostring(L, 2);
    if (lua_gettop(L) >= 3 && !lua_isnil(L, 3))
        font_size = (int)lua_tointeger(L, 3);
    if (lua_gettop(L) >= 4 && !lua_isnil(L, 4))
        align_str = lua_tostring(L, 4);

    lua_newtable(L);

    lua_pushstring(L, text);
    lua_setfield(L, -2, "text");

    if (color_str) {
        lua_pushstring(L, color_str);
        lua_setfield(L, -2, "color");
    }
    if (font_size > 0) {
        lua_pushinteger(L, font_size);
        lua_setfield(L, -2, "size");
    }
    if (align_str) {
        lua_pushstring(L, align_str);
        lua_setfield(L, -2, "align");
    }

    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "__is_span");

    luaL_getmetatable(L, SPAN_MT);
    lua_setmetatable(L, -2);
    return 1;
}

/* icon(source, width, height, align) -> image span table */
static int l_icon(lua_State *L) {
    const char *source = luaL_checkstring(L, 1);
    int img_w = 16, img_h = 16;
    const char *align_str = NULL;

    if (lua_gettop(L) >= 2 && !lua_isnil(L, 2))
        img_w = (int)lua_tointeger(L, 2);
    if (lua_gettop(L) >= 3 && !lua_isnil(L, 3))
        img_h = (int)lua_tointeger(L, 3);
    if (lua_gettop(L) >= 4 && !lua_isnil(L, 4))
        align_str = lua_tostring(L, 4);

    lua_newtable(L);

    lua_pushstring(L, source);
    lua_setfield(L, -2, "img_source");

    lua_pushinteger(L, img_w);
    lua_setfield(L, -2, "img_w");

    lua_pushinteger(L, img_h);
    lua_setfield(L, -2, "img_h");

    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "__is_image");

    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "__is_span");

    if (align_str) {
        lua_pushstring(L, align_str);
        lua_setfield(L, -2, "align");
    }

    luaL_getmetatable(L, SPAN_MT);
    lua_setmetatable(L, -2);
    return 1;
}

/* Is the value at idx a span or a span list? */
static int is_span(lua_State *L, int idx) {
    if (!lua_istable(L, idx)) return 0;
    lua_getfield(L, idx, "__is_span");
    int r = lua_toboolean(L, -1);
    lua_pop(L, 1);
    if (r) return 1;
    lua_getfield(L, idx, "__is_spanlist");
    r = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return r;
}

/* Append span(s) from src into the dest list table. */
static void append_spans(lua_State *L, int src_idx, int dest_idx) {
    int abs_src = (src_idx > 0) ? src_idx : lua_gettop(L) + src_idx + 1;
    int abs_dest = (dest_idx > 0) ? dest_idx : lua_gettop(L) + dest_idx + 1;

    lua_getfield(L, abs_src, "__is_spanlist");
    int is_list = lua_toboolean(L, -1);
    lua_pop(L, 1);

    if (is_list) {
        int len = (int)lua_rawlen(L, abs_src);
        int dest_len = (int)lua_rawlen(L, abs_dest);
        for (int i = 1; i <= len; i++) {
            lua_rawgeti(L, abs_src, i);
            lua_rawseti(L, abs_dest, dest_len + i);
        }
    } else {
        int dest_len = (int)lua_rawlen(L, abs_dest);
        lua_pushvalue(L, abs_src);
        lua_rawseti(L, abs_dest, dest_len + 1);
    }
}

/* __concat: span .. span -> span list */
static int l_span_concat(lua_State *L) {
    lua_newtable(L);
    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "__is_spanlist");

    luaL_getmetatable(L, SPAN_MT);
    lua_setmetatable(L, -2);

    int result_idx = lua_gettop(L);

    /* left operand */
    if (lua_isstring(L, 1)) {
        lua_newtable(L);
        lua_pushvalue(L, 1);
        lua_setfield(L, -2, "text");
        lua_pushboolean(L, 1);
        lua_setfield(L, -2, "__is_span");
        lua_rawseti(L, result_idx, 1);
    } else if (lua_istable(L, 1)) {
        append_spans(L, 1, result_idx);
    }

    /* right operand */
    if (lua_isstring(L, 2)) {
        lua_newtable(L);
        lua_pushvalue(L, 2);
        lua_setfield(L, -2, "text");
        lua_pushboolean(L, 1);
        lua_setfield(L, -2, "__is_span");
        int n = (int)lua_rawlen(L, result_idx);
        lua_rawseti(L, result_idx, n + 1);
    } else if (lua_istable(L, 2)) {
        append_spans(L, 2, result_idx);
    }

    return 1;
}

/* ─── dialog(spec) ─── */

static int l_dialog(lua_State *L) {
    if (!lua_istable(L, 1)) {
        lua_newtable(L);
        return 1;
    }
    lua_pushboolean(L, 1);
    lua_setfield(L, 1, "_dialog");
    lua_pushvalue(L, 1);
    return 1;
}

static int is_dialog_table(lua_State *L, int idx) {
    if (!lua_istable(L, idx)) return 0;
    lua_getfield(L, idx, "_dialog");
    int r = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return r;
}

/* ─── rich span extraction ─── */

static void parse_rich_result(lua_State *L, int idx, TPDisplayContent *rich) {
    rich->count = 0;
    if (!lua_istable(L, idx)) return;

    lua_getfield(L, idx, "__is_span");
    int single = lua_toboolean(L, -1);
    lua_pop(L, 1);

    if (single) {
        TPSpan *sp = &rich->spans[0];
        memset(sp, 0, sizeof(*sp));

        lua_getfield(L, idx, "__is_image");
        int is_img = lua_toboolean(L, -1);
        lua_pop(L, 1);

        if (is_img) {
            sp->is_image = 1;
            lua_getfield(L, idx, "img_source");
            copy_str(sp->text, sizeof(sp->text), lua_tostring(L, -1));
            lua_pop(L, 1);
            lua_getfield(L, idx, "img_w");
            if (!lua_isnil(L, -1)) sp->img_w = (int)lua_tointeger(L, -1);
            lua_pop(L, 1);
            lua_getfield(L, idx, "img_h");
            if (!lua_isnil(L, -1)) sp->img_h = (int)lua_tointeger(L, -1);
            lua_pop(L, 1);
            lua_getfield(L, idx, "align");
            sp->align = parse_align_str(lua_tostring(L, -1));
            lua_pop(L, 1);
            rich->count = 1;
            return;
        }

        lua_getfield(L, idx, "text");
        const char *t = lua_tostring(L, -1);
        if (t) {
            copy_str(sp->text, sizeof(sp->text), t);
            sp->align = TP_SPAN_ALIGN_LEFT;
            sp->newline = 0;
            if (strcmp(sp->text, "\n") == 0) { sp->text[0] = '\0'; sp->newline = 1; }
            lua_pop(L, 1);

            lua_getfield(L, idx, "color");
            set_color_field(sp->color, sizeof(sp->color), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, idx, "size");
            if (!lua_isnil(L, -1)) sp->font_size = (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

            lua_getfield(L, idx, "align");
            sp->align = parse_align_str(lua_tostring(L, -1));
            lua_pop(L, 1);

            rich->count = 1;
        } else {
            lua_pop(L, 1);
        }
        return;
    }

    /* span list */
    int len = (int)lua_rawlen(L, idx);
    if (len > TP_MAX_SPANS) len = TP_MAX_SPANS;

    for (int i = 1; i <= len; i++) {
        lua_rawgeti(L, idx, i);
        if (lua_istable(L, -1)) {
            TPSpan *sp = &rich->spans[rich->count];
            memset(sp, 0, sizeof(*sp));
            sp->align = TP_SPAN_ALIGN_LEFT;
            sp->newline = 0;

            lua_getfield(L, -1, "__is_image");
            int is_img = lua_toboolean(L, -1);
            lua_pop(L, 1);

            if (is_img) {
                sp->is_image = 1;
                lua_getfield(L, -1, "img_source");
                copy_str(sp->text, sizeof(sp->text), lua_tostring(L, -1));
                lua_pop(L, 1);
                lua_getfield(L, -1, "img_w");
                if (!lua_isnil(L, -1)) sp->img_w = (int)lua_tointeger(L, -1);
                lua_pop(L, 1);
                lua_getfield(L, -1, "img_h");
                if (!lua_isnil(L, -1)) sp->img_h = (int)lua_tointeger(L, -1);
                lua_pop(L, 1);
                lua_getfield(L, -1, "align");
                sp->align = parse_align_str(lua_tostring(L, -1));
                lua_pop(L, 1);
                rich->count++;
                lua_pop(L, 1);
                continue;
            }

            lua_getfield(L, -1, "text");
            const char *t = lua_tostring(L, -1);
            if (t) {
                copy_str(sp->text, sizeof(sp->text), t);
                if (strcmp(sp->text, "\n") == 0) { sp->text[0] = '\0'; sp->newline = 1; }
            } else {
                sp->text[0] = '\0';
            }
            lua_pop(L, 1);

            lua_getfield(L, -1, "color");
            set_color_field(sp->color, sizeof(sp->color), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "size");
            if (!lua_isnil(L, -1)) sp->font_size = (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

            lua_getfield(L, -1, "align");
            sp->align = parse_align_str(lua_tostring(L, -1));
            lua_pop(L, 1);

            rich->count++;
        }
        lua_pop(L, 1);
    }
}

/* ─── dialog spec extraction ─── */

static void parse_dialog_spec(lua_State *L, int idx, TPDialogSpec *spec) {
    memset(spec, 0, sizeof(*spec));
    spec->width = 400;
    spec->height = 300;
    spec->opacity = 255;

    if (!lua_istable(L, idx)) return;

    lua_getfield(L, idx, "title");
    const char *title = lua_tostring(L, -1);
    copy_str(spec->title, sizeof(spec->title), title ? title : "Dialog");
    lua_pop(L, 1);

    lua_getfield(L, idx, "width");
    if (!lua_isnil(L, -1)) spec->width = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "height");
    if (!lua_isnil(L, -1)) spec->height = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "refresh");
    if (!lua_isnil(L, -1)) spec->refresh = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "borderless");
    spec->borderless = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "clickthrough");
    spec->clickthrough = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "opacity");
    if (!lua_isnil(L, -1)) {
        spec->opacity = (int)lua_tointeger(L, -1);
        if (spec->opacity < 0) spec->opacity = 0;
        if (spec->opacity > 255) spec->opacity = 255;
    } else {
        spec->opacity = 255;
    }
    lua_pop(L, 1);

    /* bg_color is carried by lib/scripting.h's DialogSpec on the Windows side
     * and by the mac bridge's TPDialogSpec; both engines read it. */
    lua_getfield(L, idx, "bg_color");
    set_color_field(spec->bg_color, sizeof(spec->bg_color), lua_tostring(L, -1));
    lua_pop(L, 1);

    /* transparent_bg: the host composites the dialog over the desktop rather
     * than painting bg_color. Carried through for the Flutter dialog window
     * (Phase 6); lib/scripting.c had no such field, so this is purely additive
     * and no golden baseline can depend on it. */
    lua_getfield(L, idx, "transparent_bg");
    spec->transparent_bg = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "content");
    if (!lua_istable(L, -1)) { lua_pop(L, 1); return; }

    int content_idx = lua_gettop(L);
    int n = (int)lua_rawlen(L, content_idx);
    if (n > TP_DIALOG_MAX_ITEMS) n = TP_DIALOG_MAX_ITEMS;

    for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, content_idx, i);
        if (!lua_istable(L, -1)) { lua_pop(L, 1); continue; }

        TPDialogItem *item = &spec->items[spec->item_count];
        memset(item, 0, sizeof(*item));

        lua_getfield(L, -1, "type");
        const char *type = lua_tostring(L, -1);
        if (!type) { lua_pop(L, 2); continue; }

        if (strcmp(type, "text") == 0) {
            copy_str(item->type, sizeof(item->type), "text");
            lua_pop(L, 1);

            lua_getfield(L, -1, "value");
            copy_str(item->value, sizeof(item->value), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "color");
            set_color_field(item->color, sizeof(item->color), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "size");
            if (!lua_isnil(L, -1)) item->font_size = (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

            lua_getfield(L, -1, "bold");
            item->bold = lua_toboolean(L, -1);
            lua_pop(L, 1);

            lua_getfield(L, -1, "image");
            copy_str(item->image, sizeof(item->image), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "image_width");
            item->image_width = lua_isnil(L, -1) ? 0 : (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

            lua_getfield(L, -1, "image_height");
            item->image_height = lua_isnil(L, -1) ? 0 : (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

        } else if (strcmp(type, "hr") == 0) {
            copy_str(item->type, sizeof(item->type), "hr");
            lua_pop(L, 1);

        } else if (strcmp(type, "table") == 0) {
            copy_str(item->type, sizeof(item->type), "table");
            lua_pop(L, 1);

            lua_getfield(L, -1, "columns");
            if (lua_istable(L, -1)) {
                int nc = (int)lua_rawlen(L, -1);
                if (nc > TP_DIALOG_MAX_COLS) nc = TP_DIALOG_MAX_COLS;
                item->col_count = nc;
                for (int c = 1; c <= nc; c++) {
                    lua_rawgeti(L, -1, c);
                    copy_str(item->columns[c - 1], sizeof(item->columns[0]), lua_tostring(L, -1));
                    lua_pop(L, 1);
                }
            }
            lua_pop(L, 1);

            lua_getfield(L, -1, "rows");
            if (lua_istable(L, -1)) {
                int nr = (int)lua_rawlen(L, -1);
                if (nr > TP_DIALOG_MAX_ROWS) nr = TP_DIALOG_MAX_ROWS;
                item->row_count = nr;
                for (int r = 1; r <= nr; r++) {
                    lua_rawgeti(L, -1, r);
                    if (lua_istable(L, -1)) {
                        int rc = (int)lua_rawlen(L, -1);
                        if (rc > item->col_count) rc = item->col_count;
                        for (int c = 1; c <= rc; c++) {
                            lua_rawgeti(L, -1, c);
                            copy_str(item->cells[r - 1][c - 1], sizeof(item->cells[0][0]),
                                     lua_tostring(L, -1));
                            lua_pop(L, 1);
                        }
                        lua_getfield(L, -1, "url");
                        copy_str(item->row_urls[r - 1], sizeof(item->row_urls[0]),
                                 lua_tostring(L, -1));
                        lua_pop(L, 1);
                        lua_getfield(L, -1, "cmd");
                        copy_str(item->row_cmds[r - 1], sizeof(item->row_cmds[0]),
                                 lua_tostring(L, -1));
                        lua_pop(L, 1);
                    }
                    lua_pop(L, 1);
                }
            }
            lua_pop(L, 1);

        } else if (strcmp(type, "image") == 0) {
            copy_str(item->type, sizeof(item->type), "image");
            lua_pop(L, 1);

            lua_getfield(L, -1, "source");
            copy_str(item->image, sizeof(item->image), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "width");
            item->image_width = lua_isnil(L, -1) ? 0 : (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

            lua_getfield(L, -1, "height");
            item->image_height = lua_isnil(L, -1) ? 0 : (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

        } else if (strcmp(type, "button") == 0) {
            copy_str(item->type, sizeof(item->type), "button");
            lua_pop(L, 1);

            lua_getfield(L, -1, "value");
            copy_str(item->value, sizeof(item->value), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "url");
            copy_str(item->url, sizeof(item->url), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "cmd");
            copy_str(item->cmd, sizeof(item->cmd), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "color");
            set_color_field(item->color, sizeof(item->color), lua_tostring(L, -1));
            lua_pop(L, 1);

            /* lib/scripting.c reads the button background from "bg". */
            lua_getfield(L, -1, "bg");
            set_color_field(item->bg, sizeof(item->bg), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "size");
            if (!lua_isnil(L, -1)) item->font_size = (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

        } else if (strcmp(type, "webview") == 0) {
            /* Carried only. The engine records the item so the Flutter dialog
             * window can host a WebView2 / WKWebView; embedding itself is
             * Phase 9 (native/win/webview2_host.cpp, native/mac/WebViewHost.swift)
             * and deliberately does not live in this platform-neutral file.
             * The URL reuses `url`; the box size is `web_w`/`web_h`. */
            copy_str(item->type, sizeof(item->type), TP_DIALOG_TYPE_WEBVIEW);
            lua_pop(L, 1);

            lua_getfield(L, -1, "url");
            copy_str(item->url, sizeof(item->url), lua_tostring(L, -1));
            lua_pop(L, 1);

            lua_getfield(L, -1, "width");
            item->web_w = lua_isnil(L, -1) ? 0 : (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

            lua_getfield(L, -1, "height");
            item->web_h = lua_isnil(L, -1) ? 0 : (int)lua_tointeger(L, -1);
            lua_pop(L, 1);

        } else {
            lua_pop(L, 1);
            lua_pop(L, 1);
            continue;
        }

        spec->item_count++;
        lua_pop(L, 1); /* content item */
    }
    lua_pop(L, 1); /* content table */
}

/* ─── result tuple ─── */

/* Consume up to 3 return values sitting on the stack and fill `out`.
 * The stack is cleared before returning. */
static void parse_return_values(lua_State *L, TPScriptResult *out) {
    int nresults = lua_gettop(L);

    out->rich.count = 0;
    out->display[0] = '\0';

    if (nresults >= 1 && lua_istable(L, 1) && is_span(L, 1)) {
        parse_rich_result(L, 1, &out->rich);
        /* Plain-text fallback = concatenation of every span's text.
         * FOLLOW-UP: for an image span, `text` holds the image source, so
         * image sources are concatenated in here too. lib/scripting.c does
         * exactly the same thing (it strcats sp->text for all spans), so
         * this is preserved byte-for-byte for the golden baseline. Hosts
         * that render rich.count > 0 never look at `display`. */
        size_t used = 0;
        for (int i = 0; i < out->rich.count; i++) {
            const char *s = out->rich.spans[i].text;
            size_t n = strlen(s);
            if (used + n >= sizeof(out->display)) n = sizeof(out->display) - used - 1;
            memcpy(out->display + used, s, n);
            used += n;
            out->display[used] = '\0';
        }
    } else if (nresults >= 1) {
        const char *s = lua_tostring(L, 1);
        if (s) copy_str(out->display, sizeof(out->display), s);
    }

    if (nresults >= 2) {
        out->clickable = lua_toboolean(L, 2);
    }

    if (nresults >= 3) {
        if (is_dialog_table(L, 3)) {
            out->click_action = TP_CLICK_DIALOG;
            parse_dialog_spec(L, 3, &out->dialog);
        } else {
            out->click_action = TP_CLICK_URL;
            const char *url = lua_tostring(L, 3);
            if (url) copy_str(out->click_url, sizeof(out->click_url), url);
        }
    }

    lua_settop(L, 0);
}

/* ─── execution entry points ─── */

int tp_lua_run_source(TPEngine *e, const char *src, size_t len,
                      const char *chunkname, const char *args_json,
                      TPScriptResult *out) {
    lua_State *L = e->L;

    /* inject `args` (shared by the file and template paths) */
    if (args_json && args_json[0]) {
        if (!tp_json_to_lua(L, args_json) || !lua_istable(L, -1)) {
            lua_settop(L, 0);
            lua_newtable(L);
        }
    } else {
        lua_newtable(L);
    }
    lua_setglobal(L, "args");

    int status = luaL_loadbuffer(L, src, len, chunkname);
    if (status == LUA_OK) {
        status = lua_pcall(L, 0, LUA_MULTRET, 0);
    }

    if (status != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        copy_str(out->error, sizeof(out->error), err ? err : "[lua error]");
        out->ok = 0;
        tp_engine_log(e, out->error);
        lua_settop(L, 0);
        return 0;
    }

    parse_return_values(L, out);
    out->ok = 1;
    return 1;
}

int tp_lua_run_template(TPEngine *e, const char *lua_code,
                        const char *response_raw, TPScriptResult *out) {
    lua_State *L = e->L;

    lua_pushstring(L, response_raw ? response_raw : "");
    lua_setglobal(L, "response");

    /* Wrap the code so multiple return values work, exactly as
     * lib/scripting.c's script_exec does. */
    size_t code_len = strlen(lua_code);
    size_t cap = code_len + 64;
    char *wrapped = (char *)malloc(cap);
    if (!wrapped) {
        copy_str(out->error, sizeof(out->error), "out of memory");
        out->ok = 0;
        return 0;
    }
    snprintf(wrapped, cap, "return (function()\n%s\nend)()", lua_code);

    int rc = tp_lua_run_source(e, wrapped, strlen(wrapped), "=template",
                               NULL, out);
    free(wrapped);
    return rc;
}

/* ─── registration ─── */

void tp_lua_register_api(TPEngine *e) {
    lua_State *L = e->L;

    /* span metatable (__concat) */
    luaL_newmetatable(L, SPAN_MT);
    lua_pushcfunction(L, l_span_concat);
    lua_setfield(L, -2, "__concat");
    lua_pop(L, 1);

    /* font / icon / dialog */
    lua_pushcfunction(L, l_font);
    lua_setglobal(L, "font");
    lua_pushcfunction(L, l_icon);
    lua_setglobal(L, "icon");
    lua_pushcfunction(L, l_dialog);
    lua_setglobal(L, "dialog");

    /* log() carries the engine as an upvalue so it can reach the sink */
    lua_pushlightuserdata(L, e);
    lua_pushcclosure(L, l_log, 1);
    lua_setglobal(L, "log");

    /* json.decode */
    lua_newtable(L);
    lua_pushcfunction(L, l_json_decode);
    lua_setfield(L, -2, "decode");
    lua_setglobal(L, "json");

    /* http.* */
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

    /* sys.* (platform-owned table) */
    tp_sysinfo_register_lua(L);
}
