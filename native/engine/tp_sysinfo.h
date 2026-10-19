/*
 * tp_sysinfo.h — internal platform ABI for the sys.*() Lua API.
 *
 * The platform TU owns the whole `sys` table: it creates it, fills in the
 * functions it can support, and assigns it as the global `sys`. That way the
 * Lua layer has no #ifdefs and no knowledge of what a given OS provides.
 *
 * Implementations:
 *   tp_sysinfo_win.c  ported from lib/sysinfo.c
 *   tp_sysinfo_mac.m  mach/sysctl, TODO — macOS phase
 */

#ifndef TP_SYSINFO_H
#define TP_SYSINFO_H

#include "lua.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Build the global `sys` table on the given state. */
void tp_sysinfo_register_lua(lua_State *L);

#ifdef __cplusplus
}
#endif

#endif /* TP_SYSINFO_H */
