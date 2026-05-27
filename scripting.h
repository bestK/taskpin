#ifndef TASKPIN_SCRIPTING_H
#define TASKPIN_SCRIPTING_H

#include <windows.h>
#include "config.h"

typedef struct {
    WCHAR display[2048];     /* text to show in taskbar */
    BOOL  clickable;         /* whether click opens URL */
    WCHAR click_url[1024];   /* URL to open on click */
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