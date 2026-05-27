#ifndef TASKPIN_CONFIG_H
#define TASKPIN_CONFIG_H

#include <windows.h>

#define CFG_MAX_URL   1024
#define CFG_MAX_NAME  128
#define CFG_MAX_EXPR  512
#define CFG_MAX_PATH  512
#define CFG_MAX_ITEMS 64

typedef struct {
    WCHAR name[CFG_MAX_NAME];
    WCHAR url[CFG_MAX_URL];
    DWORD interval_ms;
    WCHAR field_expr[CFG_MAX_EXPR];  /* template: "label:$.path" */
    BOOL  click_enabled;
    WCHAR click_url[CFG_MAX_URL];    /* click URL template: "http://x/$.id" */
} PinItem;

typedef struct {
    PinItem items[CFG_MAX_ITEMS];
    int     count;
    int     selected;   /* index of active item shown in taskbar, -1 = none */
    int     width;
    int     pos_x;      /* -1 = auto (left of tray notify area) */
    int     pos_y;      /* -1 = auto */
    int     font_size;  /* point size, default 9 */
    COLORREF font_color;
    COLORREF bg_color;  /* background, use 0xFFFFFFFF for transparent */
} TaskPinConfig;

void config_load(TaskPinConfig *cfg);
void config_save(const TaskPinConfig *cfg);
void config_get_path(WCHAR *buf, DWORD len);

#endif