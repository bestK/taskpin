#ifndef taskpin_lua_h
#define taskpin_lua_h

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

typedef struct {
    char text[512];
    char color[16];
    int font_size;
    int is_image;
    int img_w, img_h;
} TPSpan;

typedef struct {
    char type[16];       // text, hr, button, image, table
    char value[256];
    char color[16];
    int font_size;
    int bold;
    char image[512];
    int image_width, image_height;
    char url[512];
    char cmd[512];
    // table
    int col_count;
    int row_count;
    char columns[6][64];
    char cells[24][6][64];
    char row_urls[24][256];
} TPDialogItem;

typedef struct {
    char title[128];
    int width, height;
    int refresh;
    int borderless;
    int clickthrough;
    int opacity;
    int item_count;
    TPDialogItem items[8];
} TPDialogSpec;

void tp_lua_init(void);
void tp_lua_shutdown(void);

int tp_lua_execute(const char *filepath, const char *args_json);

int tp_lua_get_nresults(void);
void tp_lua_clear_stack(void);
const char *tp_lua_get_error(void);
int tp_lua_is_span(int idx);
int tp_lua_is_dialog(int idx);
int tp_lua_get_bool(int idx);
const char *tp_lua_get_string(int idx);

int tp_lua_span_count(int idx);
TPSpan tp_lua_get_span(int list_idx, int span_idx);

// Dialog extraction
TPDialogSpec tp_lua_get_dialog(int idx);

#endif
