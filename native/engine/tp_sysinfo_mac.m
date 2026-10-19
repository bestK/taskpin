/*
 * tp_sysinfo_mac.m — the sys.*() Lua API on macOS.
 *
 * STATUS: NOT IMPLEMENTED. This is a Phase 8 (macOS) deliverable.
 *
 * The signature is final so the Lua layer does not change when this lands.
 * CMake compiles this file on Apple targets only.
 *
 * TODO (macOS phase): port the implementations the macOS bridge already
 * carries in src/clua_bridge/taskpin_lua.c (they are proven there), keeping
 * the Lua-visible shapes identical to tp_sysinfo_win.c so scripts do not
 * care which platform they run on:
 *   cpu            -> getloadavg() / hw.ncpu, clamped to 100
 *   memory         -> hw.memsize + host_statistics64, {total_mb, used_mb, percent}
 *   disk(path)     -> statfs, {total_gb, free_gb, percent}
 *   battery        -> IOKit power sources; the bridge currently reports -1/false/-1
 *   uptime         -> kern.boottime
 *   process_count  -> kern.proc
 *   net            -> getifaddrs AF_LINK, {recv_bytes, send_bytes}
 *   net_speed      -> delta against the previous call, {download, upload}
 *   net_processes  -> proc_listpids + per-PID rusage, array of
 *                     {pid, name, connections, download, upload}
 *   file_mtime     -> stat, seconds since epoch
 *   find_newest    -> recursive opendir/stat walk
 *   read_file      -> read + strip UTF-8 BOM
 *   country        -> NSLocale.currentLocale.countryCode (instant, OS setting)
 *   language       -> NSLocale.currentLocale.languageCode / localeIdentifier
 *                     (instant, OS setting — NOT the network geo-IP below)
 *   is_china       -> network geo-IP via NSURLSession, cached tri-state, same
 *                     endpoint and same country_code=="CN" test as Windows
 *   gh_proxy       -> pure string transform; mirrors tp_sysinfo_win.c exactly
 *                     so scripts see identical URLs on both platforms
 *   watch_keys     -> no-op returning {} (AppKit has no GetAsyncKeyState);
 *                     see the note below
 *   key_pressed    -> NSEvent.modifierFlags / pressedMouseButtons where it can
 *                     be answered without a hook, false otherwise
 *   key_triggered  -> rising edge over key_pressed
 *
 * macOS note on the key APIs: AppKit exposes no global "is this key down"
 * query. A faithful port needs either an NSEvent global monitor (which is
 * the macOS equivalent of the invasive hook the Windows side deliberately
 * avoided) or CGEventSourceKeyState. Decide when the macOS phase lands; do
 * not silently return a stub that makes scripts believe keys work.
 *
 * Until then the build refuses to produce a silently-broken macOS engine:
 * define TP_ALLOW_UNIMPLEMENTED_MAC to opt in to the failing stub.
 */

#if !defined(__APPLE__)
/* Compiled on a non-Apple target by mistake; CMake should prevent this. */
#error "tp_sysinfo_mac.m is macOS-only; native/engine/CMakeLists.txt must not compile it elsewhere."
#endif

#if !defined(TP_ALLOW_UNIMPLEMENTED_MAC)
#error "tp_sysinfo_mac.m is not implemented yet (Phase 8). Define TP_ALLOW_UNIMPLEMENTED_MAC to build the failing stub."
#endif

#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"

#include "tp_sysinfo.h"

void tp_sysinfo_register_lua(lua_State *L) {
    /* TODO: register the real functions listed above (Phase 8). */
    fprintf(stderr, "[TaskPin] tp_sysinfo_register_lua: macOS implementation pending\n");
    lua_newtable(L);
    lua_setglobal(L, "sys");
}
