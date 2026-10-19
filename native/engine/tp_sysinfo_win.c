/*
 * tp_sysinfo_win.c — the sys.*() Lua API on Windows.
 *
 * Ported from lib/sysinfo.c. The Lua-visible shapes are preserved exactly
 * (key names, units, the "0 on first CPU sample" and "-1 on failure"
 * conventions, net_speed being a delta against the previous call), because
 * examples/system_monitor.lua and the golden baseline depend on them.
 *
 * This is the only place in native/engine that includes windows.h, together
 * with tp_http_win.c — which is the whole point of the split.
 *
 * MSVC-clean C: no VLAs, no GNU extensions. _WIN32_WINNT is raised for
 * GetTickCount64 / QueryFullProcessImageNameW.
 */

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601 /* Windows 7 */
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <winsock2.h>
#include <windows.h>
#include <tlhelp32.h>
#include <iphlpapi.h>
#include <tcpmib.h>
#include <psapi.h>
#include <winnls.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"

#include "tp_http.h"
#include "tp_sysinfo.h"

/* tp_json.c — declared here rather than pulling in taskpin_engine.h, which
 * would drag the whole ABI header into a platform TU for one prototype. */
int tp_json_to_lua(lua_State *L, const char *json);

#define TP_NET_PROC_MAX 128
#define TP_IF_TYPE_IEEE80211 71

/* ─── sys.cpu() — GetSystemTimes delta ─── */

static ULONGLONG tp_ft_to_u64(FILETIME ft) {
    return ((ULONGLONG)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
}

static int l_sys_cpu(lua_State *L) {
    static ULONGLONG prev_idle = 0, prev_kernel = 0, prev_user = 0;
    FILETIME idle, kernel, user;

    if (!GetSystemTimes(&idle, &kernel, &user)) {
        lua_pushinteger(L, -1);
        return 1;
    }

    ULONGLONG i = tp_ft_to_u64(idle);
    ULONGLONG k = tp_ft_to_u64(kernel);
    ULONGLONG u = tp_ft_to_u64(user);

    /* First sample only establishes the baseline; report 0. */
    if (prev_kernel == 0 && prev_user == 0) {
        prev_idle = i; prev_kernel = k; prev_user = u;
        lua_pushinteger(L, 0);
        return 1;
    }

    ULONGLONG di = i - prev_idle;
    ULONGLONG dk = k - prev_kernel;
    ULONGLONG du = u - prev_user;
    ULONGLONG total = dk + du;

    prev_idle = i; prev_kernel = k; prev_user = u;

    if (total == 0) { lua_pushinteger(L, 0); return 1; }

    lua_pushinteger(L, (lua_Integer)((total - di) * 100 / total));
    return 1;
}

/* ─── sys.memory() ─── */

static int l_sys_memory(lua_State *L) {
    MEMORYSTATUSEX ms;
    memset(&ms, 0, sizeof(ms));
    ms.dwLength = sizeof(ms);
    if (!GlobalMemoryStatusEx(&ms)) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);
    lua_pushinteger(L, (lua_Integer)(ms.ullTotalPhys / (1024 * 1024)));
    lua_setfield(L, -2, "total_mb");
    lua_pushinteger(L, (lua_Integer)((ms.ullTotalPhys - ms.ullAvailPhys) / (1024 * 1024)));
    lua_setfield(L, -2, "used_mb");
    lua_pushinteger(L, (lua_Integer)ms.dwMemoryLoad);
    lua_setfield(L, -2, "percent");
    return 1;
}

/* ─── sys.disk(drive) ─── */

static int l_sys_disk(lua_State *L) {
    const char *drive = luaL_optstring(L, 1, "C:");
    WCHAR wdrive[8];
    MultiByteToWideChar(CP_UTF8, 0, drive, -1, wdrive, 8);

    int len = (int)wcslen(wdrive);
    if (len > 0 && wdrive[len - 1] != L'\\' && len + 1 < 8) {
        wdrive[len] = L'\\';
        wdrive[len + 1] = 0;
    }

    ULARGE_INTEGER free_avail, total, total_free;
    if (!GetDiskFreeSpaceExW(wdrive, &free_avail, &total, &total_free)) {
        lua_pushnil(L);
        return 1;
    }

    double total_gb = (double)total.QuadPart / (1024.0 * 1024.0 * 1024.0);
    double free_gb = (double)free_avail.QuadPart / (1024.0 * 1024.0 * 1024.0);
    int pct = (total.QuadPart > 0)
        ? (int)((total.QuadPart - free_avail.QuadPart) * 100 / total.QuadPart)
        : 0;

    lua_newtable(L);
    lua_pushnumber(L, total_gb);
    lua_setfield(L, -2, "total_gb");
    lua_pushnumber(L, free_gb);
    lua_setfield(L, -2, "free_gb");
    lua_pushinteger(L, pct);
    lua_setfield(L, -2, "percent");
    return 1;
}

/* ─── sys.battery() ─── */

static int l_sys_battery(lua_State *L) {
    SYSTEM_POWER_STATUS sps;
    if (!GetSystemPowerStatus(&sps)) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);
    lua_pushinteger(L, sps.BatteryLifePercent == 255 ? -1 : sps.BatteryLifePercent);
    lua_setfield(L, -2, "percent");
    lua_pushboolean(L, sps.ACLineStatus == 1);
    lua_setfield(L, -2, "charging");
    lua_pushinteger(L, sps.BatteryLifeTime == (DWORD)-1 ? -1 : (int)sps.BatteryLifeTime);
    lua_setfield(L, -2, "seconds_left");
    return 1;
}

/* ─── sys.uptime() ─── */

static int l_sys_uptime(lua_State *L) {
    lua_pushinteger(L, (lua_Integer)(GetTickCount64() / 1000));
    return 1;
}

/* ─── sys.process_count() ─── */

static int l_sys_process_count(lua_State *L) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) { lua_pushinteger(L, -1); return 1; }

    PROCESSENTRY32W pe;
    memset(&pe, 0, sizeof(pe));
    pe.dwSize = sizeof(pe);
    int count = 0;
    if (Process32FirstW(snap, &pe)) {
        do { count++; } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    lua_pushinteger(L, count);
    return 1;
}

/* ─── network byte totals (shared by net / net_speed) ─── */

static void tp_net_get_totals(ULONG64 *recv_out, ULONG64 *send_out) {
    *recv_out = 0;
    *send_out = 0;

    DWORD size = 0;
    GetIfTable(NULL, &size, FALSE);
    if (size == 0) return;

    MIB_IFTABLE *table = (MIB_IFTABLE *)malloc(size);
    if (!table) return;

    if (GetIfTable(table, &size, FALSE) == NO_ERROR) {
        for (DWORD i = 0; i < table->dwNumEntries; i++) {
            MIB_IFROW *row = &table->table[i];
            if (row->dwType == IF_TYPE_ETHERNET_CSMACD ||
                row->dwType == TP_IF_TYPE_IEEE80211) {
                *recv_out += row->dwInOctets;
                *send_out += row->dwOutOctets;
            }
        }
    }
    free(table);
}

/* ─── sys.net() ─── */

static int l_sys_net(lua_State *L) {
    ULONG64 recv_total = 0, send_total = 0;
    tp_net_get_totals(&recv_total, &send_total);

    lua_newtable(L);
    lua_pushnumber(L, (double)recv_total);
    lua_setfield(L, -2, "recv_bytes");
    lua_pushnumber(L, (double)send_total);
    lua_setfield(L, -2, "send_bytes");
    return 1;
}

/* ─── sys.net_speed() ─── */

static ULONG64 s_prev_recv = 0, s_prev_send = 0;
static DWORD s_prev_tick = 0;

static int l_sys_net_speed(lua_State *L) {
    ULONG64 cur_recv, cur_send;
    tp_net_get_totals(&cur_recv, &cur_send);
    DWORD now = GetTickCount();

    double dl_speed = 0, ul_speed = 0;
    if (s_prev_tick > 0) {
        DWORD dt = now - s_prev_tick;
        if (dt > 0) {
            dl_speed = (double)(cur_recv - s_prev_recv) * 1000.0 / dt;
            ul_speed = (double)(cur_send - s_prev_send) * 1000.0 / dt;
        }
    }
    s_prev_recv = cur_recv;
    s_prev_send = cur_send;
    s_prev_tick = now;

    lua_newtable(L);
    lua_pushnumber(L, dl_speed);
    lua_setfield(L, -2, "download");
    lua_pushnumber(L, ul_speed);
    lua_setfield(L, -2, "upload");
    return 1;
}

/* ─── sys.net_processes() ─── */

typedef struct {
    DWORD pid;
    ULONG64 io_read;
    ULONG64 io_write;
} TpNetProcSnap;

static TpNetProcSnap s_np_prev[TP_NET_PROC_MAX];
static int s_np_prev_count = 0;
static DWORD s_np_prev_tick = 0;

typedef struct { DWORD pid; int conns; } TpPidEntry;

static int l_sys_net_processes(lua_State *L) {
    /* 1. All TCP connections with their owning PID. */
    DWORD tcp_size = 0;
    GetExtendedTcpTable(NULL, &tcp_size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0);
    if (tcp_size == 0) { lua_newtable(L); return 1; }

    MIB_TCPTABLE_OWNER_PID *tcp_table = (MIB_TCPTABLE_OWNER_PID *)malloc(tcp_size);
    if (!tcp_table) { lua_newtable(L); return 1; }

    if (GetExtendedTcpTable(tcp_table, &tcp_size, FALSE, AF_INET,
                            TCP_TABLE_OWNER_PID_ALL, 0) != NO_ERROR) {
        free(tcp_table);
        lua_newtable(L);
        return 1;
    }

    /* 2. Aggregate ESTABLISHED connections per PID. */
    TpPidEntry pids[TP_NET_PROC_MAX];
    int pid_count = 0;

    for (DWORD i = 0; i < tcp_table->dwNumEntries; i++) {
        MIB_TCPROW_OWNER_PID *row = &tcp_table->table[i];
        if (row->dwState != MIB_TCP_STATE_ESTAB) continue;
        DWORD pid = row->dwOwningPid;
        if (pid == 0) continue;

        int found = 0;
        for (int j = 0; j < pid_count; j++) {
            if (pids[j].pid == pid) { pids[j].conns++; found = 1; break; }
        }
        if (!found && pid_count < TP_NET_PROC_MAX) {
            pids[pid_count].pid = pid;
            pids[pid_count].conns = 1;
            pid_count++;
        }
    }
    free(tcp_table);

    /* 3. Per PID: image name + IO counters, and the delta against the
     *    previous snapshot. */
    DWORD now = GetTickCount();
    DWORD dt = (s_np_prev_tick > 0) ? (now - s_np_prev_tick) : 0;

    TpNetProcSnap cur_snap[TP_NET_PROC_MAX];
    int cur_snap_count = 0;

    lua_newtable(L);
    int idx = 1;

    for (int i = 0; i < pid_count; i++) {
        DWORD pid = pids[i].pid;
        HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (!hProc) continue;

        WCHAR wname[MAX_PATH];
        DWORD name_size = MAX_PATH;
        char name8[MAX_PATH];
        if (QueryFullProcessImageNameW(hProc, 0, wname, &name_size)) {
            WCHAR *slash = wcsrchr(wname, L'\\');
            WCHAR *base = slash ? slash + 1 : wname;
            WideCharToMultiByte(CP_UTF8, 0, base, -1, name8, MAX_PATH, NULL, NULL);
        } else {
            strcpy(name8, "unknown");
        }

        IO_COUNTERS ioc;
        ULONG64 io_read = 0, io_write = 0;
        double read_speed = 0, write_speed = 0;
        if (GetProcessIoCounters(hProc, &ioc)) {
            io_read = ioc.ReadTransferCount;
            io_write = ioc.WriteTransferCount;

            if (dt > 0) {
                for (int j = 0; j < s_np_prev_count; j++) {
                    if (s_np_prev[j].pid == pid) {
                        read_speed = (double)(io_read - s_np_prev[j].io_read) * 1000.0 / dt;
                        write_speed = (double)(io_write - s_np_prev[j].io_write) * 1000.0 / dt;
                        if (read_speed < 0) read_speed = 0;
                        if (write_speed < 0) write_speed = 0;
                        break;
                    }
                }
            }

            if (cur_snap_count < TP_NET_PROC_MAX) {
                cur_snap[cur_snap_count].pid = pid;
                cur_snap[cur_snap_count].io_read = io_read;
                cur_snap[cur_snap_count].io_write = io_write;
                cur_snap_count++;
            }
        }
        CloseHandle(hProc);

        lua_newtable(L);
        lua_pushinteger(L, (lua_Integer)pid);
        lua_setfield(L, -2, "pid");
        lua_pushstring(L, name8);
        lua_setfield(L, -2, "name");
        lua_pushinteger(L, pids[i].conns);
        lua_setfield(L, -2, "connections");
        lua_pushnumber(L, read_speed);
        lua_setfield(L, -2, "download");
        lua_pushnumber(L, write_speed);
        lua_setfield(L, -2, "upload");
        lua_rawseti(L, -2, idx++);
    }

    memcpy(s_np_prev, cur_snap, sizeof(TpNetProcSnap) * (size_t)cur_snap_count);
    s_np_prev_count = cur_snap_count;
    s_np_prev_tick = now;

    return 1;
}

/* ─── sys.file_mtime(path) ─── */

static int l_sys_file_mtime(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    WCHAR wpath[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (!GetFileAttributesExW(wpath, GetFileExInfoStandard, &fad)) {
        lua_pushnil(L);
        return 1;
    }

    ULARGE_INTEGER uli;
    uli.LowPart = fad.ftLastWriteTime.dwLowDateTime;
    uli.HighPart = fad.ftLastWriteTime.dwHighDateTime;
    /* FILETIME epoch (1601) -> Unix epoch (1970) */
    lua_pushinteger(L, (lua_Integer)((uli.QuadPart - 116444736000000000ULL) / 10000000ULL));
    return 1;
}

/* ─── sys.find_newest(dir, ext) ─── */

static ULARGE_INTEGER s_newest_time;
static WCHAR s_newest_path[MAX_PATH];

static void tp_find_newest_recurse(const WCHAR *dir, const WCHAR *ext) {
    WCHAR pattern[MAX_PATH];
    _snwprintf(pattern, MAX_PATH, L"%s\\*", dir);

    WIN32_FIND_DATAW fd;
    HANDLE hFind = FindFirstFileW(pattern, &fd);
    if (hFind == INVALID_HANDLE_VALUE) return;

    do {
        if (fd.cFileName[0] == L'.') continue;

        WCHAR full[MAX_PATH];
        _snwprintf(full, MAX_PATH, L"%s\\%s", dir, fd.cFileName);

        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            tp_find_newest_recurse(full, ext);
        } else {
            WCHAR *dot = wcsrchr(fd.cFileName, L'.');
            if (dot && _wcsicmp(dot, ext) == 0) {
                ULARGE_INTEGER ft;
                ft.LowPart = fd.ftLastWriteTime.dwLowDateTime;
                ft.HighPart = fd.ftLastWriteTime.dwHighDateTime;
                if (ft.QuadPart > s_newest_time.QuadPart) {
                    s_newest_time = ft;
                    wcsncpy(s_newest_path, full, MAX_PATH - 1);
                    s_newest_path[MAX_PATH - 1] = 0;
                }
            }
        }
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
}

static int l_sys_find_newest(lua_State *L) {
    const char *dir = luaL_checkstring(L, 1);
    const char *ext = luaL_checkstring(L, 2);

    WCHAR wdir[MAX_PATH], wext[32];
    MultiByteToWideChar(CP_UTF8, 0, dir, -1, wdir, MAX_PATH);
    MultiByteToWideChar(CP_UTF8, 0, ext, -1, wext, 32);

    s_newest_time.QuadPart = 0;
    s_newest_path[0] = L'\0';

    tp_find_newest_recurse(wdir, wext);

    if (s_newest_path[0]) {
        char result[MAX_PATH];
        WideCharToMultiByte(CP_UTF8, 0, s_newest_path, -1, result, MAX_PATH, NULL, NULL);
        lua_pushstring(L, result);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

/* ─── sys.read_file(path) ─── */

static int l_sys_read_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    WCHAR wpath[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

    HANDLE hFile = CreateFileW(wpath, GENERIC_READ, FILE_SHARE_READ, NULL,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) { lua_pushnil(L); return 1; }

    DWORD size = GetFileSize(hFile, NULL);
    if (size == 0 || size == INVALID_FILE_SIZE) {
        CloseHandle(hFile);
        lua_pushstring(L, "");
        return 1;
    }

    char *buf = (char *)malloc((size_t)size + 1);
    if (!buf) { CloseHandle(hFile); lua_pushnil(L); return 1; }

    DWORD read_bytes = 0;
    ReadFile(hFile, buf, size, &read_bytes, NULL);
    CloseHandle(hFile);
    buf[read_bytes] = '\0';

    char *start = buf;
    size_t len = read_bytes;
    if (len >= 3 && (unsigned char)buf[0] == 0xEF &&
        (unsigned char)buf[1] == 0xBB && (unsigned char)buf[2] == 0xBF) {
        start = buf + 3;
        len -= 3;
    }

    lua_pushlstring(L, start, len);
    free(buf);
    return 1;
}

/* ══════════════════════════════════════════════════════════════════════════
 * OS locale: sys.country() / sys.language()
 *
 * These read the *operating system's* regional settings. They are instant,
 * synchronous and need no network, so unlike sys.is_china() they are not
 * cached — the values cannot change while the process runs, and the calls
 * are cheap enough to make every refresh.
 *
 * The distinction from sys.is_china() is deliberate and worth stating
 * plainly, because "which country" has two different answers:
 *
 *   sys.country()   OS region setting     instant, offline, never lies about
 *                                         the setting, says nothing about
 *                                         where the machine actually is
 *   sys.is_china()  network geo-IP        cached, needs the network, and is
 *                                         false when offline or when the
 *                                         geo-IP service is wrong/blocked
 *
 * Consequence a script author has to know: a user physically in China whose
 * Windows is set to en-US gets country()=="CN" and language()=="en-US",
 * while is_china() is a separate question that may answer false offline.
 * ══════════════════════════════════════════════════════════════════════════ */

/* sys.country() -> "CN" / "US" / ...  (ISO 3166-1 alpha-2), "" on failure.
 *
 * GetUserDefaultGeoName (Windows 10 1709+) is the modern source and is the
 * one that follows the "Country or region" dropdown in Settings. The
 * LOCALE_SISO3166CTRYNAME fallback covers older builds and the case where
 * the geo name is unavailable; it reads the region off the locale instead,
 * which is the same value in practice. */
static int l_sys_country(lua_State *L) {
    WCHAR geo[64];
    geo[0] = 0;

    if (GetUserDefaultGeoName(geo, 64) > 0 && geo[0]) {
        char out[64];
        out[0] = 0;
        WideCharToMultiByte(CP_UTF8, 0, geo, -1, out, 64, NULL, NULL);
        lua_pushstring(L, out);
        return 1;
    }

    WCHAR ctry[64];
    ctry[0] = 0;
    if (GetLocaleInfoEx(LOCALE_NAME_USER_DEFAULT, LOCALE_SISO3166CTRYNAME,
                        ctry, 64) > 0 && ctry[0]) {
        char out[64];
        out[0] = 0;
        WideCharToMultiByte(CP_UTF8, 0, ctry, -1, out, 64, NULL, NULL);
        lua_pushstring(L, out);
        return 1;
    }

    lua_pushstring(L, "");
    return 1;
}

/* sys.language() -> "zh-CN" / "en-US" / ... , "" on failure.
 *
 * GetUserDefaultLocaleName is the user locale (Windows 7+). The
 * GetUserDefaultUILanguage + LCIDToLocaleName fallback returns the UI
 * language instead, which can differ when the two are configured
 * separately; it is only reached if the primary call fails. */
static int l_sys_language(lua_State *L) {
    WCHAR loc[LOCALE_NAME_MAX_LENGTH];
    loc[0] = 0;

    if (GetUserDefaultLocaleName(loc, LOCALE_NAME_MAX_LENGTH) > 0 && loc[0]) {
        char out[LOCALE_NAME_MAX_LENGTH * 2];
        out[0] = 0;
        WideCharToMultiByte(CP_UTF8, 0, loc, -1, out, (int)sizeof(out), NULL, NULL);
        lua_pushstring(L, out);
        return 1;
    }

    WCHAR ui[LOCALE_NAME_MAX_LENGTH];
    ui[0] = 0;
    if (LCIDToLocaleName(GetUserDefaultUILanguage(), ui,
                         LOCALE_NAME_MAX_LENGTH, 0) > 0 && ui[0]) {
        char out[LOCALE_NAME_MAX_LENGTH * 2];
        out[0] = 0;
        WideCharToMultiByte(CP_UTF8, 0, ui, -1, out, (int)sizeof(out), NULL, NULL);
        lua_pushstring(L, out);
        return 1;
    }

    lua_pushstring(L, "");
    return 1;
}

/* ══════════════════════════════════════════════════════════════════════════
 * Network geo-IP: sys.is_china() / sys.gh_proxy()
 *
 * Logic reused from the two existing implementations rather than reinvented:
 *   lib/update.c:11-17      is_in_china()   — strstr on the raw body
 *   src/market_dialog.c:18-35 mkt_check_geo() — JSON parse of country_code
 *
 * Both are folded in here: the JSON parse is tried first (it is the more
 * precise of the two and is what market_dialog uses), with the strstr as a
 * fallback for bodies the minimal decoder cannot handle.
 * ══════════════════════════════════════════════════════════════════════════ */

#define TP_GEO_URL_DEFAULT "https://api.ip.sb/geoip"

/* Tri-state: -1 = not checked yet, 0 = not in China, 1 = in China.
 * Scripts call is_china() on every refresh, so the request must happen at
 * most once per process, ever. */
static int s_is_china = -1;

/* Endpoint override, purely a diagnostic/testing seam: pointing this at an
 * unreachable host is how the offline path is exercised without unplugging
 * the machine. Not a documented script-facing feature. */
static const char *tp_geo_url(void) {
    const char *env = getenv("TASKPIN_GEO_URL");
    return (env && env[0]) ? env : TP_GEO_URL_DEFAULT;
}

/* sys.is_china() -> boolean. Cached: the network is hit at most once. */
static int l_sys_is_china(lua_State *L) {
    if (s_is_china < 0) {
        s_is_china = 0; /* pessimistic default; offline means "not in China" */

        char *resp = tp_http_request_sync(tp_geo_url(), "GET", NULL, NULL, NULL, 0);
        if (resp) {
            /* Preferred path: parse the JSON and read country_code, exactly as
             * mkt_check_geo does. */
            if (tp_json_to_lua(L, resp) && lua_istable(L, -1)) {
                lua_getfield(L, -1, "country_code");
                const char *cc = lua_tostring(L, -1);
                if (cc && strcmp(cc, "CN") == 0) s_is_china = 1;
                lua_pop(L, 1);
            }
            lua_pop(L, 1); /* the decoded value (or nil) */

            /* Fallback: lib/update.c's raw substring test, for bodies the
             * minimal decoder rejects. */
            if (!s_is_china && strstr(resp, "\"country_code\":\"CN\"")) {
                s_is_china = 1;
            }

            free(resp);
        }
    }

    lua_pushboolean(L, s_is_china == 1);
    return 1;
}

/* sys.gh_proxy(url) -> string.
 *
 * Rewrites a GitHub URL through the gh-proxy.com mirror when in China;
 * returns the input unchanged otherwise. The output shape is the one both
 * existing call sites already build:
 *
 *   https://gh-proxy.com/https://github.com/<path>     (lib/update.c:20-26)
 *   https://gh-proxy.com/https://raw.githubusercontent.com/...  (market_dialog.c:37-42)
 *
 * Only GitHub hosts are rewritten: gh-proxy.com can only fetch from GitHub,
 * so prefixing an arbitrary host would produce a URL that cannot resolve. */
static int l_sys_gh_proxy(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);

    /* Not in China, or already proxied: hand the input straight back. */
    if (s_is_china != 1 || strncmp(url, "https://gh-proxy.com/", 20) == 0) {
        lua_pushstring(L, url);
        return 1;
    }

    /* Host = between "://" and the next "/" (or the end). */
    const char *scheme = strstr(url, "://");
    const char *host = scheme ? scheme + 3 : url;
    const char *slash = strchr(host, '/');
    size_t host_len = slash ? (size_t)(slash - host) : strlen(host);

    /* "github" covers github.com, raw.githubusercontent.com and
     * api.github.com without enumerating them. */
    char host_buf[256];
    size_t n = host_len < sizeof(host_buf) - 1 ? host_len : sizeof(host_buf) - 1;
    memcpy(host_buf, host, n);
    host_buf[n] = '\0';

    if (!strstr(host_buf, "github")) {
        lua_pushstring(L, url);
        return 1;
    }

    size_t len = strlen(url);
    char *out = (char *)malloc(len + 32);
    if (!out) {
        lua_pushstring(L, url);
        return 1;
    }
    snprintf(out, len + 32, "https://gh-proxy.com/%s", url);
    lua_pushstring(L, out);
    free(out);
    return 1;
}

/* ══════════════════════════════════════════════════════════════════════════
 * Keyboard: sys.watch_keys() / sys.key_pressed() / sys.key_triggered()
 *
 * CONTRACT (inferred from scripts/dino_runner.lua, the only caller):
 *
 *   sys.watch_keys(name, ...)      declares the keys the script cares about.
 *                                  Returns an array table of the resolved
 *                                  names. dino_runner ignores the return
 *                                  value; it exists so a script (or a test)
 *                                  can verify what was registered.
 *   sys.key_pressed(name)  -> bool level: is the key down right now
 *   sys.key_triggered(name)-> bool rising edge: true on the first call that
 *                                  sees the key down after it was up.
 *
 * dino_runner line 5 calls watch_keys("space","up","lclick"), then lines
 * 38-41 prefer key_triggered("space"|"up"|"lclick") and fall back to
 * key_pressed("space"|"up"). All three are therefore implemented.
 *
 * WHY POLLING AND NOT A HOOK: a WH_KEYBOARD_LL global hook is process-wide,
 * requires a message pump, sits in the input path of every other process,
 * and is a well-known AV/keylogger false-positive trigger. This script runs
 * at a few Hz and only wants to know "is space down". GetAsyncKeyState reads
 * state on demand, installs nothing, and cannot be flagged as surveillance.
 *
 * The edge state lives in a process-global table rather than in the Lua
 * state because the engine re-runs the same script on every refresh: the Lua
 * state persists (which is why dino_runner can keep _G._dino), and the key
 * edges have to persist across those runs for key_triggered to mean
 * anything. Note the state is shared if a host ever runs two engines.
 * ══════════════════════════════════════════════════════════════════════════ */

static unsigned char s_key_prev[256]; /* previous polled state per VK */

typedef struct { const char *name; int vk; } TpKeyName;

/* Case-insensitive lookup; names are matched exactly (no "return" aliasing
 * surprises beyond the two explicit spellings). */
static int tp_key_vk(const char *name) {
    if (!name) return 0;

    if (!_stricmp(name, "space"))  return VK_SPACE;
    if (!_stricmp(name, "up"))     return VK_UP;
    if (!_stricmp(name, "down"))   return VK_DOWN;
    if (!_stricmp(name, "left"))   return VK_LEFT;
    if (!_stricmp(name, "right"))  return VK_RIGHT;
    if (!_stricmp(name, "enter"))  return VK_RETURN;
    if (!_stricmp(name, "return")) return VK_RETURN;
    if (!_stricmp(name, "esc"))    return VK_ESCAPE;
    if (!_stricmp(name, "escape")) return VK_ESCAPE;
    if (!_stricmp(name, "tab"))    return VK_TAB;
    if (!_stricmp(name, "shift"))  return VK_SHIFT;
    if (!_stricmp(name, "ctrl"))   return VK_CONTROL;
    if (!_stricmp(name, "alt"))    return VK_MENU;
    if (!_stricmp(name, "lclick")) return VK_LBUTTON;
    if (!_stricmp(name, "rclick")) return VK_RBUTTON;
    if (!_stricmp(name, "mclick")) return VK_MBUTTON;

    /* single letter a-z */
    if (name[1] == '\0') {
        char c = name[0];
        if (c >= 'a' && c <= 'z') return 'A' + (c - 'a');
        if (c >= 'A' && c <= 'Z') return 'A' + (c - 'A');
        if (c >= '0' && c <= '9') return '0' + (c - '0');
    }

    /* f1-f12 */
    if ((name[0] == 'f' || name[0] == 'F') && name[1] != '\0') {
        char *end = NULL;
        long fn = strtol(name + 1, &end, 10);
        if (end && *end == '\0' && fn >= 1 && fn <= 12) {
            return VK_F1 + (int)fn - 1;
        }
    }

    return 0; /* unknown */
}

static int tp_key_down(int vk) {
    return (GetAsyncKeyState(vk) & 0x8000) != 0;
}

/* sys.watch_keys(name, ...) -> array of resolved names. */
static int l_sys_watch_keys(lua_State *L) {
    int n = lua_gettop(L);
    lua_newtable(L);
    int idx = 1;
    for (int i = 1; i <= n; i++) {
        const char *name = lua_tostring(L, i);
        if (!name || !tp_key_vk(name)) continue; /* unknown names are skipped */
        lua_pushstring(L, name);
        lua_rawseti(L, -2, idx++);
    }
    return 1;
}

/* sys.key_pressed(name) -> boolean. Level state; does not touch the edge. */
static int l_sys_key_pressed(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    int vk = tp_key_vk(name);
    if (!vk) { lua_pushboolean(L, 0); return 1; }
    lua_pushboolean(L, tp_key_down(vk));
    return 1;
}

/* sys.key_triggered(name) -> boolean. Rising edge only. */
static int l_sys_key_triggered(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    int vk = tp_key_vk(name);
    if (!vk) { lua_pushboolean(L, 0); return 1; }

    int down = tp_key_down(vk);
    int edge = down && !s_key_prev[vk & 0xFF];
    s_key_prev[vk & 0xFF] = (unsigned char)down;
    lua_pushboolean(L, edge);
    return 1;
}

/* ─── registration ─── */

void tp_sysinfo_register_lua(lua_State *L) {
    lua_newtable(L);
    lua_pushcfunction(L, l_sys_cpu);           lua_setfield(L, -2, "cpu");
    lua_pushcfunction(L, l_sys_memory);        lua_setfield(L, -2, "memory");
    lua_pushcfunction(L, l_sys_disk);          lua_setfield(L, -2, "disk");
    lua_pushcfunction(L, l_sys_battery);       lua_setfield(L, -2, "battery");
    lua_pushcfunction(L, l_sys_uptime);        lua_setfield(L, -2, "uptime");
    lua_pushcfunction(L, l_sys_process_count); lua_setfield(L, -2, "process_count");
    lua_pushcfunction(L, l_sys_net);           lua_setfield(L, -2, "net");
    lua_pushcfunction(L, l_sys_net_speed);     lua_setfield(L, -2, "net_speed");
    lua_pushcfunction(L, l_sys_net_processes); lua_setfield(L, -2, "net_processes");
    lua_pushcfunction(L, l_sys_file_mtime);    lua_setfield(L, -2, "file_mtime");
    lua_pushcfunction(L, l_sys_find_newest);   lua_setfield(L, -2, "find_newest");
    lua_pushcfunction(L, l_sys_read_file);     lua_setfield(L, -2, "read_file");
    lua_pushcfunction(L, l_sys_country);       lua_setfield(L, -2, "country");
    lua_pushcfunction(L, l_sys_language);      lua_setfield(L, -2, "language");
    lua_pushcfunction(L, l_sys_is_china);      lua_setfield(L, -2, "is_china");
    lua_pushcfunction(L, l_sys_gh_proxy);      lua_setfield(L, -2, "gh_proxy");
    lua_pushcfunction(L, l_sys_watch_keys);    lua_setfield(L, -2, "watch_keys");
    lua_pushcfunction(L, l_sys_key_pressed);   lua_setfield(L, -2, "key_pressed");
    lua_pushcfunction(L, l_sys_key_triggered); lua_setfield(L, -2, "key_triggered");
    lua_setglobal(L, "sys");
}
