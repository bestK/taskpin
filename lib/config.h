#ifndef TASKPIN_CONFIG_H
#define TASKPIN_CONFIG_H

#include <windows.h>

#define CFG_MAX_URL   1024
#define CFG_MAX_NAME  128
#define CFG_MAX_EXPR  4096
#define CFG_MAX_PATH  512
#define CFG_MAX_ITEMS 64
#define CFG_MAX_PARAMS 16
#define CFG_MAX_PARAM_KEY 64
#define CFG_MAX_PARAM_VAL 256
#define CFG_MAX_SOURCES 8

#define ITEM_TYPE_URL  0
#define ITEM_TYPE_LUA  1

typedef struct {
    WCHAR key[CFG_MAX_PARAM_KEY];
    WCHAR value[CFG_MAX_PARAM_VAL];
    WCHAR label[CFG_MAX_NAME];       /* display label from @param comment */
} ParamEntry;

typedef struct {
    int   type;                      /* ITEM_TYPE_URL or ITEM_TYPE_LUA */
    WCHAR name[CFG_MAX_NAME];
    DWORD interval_ms;
    /* URL mode */
    WCHAR url[CFG_MAX_URL];
    WCHAR req_headers[CFG_MAX_URL];  /* custom HTTP headers for URL mode */
    WCHAR field_expr[CFG_MAX_EXPR];  /* Lua code or $.path template */
    BOOL  click_enabled;
    WCHAR click_url[CFG_MAX_URL];
    /* Lua file mode */
    WCHAR lua_path[CFG_MAX_PATH];
    /* Script params (from @param declarations) */
    ParamEntry params[CFG_MAX_PARAMS];
    int param_count;
    BOOL pinned;                     /* whether this item is shown in taskbar */
    int   bar_width;                 /* 0 = use global default */
    int   bar_x;                     /* -1 = auto position */
    int   bar_y;                     /* -1 = auto position */
    COLORREF bar_bg_color;           /* 0xFFFFFFFF = use global default */
} PinItem;

typedef struct {
    PinItem items[CFG_MAX_ITEMS];
    int     count;
    int     width;
    int     pos_x;      /* -1 = auto (left of tray notify area) */
    int     pos_y;      /* -1 = auto */
    int     font_size;  /* point size, default 9 */
    COLORREF font_color;
    COLORREF bg_color;  /* background, use 0xFFFFFFFF for transparent */
    BOOL  scroll_enabled; /* auto-scroll long text, default TRUE */
    /* Plugin market sources (GitHub repos like "user/repo") */
    WCHAR sources[CFG_MAX_SOURCES][CFG_MAX_NAME];
    int   source_count;
} TaskPinConfig;

void config_load(TaskPinConfig *cfg);
void config_save(const TaskPinConfig *cfg);
void config_get_path(WCHAR *buf, DWORD len);

#endif