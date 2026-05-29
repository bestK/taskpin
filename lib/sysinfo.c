#include "sysinfo.h"
#include "lua/lua.h"
#include "lua/lauxlib.h"
#include <windows.h>
#include <string.h>
#include <stdio.h>

/* ─── CPU usage via GetSystemTimes delta ─── */

static ULONGLONG ft_to_u64(FILETIME ft) {
    return ((ULONGLONG)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
}

static int l_sys_cpu(lua_State *ls) {
    static ULONGLONG prev_idle = 0, prev_kernel = 0, prev_user = 0;
    FILETIME idle, kernel, user;

    if (!GetSystemTimes(&idle, &kernel, &user)) {
        lua_pushinteger(ls, -1);
        return 1;
    }

    ULONGLONG i = ft_to_u64(idle);
    ULONGLONG k = ft_to_u64(kernel);
    ULONGLONG u = ft_to_u64(user);

    if (prev_kernel == 0 && prev_user == 0) {
        prev_idle = i; prev_kernel = k; prev_user = u;
        lua_pushinteger(ls, 0);
        return 1;
    }

    ULONGLONG di = i - prev_idle;
    ULONGLONG dk = k - prev_kernel;
    ULONGLONG du = u - prev_user;
    ULONGLONG total = dk + du;

    prev_idle = i; prev_kernel = k; prev_user = u;

    if (total == 0) { lua_pushinteger(ls, 0); return 1; }

    int pct = (int)((total - di) * 100 / total);
    lua_pushinteger(ls, pct);
    return 1;
}

/* ─── Memory ─── */

static int l_sys_memory(lua_State *ls) {
    MEMORYSTATUSEX ms;
    memset(&ms, 0, sizeof(ms));
    ms.dwLength = sizeof(ms);
    if (!GlobalMemoryStatusEx(&ms)) {
        lua_pushnil(ls);
        return 1;
    }

    lua_newtable(ls);
    lua_pushinteger(ls, (lua_Integer)(ms.ullTotalPhys / (1024 * 1024)));
    lua_setfield(ls, -2, "total_mb");
    lua_pushinteger(ls, (lua_Integer)((ms.ullTotalPhys - ms.ullAvailPhys) / (1024 * 1024)));
    lua_setfield(ls, -2, "used_mb");
    lua_pushinteger(ls, (lua_Integer)ms.dwMemoryLoad);
    lua_setfield(ls, -2, "percent");
    return 1;
}

/* ─── Disk ─── */

static int l_sys_disk(lua_State *ls) {
    const char *drive = luaL_optstring(ls, 1, "C:");
    WCHAR wdrive[8];
    MultiByteToWideChar(CP_UTF8, 0, drive, -1, wdrive, 8);

    /* Ensure trailing backslash */
    int len = lstrlenW(wdrive);
    if (len > 0 && wdrive[len-1] != L'\\') {
        wdrive[len] = L'\\'; wdrive[len+1] = 0;
    }

    ULARGE_INTEGER free_avail, total, total_free;
    if (!GetDiskFreeSpaceExW(wdrive, &free_avail, &total, &total_free)) {
        lua_pushnil(ls);
        return 1;
    }

    double total_gb = (double)total.QuadPart / (1024.0 * 1024.0 * 1024.0);
    double free_gb = (double)free_avail.QuadPart / (1024.0 * 1024.0 * 1024.0);
    int pct = (total.QuadPart > 0)
        ? (int)((total.QuadPart - free_avail.QuadPart) * 100 / total.QuadPart)
        : 0;

    lua_newtable(ls);
    lua_pushnumber(ls, total_gb);
    lua_setfield(ls, -2, "total_gb");
    lua_pushnumber(ls, free_gb);
    lua_setfield(ls, -2, "free_gb");
    lua_pushinteger(ls, pct);
    lua_setfield(ls, -2, "percent");
    return 1;
}

/* ─── Battery ─── */

static int l_sys_battery(lua_State *ls) {
    SYSTEM_POWER_STATUS sps;
    if (!GetSystemPowerStatus(&sps)) {
        lua_pushnil(ls);
        return 1;
    }

    lua_newtable(ls);
    lua_pushinteger(ls, sps.BatteryLifePercent == 255 ? -1 : sps.BatteryLifePercent);
    lua_setfield(ls, -2, "percent");
    lua_pushboolean(ls, sps.ACLineStatus == 1);
    lua_setfield(ls, -2, "charging");
    lua_pushinteger(ls, sps.BatteryLifeTime == (DWORD)-1 ? -1 : (int)sps.BatteryLifeTime);
    lua_setfield(ls, -2, "seconds_left");
    return 1;
}

/* ─── Uptime ─── */

static int l_sys_uptime(lua_State *ls) {
    lua_pushinteger(ls, (lua_Integer)(GetTickCount64() / 1000));
    return 1;
}

/* ─── Process count ─── */

#include <tlhelp32.h>

static int l_sys_process_count(lua_State *ls) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) { lua_pushinteger(ls, -1); return 1; }

    PROCESSENTRY32W pe;
    memset(&pe, 0, sizeof(pe));
    pe.dwSize = sizeof(pe);
    int count = 0;
    if (Process32FirstW(snap, &pe)) {
        do { count++; } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    lua_pushinteger(ls, count);
    return 1;
}

/* ─── Network bytes (total across all adapters) ─── */

#include <iphlpapi.h>

static int l_sys_net(lua_State *ls) {
    DWORD size = 0;
    GetIfTable(NULL, &size, FALSE);
    if (size == 0) { lua_pushnil(ls); return 1; }

    MIB_IFTABLE *table = (MIB_IFTABLE *)malloc(size);
    if (!table) { lua_pushnil(ls); return 1; }

    if (GetIfTable(table, &size, FALSE) != NO_ERROR) {
        free(table);
        lua_pushnil(ls);
        return 1;
    }

    ULONG64 recv_total = 0, send_total = 0;
    for (DWORD i = 0; i < table->dwNumEntries; i++) {
        MIB_IFROW *row = &table->table[i];
        if (row->dwType == IF_TYPE_ETHERNET_CSMACD || row->dwType == 71 /* IF_TYPE_IEEE80211 */) {
            recv_total += row->dwInOctets;
            send_total += row->dwOutOctets;
        }
    }
    free(table);

    lua_newtable(ls);
    lua_pushnumber(ls, (double)recv_total);
    lua_setfield(ls, -2, "recv_bytes");
    lua_pushnumber(ls, (double)send_total);
    lua_setfield(ls, -2, "send_bytes");
    return 1;
}

/* ─── Network speed (bytes/sec delta) ─── */

static ULONG64 s_prev_recv = 0, s_prev_send = 0;
static DWORD s_prev_tick = 0;

static void net_get_totals(ULONG64 *recv_out, ULONG64 *send_out) {
    *recv_out = 0; *send_out = 0;
    DWORD size = 0;
    GetIfTable(NULL, &size, FALSE);
    if (size == 0) return;
    MIB_IFTABLE *table = (MIB_IFTABLE *)malloc(size);
    if (!table) return;
    if (GetIfTable(table, &size, FALSE) == NO_ERROR) {
        for (DWORD i = 0; i < table->dwNumEntries; i++) {
            MIB_IFROW *row = &table->table[i];
            if (row->dwType == IF_TYPE_ETHERNET_CSMACD || row->dwType == 71) {
                *recv_out += row->dwInOctets;
                *send_out += row->dwOutOctets;
            }
        }
    }
    free(table);
}

static int l_sys_net_speed(lua_State *ls) {
    ULONG64 cur_recv, cur_send;
    net_get_totals(&cur_recv, &cur_send);
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

    lua_newtable(ls);
    lua_pushnumber(ls, dl_speed);
    lua_setfield(ls, -2, "download");
    lua_pushnumber(ls, ul_speed);
    lua_setfield(ls, -2, "upload");
    return 1;
}

/* ─── Per-process network connections + IO speed ─── */

#include <tcpmib.h>
#include <winsock2.h>
#include <psapi.h>

#define NET_PROC_MAX 128

typedef struct {
    DWORD pid;
    ULONG64 io_read;
    ULONG64 io_write;
} NetProcSnap;

static NetProcSnap s_np_prev[NET_PROC_MAX];
static int s_np_prev_count = 0;
static DWORD s_np_prev_tick = 0;

static int l_sys_net_processes(lua_State *ls) {
    /* Step 1: Get all TCP connections with owning PID */
    DWORD tcp_size = 0;
    GetExtendedTcpTable(NULL, &tcp_size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0);
    if (tcp_size == 0) { lua_newtable(ls); return 1; }

    MIB_TCPTABLE_OWNER_PID *tcp_table = (MIB_TCPTABLE_OWNER_PID *)malloc(tcp_size);
    if (!tcp_table) { lua_newtable(ls); return 1; }

    if (GetExtendedTcpTable(tcp_table, &tcp_size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0) != NO_ERROR) {
        free(tcp_table);
        lua_newtable(ls);
        return 1;
    }

    /* Step 2: Aggregate connections by PID (only ESTABLISHED) */
    typedef struct { DWORD pid; int conns; } PidEntry;
    PidEntry pids[NET_PROC_MAX];
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
        if (!found && pid_count < NET_PROC_MAX) {
            pids[pid_count].pid = pid;
            pids[pid_count].conns = 1;
            pid_count++;
        }
    }
    free(tcp_table);

    /* Step 3: For each PID, get process name + IO counters */
    DWORD now = GetTickCount();
    DWORD dt = (s_np_prev_tick > 0) ? (now - s_np_prev_tick) : 0;

    NetProcSnap cur_snap[NET_PROC_MAX];
    int cur_snap_count = 0;

    lua_newtable(ls);
    int idx = 1;

    for (int i = 0; i < pid_count; i++) {
        DWORD pid = pids[i].pid;
        HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (!hProc) continue;

        /* Get process name */
        WCHAR wname[MAX_PATH];
        DWORD name_size = MAX_PATH;
        char name8[MAX_PATH];
        if (QueryFullProcessImageNameW(hProc, 0, wname, &name_size)) {
            WCHAR *slash = wcsrchr(wname, L'\\');
            WCHAR *base = slash ? slash + 1 : wname;
            WideCharToMultiByte(CP_UTF8, 0, base, -1, name8, MAX_PATH, NULL, NULL);
        } else {
            lstrcpyA(name8, "unknown");
        }

        /* Get IO counters */
        IO_COUNTERS ioc;
        ULONG64 io_read = 0, io_write = 0;
        double read_speed = 0, write_speed = 0;
        if (GetProcessIoCounters(hProc, &ioc)) {
            io_read = ioc.ReadTransferCount;
            io_write = ioc.WriteTransferCount;

            /* Find previous snapshot for this PID */
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

            /* Save to current snapshot */
            if (cur_snap_count < NET_PROC_MAX) {
                cur_snap[cur_snap_count].pid = pid;
                cur_snap[cur_snap_count].io_read = io_read;
                cur_snap[cur_snap_count].io_write = io_write;
                cur_snap_count++;
            }
        }
        CloseHandle(hProc);

        /* Push entry to lua table */
        lua_newtable(ls);
        lua_pushinteger(ls, (lua_Integer)pid);
        lua_setfield(ls, -2, "pid");
        lua_pushstring(ls, name8);
        lua_setfield(ls, -2, "name");
        lua_pushinteger(ls, pids[i].conns);
        lua_setfield(ls, -2, "connections");
        lua_pushnumber(ls, read_speed);
        lua_setfield(ls, -2, "download");
        lua_pushnumber(ls, write_speed);
        lua_setfield(ls, -2, "upload");
        lua_rawseti(ls, -2, idx++);
    }

    /* Update snapshot */
    memcpy(s_np_prev, cur_snap, sizeof(NetProcSnap) * cur_snap_count);
    s_np_prev_count = cur_snap_count;
    s_np_prev_tick = now;

    return 1;
}

/* ─── Registration ─── */

void sysinfo_register_lua(void *lua_state) {
    lua_State *ls = (lua_State *)lua_state;

    lua_newtable(ls);
    lua_pushcfunction(ls, l_sys_cpu);
    lua_setfield(ls, -2, "cpu");
    lua_pushcfunction(ls, l_sys_memory);
    lua_setfield(ls, -2, "memory");
    lua_pushcfunction(ls, l_sys_disk);
    lua_setfield(ls, -2, "disk");
    lua_pushcfunction(ls, l_sys_battery);
    lua_setfield(ls, -2, "battery");
    lua_pushcfunction(ls, l_sys_uptime);
    lua_setfield(ls, -2, "uptime");
    lua_pushcfunction(ls, l_sys_process_count);
    lua_setfield(ls, -2, "process_count");
    lua_pushcfunction(ls, l_sys_net);
    lua_setfield(ls, -2, "net");
    lua_pushcfunction(ls, l_sys_net_speed);
    lua_setfield(ls, -2, "net_speed");
    lua_pushcfunction(ls, l_sys_net_processes);
    lua_setfield(ls, -2, "net_processes");
    lua_setglobal(ls, "sys");
}