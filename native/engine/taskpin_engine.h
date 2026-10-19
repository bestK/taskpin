/*
 * taskpin_engine.h — the single public ABI of the TaskPin Lua engine.
 *
 * Design rules (see docs/FLUTTER_REWRITE_PLAN.md, "Phase 2 — 统一 C 引擎"):
 *
 *   - UTF-8 everywhere. No wide strings cross this boundary.
 *   - No windows.h, no Objective-C types. This header must compile under
 *     MinGW gcc, MSVC and Apple clang alike, so it is what dart:ffi binds to.
 *   - Handle-based even though v1 uses a single instance, so that a later
 *     build can run N engines (e.g. one for slow HTTP items) without an ABI
 *     change.
 *   - POD structs, flat arrays, fixed capacities — the shape dart:ffi wants.
 *
 * The layout is derived from the macOS bridge's flat UTF-8 ABI
 * (src/clua_bridge/taskpin_lua.h) and extended with what the Windows engine
 * carries (lib/scripting.h):
 *
 *   - TPSpan gains `align` and `newline` (the mac bridge was missing both,
 *     which is why the macOS menu bar only kept the first span's colour).
 *   - TPDialogItem gains `bg` (button background), per-row `cmd`, and the
 *     carried-only `webview` item (url + web_w/web_h).
 *   - TPDialogSpec gains `bg_color` and `transparent_bg`.
 *   - TPScriptResult gains `error[1024]` and `ok`, so a Lua failure is never
 *     rendered into the taskbar as a raw traceback.
 */

#ifndef TASKPIN_ENGINE_H
#define TASKPIN_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

/* ─── capacities (mirrors lib/scripting.h) ─── */

#define TP_MAX_SPANS        32
#define TP_SPAN_TEXT_LEN    512
#define TP_COLOR_LEN        16
#define TP_DISPLAY_LEN      2048
#define TP_URL_LEN          1024
#define TP_ERROR_LEN        1024

#define TP_DIALOG_MAX_ITEMS 8
#define TP_DIALOG_MAX_COLS  6
#define TP_DIALOG_MAX_ROWS  24

/* span alignment */
#define TP_SPAN_ALIGN_LEFT   0
#define TP_SPAN_ALIGN_RIGHT  1
#define TP_SPAN_ALIGN_CENTER 2

/* click_action */
#define TP_CLICK_URL    0
#define TP_CLICK_DIALOG 1

/* dialog content item types, as carried in TPDialogItem.type.
 *
 * TP_DIALOG_TYPE_WEBVIEW is carried only: the engine parses the item and
 * passes url/width/height through so the Flutter UI can render it. WebView2
 * embedding is Phase 9 of the rewrite plan and lives in native/win, not here. */
#define TP_DIALOG_TYPE_WEBVIEW "webview"

/* ─── display spans ─── */

typedef struct {
    char text[TP_SPAN_TEXT_LEN]; /* text, or the image source when is_image */
    char color[TP_COLOR_LEN];    /* "#RRGGBB" / "#RGB", "" = use default     */
    int  font_size;              /* 0 = default                              */
    int  align;                  /* TP_SPAN_ALIGN_*                          */
    int  newline;                /* 1 = this span starts a new line          */
    int  is_image;               /* 1 = `text` holds an image source         */
    int  img_w, img_h;           /* requested display size                   */
} TPSpan;

typedef struct {
    TPSpan spans[TP_MAX_SPANS];
    int count;
} TPDisplayContent;

/* ─── dialog DSL ─── */

typedef struct {
    char type[16];       /* "text" | "hr" | "table" | "image" | "button"
                          * | "webview"                                */
    char value[256];     /* text / button label                               */
    char color[TP_COLOR_LEN];
    int  font_size;      /* 0 = default                                       */
    int  bold;
    char image[512];     /* inline icon source for a text item                */
    int  image_width, image_height;
    char url[512];       /* button / table-row URL, or the webview URL        */
    char cmd[512];       /* button / table-row command                        */
    char bg[TP_COLOR_LEN]; /* button background; "" = default                 */
    /* webview (type == "webview"): url is above, these are its box size. */
    int  web_w, web_h;
    /* table */
    int  col_count;
    int  row_count;
    char columns[TP_DIALOG_MAX_COLS][64];
    char cells[TP_DIALOG_MAX_ROWS][TP_DIALOG_MAX_COLS][64];
    char row_urls[TP_DIALOG_MAX_ROWS][256];
    char row_cmds[TP_DIALOG_MAX_ROWS][256];
} TPDialogItem;

typedef struct {
    char title[128];
    int  width, height;
    int  refresh;         /* seconds, 0 = no auto-refresh                     */
    int  borderless;
    int  clickthrough;
    int  opacity;         /* 0-255, 255 = opaque (default)                    */
    char bg_color[TP_COLOR_LEN]; /* "" = default                              */
    int  transparent_bg;  /* 1 = let the host composite the dialog over the
                           *     desktop instead of painting bg_color       */
    int  item_count;
    TPDialogItem items[TP_DIALOG_MAX_ITEMS];
} TPDialogSpec;

/* ─── script result ─── */

typedef struct {
    TPDisplayContent rich;      /* rich spans; use when rich.count > 0         */
    char display[TP_DISPLAY_LEN]; /* plain-text fallback                       */
    int  clickable;
    int  click_action;          /* TP_CLICK_URL | TP_CLICK_DIALOG              */
    char click_url[TP_URL_LEN]; /* valid when click_action == TP_CLICK_URL     */
    TPDialogSpec dialog;        /* valid when click_action == TP_CLICK_DIALOG  */
    char error[TP_ERROR_LEN];   /* Lua error text; empty on success            */
    int  ok;                    /* 1 = ran without a Lua error                 */
} TPScriptResult;

/* ─── @param / @refresh declarations ─── */

typedef struct {
    char key[64];
    char type[16];   /* "string", "number", ... as written in the header      */
    char label[128];
} TPParamDecl;

/* ─── engine handle ─── */

typedef struct TPEngine TPEngine;

/* Log sink. level is reserved (always 0 for now); utf8_msg is NUL-terminated. */
typedef void (*TPLogFn)(int level, const char *utf8_msg, void *user);

/* ─── lifecycle ─── */

/* Create an engine (one Lua state + the TaskPin API). NULL on failure. */
TPEngine *tp_engine_create(void);

/* Destroy an engine and its Lua state. */
void tp_engine_destroy(TPEngine *e);

/* Redirect log() output. Passing NULL restores the default sink, which
 * appends to "taskpin.log" in the current working directory (matching
 * lib/scripting.c's script_log_write). */
void tp_set_log_callback(TPEngine *e, TPLogFn cb, void *user);

/* Per-execution Lua instruction budget; exceeding it raises a Lua error
 * ("instruction budget exceeded") instead of hanging. Default 50,000,000.
 * Pass <= 0 to disable the watchdog. */
void tp_engine_set_instruction_budget(TPEngine *e, long long instructions);

/* ─── execution ─── */

/* Run a .lua file. `args_json` is an optional JSON object that becomes the
 * global `args` table (NULL or "" means an empty table).
 *
 * The path is used as given: absolute, or relative to the current working
 * directory. Path resolution is the host's job, not the engine's.
 *
 * Returns 1 on success (out->ok == 1), 0 on a Lua/IO error (out->error set).
 * `out` is always fully initialised. */
int tp_execute_file(TPEngine *e, const char *utf8_path,
                    const char *args_json, TPScriptResult *out);

/* Run Lua source with the global `response` set to `response_raw`, as the
 * expression-template mode of lib/scripting.c does. Same return contract. */
int tp_execute_template(TPEngine *e, const char *lua_code,
                        const char *response_raw, TPScriptResult *out);

/* ─── header declarations ─── */

/* Parse `-- @param <key> <type> <label>` lines from a script header.
 * Returns the number of declarations found (up to max_decls). */
int tp_parse_params(const char *utf8_path, TPParamDecl *out, int max_decls);

/* Parse `-- @refresh <ms>` from a script header. Returns milliseconds,
 * or 0 when not declared. */
int tp_parse_refresh(const char *utf8_path);

/* ─── internals ─────────────────────────────────────────────────────────
 * Not part of the public ABI. Translation units inside native/engine define
 * TASKPIN_ENGINE_INTERNAL before including this header; everyone else
 * (dart:ffi, tool/engine_cli.c) never sees this block.
 * -------------------------------------------------------------------- */

#ifdef TASKPIN_ENGINE_INTERNAL

#include <stddef.h>

/* Forward declaration so this header stays free of Lua includes. lua.h
 * declares the same type as `typedef struct lua_State lua_State;`. */
typedef struct lua_State lua_State;

/* One engine == one Lua state. Defined here so the Lua-facing TU can reach
 * the log sink. */
struct TPEngine {
    lua_State *L;
    TPLogFn    log_cb;
    void      *log_user;
    long long  budget;    /* instruction budget per execution (<= 0 = off)  */
    long long  used;      /* instructions consumed by the current execution */
    long long  hook_step; /* hook period, in instructions                   */
};

#define TP_ENGINE_REGISTRY_KEY "taskpin.engine"

/* taskpin_lua.c */
void tp_lua_register_api(TPEngine *e);
int  tp_lua_run_source(TPEngine *e, const char *src, size_t len,
                       const char *chunkname, const char *args_json,
                       TPScriptResult *out);
int  tp_lua_run_template(TPEngine *e, const char *lua_code,
                         const char *response_raw, TPScriptResult *out);

/* tp_json.c — decode UTF-8 JSON onto the Lua stack.
 * Returns 1 when a value was pushed, 0 when nil was pushed (invalid JSON). */
int  tp_json_to_lua(lua_State *L, const char *json);

/* tp_engine.c */
void tp_engine_log(TPEngine *e, const char *utf8_msg);

#endif /* TASKPIN_ENGINE_INTERNAL */

#ifdef __cplusplus
}
#endif

#endif /* TASKPIN_ENGINE_H */
