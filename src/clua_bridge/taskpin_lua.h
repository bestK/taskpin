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

void tp_lua_init(void);
void tp_lua_shutdown(void);

// Execute a Lua file. Returns number of return values on stack, or -1 on error.
int tp_lua_execute(const char *filepath, const char *args_json);

// Stack inspection
int tp_lua_get_nresults(void);
void tp_lua_clear_stack(void);
const char *tp_lua_get_error(void);
int tp_lua_is_span(int idx);
int tp_lua_is_dialog(int idx);
int tp_lua_get_bool(int idx);
const char *tp_lua_get_string(int idx);

// Span extraction
int tp_lua_span_count(int idx);
TPSpan tp_lua_get_span(int list_idx, int span_idx);

#endif
