/*
 * tp_engine.c — engine lifecycle, execution entry points, the instruction
 * watchdog, the log sink, and @param/@refresh header parsing.
 *
 * The header parsing lives here so that it exists once instead of being
 * duplicated between lib/scripting.c (Windows) and the hand-rolled Swift
 * copy in src/macos/Views/ItemEditView.swift.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define TASKPIN_ENGINE_INTERNAL
#include "taskpin_engine.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* ─── watchdog ─── */

/* Instruction budget per execution. 50M is the figure the rewrite plan
 * calls for: comfortably more than any real TaskPin script (they are a few
 * hundred instructions of string formatting around one sysinfo call), and
 * small enough that `while true do end` aborts in well under a second. */
#define TP_DEFAULT_INSTRUCTION_BUDGET 50000000LL

/* The hook fires every N instructions; each firing is one counter update.
 * A larger step means less overhead per execution; too large and the
 * overshoot past the budget grows. 100k keeps overshoot negligible. */
#define TP_HOOK_STEP 100000LL

static void tp_watchdog_hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    /* lua_getextraspace() returns the ADDRESS of the per-state extra space;
     * the engine pointer is stored *inside* it (see tp_engine_create). Cast
     * the address itself and you get a pointer to the raw extra-space bytes,
     * and writing through it corrupts the lua_State. */
    TPEngine *e = *(TPEngine **)lua_getextraspace(L);
    if (!e || e->budget <= 0) return;

    e->used += e->hook_step;
    if (e->used > e->budget) {
        /* Raised as a normal Lua error so it unwinds through pcall and the
         * engine's error path, rather than longjmp'ing out of the host.
         *
         * Deliberately lua_error() with a literal rather than luaL_error():
         * luaL_error runs luaL_where + lua_pushfstring, i.e. debug-info
         * lookup and stack manipulation from inside a count hook, which is
         * a lot of machinery for a hot abort path. A literal costs one
         * interned string and no allocation. */
        lua_pushliteral(L, "instruction budget exceeded; "
                           "script aborted by watchdog");
        lua_error(L);
    }
}

static void tp_arm_watchdog(TPEngine *e) {
    if (e->budget > 0) {
        e->used = 0;
        /* The hook fires every hook_step instructions, so the overshoot past
         * the budget is at most one step. Clamp the step down for small
         * budgets, otherwise a budget below the step would never trip. */
        e->hook_step = TP_HOOK_STEP;
        if (e->budget < e->hook_step) e->hook_step = e->budget;
        if (e->hook_step < 1) e->hook_step = 1;
        lua_sethook(e->L, tp_watchdog_hook, LUA_MASKCOUNT, (int)e->hook_step);
    } else {
        lua_sethook(e->L, NULL, 0, 0);
    }
}

static void tp_disarm_watchdog(TPEngine *e) {
    lua_sethook(e->L, NULL, 0, 0);
}

/* ─── log sink ─── */

#define TP_LOG_PATH "taskpin.log"
#define TP_LOG_ROTATE_BYTES 65536

/* Default sink: append to taskpin.log in the CWD, rotating at 64 KB.
 * lib/scripting.c writes next to the module instead, which needs Win32;
 * keeping it in the CWD is the platform-neutral equivalent and the host can
 * redirect it with tp_set_log_callback. */
static void tp_default_log(int level, const char *msg, void *user) {
    (void)level;
    (void)user;
    if (!msg) return;

    FILE *probe = fopen(TP_LOG_PATH, "rb");
    if (probe) {
        fseek(probe, 0, SEEK_END);
        long size = ftell(probe);
        fclose(probe);
        if (size > TP_LOG_ROTATE_BYTES) remove(TP_LOG_PATH);
    }

    FILE *f = fopen(TP_LOG_PATH, "a");
    if (!f) return;

    /* Timestamp: local time, same shape as script_log_write. */
    time_t now = time(NULL);
    struct tm *lt = localtime(&now);
    if (lt) {
        fprintf(f, "[%04d-%02d-%02d %02d:%02d:%02d] %s\n",
                lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday,
                lt->tm_hour, lt->tm_min, lt->tm_sec, msg);
    } else {
        fprintf(f, "%s\n", msg);
    }
    fclose(f);
}

void tp_engine_log(TPEngine *e, const char *utf8_msg) {
    if (!utf8_msg) return;
    if (e && e->log_cb) e->log_cb(0, utf8_msg, e->log_user);
    else tp_default_log(0, utf8_msg, NULL);
}

/* ─── lifecycle ─── */

TPEngine *tp_engine_create(void) {
    TPEngine *e = (TPEngine *)calloc(1, sizeof(TPEngine));
    if (!e) return NULL;

    e->budget = TP_DEFAULT_INSTRUCTION_BUDGET;
    e->hook_step = TP_HOOK_STEP;

    e->L = luaL_newstate();
    if (!e->L) {
        free(e);
        return NULL;
    }

    /* The watchdog hook finds its engine through the state's extra space,
     * so this must happen before any execution. */
    *(TPEngine **)lua_getextraspace(e->L) = e;

    luaL_openlibs(e->L);
    tp_lua_register_api(e);

    return e;
}

void tp_engine_destroy(TPEngine *e) {
    if (!e) return;
    if (e->L) {
        lua_settop(e->L, 0);
        lua_close(e->L);
        e->L = NULL;
    }
    free(e);
}

void tp_set_log_callback(TPEngine *e, TPLogFn cb, void *user) {
    if (!e) return;
    e->log_cb = cb;
    e->log_user = user;
}

void tp_engine_set_instruction_budget(TPEngine *e, long long instructions) {
    if (!e) return;
    e->budget = instructions;
}

/* ─── execution ─── */

static void result_init(TPScriptResult *out) {
    memset(out, 0, sizeof(*out));
    out->click_action = TP_CLICK_URL;
    out->dialog.opacity = 255;
}

int tp_execute_file(TPEngine *e, const char *utf8_path,
                    const char *args_json, TPScriptResult *out) {
    if (!out) return 0;
    result_init(out);

    if (!e || !utf8_path || !utf8_path[0]) {
        strncpy(out->error, "invalid engine or path", sizeof(out->error) - 1);
        out->ok = 0;
        return 0;
    }

    FILE *f = fopen(utf8_path, "rb");
    if (!f) {
        snprintf(out->error, sizeof(out->error), "cannot open script: %s", utf8_path);
        out->ok = 0;
        return 0;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0) {
        fclose(f);
        snprintf(out->error, sizeof(out->error), "cannot size script: %s", utf8_path);
        out->ok = 0;
        return 0;
    }

    char *src = (char *)malloc((size_t)size + 1);
    if (!src) {
        fclose(f);
        snprintf(out->error, sizeof(out->error), "out of memory reading: %s", utf8_path);
        out->ok = 0;
        return 0;
    }

    size_t got = fread(src, 1, (size_t)size, f);
    fclose(f);
    src[got] = '\0';

    /* Skip a UTF-8 BOM so the first line's "-- @param" is still a comment. */
    char *start = src;
    if (got >= 3 && (unsigned char)src[0] == 0xEF &&
        (unsigned char)src[1] == 0xBB && (unsigned char)src[2] == 0xBF) {
        start = src + 3;
        got -= 3;
    }

    /* "@name" tells Lua the chunk name is not a file path, so error
     * messages read `@script.lua:12:` like the reference engine. */
    char chunkname[512];
    snprintf(chunkname, sizeof(chunkname), "@%s", utf8_path);

    tp_arm_watchdog(e);
    int rc = tp_lua_run_source(e, start, got, chunkname, args_json, out);
    tp_disarm_watchdog(e);

    free(src);
    return rc;
}

int tp_execute_template(TPEngine *e, const char *lua_code,
                        const char *response_raw, TPScriptResult *out) {
    if (!out) return 0;
    result_init(out);

    if (!e || !lua_code) {
        strncpy(out->error, "invalid engine or code", sizeof(out->error) - 1);
        out->ok = 0;
        return 0;
    }

    tp_arm_watchdog(e);
    int rc = tp_lua_run_template(e, lua_code, response_raw, out);
    tp_disarm_watchdog(e);
    return rc;
}

/* ─── @param / @refresh ─── */

/*
 * Header grammar, preserved from lib/scripting.c:
 *
 *   - leading spaces/tabs are skipped; scanning stops at the first line that
 *     is not a "--" comment
 *   - "@param <key> <type> <label...>"  (label is the rest of the line)
 *   - "@refresh <ms>"                   (atoi, first match wins)
 *   - key is dropped when empty or >= 64 bytes; type is truncated to 15
 *   - label is truncated to 127 and has trailing CR/LF stripped
 *
 * The reference implementation fgets()s into a 512-byte buffer, so a longer
 * line is split; we read a line at a time with the same 512-byte ceiling to
 * keep the results identical.
 */
#define TP_HDR_LINE 512

static int header_next_line(FILE *f, char *line, int cap) {
    if (!fgets(line, cap, f)) return 0;
    return 1;
}

int tp_parse_params(const char *utf8_path, TPParamDecl *out, int max_decls) {
    if (!utf8_path || !utf8_path[0] || !out || max_decls <= 0) return 0;

    FILE *f = fopen(utf8_path, "r");
    if (!f) return 0;

    int count = 0;
    char line[TP_HDR_LINE];

    while (count < max_decls && header_next_line(f, line, sizeof(line))) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@param", 6) != 0) continue;
        p += 6;
        while (*p == ' ') p++;

        /* key */
        char *start = p;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
        int klen = (int)(p - start);
        if (klen <= 0 || klen >= 64) continue;
        memcpy(out[count].key, start, (size_t)klen);
        out[count].key[klen] = '\0';

        /* type */
        while (*p == ' ' || *p == '\t') p++;
        start = p;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
        int tlen = (int)(p - start);
        if (tlen >= 16) tlen = 15;
        memcpy(out[count].type, start, (size_t)tlen);
        out[count].type[tlen] = '\0';

        /* label = rest of the line */
        while (*p == ' ' || *p == '\t') p++;
        start = p;
        int llen = (int)strlen(start);
        while (llen > 0 && (start[llen - 1] == '\n' || start[llen - 1] == '\r')) llen--;
        if (llen >= 128) llen = 127;
        memcpy(out[count].label, start, (size_t)llen);
        out[count].label[llen] = '\0';

        count++;
    }

    fclose(f);
    return count;
}

int tp_parse_refresh(const char *utf8_path) {
    if (!utf8_path || !utf8_path[0]) return 0;

    FILE *f = fopen(utf8_path, "r");
    if (!f) return 0;

    char line[TP_HDR_LINE];
    int result = 0;

    while (header_next_line(f, line, sizeof(line))) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (p[0] != '-' || p[1] != '-') break;
        p += 2;
        while (*p == ' ') p++;
        if (strncmp(p, "@refresh", 8) != 0) continue;
        p += 8;
        while (*p == ' ' || *p == '\t') p++;
        result = atoi(p);
        break;
    }

    fclose(f);
    return result;
}
