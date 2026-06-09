#ifndef TASKPIN_SCRIPT_DIALOG_H
#define TASKPIN_SCRIPT_DIALOG_H

#include <windows.h>
#include "scripting.h"
#include "config.h"

#define IDT_DIALOG_REFRESH 10

void script_dialog_init(HINSTANCE hinst);
void show_script_dialog(const WCHAR *lua_path, const ParamEntry *params, int param_count,
                        const DialogSpec *spec);
void script_dialog_close_by_path(const WCHAR *lua_path);
void script_dialog_close_all(void);
BOOL script_dialog_is_open(const WCHAR *lua_path);

#endif