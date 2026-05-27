#ifndef TASKPIN_SCRIPTING_H
#define TASKPIN_SCRIPTING_H

#include <windows.h>

typedef struct {
    WCHAR display[2048];     /* text to show in taskbar */
    BOOL  clickable;         /* whether click opens URL */
    WCHAR click_url[1024];   /* URL to open on click */
} ScriptResult;

void script_init(void);
void script_shutdown(void);

/* Execute Lua code with `response` global set to response_raw.
   Script should: return "display text", true/false, "url"
   Returns TRUE if script executed successfully. */
BOOL script_exec(const char *lua_code, const char *response_raw, ScriptResult *result);

/* Execute a Lua file. The file should return 3 values like script_exec.
   No `response` global is set — the script fetches its own data via http.get(). */
BOOL script_exec_file(const WCHAR *lua_path, ScriptResult *result);

#endif