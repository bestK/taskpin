#include "taskpin_lua.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static lua_State *g_L = NULL;

// MARK: - Span concat metatable

#define SPAN_MT "TaskPin.Span"

static int l_span_concat(lua_State *L) {
    lua_createtable(L, 0, 0);
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_spanlist");
    luaL_getmetatable(L, SPAN_MT); lua_setmetatable(L, -2);
    int result = lua_gettop(L);

    for (int side = 1; side <= 2; side++) {
        if (lua_istable(L, side)) {
            lua_getfield(L, side, "__is_spanlist");
            int is_list = lua_toboolean(L, -1);
            lua_pop(L, 1);
            if (is_list) {
                int len = (int)lua_rawlen(L, side);
                int dlen = (int)lua_rawlen(L, result);
                for (int i = 1; i <= len; i++) {
                    lua_rawgeti(L, side, i);
                    lua_rawseti(L, result, dlen + i);
                }
            } else {
                int dlen = (int)lua_rawlen(L, result);
                lua_pushvalue(L, side);
                lua_rawseti(L, result, dlen + 1);
            }
        } else if (lua_isstring(L, side)) {
            lua_createtable(L, 0, 0);
            lua_pushvalue(L, side); lua_setfield(L, -2, "text");
            lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span");
            int dlen = (int)lua_rawlen(L, result);
            lua_rawseti(L, result, dlen + 1);
        }
    }
    return 1;
}

// MARK: - font(text, color, size, align)

static int l_font(lua_State *L) {
    lua_createtable(L, 0, 0);
    if (lua_isstring(L, 1)) { lua_pushvalue(L, 1); lua_setfield(L, -2, "text"); }
    if (lua_gettop(L) >= 3 && !lua_isnoneornil(L, 2)) { lua_pushvalue(L, 2); lua_setfield(L, -2, "color"); }
    if (lua_gettop(L) >= 4 && !lua_isnoneornil(L, 3)) { lua_pushvalue(L, 3); lua_setfield(L, -2, "size"); }
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span");
    luaL_getmetatable(L, SPAN_MT); lua_setmetatable(L, -2);
    return 1;
}

// MARK: - icon(source, w, h)

static int l_icon(lua_State *L) {
    lua_createtable(L, 0, 0);
    if (lua_isstring(L, 1)) { lua_pushvalue(L, 1); lua_setfield(L, -2, "img_source"); }
    lua_pushinteger(L, lua_gettop(L) >= 2 ? lua_tointeger(L, 2) : 16); lua_setfield(L, -2, "img_w");
    lua_pushinteger(L, lua_gettop(L) >= 3 ? lua_tointeger(L, 3) : 16); lua_setfield(L, -2, "img_h");
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_image");
    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span");
    luaL_getmetatable(L, SPAN_MT); lua_setmetatable(L, -2);
    return 1;
}

// MARK: - dialog(spec)

static int l_dialog(lua_State *L) {
    if (lua_istable(L, 1)) { lua_pushboolean(L, 1); lua_setfield(L, 1, "_dialog"); }
    lua_pushvalue(L, 1);
    return 1;
}

// MARK: - log(...)

static int l_log(lua_State *L) {
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++) {
        size_t len;
        const char *s = luaL_tolstring(L, i, &len);
        if (s) fprintf(stderr, "%s%s", s, i < n ? "\t" : "");
        lua_pop(L, 1);
    }
    fprintf(stderr, "\n");
    return 0;
}

// MARK: - json.decode (minimal)

static void push_json_value(lua_State *L, const char **p);

static void skip_ws(const char **p) { while (**p == ' ' || **p == '\t' || **p == '\n' || **p == '\r') (*p)++; }

static void push_json_string(lua_State *L, const char **p) {
    (*p)++; // skip "
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    while (**p && **p != '"') {
        if (**p == '\\') {
            (*p)++;
            switch (**p) {
                case '"': luaL_addchar(&buf, '"'); break;
                case '\\': luaL_addchar(&buf, '\\'); break;
                case '/': luaL_addchar(&buf, '/'); break;
                case 'n': luaL_addchar(&buf, '\n'); break;
                case 't': luaL_addchar(&buf, '\t'); break;
                case 'r': luaL_addchar(&buf, '\r'); break;
                default: luaL_addchar(&buf, **p); break;
            }
        } else {
            luaL_addchar(&buf, **p);
        }
        (*p)++;
    }
    if (**p == '"') (*p)++;
    luaL_pushresult(&buf);
}

static void push_json_value(lua_State *L, const char **p) {
    skip_ws(p);
    if (**p == '"') {
        push_json_string(L, p);
    } else if (**p == '{') {
        (*p)++;
        lua_createtable(L, 0, 0);
        skip_ws(p);
        if (**p != '}') {
            while (1) {
                skip_ws(p);
                if (**p != '"') break;
                push_json_string(L, p);
                skip_ws(p);
                if (**p == ':') (*p)++;
                push_json_value(L, p);
                lua_settable(L, -3);
                skip_ws(p);
                if (**p == ',') (*p)++; else break;
            }
        }
        if (**p == '}') (*p)++;
    } else if (**p == '[') {
        (*p)++;
        lua_createtable(L, 0, 0);
        int idx = 1;
        skip_ws(p);
        if (**p != ']') {
            while (1) {
                push_json_value(L, p);
                lua_rawseti(L, -2, idx++);
                skip_ws(p);
                if (**p == ',') (*p)++; else break;
            }
        }
        if (**p == ']') (*p)++;
    } else if (strncmp(*p, "true", 4) == 0) {
        lua_pushboolean(L, 1); *p += 4;
    } else if (strncmp(*p, "false", 5) == 0) {
        lua_pushboolean(L, 0); *p += 5;
    } else if (strncmp(*p, "null", 4) == 0) {
        lua_pushnil(L); *p += 4;
    } else {
        char *end;
        double num = strtod(*p, &end);
        lua_pushnumber(L, num);
        *p = end;
    }
}

static int l_json_decode(lua_State *L) {
    const char *str = luaL_checkstring(L, 1);
    const char *start = str;
    skip_ws(&start);
    if (*start != '{' && *start != '[' && *start != '"'
        && strncmp(start, "true", 4) != 0
        && strncmp(start, "false", 5) != 0
        && strncmp(start, "null", 4) != 0
        && (*start < '0' || *start > '9') && *start != '-') {
        lua_pushnil(L);
        return 1;
    }
    push_json_value(L, &str);
    return 1;
}

// MARK: - http.get (using curl)

static int l_http_get(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "curl -sL '%s'", url);
    FILE *fp = popen(cmd, "r");
    if (!fp) { lua_pushnil(L); return 1; }
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    char chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
        luaL_addlstring(&buf, chunk, n);
    }
    pclose(fp);
    luaL_pushresult(&buf);
    return 1;
}

static int l_http_post(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    const char *body = lua_gettop(L) >= 2 ? lua_tostring(L, 2) : NULL;
    const char *headers = lua_gettop(L) >= 3 ? lua_tostring(L, 3) : NULL;
    char cmd[4096];
    if (body && headers) {
        snprintf(cmd, sizeof(cmd), "curl -sL -X POST -H '%s' -d '%s' '%s'", headers, body, url);
    } else if (body) {
        snprintf(cmd, sizeof(cmd), "curl -sL -X POST -d '%s' '%s'", body, url);
    } else {
        snprintf(cmd, sizeof(cmd), "curl -sL -X POST '%s'", url);
    }
    FILE *fp = popen(cmd, "r");
    if (!fp) { lua_pushnil(L); return 1; }
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    char chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
        luaL_addlstring(&buf, chunk, n);
    }
    pclose(fp);
    luaL_pushresult(&buf);
    return 1;
}

static int l_http_put(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    const char *body = lua_gettop(L) >= 2 ? lua_tostring(L, 2) : NULL;
    const char *headers = lua_gettop(L) >= 3 ? lua_tostring(L, 3) : NULL;
    char cmd[4096];
    if (body && headers) {
        snprintf(cmd, sizeof(cmd), "curl -sL -X PUT -H '%s' -d '%s' '%s'", headers, body, url);
    } else if (body) {
        snprintf(cmd, sizeof(cmd), "curl -sL -X PUT -d '%s' '%s'", body, url);
    } else {
        snprintf(cmd, sizeof(cmd), "curl -sL -X PUT '%s'", url);
    }
    FILE *fp = popen(cmd, "r");
    if (!fp) { lua_pushnil(L); return 1; }
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    char chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
        luaL_addlstring(&buf, chunk, n);
    }
    pclose(fp);
    luaL_pushresult(&buf);
    return 1;
}

static int l_http_delete(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "curl -sL -X DELETE '%s'", url);
    FILE *fp = popen(cmd, "r");
    if (!fp) { lua_pushnil(L); return 1; }
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    char chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
        luaL_addlstring(&buf, chunk, n);
    }
    pclose(fp);
    luaL_pushresult(&buf);
    return 1;
}

// MARK: - sys.cpu / sys.memory

#ifdef __APPLE__
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/mount.h>
#include <sys/time.h>
#include <sys/proc.h>
#include <sys/stat.h>
#include <libproc.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <net/if_dl.h>
#include <dirent.h>

static int l_sys_cpu(lua_State *L) {
    // Simplified: return load average * 100 / ncpu
    double load[1];
    getloadavg(load, 1);
    int ncpu = 1;
    size_t sz = sizeof(ncpu);
    sysctlbyname("hw.ncpu", &ncpu, &sz, NULL, 0);
    int pct = (int)(load[0] * 100.0 / ncpu);
    if (pct > 100) pct = 100;
    lua_pushinteger(L, pct);
    return 1;
}

static int l_sys_memory(lua_State *L) {
    int64_t total = 0;
    size_t sz = sizeof(total);
    sysctlbyname("hw.memsize", &total, &sz, NULL, 0);

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count);
    int64_t used = ((int64_t)vm.active_count + vm.wire_count) * vm_page_size;

    lua_createtable(L, 0, 3);
    lua_pushinteger(L, total / (1024*1024)); lua_setfield(L, -2, "total_mb");
    lua_pushinteger(L, used / (1024*1024)); lua_setfield(L, -2, "used_mb");
    lua_pushinteger(L, (int)(used * 100 / total)); lua_setfield(L, -2, "percent");
    return 1;
}

static int l_sys_disk(lua_State *L) {
    struct statfs sf;
    const char *path = lua_gettop(L) >= 1 ? lua_tostring(L, 1) : "/";
    if (statfs(path, &sf) != 0) { lua_pushnil(L); return 1; }
    double total = (double)sf.f_blocks * sf.f_bsize / (1024.0*1024*1024);
    double free_gb = (double)sf.f_bavail * sf.f_bsize / (1024.0*1024*1024);
    lua_createtable(L, 0, 3);
    lua_pushnumber(L, total); lua_setfield(L, -2, "total_gb");
    lua_pushnumber(L, free_gb); lua_setfield(L, -2, "free_gb");
    lua_pushinteger(L, (int)((1.0 - free_gb/total) * 100)); lua_setfield(L, -2, "percent");
    return 1;
}

static int l_sys_uptime(lua_State *L) {
    struct timeval boottime;
    size_t sz = sizeof(boottime);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    sysctl(mib, 2, &boottime, &sz, NULL, 0);
    time_t now; time(&now);
    lua_pushinteger(L, (lua_Integer)(now - boottime.tv_sec));
    return 1;
}

static int l_sys_process_count(lua_State *L) {
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t sz = 0;
    sysctl(mib, 3, NULL, &sz, NULL, 0);
    lua_pushinteger(L, (lua_Integer)(sz / sizeof(struct kinfo_proc)));
    return 1;
}

static uint64_t get_time_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static uint64_t s_prev_recv = 0, s_prev_send = 0;
static uint64_t s_prev_net_time = 0;

static void net_get_totals(uint64_t *recv_out, uint64_t *send_out) {
    *recv_out = 0; *send_out = 0;
    struct ifaddrs *ifap, *ifa;
    if (getifaddrs(&ifap) != 0) return;
    for (ifa = ifap; ifa; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
        if (ifa->ifa_addr->sa_family != AF_LINK) continue;
        if ((ifa->ifa_flags & IFF_UP) == 0) continue;
        if (ifa->ifa_flags & IFF_LOOPBACK) continue;
        struct if_data *ifd = (struct if_data *)ifa->ifa_data;
        if (ifd) {
            *recv_out += ifd->ifi_ibytes;
            *send_out += ifd->ifi_obytes;
        }
    }
    freeifaddrs(ifap);
}

static int l_sys_net_speed(lua_State *L) {
    uint64_t cur_recv, cur_send;
    net_get_totals(&cur_recv, &cur_send);
    uint64_t now = get_time_ms();

    double dl_speed = 0, ul_speed = 0;
    if (s_prev_net_time > 0) {
        uint64_t dt = now - s_prev_net_time;
        if (dt > 0) {
            dl_speed = (double)(cur_recv - s_prev_recv) * 1000.0 / dt;
            ul_speed = (double)(cur_send - s_prev_send) * 1000.0 / dt;
            if (dl_speed < 0) dl_speed = 0;
            if (ul_speed < 0) ul_speed = 0;
        }
    }
    s_prev_recv = cur_recv;
    s_prev_send = cur_send;
    s_prev_net_time = now;

    lua_createtable(L, 0, 2);
    lua_pushnumber(L, dl_speed); lua_setfield(L, -2, "download");
    lua_pushnumber(L, ul_speed); lua_setfield(L, -2, "upload");
    return 1;
}

#define NET_PROC_MAX 128

typedef struct {
    pid_t pid;
    uint64_t io_read;
    uint64_t io_write;
} MacNetProcSnap;

static MacNetProcSnap s_np_prev[NET_PROC_MAX];
static int s_np_prev_count = 0;
static uint64_t s_np_prev_time = 0;

static int l_sys_net_processes(lua_State *L) {
    int buf_size = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (buf_size <= 0) { lua_newtable(L); return 1; }

    pid_t *pids = (pid_t *)malloc(buf_size);
    if (!pids) { lua_newtable(L); return 1; }

    buf_size = proc_listpids(PROC_ALL_PIDS, 0, pids, buf_size);
    int pid_count = buf_size / sizeof(pid_t);

    typedef struct { pid_t pid; char name[256]; int conns; uint64_t io_read; uint64_t io_write; } ProcInfo;
    ProcInfo *procs = (ProcInfo *)calloc(NET_PROC_MAX, sizeof(ProcInfo));
    int proc_count = 0;

    for (int i = 0; i < pid_count && proc_count < NET_PROC_MAX; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        int fds_size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (fds_size <= 0) continue;

        struct proc_fdinfo *fds = (struct proc_fdinfo *)malloc(fds_size);
        if (!fds) continue;

        int actual = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, fds_size);
        int fd_count = actual / sizeof(struct proc_fdinfo);

        int socket_count = 0;
        for (int j = 0; j < fd_count; j++) {
            if (fds[j].proc_fdtype == PROX_FDTYPE_SOCKET) {
                struct socket_fdinfo si;
                int si_size = proc_pidfdinfo(pid, fds[j].proc_fd, PROC_PIDFDSOCKETINFO, &si, sizeof(si));
                if (si_size == sizeof(si)) {
                    if (si.psi.soi_family == AF_INET || si.psi.soi_family == AF_INET6) {
                        if (si.psi.soi_kind == SOCKINFO_TCP &&
                            si.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_ESTABLISHED) {
                            socket_count++;
                        }
                    }
                }
            }
        }
        free(fds);

        if (socket_count > 0) {
            ProcInfo *p = &procs[proc_count];
            p->pid = pid;
            p->conns = socket_count;
            proc_name(pid, p->name, sizeof(p->name));
            if (p->name[0] == '\0') snprintf(p->name, sizeof(p->name), "pid_%d", pid);

            struct rusage_info_v2 rusage;
            if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (void **)&rusage) == 0) {
                p->io_read = rusage.ri_diskio_bytesread;
                p->io_write = rusage.ri_diskio_byteswritten;
            }
            proc_count++;
        }
    }
    free(pids);

    uint64_t now = get_time_ms();
    uint64_t dt = (s_np_prev_time > 0) ? (now - s_np_prev_time) : 0;

    lua_newtable(L);
    for (int i = 0; i < proc_count; i++) {
        double dl_speed = 0, ul_speed = 0;
        if (dt > 0) {
            for (int j = 0; j < s_np_prev_count; j++) {
                if (s_np_prev[j].pid == procs[i].pid) {
                    dl_speed = (double)(procs[i].io_read - s_np_prev[j].io_read) * 1000.0 / dt;
                    ul_speed = (double)(procs[i].io_write - s_np_prev[j].io_write) * 1000.0 / dt;
                    if (dl_speed < 0) dl_speed = 0;
                    if (ul_speed < 0) ul_speed = 0;
                    break;
                }
            }
        }

        lua_newtable(L);
        lua_pushinteger(L, procs[i].pid); lua_setfield(L, -2, "pid");
        lua_pushstring(L, procs[i].name); lua_setfield(L, -2, "name");
        lua_pushinteger(L, procs[i].conns); lua_setfield(L, -2, "connections");
        lua_pushnumber(L, dl_speed); lua_setfield(L, -2, "download");
        lua_pushnumber(L, ul_speed); lua_setfield(L, -2, "upload");
        lua_rawseti(L, -2, i + 1);
    }

    for (int i = 0; i < proc_count && i < NET_PROC_MAX; i++) {
        s_np_prev[i].pid = procs[i].pid;
        s_np_prev[i].io_read = procs[i].io_read;
        s_np_prev[i].io_write = procs[i].io_write;
    }
    s_np_prev_count = proc_count < NET_PROC_MAX ? proc_count : NET_PROC_MAX;
    s_np_prev_time = now;

    free(procs);
    return 1;
}

static int l_sys_battery(lua_State *L) {
    lua_createtable(L, 0, 3);
    lua_pushinteger(L, -1); lua_setfield(L, -2, "percent");
    lua_pushboolean(L, 0); lua_setfield(L, -2, "charging");
    lua_pushinteger(L, -1); lua_setfield(L, -2, "seconds_left");
    return 1;
}

static int l_sys_net(lua_State *L) {
    struct ifaddrs *ifap, *ifa;
    if (getifaddrs(&ifap) != 0) { lua_pushnil(L); return 1; }

    uint64_t recv_total = 0, send_total = 0;
    for (ifa = ifap; ifa; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
        if (ifa->ifa_addr->sa_family != AF_LINK) continue;
        if ((ifa->ifa_flags & IFF_UP) == 0) continue;
        if (ifa->ifa_flags & IFF_LOOPBACK) continue;

        struct if_data *ifd = (struct if_data *)ifa->ifa_data;
        if (ifd) {
            recv_total += ifd->ifi_ibytes;
            send_total += ifd->ifi_obytes;
        }
    }
    freeifaddrs(ifap);

    lua_createtable(L, 0, 2);
    lua_pushnumber(L, (double)recv_total); lua_setfield(L, -2, "recv_bytes");
    lua_pushnumber(L, (double)send_total); lua_setfield(L, -2, "send_bytes");
    return 1;
}

static int l_sys_file_mtime(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    struct stat st;
    if (stat(path, &st) != 0) { lua_pushnil(L); return 1; }
    lua_pushinteger(L, (lua_Integer)st.st_mtime);
    return 1;
}

static time_t s_newest_mtime;
static char s_newest_path[1024];

static void find_newest_recurse(const char *dir, const char *ext) {
    DIR *d = opendir(dir);
    if (!d) return;

    struct dirent *entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.') continue;

        char full[1024];
        snprintf(full, sizeof(full), "%s/%s", dir, entry->d_name);

        struct stat st;
        if (stat(full, &st) != 0) continue;

        if (S_ISDIR(st.st_mode)) {
            find_newest_recurse(full, ext);
        } else {
            const char *dot = strrchr(entry->d_name, '.');
            if (dot && strcasecmp(dot, ext) == 0) {
                if (st.st_mtime > s_newest_mtime) {
                    s_newest_mtime = st.st_mtime;
                    snprintf(s_newest_path, sizeof(s_newest_path), "%s", full);
                }
            }
        }
    }
    closedir(d);
}

static int l_sys_find_newest(lua_State *L) {
    const char *dir = luaL_checkstring(L, 1);
    const char *ext = luaL_checkstring(L, 2);

    s_newest_mtime = 0;
    s_newest_path[0] = '\0';

    find_newest_recurse(dir, ext);

    if (s_newest_path[0]) {
        lua_pushstring(L, s_newest_path);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

static int l_sys_read_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    FILE *f = fopen(path, "rb");
    if (!f) { lua_pushnil(L); return 1; }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size <= 0) { fclose(f); lua_pushstring(L, ""); return 1; }

    char *buf = (char *)malloc(size + 1);
    if (!buf) { fclose(f); lua_pushnil(L); return 1; }

    size_t read_bytes = fread(buf, 1, size, f);
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

#endif

// MARK: - Init / Execute

void tp_lua_init(void) {
    if (g_L) return;
    g_L = luaL_newstate();
    luaL_openlibs(g_L);

    // Span metatable
    luaL_newmetatable(g_L, SPAN_MT);
    lua_pushcfunction(g_L, l_span_concat); lua_setfield(g_L, -2, "__concat");
    lua_pop(g_L, 1);

    // Globals
    lua_pushcfunction(g_L, l_font); lua_setglobal(g_L, "font");
    lua_pushcfunction(g_L, l_icon); lua_setglobal(g_L, "icon");
    lua_pushcfunction(g_L, l_dialog); lua_setglobal(g_L, "dialog");
    lua_pushcfunction(g_L, l_log); lua_setglobal(g_L, "log");

    // json
    lua_createtable(g_L, 0, 0);
    lua_pushcfunction(g_L, l_json_decode); lua_setfield(g_L, -2, "decode");
    lua_setglobal(g_L, "json");

    // http
    lua_createtable(g_L, 0, 0);
    lua_pushcfunction(g_L, l_http_get); lua_setfield(g_L, -2, "get");
    lua_pushcfunction(g_L, l_http_post); lua_setfield(g_L, -2, "post");
    lua_pushcfunction(g_L, l_http_put); lua_setfield(g_L, -2, "put");
    lua_pushcfunction(g_L, l_http_delete); lua_setfield(g_L, -2, "delete");
    lua_setglobal(g_L, "http");

    // sys
    lua_createtable(g_L, 0, 0);
#ifdef __APPLE__
    lua_pushcfunction(g_L, l_sys_cpu); lua_setfield(g_L, -2, "cpu");
    lua_pushcfunction(g_L, l_sys_memory); lua_setfield(g_L, -2, "memory");
    lua_pushcfunction(g_L, l_sys_disk); lua_setfield(g_L, -2, "disk");
    lua_pushcfunction(g_L, l_sys_uptime); lua_setfield(g_L, -2, "uptime");
    lua_pushcfunction(g_L, l_sys_process_count); lua_setfield(g_L, -2, "process_count");
    lua_pushcfunction(g_L, l_sys_net_speed); lua_setfield(g_L, -2, "net_speed");
    lua_pushcfunction(g_L, l_sys_battery); lua_setfield(g_L, -2, "battery");
    lua_pushcfunction(g_L, l_sys_net_processes); lua_setfield(g_L, -2, "net_processes");
    lua_pushcfunction(g_L, l_sys_net); lua_setfield(g_L, -2, "net");
    lua_pushcfunction(g_L, l_sys_file_mtime); lua_setfield(g_L, -2, "file_mtime");
    lua_pushcfunction(g_L, l_sys_find_newest); lua_setfield(g_L, -2, "find_newest");
    lua_pushcfunction(g_L, l_sys_read_file); lua_setfield(g_L, -2, "read_file");
#endif
    lua_setglobal(g_L, "sys");
}

void tp_lua_shutdown(void) {
    if (g_L) { lua_close(g_L); g_L = NULL; }
}

int tp_lua_execute(const char *filepath, const char *args_json) {
    if (!g_L || !filepath) return -1;

    // Inject args
    lua_createtable(g_L, 0, 0);
    if (args_json && args_json[0]) {
        const char *p = args_json;
        push_json_value(g_L, &p);
        if (lua_istable(g_L, -1)) {
            lua_remove(g_L, -2); // remove empty table
        } else {
            lua_pop(g_L, 1);
        }
    }
    lua_setglobal(g_L, "args");

    if (luaL_loadfile(g_L, filepath) != LUA_OK || lua_pcall(g_L, 0, LUA_MULTRET, 0) != LUA_OK) {
        fprintf(stderr, "[TaskPin] %s\n", lua_tostring(g_L, -1));
        lua_settop(g_L, 0);
        return -1;
    }
    return lua_gettop(g_L);
}

const char *tp_lua_get_error(void) {
    if (!g_L) return NULL;
    if (lua_isstring(g_L, -1)) return lua_tostring(g_L, -1);
    return NULL;
}

int tp_lua_get_nresults(void) {
    return g_L ? lua_gettop(g_L) : 0;
}

void tp_lua_clear_stack(void) {
    if (g_L) lua_settop(g_L, 0);
}

// MARK: - Result extraction

int tp_lua_is_span(int idx) {
    if (!g_L || !lua_istable(g_L, idx)) return 0;
    lua_getfield(g_L, idx, "__is_span");
    int r = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    if (r) return 1;
    lua_getfield(g_L, idx, "__is_spanlist");
    r = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    return r;
}

int tp_lua_is_dialog(int idx) {
    if (!g_L || !lua_istable(g_L, idx)) return 0;
    lua_getfield(g_L, idx, "_dialog");
    int r = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    return r;
}

int tp_lua_get_bool(int idx) {
    return g_L ? lua_toboolean(g_L, idx) : 0;
}

const char *tp_lua_get_string(int idx) {
    return (g_L && lua_isstring(g_L, idx)) ? lua_tostring(g_L, idx) : NULL;
}

int tp_lua_span_count(int idx) {
    if (!g_L || !lua_istable(g_L, idx)) return 0;
    lua_getfield(g_L, idx, "__is_spanlist");
    int is_list = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);
    if (is_list) return (int)lua_rawlen(g_L, idx);
    return 1;
}

TPSpan tp_lua_get_span(int list_idx, int span_idx) {
    TPSpan span = {0};
    if (!g_L) return span;

    int target;
    lua_getfield(g_L, list_idx, "__is_spanlist");
    int is_list = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    if (is_list) {
        lua_rawgeti(g_L, list_idx, span_idx + 1);
        target = lua_gettop(g_L);
    } else {
        target = list_idx;
    }

    lua_getfield(g_L, target, "__is_image");
    span.is_image = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    if (span.is_image) {
        lua_getfield(g_L, target, "img_source");
        if (lua_isstring(g_L, -1)) { strncpy(span.text, lua_tostring(g_L, -1), 511); span.text[511] = '\0'; }
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "img_w");
        span.img_w = lua_isnil(g_L, -1) ? 16 : (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "img_h");
        span.img_h = lua_isnil(g_L, -1) ? 16 : (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);
    } else {
        lua_getfield(g_L, target, "text");
        if (lua_isstring(g_L, -1)) { strncpy(span.text, lua_tostring(g_L, -1), 511); span.text[511] = '\0'; }
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "color");
        if (lua_isstring(g_L, -1)) { strncpy(span.color, lua_tostring(g_L, -1), 15); span.color[15] = '\0'; }
        lua_pop(g_L, 1);
        lua_getfield(g_L, target, "size");
        span.font_size = lua_isnil(g_L, -1) ? 0 : (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);
    }

    if (is_list) lua_pop(g_L, 1);
    return span;
}

// MARK: - Dialog extraction

TPDialogSpec tp_lua_get_dialog(int idx) {
    TPDialogSpec spec = {0};
    if (!g_L || !lua_istable(g_L, idx)) return spec;

    spec.width = 400; spec.height = 300; spec.opacity = 255;

    lua_getfield(g_L, idx, "title");
    if (lua_isstring(g_L, -1)) strncpy(spec.title, lua_tostring(g_L, -1), 127);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "width");
    if (!lua_isnil(g_L, -1)) spec.width = (int)lua_tointeger(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "height");
    if (!lua_isnil(g_L, -1)) spec.height = (int)lua_tointeger(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "refresh");
    if (!lua_isnil(g_L, -1)) spec.refresh = (int)lua_tointeger(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "borderless");
    spec.borderless = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "clickthrough");
    spec.clickthrough = lua_toboolean(g_L, -1);
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "opacity");
    if (!lua_isnil(g_L, -1)) spec.opacity = (int)lua_tointeger(g_L, -1);
    else spec.opacity = 255;
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "bg_color");
    if (lua_isstring(g_L, -1)) { strncpy(spec.bg_color, lua_tostring(g_L, -1), 15); spec.bg_color[15] = '\0'; }
    lua_pop(g_L, 1);

    lua_getfield(g_L, idx, "content");
    if (!lua_istable(g_L, -1)) { lua_pop(g_L, 1); return spec; }

    int content_idx = lua_gettop(g_L);
    int n = (int)lua_rawlen(g_L, content_idx);
    if (n > 8) n = 8;

    for (int i = 1; i <= n; i++) {
        lua_rawgeti(g_L, content_idx, i);
        if (!lua_istable(g_L, -1)) { lua_pop(g_L, 1); continue; }

        TPDialogItem *item = &spec.items[spec.item_count];
        memset(item, 0, sizeof(TPDialogItem));

        lua_getfield(g_L, -1, "type");
        if (lua_isstring(g_L, -1)) strncpy(item->type, lua_tostring(g_L, -1), 15);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "value");
        if (lua_isstring(g_L, -1)) strncpy(item->value, lua_tostring(g_L, -1), 255);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "color");
        if (lua_isstring(g_L, -1)) strncpy(item->color, lua_tostring(g_L, -1), 15);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "size");
        if (!lua_isnil(g_L, -1)) item->font_size = (int)lua_tointeger(g_L, -1);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "bold");
        item->bold = lua_toboolean(g_L, -1);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "image");
        if (lua_isstring(g_L, -1)) strncpy(item->image, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "image_width");
        if (!lua_isnil(g_L, -1)) item->image_width = (int)lua_tointeger(g_L, -1);
        else item->image_width = 16;
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "image_height");
        if (!lua_isnil(g_L, -1)) item->image_height = (int)lua_tointeger(g_L, -1);
        else item->image_height = 16;
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "url");
        if (lua_isstring(g_L, -1)) strncpy(item->url, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);

        lua_getfield(g_L, -1, "cmd");
        if (lua_isstring(g_L, -1)) strncpy(item->cmd, lua_tostring(g_L, -1), 511);
        lua_pop(g_L, 1);

        // Parse table columns/rows
        if (strcmp(item->type, "table") == 0) {
            lua_getfield(g_L, -1, "columns");
            if (lua_istable(g_L, -1)) {
                int nc = (int)lua_rawlen(g_L, -1);
                if (nc > 6) nc = 6;
                item->col_count = nc;
                for (int c = 1; c <= nc; c++) {
                    lua_rawgeti(g_L, -1, c);
                    if (lua_isstring(g_L, -1)) strncpy(item->columns[c-1], lua_tostring(g_L, -1), 63);
                    lua_pop(g_L, 1);
                }
            }
            lua_pop(g_L, 1);

            lua_getfield(g_L, -1, "rows");
            if (lua_istable(g_L, -1)) {
                int nr = (int)lua_rawlen(g_L, -1);
                if (nr > 24) nr = 24;
                item->row_count = nr;
                for (int r = 1; r <= nr; r++) {
                    lua_rawgeti(g_L, -1, r);
                    if (lua_istable(g_L, -1)) {
                        int rc = (int)lua_rawlen(g_L, -1);
                        if (rc > item->col_count) rc = item->col_count;
                        for (int c = 1; c <= rc; c++) {
                            lua_rawgeti(g_L, -1, c);
                            if (lua_isstring(g_L, -1)) strncpy(item->cells[r-1][c-1], lua_tostring(g_L, -1), 63);
                            lua_pop(g_L, 1);
                        }
                        lua_getfield(g_L, -1, "url");
                        if (lua_isstring(g_L, -1)) strncpy(item->row_urls[r-1], lua_tostring(g_L, -1), 255);
                        lua_pop(g_L, 1);
                    }
                    lua_pop(g_L, 1);
                }
            }
            lua_pop(g_L, 1);
        }

        spec.item_count++;
        lua_pop(g_L, 1);
    }
    lua_pop(g_L, 1); // content table
    return spec;
}

void tp_lua_get_dialog_into(int idx, TPDialogSpec *out) {
    if (!out) return;
    *out = tp_lua_get_dialog(idx);
}
