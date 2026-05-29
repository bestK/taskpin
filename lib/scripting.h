#ifndef TASKPIN_SCRIPTING_H
#define TASKPIN_SCRIPTING_H

#include <windows.h>
#include "config.h"

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

typedef enum { DI_TEXT, DI_HR, DI_TABLE, DI_IMG, DI_BUTTON } DialogItemType;

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
    WCHAR cells[DIALOG_MAX_ROWS][DIALOG_MAX_COLS][64];
    COLORREF row_colors[DIALOG_MAX_ROWS];
    char row_urls[DIALOG_MAX_ROWS][256];
    /* image fields (for DI_IMG standalone or DI_TEXT inline icon) */
    char img_source[512];
    int img_w, img_h;
    /* button/link url or command */
    char url[512];
    char cmd[512];
} DialogItem;

typedef struct {
    WCHAR title[128];
    int width, height;
    int refresh;         /* seconds, 0 = no auto-refresh */
    BOOL borderless;     /* TRUE = no title bar */
    BOOL clickthrough;   /* TRUE = mouse clicks pass through */
    int opacity;         /* 0-255, 0=fully transparent, 255=opaque (default) */
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
} ScriptResult;

/* Parsed @param declaration from script header */
typedef struct {
    char key[64];
    char type[16];   /* "string", "number" */
    char label[128];
} ScriptParamDecl;

void script_init(void);
void script_shutdown(void);

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

#endif