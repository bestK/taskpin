#ifndef TASKPIN_SCRIPTING_H
#define TASKPIN_SCRIPTING_H

#include <windows.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_SPANS 32
#define SPAN_TEXT_LEN 256
#define IMG_SOURCE_MAX (200 * 1024)

#define SPAN_ALIGN_LEFT   0
#define SPAN_ALIGN_RIGHT  1
#define SPAN_ALIGN_CENTER 2

typedef struct {
    WCHAR text[SPAN_TEXT_LEN];
    COLORREF color;      /* 0xFFFFFFFF = use default */
    int font_size;       /* 0 = use default */
    int align;           /* SPAN_ALIGN_LEFT/RIGHT/CENTER */
    BOOL newline;        /* this span starts a new line */
    BOOL is_image;       /* TRUE = this span is an image, not text */
    char img_source[IMG_SOURCE_MAX]; /* image source: path/url/data URI */
    int img_w, img_h;    /* requested display size */
    int src_x, src_y, src_w, src_h;  /* sprite sheet crop (0 = full) */
    BOOL is_button;      /* TRUE = clickable button with bg fill + border */
    BOOL is_input;       /* TRUE = render as EDIT input field */
    char cmd[512];       /* shell command (when is_button) */
    char response[4096]; /* response content to write to event response_file */
    char prompt[256];    /* input name (used as {name} placeholder in response) */
    char placeholder[256]; /* input cue banner text */
    int input_w, input_h; /* input field size (px), 0 = default */
    COLORREF bg_color;   /* button/input background color, 0xFFFFFFFF = default */
    COLORREF hover_bg;   /* button hover background, 0xFFFFFFFF = default */
    COLORREF hover_color;/* button hover text color, 0xFFFFFFFF = default */
    COLORREF border_color;/* button border color, 0xFFFFFFFF = use text color */
    int margin;          /* margin-right in pixels, default 0 */
    char patch_local[512];  /* JSON: keys to patch into bar-local state */
    char patch_global[512]; /* JSON: keys to patch into global state */
} DisplaySpan;

typedef struct {
    DisplaySpan spans[MAX_SPANS];
    int count;
} DisplayContent;

/* ─── Dialog DSL ─── */

#define DIALOG_MAX_ITEMS 8
#define DIALOG_MAX_COLS  6
#define DIALOG_MAX_ROWS  24

#define CLICK_URL    0
#define CLICK_DIALOG 1

typedef enum { DI_TEXT, DI_HR, DI_TABLE, DI_IMG, DI_BUTTON, DI_WEBVIEW } DialogItemType;

typedef struct {
    DialogItemType type;
    WCHAR text[256];
    COLORREF color;      /* 0xFFFFFFFF = use default (text/button fg color) */
    COLORREF bg_color;   /* 0xFFFFFFFF = use default (button bg) */
    int font_size;       /* 0 = use default */
    BOOL bold;
    int col_count;
    int row_count;
    WCHAR columns[DIALOG_MAX_COLS][64];
    int col_widths[DIALOG_MAX_COLS];  /* per-column width in px, 0 = auto */
    WCHAR cells[DIALOG_MAX_ROWS][DIALOG_MAX_COLS][64];
    COLORREF row_colors[DIALOG_MAX_ROWS];
    char row_urls[DIALOG_MAX_ROWS][256];
    char row_cmds[DIALOG_MAX_ROWS][256];
    char row_luas[DIALOG_MAX_ROWS][256];
    WCHAR row_btn_text[DIALOG_MAX_ROWS][32];
    /* image fields (for DI_IMG standalone or DI_TEXT inline icon) */
    char img_source[512];
    int src_x, src_y, src_w, src_h;  /* sprite sheet crop region (0 = use full image) */
    /* generic item dimensions — used by image, button, webview */
    int width, height;
    /* button/link url or command or lua code */
    char url[512];
    char cmd[512];
    char lua_code[512];
    int align;  /* ALIGN_LEFT=0, ALIGN_CENTER, ALIGN_RIGHT, ALIGN_INLINE */
    BOOL word_wrap;  /* TRUE = auto wrap text in table cells */
} DialogItem;

enum { ALIGN_LEFT = 0, ALIGN_CENTER, ALIGN_RIGHT, ALIGN_INLINE };

typedef struct {
    WCHAR title[128];
    COLORREF title_bg_color;   /* title bar background color, 0xFFFFFFFF = default */
    COLORREF title_color;      /* title bar text color, 0xFFFFFFFF = default */
    char icon[512];            /* title bar icon path (local file or URL) */
    int width, height;
    int refresh;         /* milliseconds, 0 = no auto-refresh */
    BOOL borderless;     /* TRUE = no title bar */
    BOOL clickthrough;   /* TRUE = mouse clicks pass through */
    BOOL transparent_bg; /* TRUE = background is transparent (color key) */
    int opacity;         /* 0-255, 0=fully transparent, 255=opaque (default) */
    int x, y;            /* window position, -1 = center/no-move */
    DialogItem items[DIALOG_MAX_ITEMS];
    int item_count;
} DialogSpec;

/* ─── Script result ─── */

typedef struct {
    WCHAR display[2048];     /* text to show in taskbar (plain mode) */
    BOOL  clickable;         /* whether click action is enabled */
    int   click_action;      /* CLICK_URL or CLICK_DIALOG */
    WCHAR click_url[1024];   /* URL to open (when click_action==CLICK_URL) */
    DisplayContent rich;     /* rich text spans (if count>0, use this) */
    DialogSpec dialog;       /* dialog spec (when click_action==CLICK_DIALOG) */
    WCHAR tooltip[512];      /* tooltip text (4th return value) */
} ScriptResult;

/* Parsed @param declaration from script header */
typedef struct {
    char key[64];
    char type[16];   /* "string", "number" */
    char label[128];
} ScriptParamDecl;

void script_init(void);
void script_shutdown(void);
void script_set_global_bool(const char *name, BOOL value);
void script_set_global_string(const char *name, const char *value);

/* Execute a Lua expression and return result as JSON string (caller frees).
   E.g. expr="sys.cpu()" → returns "45" or "null" on error. */
char *script_eval_expr(const char *expr);

BOOL script_exec(const char *lua_code, const char *response_raw, ScriptResult *result);

/* Execute a Lua file with params injected as `args` table. */
BOOL script_exec_file(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                      ScriptResult *result);

/* Parse @param declarations from a Lua file header.
   Returns number of params found (up to max_decls). */
int script_parse_params(const WCHAR *lua_path, ScriptParamDecl *decls, int max_decls);

/* Parse @refresh declaration from a Lua file header.
   Returns milliseconds (0 if not declared). */
int script_parse_refresh(const WCHAR *lua_path);

/* Parse @realtime declaration from script header. */
BOOL script_parse_realtime(const WCHAR *lua_path);

/* Parse @bar_width declaration from a Lua file header.
   Returns pixels (0 if not declared). */
int script_parse_bar_width(const WCHAR *lua_path);

/* Parse @name declaration or first-line description from a Lua file header. */
void script_parse_name(const WCHAR *lua_path, WCHAR *out, int out_size);

/* Parse @hotkey declaration from a Lua file header.
   Returns the hotkey string (e.g. "Ctrl+Shift+T") or empty. */
void script_parse_hotkey(const WCHAR *lua_path, char *out, int out_size);

/* Parse @admin declaration from script header.
   Returns TRUE if declared. If out_desc provided, copies the description. */
BOOL script_parse_admin(const WCHAR *lua_path);
void script_parse_admin_desc(const WCHAR *lua_path, char *out_desc, int out_size);

/* Parse @version declaration from a Lua file header. */
void script_parse_version(const WCHAR *lua_path, char *out, int out_size);

/* Check @require declaration. Returns TRUE if satisfied or not declared. */
BOOL script_check_require(const WCHAR *lua_path, char *required, int req_size);

#ifdef __cplusplus
}
#endif

#endif