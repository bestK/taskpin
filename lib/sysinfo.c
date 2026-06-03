#include "sysinfo.h"
#include "lua/lua.h"
#include "lua/lauxlib.h"
#include <windows.h>
#include <shellapi.h>
#include <string.h>
#include <stdio.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <wininet.h>

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

/* ─── Top processes by CPU / memory ─── */

#include <psapi.h>

#define TOP_PROC_MAX 128

typedef struct {
    DWORD pid;
    ULONGLONG kernel_time;
    ULONGLONG user_time;
} TopProcSnap;

static TopProcSnap s_tp_prev[TOP_PROC_MAX];
static int s_tp_prev_count = 0;
static DWORD s_tp_prev_tick = 0;

static int l_sys_top_processes(lua_State *ls) {
    const char *mode = luaL_optstring(ls, 1, "cpu");
    int limit = (int)luaL_optinteger(ls, 2, 15);
    if (limit < 1) limit = 1;
    if (limit > TOP_PROC_MAX) limit = TOP_PROC_MAX;

    int mode_mem = (strcmp(mode, "mem") == 0);

    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) { lua_newtable(ls); return 1; }

    DWORD now = GetTickCount();
    DWORD dt = (s_tp_prev_tick > 0) ? (now - s_tp_prev_tick) : 0;

    typedef struct {
        DWORD pid;
        char name[256];
        char path[MAX_PATH];
        double cpu_pct;
        ULONGLONG mem_bytes;
        ULONGLONG kernel_time;
        ULONGLONG user_time;
    } ProcInfo;

    ProcInfo *infos = (ProcInfo *)calloc(TOP_PROC_MAX * 4, sizeof(ProcInfo));
    if (!infos) { CloseHandle(snap); lua_newtable(ls); return 1; }
    int count = 0;

    PROCESSENTRY32W pe = { .dwSize = sizeof(pe) };
    if (Process32FirstW(snap, &pe)) {
        do {
            if (pe.th32ProcessID == 0) continue;
            if (count >= TOP_PROC_MAX * 4) break;
            HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pe.th32ProcessID);
            if (!hProc) continue;

            PROCESS_MEMORY_COUNTERS pmc = {0};
            pmc.cb = sizeof(pmc);
            FILETIME ft_create = {0}, ft_exit = {0}, ft_kernel = {0}, ft_user = {0};
            ULONGLONG kt = 0, ut = 0, mem_b = 0;

            if (GetProcessMemoryInfo(hProc, &pmc, sizeof(pmc))) {
                mem_b = pmc.WorkingSetSize;
            }
            if (GetProcessTimes(hProc, &ft_create, &ft_exit, &ft_kernel, &ft_user)) {
                kt = ft_to_u64(ft_kernel);
                ut = ft_to_u64(ft_user);
            }

            /* Get full path */
            WCHAR wfull[MAX_PATH];
            DWORD path_size = MAX_PATH;
            char path8[MAX_PATH] = "";
            if (QueryFullProcessImageNameW(hProc, 0, wfull, &path_size)) {
                WideCharToMultiByte(CP_UTF8, 0, wfull, -1, path8, MAX_PATH, NULL, NULL);
            }

            CloseHandle(hProc);

            double cpu_pct = 0;
            if (dt > 0) {
                for (int j = 0; j < s_tp_prev_count; j++) {
                    if (s_tp_prev[j].pid == pe.th32ProcessID) {
                        ULONGLONG d_total = (kt - s_tp_prev[j].kernel_time) + (ut - s_tp_prev[j].user_time);
                        cpu_pct = (double)d_total / ((double)dt * 10000.0);
                        if (cpu_pct < 0) cpu_pct = 0;
                        if (cpu_pct > 100) cpu_pct = 100;
                        break;
                    }
                }
            }

            ProcInfo *pi = &infos[count];
            pi->pid = pe.th32ProcessID;
            WideCharToMultiByte(CP_UTF8, 0, pe.szExeFile, -1, pi->name, sizeof(pi->name), NULL, NULL);
            pi->name[sizeof(pi->name) - 1] = '\0';
            strncpy(pi->path, path8, MAX_PATH - 1);
            pi->path[MAX_PATH - 1] = '\0';
            pi->cpu_pct = cpu_pct;
            pi->mem_bytes = mem_b;
            pi->kernel_time = kt;
            pi->user_time = ut;
            count++;
            if (count >= TOP_PROC_MAX * 4) break;
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);

    /* Save snapshot for next delta */
    s_tp_prev_count = 0;
    for (int i = 0; i < count && s_tp_prev_count < TOP_PROC_MAX; i++) {
        s_tp_prev[s_tp_prev_count].pid = infos[i].pid;
        s_tp_prev[s_tp_prev_count].kernel_time = infos[i].kernel_time;
        s_tp_prev[s_tp_prev_count].user_time = infos[i].user_time;
        s_tp_prev_count++;
    }
    s_tp_prev_tick = now;

    /* Sort */
    for (int i = 0; i < count - 1; i++) {
        for (int j = i + 1; j < count; j++) {
            int swap = 0;
            if (mode_mem) {
                if (infos[j].mem_bytes > infos[i].mem_bytes) swap = 1;
            } else {
                if (infos[j].cpu_pct > infos[i].cpu_pct) swap = 1;
                else if (infos[j].cpu_pct == infos[i].cpu_pct && infos[j].mem_bytes > infos[i].mem_bytes) swap = 1;
            }
            if (swap) { ProcInfo tmp = infos[i]; infos[i] = infos[j]; infos[j] = tmp; }
        }
    }

    /* Push top N to Lua */
    lua_newtable(ls);
    int n = (count < limit) ? count : limit;
    for (int i = 0; i < n; i++) {
        lua_newtable(ls);
        lua_pushinteger(ls, (lua_Integer)infos[i].pid);
        lua_setfield(ls, -2, "pid");
        lua_pushstring(ls, infos[i].name);
        lua_setfield(ls, -2, "name");
        lua_pushstring(ls, infos[i].path);
        lua_setfield(ls, -2, "path");
        lua_pushnumber(ls, infos[i].cpu_pct);
        lua_setfield(ls, -2, "cpu");
        lua_pushinteger(ls, (lua_Integer)(infos[i].mem_bytes / (1024 * 1024)));
        lua_setfield(ls, -2, "mem_mb");
        lua_rawseti(ls, -2, i + 1);
    }

    free(infos);
    return 1;
}

/* ─── Per-process network connections + IO speed ─── */

#include <tcpmib.h>
#include <winsock2.h>

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

        /* Get process name and full path */
        WCHAR wname[MAX_PATH];
        DWORD name_size = MAX_PATH;
        char name8[MAX_PATH];
        char path8[MAX_PATH] = "";
        if (QueryFullProcessImageNameW(hProc, 0, wname, &name_size)) {
            WideCharToMultiByte(CP_UTF8, 0, wname, -1, path8, MAX_PATH, NULL, NULL);
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
        lua_pushstring(ls, path8);
        lua_setfield(ls, -2, "path");
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

/* ─── File modification time (seconds since epoch) ─── */

static int l_sys_file_mtime(lua_State *ls) {
    const char *path = luaL_checkstring(ls, 1);
    WCHAR wpath[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (!GetFileAttributesExW(wpath, GetFileExInfoStandard, &fad)) {
        lua_pushnil(ls);
        return 1;
    }
    /* Convert FILETIME to Unix timestamp */
    ULARGE_INTEGER uli;
    uli.LowPart = fad.ftLastWriteTime.dwLowDateTime;
    uli.HighPart = fad.ftLastWriteTime.dwHighDateTime;
    lua_Integer epoch = (lua_Integer)((uli.QuadPart - 116444736000000000ULL) / 10000000ULL);
    lua_pushinteger(ls, epoch);
    return 1;
}

/* ─── Find newest file recursively ─── */

static ULARGE_INTEGER s_newest_time;
static WCHAR s_newest_path[MAX_PATH];

static void find_newest_recurse(const WCHAR *dir, const WCHAR *ext) {
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
            find_newest_recurse(full, ext);
        } else {
            /* Check extension */
            WCHAR *dot = wcsrchr(fd.cFileName, L'.');
            if (dot && _wcsicmp(dot, ext) == 0) {
                ULARGE_INTEGER ft;
                ft.LowPart = fd.ftLastWriteTime.dwLowDateTime;
                ft.HighPart = fd.ftLastWriteTime.dwHighDateTime;
                if (ft.QuadPart > s_newest_time.QuadPart) {
                    s_newest_time = ft;
                    lstrcpynW(s_newest_path, full, MAX_PATH);
                }
            }
        }
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
}

static int l_sys_find_newest(lua_State *ls) {
    const char *dir = luaL_checkstring(ls, 1);
    const char *ext = luaL_checkstring(ls, 2); /* e.g. ".jsonl" */

    WCHAR wdir[MAX_PATH], wext[32];
    MultiByteToWideChar(CP_UTF8, 0, dir, -1, wdir, MAX_PATH);
    MultiByteToWideChar(CP_UTF8, 0, ext, -1, wext, 32);

    s_newest_time.QuadPart = 0;
    s_newest_path[0] = L'\0';

    find_newest_recurse(wdir, wext);

    if (s_newest_path[0]) {
        char result[MAX_PATH];
        WideCharToMultiByte(CP_UTF8, 0, s_newest_path, -1, result, MAX_PATH, NULL, NULL);
        lua_pushstring(ls, result);
    } else {
        lua_pushnil(ls);
    }
    return 1;
}

/* ─── Read file with Unicode path support ─── */

static int l_sys_read_file(lua_State *ls) {
    const char *path = luaL_checkstring(ls, 1);
    WCHAR wpath[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

    HANDLE hFile = CreateFileW(wpath, GENERIC_READ, FILE_SHARE_READ, NULL,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) { lua_pushnil(ls); return 1; }

    DWORD size = GetFileSize(hFile, NULL);
    if (size == 0 || size == INVALID_FILE_SIZE) {
        CloseHandle(hFile);
        lua_pushstring(ls, "");
        return 1;
    }

    char *buf = (char *)malloc(size + 1);
    if (!buf) { CloseHandle(hFile); lua_pushnil(ls); return 1; }

    DWORD read_bytes = 0;
    ReadFile(hFile, buf, size, &read_bytes, NULL);
    CloseHandle(hFile);
    buf[read_bytes] = '\0';

    /* Skip UTF-8 BOM if present */
    char *start = buf;
    if (read_bytes >= 3 && (unsigned char)buf[0] == 0xEF &&
        (unsigned char)buf[1] == 0xBB && (unsigned char)buf[2] == 0xBF) {
        start = buf + 3;
        read_bytes -= 3;
    }

    lua_pushlstring(ls, start, read_bytes);
    free(buf);
    return 1;
}

static int l_sys_write_file(lua_State *ls) {
    const char *path = luaL_checkstring(ls, 1);
    size_t len = 0;
    const char *content = luaL_checklstring(ls, 2, &len);
    WCHAR wpath[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

    HANDLE hFile = CreateFileW(wpath, GENERIC_WRITE, 0, NULL,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) { lua_pushboolean(ls, 0); return 1; }

    DWORD written = 0;
    WriteFile(hFile, content, (DWORD)len, &written, NULL);
    CloseHandle(hFile);
    lua_pushboolean(ls, written == (DWORD)len);
    return 1;
}

static int l_sys_exe_path(lua_State *ls) {
    WCHAR wpath[MAX_PATH];
    GetModuleFileNameW(NULL, wpath, MAX_PATH);
    char path[MAX_PATH * 3];
    WideCharToMultiByte(CP_UTF8, 0, wpath, -1, path, sizeof(path), NULL, NULL);
    lua_pushstring(ls, path);
    return 1;
}

static int l_sys_version(lua_State *ls) {
    lua_pushstring(ls, TASKPIN_VERSION);
    return 1;
}

static int l_sys_screen_width(lua_State *ls) {
    lua_pushinteger(ls, GetSystemMetrics(SM_CXSCREEN));
    return 1;
}

static int l_sys_screen_height(lua_State *ls) {
    lua_pushinteger(ls, GetSystemMetrics(SM_CYSCREEN));
    return 1;
}

static int l_sys_mouse_x(lua_State *ls) {
    POINT pt; GetCursorPos(&pt);
    lua_pushinteger(ls, pt.x);
    return 1;
}

static int l_sys_mouse_y(lua_State *ls) {
    POINT pt; GetCursorPos(&pt);
    lua_pushinteger(ls, pt.y);
    return 1;
}

static int l_sys_window_at(lua_State *ls) {
    int x = (int)luaL_checkinteger(ls, 1);
    int y = (int)luaL_checkinteger(ls, 2);
    POINT pt = { x, y };
    HWND hwnd = WindowFromPoint(pt);
    if (!hwnd || hwnd == GetDesktopWindow() || hwnd == GetShellWindow()) {
        lua_pushnil(ls);
        return 1;
    }
    HWND root = GetAncestor(hwnd, GA_ROOT);
    if (root) hwnd = root;
    /* Skip TaskPin's own dialog windows */
    WCHAR cls[64];
    GetClassNameW(hwnd, cls, 64);
    if (lstrcmpW(cls, L"TaskPinScriptDialog") == 0 ||
        lstrcmpW(cls, L"TaskPinBarClass") == 0) {
        lua_pushnil(ls);
        return 1;
    }
    lua_pushinteger(ls, (lua_Integer)(intptr_t)hwnd);
    return 1;
}

static int l_sys_move_window(lua_State *ls) {
    HWND hwnd = (HWND)(intptr_t)luaL_checkinteger(ls, 1);
    int dx = (int)luaL_checkinteger(ls, 2);
    int dy = (int)luaL_checkinteger(ls, 3);
    if (!IsWindow(hwnd)) { lua_pushboolean(ls, 0); return 1; }
    RECT rc;
    GetWindowRect(hwnd, &rc);
    SetWindowPos(hwnd, NULL, rc.left + dx, rc.top + dy, 0, 0,
        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    lua_pushboolean(ls, 1);
    return 1;
}

static int l_sys_window_rect(lua_State *ls) {
    HWND hwnd = (HWND)(intptr_t)luaL_checkinteger(ls, 1);
    if (!IsWindow(hwnd)) { lua_pushnil(ls); return 1; }
    RECT rc;
    GetWindowRect(hwnd, &rc);
    lua_newtable(ls);
    lua_pushinteger(ls, rc.left);   lua_setfield(ls, -2, "x");
    lua_pushinteger(ls, rc.top);    lua_setfield(ls, -2, "y");
    lua_pushinteger(ls, rc.right - rc.left);  lua_setfield(ls, -2, "w");
    lua_pushinteger(ls, rc.bottom - rc.top);  lua_setfield(ls, -2, "h");
    return 1;
}

static int l_sys_window_title(lua_State *ls) {
    HWND hwnd = (HWND)(intptr_t)luaL_checkinteger(ls, 1);
    if (!IsWindow(hwnd)) { lua_pushnil(ls); return 1; }
    WCHAR wbuf[256];
    GetWindowTextW(hwnd, wbuf, 256);
    char buf[768];
    WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, buf, sizeof(buf), NULL, NULL);
    lua_pushstring(ls, buf);
    return 1;
}

static BOOL CALLBACK enum_windows_cb(HWND hwnd, LPARAM lp) {
    if (!IsWindowVisible(hwnd)) return TRUE;
    WCHAR cls[64];
    GetClassNameW(hwnd, cls, 64);
    if (lstrcmpW(cls, L"TaskPinScriptDialog") == 0 ||
        lstrcmpW(cls, L"TaskPinBarClass") == 0) return TRUE;
    if (hwnd == GetDesktopWindow() || hwnd == GetShellWindow()) return TRUE;

    lua_State *ls = (lua_State *)lp;
    int idx = (int)lua_rawlen(ls, -1) + 1;
    lua_newtable(ls);
    lua_pushinteger(ls, (lua_Integer)(intptr_t)hwnd);
    lua_setfield(ls, -2, "hwnd");
    WCHAR wbuf[256];
    GetWindowTextW(hwnd, wbuf, 256);
    char buf[768];
    WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, buf, sizeof(buf), NULL, NULL);
    lua_pushstring(ls, buf);
    lua_setfield(ls, -2, "title");
    lua_rawseti(ls, -2, idx);
    return TRUE;
}

static int l_sys_window_list(lua_State *ls) {
    lua_newtable(ls);
    EnumWindows(enum_windows_cb, (LPARAM)ls);
    return 1;
}

static int l_sys_active_window(lua_State *ls) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) { lua_pushnil(ls); return 1; }
    lua_pushinteger(ls, (lua_Integer)(intptr_t)hwnd);
    return 1;
}

static int l_sys_is_fullscreen(lua_State *ls) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) { lua_pushboolean(ls, 0); return 1; }
    RECT rc;
    GetWindowRect(hwnd, &rc);
    int sw = GetSystemMetrics(SM_CXSCREEN);
    int sh = GetSystemMetrics(SM_CYSCREEN);
    lua_pushboolean(ls, rc.left <= 0 && rc.top <= 0 &&
        rc.right >= sw && rc.bottom >= sh);
    return 1;
}

static int l_sys_clipboard(lua_State *ls) {
    if (!OpenClipboard(NULL)) { lua_pushnil(ls); return 1; }
    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    if (!h) { CloseClipboard(); lua_pushnil(ls); return 1; }
    WCHAR *wstr = (WCHAR *)GlobalLock(h);
    if (!wstr) { CloseClipboard(); lua_pushnil(ls); return 1; }
    int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    char *buf = (char *)malloc(len);
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buf, len, NULL, NULL);
    GlobalUnlock(h);
    CloseClipboard();
    lua_pushstring(ls, buf);
    free(buf);
    return 1;
}

static int l_sys_set_clipboard(lua_State *ls) {
    const char *text = luaL_checkstring(ls, 1);
    int wlen = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
    HGLOBAL hg = GlobalAlloc(GMEM_MOVEABLE, wlen * sizeof(WCHAR));
    if (!hg) { lua_pushboolean(ls, 0); return 1; }
    WCHAR *dst = (WCHAR *)GlobalLock(hg);
    MultiByteToWideChar(CP_UTF8, 0, text, -1, dst, wlen);
    GlobalUnlock(hg);
    if (!OpenClipboard(NULL)) { GlobalFree(hg); lua_pushboolean(ls, 0); return 1; }
    EmptyClipboard();
    SetClipboardData(CF_UNICODETEXT, hg);
    CloseClipboard();
    lua_pushboolean(ls, 1);
    return 1;
}

static int l_sys_shell(lua_State *ls) {
    const char *cmd = luaL_checkstring(ls, 1);
    WCHAR wcmd[1024];
    MultiByteToWideChar(CP_UTF8, 0, cmd, -1, wcmd, 1024);
    HINSTANCE r = ShellExecuteW(NULL, L"open", wcmd, NULL, NULL, SW_SHOWNORMAL);
    lua_pushboolean(ls, (intptr_t)r > 32);
    return 1;
}

static int l_sys_notify(lua_State *ls) {
    const char *title = luaL_checkstring(ls, 1);
    const char *msg = luaL_checkstring(ls, 2);
    NOTIFYICONDATAW nid = {0};
    nid.cbSize = sizeof(nid);
    nid.hWnd = FindWindowW(L"TaskPinBarClass", NULL);
    nid.uID = 9999;
    nid.uFlags = NIF_INFO | NIF_ICON;
    nid.dwInfoFlags = NIIF_INFO;
    nid.hIcon = LoadIcon(NULL, IDI_INFORMATION);
    MultiByteToWideChar(CP_UTF8, 0, title, -1, nid.szInfoTitle, 64);
    MultiByteToWideChar(CP_UTF8, 0, msg, -1, nid.szInfo, 256);
    if (!Shell_NotifyIconW(NIM_MODIFY, &nid)) {
        nid.uFlags |= NIF_TIP;
        lstrcpynW(nid.szTip, L"TaskPin", 64);
        Shell_NotifyIconW(NIM_ADD, &nid);
    }
    lua_pushboolean(ls, 1);
    return 1;
}

static int l_sys_resize_window(lua_State *ls) {
    HWND hwnd = (HWND)(intptr_t)luaL_checkinteger(ls, 1);
    int w = (int)luaL_checkinteger(ls, 2);
    int h = (int)luaL_checkinteger(ls, 3);
    if (!IsWindow(hwnd)) { lua_pushboolean(ls, 0); return 1; }
    SetWindowPos(hwnd, NULL, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    lua_pushboolean(ls, 1);
    return 1;
}

static int l_sys_topmost_window(lua_State *ls) {
    HWND hwnd = (HWND)(intptr_t)luaL_checkinteger(ls, 1);
    int on = lua_toboolean(ls, 2);
    if (!IsWindow(hwnd)) { lua_pushboolean(ls, 0); return 1; }
    SetWindowPos(hwnd, on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    lua_pushboolean(ls, 1);
    return 1;
}

static int l_sys_is_running(lua_State *ls) {
    const char *name = luaL_checkstring(ls, 1);
    WCHAR wname[256];
    MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, 256);
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) { lua_pushboolean(ls, 0); return 1; }
    PROCESSENTRY32W pe = { .dwSize = sizeof(pe) };
    BOOL found = FALSE;
    if (Process32FirstW(snap, &pe)) {
        do {
            if (lstrcmpiW(pe.szExeFile, wname) == 0) { found = TRUE; break; }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    lua_pushboolean(ls, found);
    return 1;
}

static int l_sys_process_list(lua_State *ls) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) { lua_newtable(ls); return 1; }
    PROCESSENTRY32W pe = { .dwSize = sizeof(pe) };
    lua_newtable(ls);
    int idx = 1;
    if (Process32FirstW(snap, &pe)) {
        do {
            lua_newtable(ls);
            lua_pushinteger(ls, pe.th32ProcessID);
            lua_setfield(ls, -2, "pid");
            char buf[512];
            WideCharToMultiByte(CP_UTF8, 0, pe.szExeFile, -1, buf, sizeof(buf), NULL, NULL);
            lua_pushstring(ls, buf);
            lua_setfield(ls, -2, "name");
            lua_rawseti(ls, -2, idx++);
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return 1;
}

static int l_sys_kill(lua_State *ls) {
    DWORD pid = (DWORD)luaL_checkinteger(ls, 1);
    HANDLE hp = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
    if (!hp) { lua_pushboolean(ls, 0); return 1; }
    BOOL ok = TerminateProcess(hp, 1);
    CloseHandle(hp);
    lua_pushboolean(ls, ok);
    return 1;
}

/* Audio volume via IAudioEndpointVolume (COM) */
DEFINE_GUID(CLSID_MMDeviceEnumerator_local, 0xBCDE0395,0xE52F,0x467C,0x8E,0x3D,0xC4,0x57,0x92,0x91,0x69,0x2E);
DEFINE_GUID(IID_IMMDeviceEnumerator_local, 0xA95664D2,0x9614,0x4F35,0xA7,0x46,0xDE,0x8D,0xB6,0x36,0x17,0xE6);
DEFINE_GUID(IID_IAudioEndpointVolume_local, 0x5CDF2C82,0x841E,0x4546,0x97,0x22,0x0C,0xF7,0x40,0x78,0x22,0x9A);

static IAudioEndpointVolume *get_volume_endpoint(void) {
    IMMDeviceEnumerator *pEnum = NULL;
    IMMDevice *pDevice = NULL;
    IAudioEndpointVolume *pVol = NULL;
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(CoCreateInstance(&CLSID_MMDeviceEnumerator_local, NULL, CLSCTX_ALL,
            &IID_IMMDeviceEnumerator_local, (void **)&pEnum))) return NULL;
    if (FAILED(pEnum->lpVtbl->GetDefaultAudioEndpoint(pEnum, eRender, eConsole, &pDevice))) {
        pEnum->lpVtbl->Release(pEnum); return NULL;
    }
    if (FAILED(pDevice->lpVtbl->Activate(pDevice, &IID_IAudioEndpointVolume_local,
            CLSCTX_ALL, NULL, (void **)&pVol))) {
        pDevice->lpVtbl->Release(pDevice); pEnum->lpVtbl->Release(pEnum); return NULL;
    }
    pDevice->lpVtbl->Release(pDevice);
    pEnum->lpVtbl->Release(pEnum);
    return pVol;
}

static int l_sys_volume(lua_State *ls) {
    IAudioEndpointVolume *pVol = get_volume_endpoint();
    if (!pVol) { lua_pushinteger(ls, -1); return 1; }
    float level = 0;
    pVol->lpVtbl->GetMasterVolumeLevelScalar(pVol, &level);
    pVol->lpVtbl->Release(pVol);
    lua_pushinteger(ls, (int)(level * 100 + 0.5f));
    return 1;
}

static int l_sys_set_volume(lua_State *ls) {
    int vol = (int)luaL_checkinteger(ls, 1);
    if (vol < 0) vol = 0;
    if (vol > 100) vol = 100;
    IAudioEndpointVolume *pVol = get_volume_endpoint();
    if (!pVol) { lua_pushboolean(ls, 0); return 1; }
    pVol->lpVtbl->SetMasterVolumeLevelScalar(pVol, vol / 100.0f, NULL);
    pVol->lpVtbl->Release(pVol);
    lua_pushboolean(ls, 1);
    return 1;
}

static int l_sys_is_muted(lua_State *ls) {
    IAudioEndpointVolume *pVol = get_volume_endpoint();
    if (!pVol) { lua_pushboolean(ls, 0); return 1; }
    BOOL muted = FALSE;
    pVol->lpVtbl->GetMute(pVol, &muted);
    pVol->lpVtbl->Release(pVol);
    lua_pushboolean(ls, muted);
    return 1;
}

static int l_sys_wifi_name(lua_State *ls) {
    /* Use netsh to get WiFi SSID - simpler than wlanapi dynamic loading */
    FILE *fp = _popen("netsh wlan show interfaces", "r");
    if (!fp) { lua_pushnil(ls); return 1; }
    char line[512];
    char ssid[256] = {0};
    while (fgets(line, sizeof(line), fp)) {
        char *p = strstr(line, "SSID");
        if (p && !strstr(line, "BSSID")) {
            p = strchr(p, ':');
            if (p) {
                p++;
                while (*p == ' ') p++;
                char *end = p + strlen(p) - 1;
                while (end > p && (*end == '\n' || *end == '\r' || *end == ' ')) *end-- = '\0';
                strncpy(ssid, p, sizeof(ssid) - 1);
                break;
            }
        }
    }
    _pclose(fp);
    if (ssid[0]) lua_pushstring(ls, ssid);
    else lua_pushnil(ls);
    return 1;
}

static int l_sys_is_connected(lua_State *ls) {
    /* Quick check: try to resolve a known host */
    DWORD flags = 0;
    BOOL online = InternetGetConnectedState(&flags, 0);
    lua_pushboolean(ls, online);
    return 1;
}

static int l_sys_is_dark_mode(lua_State *ls) {
    HKEY hkey;
    DWORD val = 1, size = sizeof(val);
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
            0, KEY_READ, &hkey) == ERROR_SUCCESS) {
        RegQueryValueExW(hkey, L"AppsUseLightTheme", NULL, NULL, (BYTE *)&val, &size);
        RegCloseKey(hkey);
    }
    lua_pushboolean(ls, val == 0);
    return 1;
}

static int l_sys_monitor_count(lua_State *ls) {
    lua_pushinteger(ls, GetSystemMetrics(SM_CMONITORS));
    return 1;
}

static BOOL CALLBACK monitor_enum_cb(HMONITOR hMon, HDC hdc, LPRECT lprc, LPARAM lp) {
    (void)hdc; (void)lprc;
    int *ctx = (int *)lp; /* ctx[0] = target index (1-based), ctx[1] = current */
    ctx[1]++;
    if (ctx[1] == ctx[0]) {
        MONITORINFO mi = { .cbSize = sizeof(mi) };
        GetMonitorInfoW(hMon, &mi);
        ctx[2] = mi.rcMonitor.left;
        ctx[3] = mi.rcMonitor.top;
        ctx[4] = mi.rcMonitor.right - mi.rcMonitor.left;
        ctx[5] = mi.rcMonitor.bottom - mi.rcMonitor.top;
        return FALSE;
    }
    return TRUE;
}

static int l_sys_monitor_rect(lua_State *ls) {
    int idx = (int)luaL_checkinteger(ls, 1);
    int ctx[6] = { idx, 0, 0, 0, 0, 0 };
    EnumDisplayMonitors(NULL, NULL, monitor_enum_cb, (LPARAM)ctx);
    if (ctx[1] < idx) { lua_pushnil(ls); return 1; }
    lua_newtable(ls);
    lua_pushinteger(ls, ctx[2]); lua_setfield(ls, -2, "x");
    lua_pushinteger(ls, ctx[3]); lua_setfield(ls, -2, "y");
    lua_pushinteger(ls, ctx[4]); lua_setfield(ls, -2, "w");
    lua_pushinteger(ls, ctx[5]); lua_setfield(ls, -2, "h");
    return 1;
}

static int l_sys_env(lua_State *ls) {
    const char *name = luaL_checkstring(ls, 1);
    WCHAR wname[256];
    MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, 256);
    WCHAR wval[4096];
    DWORD len = GetEnvironmentVariableW(wname, wval, 4096);
    if (len == 0) { lua_pushnil(ls); return 1; }
    char buf[4096];
    WideCharToMultiByte(CP_UTF8, 0, wval, -1, buf, sizeof(buf), NULL, NULL);
    lua_pushstring(ls, buf);
    return 1;
}

#include "httputil.h"

static int s_china_checked = 0;
static BOOL s_china_result = FALSE;

static void ensure_china_check(void) {
    if (s_china_checked) return;
    char *resp = http_get_sync(L"https://api.ip.sb/geoip", NULL);
    if (resp) {
        s_china_result = (strstr(resp, "\"country_code\":\"CN\"") != NULL);
        free(resp);
    }
    s_china_checked = 1;
}

static int l_sys_is_china(lua_State *ls) {
    ensure_china_check();
    lua_pushboolean(ls, s_china_result);
    return 1;
}

static int l_sys_gh_proxy(lua_State *ls) {
    const char *url = luaL_checkstring(ls, 1);
    ensure_china_check();
    if (s_china_result) {
        size_t len = strlen(url) + 32;
        char *buf = (char *)malloc(len);
        snprintf(buf, len, "https://gh-proxy.com/%s", url);
        lua_pushstring(ls, buf);
        free(buf);
    } else {
        lua_pushstring(ls, url);
    }
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
    lua_pushcfunction(ls, l_sys_top_processes);
    lua_setfield(ls, -2, "top_processes");
    lua_pushcfunction(ls, l_sys_file_mtime);
    lua_setfield(ls, -2, "file_mtime");
    lua_pushcfunction(ls, l_sys_find_newest);
    lua_setfield(ls, -2, "find_newest");
    lua_pushcfunction(ls, l_sys_read_file);
    lua_setfield(ls, -2, "read_file");
    lua_pushcfunction(ls, l_sys_write_file);
    lua_setfield(ls, -2, "write_file");
    lua_pushcfunction(ls, l_sys_exe_path);
    lua_setfield(ls, -2, "exe_path");
    lua_pushcfunction(ls, l_sys_version);
    lua_setfield(ls, -2, "version");
    lua_pushcfunction(ls, l_sys_screen_width);
    lua_setfield(ls, -2, "screen_width");
    lua_pushcfunction(ls, l_sys_screen_height);
    lua_setfield(ls, -2, "screen_height");
    lua_pushcfunction(ls, l_sys_mouse_x);
    lua_setfield(ls, -2, "mouse_x");
    lua_pushcfunction(ls, l_sys_mouse_y);
    lua_setfield(ls, -2, "mouse_y");
    lua_pushcfunction(ls, l_sys_window_at);
    lua_setfield(ls, -2, "window_at");
    lua_pushcfunction(ls, l_sys_move_window);
    lua_setfield(ls, -2, "move_window");
    lua_pushcfunction(ls, l_sys_window_rect);
    lua_setfield(ls, -2, "window_rect");
    lua_pushcfunction(ls, l_sys_window_title);
    lua_setfield(ls, -2, "window_title");
    lua_pushcfunction(ls, l_sys_window_list);
    lua_setfield(ls, -2, "window_list");
    lua_pushcfunction(ls, l_sys_active_window);
    lua_setfield(ls, -2, "active_window");
    lua_pushcfunction(ls, l_sys_is_fullscreen);
    lua_setfield(ls, -2, "is_fullscreen");
    lua_pushcfunction(ls, l_sys_clipboard);
    lua_setfield(ls, -2, "clipboard");
    lua_pushcfunction(ls, l_sys_set_clipboard);
    lua_setfield(ls, -2, "set_clipboard");
    lua_pushcfunction(ls, l_sys_shell);
    lua_setfield(ls, -2, "shell");
    lua_pushcfunction(ls, l_sys_notify);
    lua_setfield(ls, -2, "notify");
    lua_pushcfunction(ls, l_sys_resize_window);
    lua_setfield(ls, -2, "resize_window");
    lua_pushcfunction(ls, l_sys_topmost_window);
    lua_setfield(ls, -2, "topmost_window");
    lua_pushcfunction(ls, l_sys_is_running);
    lua_setfield(ls, -2, "is_running");
    lua_pushcfunction(ls, l_sys_process_list);
    lua_setfield(ls, -2, "process_list");
    lua_pushcfunction(ls, l_sys_kill);
    lua_setfield(ls, -2, "kill");
    lua_pushcfunction(ls, l_sys_volume);
    lua_setfield(ls, -2, "volume");
    lua_pushcfunction(ls, l_sys_set_volume);
    lua_setfield(ls, -2, "set_volume");
    lua_pushcfunction(ls, l_sys_is_muted);
    lua_setfield(ls, -2, "is_muted");
    lua_pushcfunction(ls, l_sys_wifi_name);
    lua_setfield(ls, -2, "wifi_name");
    lua_pushcfunction(ls, l_sys_is_connected);
    lua_setfield(ls, -2, "is_connected");
    lua_pushcfunction(ls, l_sys_is_dark_mode);
    lua_setfield(ls, -2, "is_dark_mode");
    lua_pushcfunction(ls, l_sys_monitor_count);
    lua_setfield(ls, -2, "monitor_count");
    lua_pushcfunction(ls, l_sys_monitor_rect);
    lua_setfield(ls, -2, "monitor_rect");
    lua_pushcfunction(ls, l_sys_env);
    lua_setfield(ls, -2, "env");
    lua_pushcfunction(ls, l_sys_is_china);
    lua_setfield(ls, -2, "is_china");
    lua_pushcfunction(ls, l_sys_gh_proxy);
    lua_setfield(ls, -2, "gh_proxy");
    lua_setglobal(ls, "sys");
}