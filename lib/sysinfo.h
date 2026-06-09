#ifndef TASKPIN_SYSINFO_H
#define TASKPIN_SYSINFO_H

#include <windows.h>

void sysinfo_register_lua(void *lua_state);
void sysinfo_poll_keys(void);
BOOL sysinfo_is_admin(void);

#endif