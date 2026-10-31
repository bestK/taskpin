/*
 * tp_sysinfo_mac.m — the sys.*() Lua API on macOS.
 *
 * STATUS: IMPLEMENTED (Phase 8).
 *
 * The Lua-visible shapes are kept identical to tp_sysinfo_win.c (key names,
 * units, "0 on first sample", "-1 on failure", net_speed being a delta against
 * the previous call) so a script never has to branch on the OS. The sysinfo
 * implementations are ported from the proven macOS bridge
 * (src/clua_bridge/taskpin_lua.c) and extended with the APIs that bridge never
 * had: battery, country/language, is_china, gh_proxy and the key pollers.
 *
 * Implemented here:
 *   cpu            getloadavg() / hw.ncpu, clamped to 100
 *   memory         hw.memsize + host_statistics64, {total_mb, used_mb, percent}
 *   disk(path)     statfs, {total_gb, free_gb, percent}; path defaults to "/"
 *   battery        IOKit power sources, {percent, charging, seconds_left};
 *                  -1 / false / -1 when there is no battery
 *   uptime         kern.boottime
 *   process_count  kern.proc (KERN_PROC_ALL), count of kinfo_proc records
 *   net            getifaddrs AF_LINK, {recv_bytes, send_bytes}
 *   net_speed      delta against the previous call, {download, upload}
 *   net_processes  proc_listpids + per-PID established TCP sockets and
 *                  proc_pid_rusage, array of
 *                  {pid, name, connections, download, upload}
 *   file_mtime     stat, seconds since epoch
 *   find_newest    recursive opendir/stat walk, case-insensitive extension
 *   read_file      read + strip UTF-8 BOM
 *   country        NSLocale country code (ISO 3166-1 alpha-2), instant/offline
 *   language       NSLocale locale identifier ("en_US"), instant/offline
 *   is_china       network geo-IP via tp_http_request_sync, cached tri-state,
 *                  same endpoint and country_code=="CN" test as Windows
 *   gh_proxy       pure string transform, byte-for-byte the Windows logic
 *   watch_keys     resolves key names, returns the recognised ones as an array
 *   key_pressed    level state via CGEventSourceKeyState / ButtonState
 *   key_triggered  rising edge over key_pressed
 *
 * KEY API CHOICE (the stub left this open): polling with
 * CGEventSourceKeyState / CGEventSourceButtonState, not an NSEvent global
 * monitor. A global monitor is the macOS equivalent of the WH_KEYBOARD_LL hook
 * the Windows side deliberately avoided: it sits in the input path of every
 * application and is a surveillance-style permission prompt. CGEventSource
 * only reads the current session state on demand, installs nothing, and needs
 * no Accessibility/Input Monitoring grant. If the OS ever refuses the query
 * the answer is false, never a fabricated "pressed". The key names are the
 * same set as Windows (space/up/.../lclick/f1-f12), mapped to macOS virtual
 * key codes.
 *
 * No #error gate: this file is the real implementation, so the old
 * TP_ALLOW_UNIMPLEMENTED_MAC opt-in is gone.
 */

#if !defined(__APPLE__)
/* Compiled on a non-Apple target by mistake; CMake should prevent this. */
#error "tp_sysinfo_mac.m is macOS-only; native/engine/CMakeLists.txt must not compile it elsewhere."
#endif

#import <Foundation/Foundation.h>

#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/ps/IOPowerSources.h>

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <sys/sysctl.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/proc.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <libproc.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_var.h>
#include <ifaddrs.h>
#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#include "lua.h"
#include "lauxlib.h"

#include "tp_http.h"
#include "tp_sysinfo.h"

/* tp_json.c — declared here rather than pulling in taskpin_engine.h, which
 * would drag the whole ABI header into a platform TU for one prototype. */
int tp_json_to_lua(lua_State *L, const char *json);

#define TP_NET_PROC_MAX 128

/* ─── sys.cpu() — load average / core count ─── */

static int l_sys_cpu(lua_State *L) {
    double load[1] = {0.0};
    if (getloadavg(load, 1) < 0) {
        lua_pushinteger(L, -1);
        return 1;
    }

    int ncpu = 1;
    size_t sz = sizeof(ncpu);
    if (sysctlbyname("hw.ncpu", &ncpu, &sz, NULL, 0) != 0 || ncpu <= 0) {
        ncpu = 1;
    }

    int pct = (int)(load[0] * 100.0 / ncpu);
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;

    lua_pushinteger(L, pct);
    return 1;
}

/* ─── sys.memory() ─── */

static int l_sys_memory(lua_State *L) {
    int64_t total = 0;
    size_t sz = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &sz, NULL, 0) != 0 || total <= 0) {
        lua_pushnil(L);
        return 1;
    }

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          (host_info64_t)&vm, &count) != KERN_SUCCESS) {
        lua_pushnil(L);
        return 1;
    }

    vm_size_t page_size = 0;
    if (host_page_size(mach_host_self(), &page_size) != KERN_SUCCESS || page_size == 0) {
        page_size = 4096;
    }

    /* Same definition the bridge used: active + wired pages. */
    int64_t used = ((int64_t)vm.active_count + (int64_t)vm.wire_count) * (int64_t)page_size;
    if (used < 0) used = 0;
    if (used > total) used = total;

    lua_newtable(L);
    lua_pushinteger(L, (lua_Integer)(total / (1024 * 1024)));
    lua_setfield(L, -2, "total_mb");
    lua_pushinteger(L, (lua_Integer)(used / (1024 * 1024)));
    lua_setfield(L, -2, "used_mb");
    lua_pushinteger(L, (lua_Integer)(used * 100 / total));
    lua_setfield(L, -2, "percent");
    return 1;
}

/* ─── sys.disk(path) ─── */

static int l_sys_disk(lua_State *L) {
    /* The Windows default is a drive letter; on macOS the equivalent
     * "wherever the user is" answer is the root volume. */
    const char *path = luaL_optstring(L, 1, "/");

    struct statfs sf;
    if (statfs(path, &sf) != 0) {
        lua_pushnil(L);
        return 1;
    }

    double total_gb = (double)sf.f_blocks * (double)sf.f_bsize /
                      (1024.0 * 1024.0 * 1024.0);
    double free_gb = (double)sf.f_bavail * (double)sf.f_bsize /
                     (1024.0 * 1024.0 * 1024.0);
    int pct = total_gb > 0.0
        ? (int)((total_gb - free_gb) * 100.0 / total_gb)
        : 0;
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;

    lua_newtable(L);
    lua_pushnumber(L, total_gb);
    lua_setfield(L, -2, "total_gb");
    lua_pushnumber(L, free_gb);
    lua_setfield(L, -2, "free_gb");
    lua_pushinteger(L, pct);
    lua_setfield(L, -2, "percent");
    return 1;
}

/* ─── sys.battery() — IOKit power sources ─── */

static int l_sys_battery(lua_State *L) {
    int percent = -1;
    int charging = 0;
    int seconds_left = -1;

    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob) {
        lua_pushnil(L);
        return 1;
    }

    CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
    if (sources) {
        CFIndex n = CFArrayGetCount(sources);
        for (CFIndex i = 0; i < n; i++) {
            CFDictionaryRef desc = IOPSGetPowerSourceDescription(
                blob, CFArrayGetValueAtIndex(sources, i));
            if (!desc) continue;

            CFBooleanRef present = (CFBooleanRef)CFDictionaryGetValue(
                desc, CFSTR(kIOPSIsPresentKey));
            if (present && !CFBooleanGetValue(present)) continue;

            CFNumberRef cur = (CFNumberRef)CFDictionaryGetValue(
                desc, CFSTR(kIOPSCurrentCapacityKey));
            CFNumberRef max = (CFNumberRef)CFDictionaryGetValue(
                desc, CFSTR(kIOPSMaxCapacityKey));
            int cur_v = 0, max_v = 0;
            if (cur && max &&
                CFNumberGetValue(cur, kCFNumberIntType, &cur_v) &&
                CFNumberGetValue(max, kCFNumberIntType, &max_v) &&
                max_v > 0) {
                percent = (int)((int64_t)cur_v * 100 / max_v);
                if (percent > 100) percent = 100;
            }

            CFBooleanRef ch = (CFBooleanRef)CFDictionaryGetValue(
                desc, CFSTR(kIOPSIsChargingKey));
            charging = (ch && CFBooleanGetValue(ch)) ? 1 : 0;

            /* IOKit reports minutes; the Lua API is seconds, like Windows. */
            CFNumberRef left = (CFNumberRef)CFDictionaryGetValue(
                desc, charging ? CFSTR(kIOPSTimeToFullChargeKey)
                               : CFSTR(kIOPSTimeToEmptyKey));
            int minutes = -1;
            if (left && CFNumberGetValue(left, kCFNumberIntType, &minutes) &&
                minutes > 0) {
                seconds_left = minutes * 60;
            }
            break;
        }
        CFRelease(sources);
    }
    CFRelease(blob);

    lua_newtable(L);
    lua_pushinteger(L, percent);
    lua_setfield(L, -2, "percent");
    lua_pushboolean(L, charging);
    lua_setfield(L, -2, "charging");
    lua_pushinteger(L, seconds_left);
    lua_setfield(L, -2, "seconds_left");
    return 1;
}

/* ─── sys.uptime() ─── */

static int l_sys_uptime(lua_State *L) {
    struct timeval boottime;
    size_t sz = sizeof(boottime);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};

    if (sysctl(mib, 2, &boottime, &sz, NULL, 0) != 0) {
        lua_pushinteger(L, -1);
        return 1;
    }

    time_t now = time(NULL);
    lua_pushinteger(L, (lua_Integer)(now - boottime.tv_sec));
    return 1;
}

/* ─── sys.process_count() ─── */

static int l_sys_process_count(lua_State *L) {
    int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    size_t sz = 0;

    if (sysctl(mib, 3, NULL, &sz, NULL, 0) != 0) {
        lua_pushinteger(L, -1);
        return 1;
    }

    lua_pushinteger(L, (lua_Integer)(sz / sizeof(struct kinfo_proc)));
    return 1;
}

/* ─── network byte totals (shared by net / net_speed) ─── */

static void tp_net_get_totals(uint64_t *recv_out, uint64_t *send_out) {
    *recv_out = 0;
    *send_out = 0;

    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) != 0) return;

    for (struct ifaddrs *ifa = ifap; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK) continue;
        if ((ifa->ifa_flags & IFF_UP) == 0) continue;
        if (ifa->ifa_flags & IFF_LOOPBACK) continue;

        struct if_data *ifd = (struct if_data *)ifa->ifa_data;
        if (ifd) {
            *recv_out += (uint64_t)ifd->ifi_ibytes;
            *send_out += (uint64_t)ifd->ifi_obytes;
        }
    }
    freeifaddrs(ifap);
}

/* ─── sys.net() ─── */

static int l_sys_net(lua_State *L) {
    uint64_t recv_total = 0, send_total = 0;
    tp_net_get_totals(&recv_total, &send_total);

    lua_newtable(L);
    lua_pushnumber(L, (double)recv_total);
    lua_setfield(L, -2, "recv_bytes");
    lua_pushnumber(L, (double)send_total);
    lua_setfield(L, -2, "send_bytes");
    return 1;
}

/* ─── sys.net_speed() ─── */

static uint64_t s_prev_recv = 0, s_prev_send = 0;
static uint64_t s_prev_net_ms = 0;

static uint64_t tp_now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + (uint64_t)tv.tv_usec / 1000;
}

static int l_sys_net_speed(lua_State *L) {
    uint64_t cur_recv, cur_send;
    tp_net_get_totals(&cur_recv, &cur_send);
    uint64_t now = tp_now_ms();

    double dl_speed = 0, ul_speed = 0;
    if (s_prev_net_ms > 0) {
        uint64_t dt = now - s_prev_net_ms;
        if (dt > 0) {
            /* The if_data counters are 32-bit and wrap; a wrapped sample
             * reports 0 for that interval instead of a bogus spike. */
            if (cur_recv >= s_prev_recv) {
                dl_speed = (double)(cur_recv - s_prev_recv) * 1000.0 / (double)dt;
            }
            if (cur_send >= s_prev_send) {
                ul_speed = (double)(cur_send - s_prev_send) * 1000.0 / (double)dt;
            }
        }
    }
    s_prev_recv = cur_recv;
    s_prev_send = cur_send;
    s_prev_net_ms = now;

    lua_newtable(L);
    lua_pushnumber(L, dl_speed);
    lua_setfield(L, -2, "download");
    lua_pushnumber(L, ul_speed);
    lua_setfield(L, -2, "upload");
    return 1;
}

/* ─── sys.net_processes() ─── */

typedef struct {
    pid_t pid;
    uint64_t io_read;
    uint64_t io_write;
} TpNetProcSnap;

static TpNetProcSnap s_np_prev[TP_NET_PROC_MAX];
static int s_np_prev_count = 0;
static uint64_t s_np_prev_ms = 0;

typedef struct {
    pid_t pid;
    char name[256];
    int conns;
    uint64_t io_read;
    uint64_t io_write;
} TpProcInfo;

static int l_sys_net_processes(lua_State *L) {
    int buf_size = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (buf_size <= 0) {
        lua_newtable(L);
        return 1;
    }

    pid_t *pids = (pid_t *)malloc((size_t)buf_size);
    if (!pids) {
        lua_newtable(L);
        return 1;
    }

    buf_size = proc_listpids(PROC_ALL_PIDS, 0, pids, buf_size);
    int pid_count = buf_size / (int)sizeof(pid_t);

    TpProcInfo *procs = (TpProcInfo *)calloc(TP_NET_PROC_MAX, sizeof(TpProcInfo));
    if (!procs) {
        free(pids);
        lua_newtable(L);
        return 1;
    }
    int proc_count = 0;

    for (int i = 0; i < pid_count && proc_count < TP_NET_PROC_MAX; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        int fds_size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (fds_size <= 0) continue;

        struct proc_fdinfo *fds = (struct proc_fdinfo *)malloc((size_t)fds_size);
        if (!fds) continue;

        int actual = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, fds_size);
        int fd_count = actual / (int)sizeof(struct proc_fdinfo);

        int socket_count = 0;
        for (int j = 0; j < fd_count; j++) {
            if (fds[j].proc_fdtype != PROX_FDTYPE_SOCKET) continue;

            struct socket_fdinfo si;
            int si_size = proc_pidfdinfo(pid, fds[j].proc_fd,
                                         PROC_PIDFDSOCKETINFO, &si,
                                         (int)sizeof(si));
            if (si_size != (int)sizeof(si)) continue;
            if (si.psi.soi_family != AF_INET && si.psi.soi_family != AF_INET6) {
                continue;
            }
            if (si.psi.soi_kind == SOCKINFO_TCP &&
                si.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_ESTABLISHED) {
                socket_count++;
            }
        }
        free(fds);

        if (socket_count <= 0) continue;

        TpProcInfo *p = &procs[proc_count];
        p->pid = pid;
        p->conns = socket_count;
        proc_name(pid, p->name, (uint32_t)sizeof(p->name));
        if (p->name[0] == '\0') {
            snprintf(p->name, sizeof(p->name), "pid_%d", (int)pid);
        }

        struct rusage_info_v2 rusage;
        memset(&rusage, 0, sizeof(rusage));
        if (proc_pid_rusage(pid, RUSAGE_INFO_V2,
                            (rusage_info_t *)&rusage) == 0) {
            p->io_read = rusage.ri_diskio_bytesread;
            p->io_write = rusage.ri_diskio_byteswritten;
        }
        proc_count++;
    }
    free(pids);

    uint64_t now = tp_now_ms();
    uint64_t dt = (s_np_prev_ms > 0) ? (now - s_np_prev_ms) : 0;

    lua_newtable(L);
    for (int i = 0; i < proc_count; i++) {
        double dl_speed = 0, ul_speed = 0;
        if (dt > 0) {
            for (int j = 0; j < s_np_prev_count; j++) {
                if (s_np_prev[j].pid != procs[i].pid) continue;
                if (procs[i].io_read >= s_np_prev[j].io_read) {
                    dl_speed = (double)(procs[i].io_read - s_np_prev[j].io_read) *
                               1000.0 / (double)dt;
                }
                if (procs[i].io_write >= s_np_prev[j].io_write) {
                    ul_speed = (double)(procs[i].io_write - s_np_prev[j].io_write) *
                               1000.0 / (double)dt;
                }
                break;
            }
        }

        lua_newtable(L);
        lua_pushinteger(L, (lua_Integer)procs[i].pid);
        lua_setfield(L, -2, "pid");
        lua_pushstring(L, procs[i].name);
        lua_setfield(L, -2, "name");
        lua_pushinteger(L, procs[i].conns);
        lua_setfield(L, -2, "connections");
        lua_pushnumber(L, dl_speed);
        lua_setfield(L, -2, "download");
        lua_pushnumber(L, ul_speed);
        lua_setfield(L, -2, "upload");
        lua_rawseti(L, -2, i + 1);
    }

    for (int i = 0; i < proc_count && i < TP_NET_PROC_MAX; i++) {
        s_np_prev[i].pid = procs[i].pid;
        s_np_prev[i].io_read = procs[i].io_read;
        s_np_prev[i].io_write = procs[i].io_write;
    }
    s_np_prev_count = proc_count < TP_NET_PROC_MAX ? proc_count : TP_NET_PROC_MAX;
    s_np_prev_ms = now;

    free(procs);
    return 1;
}

/* ─── sys.file_mtime(path) ─── */

static int l_sys_file_mtime(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);

    struct stat st;
    if (stat(path, &st) != 0) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushinteger(L, (lua_Integer)st.st_mtime);
    return 1;
}

/* ─── sys.find_newest(dir, ext) ─── */

static time_t s_newest_mtime;
static char s_newest_path[PATH_MAX];

static void tp_find_newest_recurse(const char *dir, const char *ext) {
    DIR *d = opendir(dir);
    if (!d) return;

    struct dirent *entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.') continue;

        char full[PATH_MAX];
        int n = snprintf(full, sizeof(full), "%s/%s", dir, entry->d_name);
        if (n <= 0 || n >= (int)sizeof(full)) continue;

        struct stat st;
        if (stat(full, &st) != 0) continue;

        if (S_ISDIR(st.st_mode)) {
            tp_find_newest_recurse(full, ext);
            continue;
        }

        const char *dot = strrchr(entry->d_name, '.');
        if (dot && strcasecmp(dot, ext) == 0 && st.st_mtime > s_newest_mtime) {
            s_newest_mtime = st.st_mtime;
            snprintf(s_newest_path, sizeof(s_newest_path), "%s", full);
        }
    }
    closedir(d);
}

static int l_sys_find_newest(lua_State *L) {
    const char *dir = luaL_checkstring(L, 1);
    const char *ext = luaL_checkstring(L, 2);

    s_newest_mtime = 0;
    s_newest_path[0] = '\0';

    tp_find_newest_recurse(dir, ext);

    if (s_newest_path[0]) {
        lua_pushstring(L, s_newest_path);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

/* ─── sys.read_file(path) ─── */

static int l_sys_read_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);

    FILE *f = fopen(path, "rb");
    if (!f) {
        lua_pushnil(L);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size <= 0) {
        fclose(f);
        lua_pushstring(L, "");
        return 1;
    }

    char *buf = (char *)malloc((size_t)size + 1);
    if (!buf) {
        fclose(f);
        lua_pushnil(L);
        return 1;
    }

    size_t read_bytes = fread(buf, 1, (size_t)size, f);
    fclose(f);
    buf[read_bytes] = '\0';

    char *start = buf;
    if (read_bytes >= 3 && (unsigned char)buf[0] == 0xEF &&
        (unsigned char)buf[1] == 0xBB && (unsigned char)buf[2] == 0xBF) {
        start = buf + 3;
        read_bytes -= 3;
    }

    lua_pushlstring(L, start, read_bytes);
    free(buf);
    return 1;
}

/* ══════════════════════════════════════════════════════════════════════════
 * OS locale: sys.country() / sys.language()
 *
 * Same distinction as tp_sysinfo_win.c: these read the operating system's
 * regional settings, are instant and offline, and are NOT the network geo-IP
 * answer that sys.is_china() gives.
 * ══════════════════════════════════════════════════════════════════════════ */

/* sys.country() -> "CN" / "US" / ...  (ISO 3166-1 alpha-2), "" on failure. */
static int l_sys_country(lua_State *L) {
    @autoreleasepool {
        NSString *code = [[NSLocale currentLocale]
            objectForKey:NSLocaleCountryCode];
        if (code.length > 0) {
            lua_pushstring(L, code.UTF8String);
            return 1;
        }
    }
    lua_pushstring(L, "");
    return 1;
}

/* sys.language() -> "en_US" / "zh_CN" / ... , "" on failure.
 *
 * The Windows side returns the full locale name ("en-US"), so the closest
 * macOS equivalent is the locale identifier rather than the bare language
 * code: it carries the region subtag too. */
static int l_sys_language(lua_State *L) {
    @autoreleasepool {
        NSString *ident = [[NSLocale currentLocale] localeIdentifier];
        if (ident.length > 0) {
            lua_pushstring(L, ident.UTF8String);
            return 1;
        }
    }
    lua_pushstring(L, "");
    return 1;
}

/* ══════════════════════════════════════════════════════════════════════════
 * Network geo-IP: sys.is_china() / sys.gh_proxy()
 *
 * Same endpoint, same JSON test and same tri-state cache as tp_sysinfo_win.c;
 * only the transport differs (tp_http_request_sync -> NSURLSession).
 * ══════════════════════════════════════════════════════════════════════════ */

#define TP_GEO_URL_DEFAULT "https://api.ip.sb/geoip"

/* -1 = not checked yet, 0 = not in China, 1 = in China. */
static int s_is_china = -1;

static const char *tp_geo_url(void) {
    const char *env = getenv("TASKPIN_GEO_URL");
    return (env && env[0]) ? env : TP_GEO_URL_DEFAULT;
}

static int l_sys_is_china(lua_State *L) {
    if (s_is_china < 0) {
        s_is_china = 0; /* pessimistic default; offline means "not in China" */

        char *resp = tp_http_request_sync(tp_geo_url(), "GET", NULL, NULL, NULL, 0);
        if (resp) {
            if (tp_json_to_lua(L, resp) && lua_istable(L, -1)) {
                lua_getfield(L, -1, "country_code");
                const char *cc = lua_tostring(L, -1);
                if (cc && strcmp(cc, "CN") == 0) s_is_china = 1;
                lua_pop(L, 1);
            }
            lua_pop(L, 1);

            if (!s_is_china && strstr(resp, "\"country_code\":\"CN\"")) {
                s_is_china = 1;
            }
            free(resp);
        }
    }

    lua_pushboolean(L, s_is_china == 1);
    return 1;
}

/* sys.gh_proxy(url) — identical transform to tp_sysinfo_win.c. */
static int l_sys_gh_proxy(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);

    if (s_is_china != 1 || strncmp(url, "https://gh-proxy.com/", 20) == 0) {
        lua_pushstring(L, url);
        return 1;
    }

    const char *scheme = strstr(url, "://");
    const char *host = scheme ? scheme + 3 : url;
    const char *slash = strchr(host, '/');
    size_t host_len = slash ? (size_t)(slash - host) : strlen(host);

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
 * See the file header for why polling with CGEventSource is used instead of
 * an NSEvent global monitor. The edge state is process-global for the same
 * reason as on Windows: the engine re-runs the script on every refresh while
 * the Lua state persists.
 * ══════════════════════════════════════════════════════════════════════════ */

/* Mouse buttons are encoded above the virtual-key range so one index space
 * serves both. */
#define TP_KEY_MOUSE_BASE 256
#define TP_KEY_PREV_MAX   512

static unsigned char s_key_prev[TP_KEY_PREV_MAX];

/* macOS virtual key codes (kVK_*). -1 = unknown. */
static int tp_key_code(const char *name) {
    if (!name) return -1;

    if (!strcasecmp(name, "space"))  return 49;
    if (!strcasecmp(name, "up"))     return 126;
    if (!strcasecmp(name, "down"))   return 125;
    if (!strcasecmp(name, "left"))   return 123;
    if (!strcasecmp(name, "right"))  return 124;
    if (!strcasecmp(name, "enter"))  return 36;
    if (!strcasecmp(name, "return")) return 36;
    if (!strcasecmp(name, "esc"))    return 53;
    if (!strcasecmp(name, "escape")) return 53;
    if (!strcasecmp(name, "tab"))    return 48;
    if (!strcasecmp(name, "shift"))  return 56; /* left shift */
    if (!strcasecmp(name, "ctrl"))   return 59; /* left control */
    if (!strcasecmp(name, "alt"))    return 58; /* left option */
    if (!strcasecmp(name, "lclick")) return TP_KEY_MOUSE_BASE + kCGMouseButtonLeft;
    if (!strcasecmp(name, "rclick")) return TP_KEY_MOUSE_BASE + kCGMouseButtonRight;
    if (!strcasecmp(name, "mclick")) return TP_KEY_MOUSE_BASE + kCGMouseButtonCenter;

    if (name[1] == '\0') {
        char c = name[0];
        if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
        if (c >= 'A' && c <= 'Z') {
            static const int letters[26] = {
                0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
                45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6
            };
            return letters[c - 'A'];
        }
        if (c >= '0' && c <= '9') {
            static const int digits[10] = {29, 18, 19, 20, 21, 23, 22, 26, 28, 25};
            return digits[c - '0'];
        }
    }

    if ((name[0] == 'f' || name[0] == 'F') && name[1] != '\0') {
        char *end = NULL;
        long fn = strtol(name + 1, &end, 10);
        if (end && *end == '\0' && fn >= 1 && fn <= 12) {
            static const int fkeys[12] = {
                122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
            };
            return fkeys[fn - 1];
        }
    }

    return -1;
}

static int tp_key_down(int code) {
    if (code < 0) return 0;
    if (code >= TP_KEY_MOUSE_BASE) {
        return CGEventSourceButtonState(
            kCGEventSourceStateCombinedSessionState,
            (CGMouseButton)(code - TP_KEY_MOUSE_BASE)) ? 1 : 0;
    }
    return CGEventSourceKeyState(
        kCGEventSourceStateCombinedSessionState,
        (CGKeyCode)code) ? 1 : 0;
}

/* sys.watch_keys(name, ...) -> array of resolved names. */
static int l_sys_watch_keys(lua_State *L) {
    int n = lua_gettop(L);
    lua_newtable(L);
    int idx = 1;
    for (int i = 1; i <= n; i++) {
        const char *name = lua_tostring(L, i);
        if (!name || tp_key_code(name) < 0) continue; /* unknown names skipped */
        lua_pushstring(L, name);
        lua_rawseti(L, -2, idx++);
    }
    return 1;
}

/* sys.key_pressed(name) -> boolean. Level state; does not touch the edge. */
static int l_sys_key_pressed(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    int code = tp_key_code(name);
    if (code < 0) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, tp_key_down(code));
    return 1;
}

/* sys.key_triggered(name) -> boolean. Rising edge only. */
static int l_sys_key_triggered(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    int code = tp_key_code(name);
    if (code < 0 || code >= TP_KEY_PREV_MAX) {
        lua_pushboolean(L, 0);
        return 1;
    }

    int down = tp_key_down(code);
    int edge = down && !s_key_prev[code];
    s_key_prev[code] = (unsigned char)down;
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
