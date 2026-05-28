#ifndef TASKPIN_SCRIPTING_H
#define TASKPIN_SCRIPTING_H

#include <windows.h>
#include "config.h"

#define MAX_SPANS 32
#define SPAN_TEXT_LEN 256

#define SPAN_ALIGN_LEFT   0
#define SPAN_ALIGN_RIGHT  1
#define SPAN_ALIGN_CENTER 2

typedef struct {
    WCHAR text[SPAN_TEXT_LEN];
    COLORREF color;      /* 0xFFFFFFFF = use default */
    int font_size;       /* 0 = use default */
    int align;           /* SPAN_ALIGN_LEFT/RIGHT/CENTER */
    BOOL newline;        /* this span starts a new line */
} DisplaySpan;

typedef struct {
    DisplaySpan spans[MAX_SPANS];
    int count;
} DisplayContent;

typedef struct {
    WCHAR display[2048];     /* text to show in taskbar (plain mode) */
    BOOL  clickable;         /* whether click opens URL */
    WCHAR click_url[1024];   /* URL to open on click */
    DisplayContent rich;     /* rich text spans (if count>0, use this) */
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

#endif