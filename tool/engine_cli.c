/*
 * engine_cli.c — run a TaskPin Lua script and dump the TPScriptResult as JSON.
 *
 * This is the Phase 2 acceptance harness from docs/FLUTTER_REWRITE_PLAN.md:
 * it exercises the engine without Flutter or MSVC, and its output is what
 * test/engine/golden/*.json will be compared against.
 *
 * Usage:
 *   engine_cli <script.lua> [args_json]
 *   engine_cli --code "<lua>" [--response "<raw>"]     (template mode)
 *
 * Options:
 *   --budget <N>   instruction budget; 0 disables the watchdog
 *   --no-header    skip @param / @refresh parsing
 *   --quiet        do not echo the script path / timing
 *
 * args_json is either a literal JSON object (starts with '{' or '[') or the
 * path to a file containing one.
 *
 * Field names in the output mirror the ABI structs one-for-one, so a golden
 * file can be diffed against the struct without a translation layer.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "taskpin_engine.h"

#if defined(_WIN32)
#include <windows.h>
static long long tp_now_ms(void) { return (long long)GetTickCount64(); }
#else
static long long tp_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
#endif

/* ─── minimal JSON writer ─── */

static void json_string(FILE *f, const char *s) {
    fputc('"', f);
    if (s) {
        for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
            switch (*p) {
            case '"':  fputs("\\\"", f); break;
            case '\\': fputs("\\\\", f); break;
            case '\n': fputs("\\n", f);  break;
            case '\r': fputs("\\r", f);  break;
            case '\t': fputs("\\t", f);  break;
            case '\b': fputs("\\b", f);  break;
            case '\f': fputs("\\f", f);  break;
            default:
                if (*p < 0x20) fprintf(f, "\\u%04x", *p);
                else fputc(*p, f);
            }
        }
    }
    fputc('"', f);
}

static void json_kv_str(FILE *f, const char *k, const char *v, int comma) {
    fputs("  ", f);
    json_string(f, k);
    fputs(": ", f);
    json_string(f, v);
    fputs(comma ? ",\n" : "\n", f);
}

static void json_kv_int(FILE *f, const char *k, long long v, int comma) {
    fprintf(f, "  \"%s\": %lld%s\n", k, v, comma ? "," : "");
}

/* ─── output ─── */

static void print_span(FILE *f, const TPSpan *s) {
    fputs("    {\n", f);
    fprintf(f, "      \"text\": ");      json_string(f, s->text);   fputs(",\n", f);
    fprintf(f, "      \"color\": ");     json_string(f, s->color);  fputs(",\n", f);
    fprintf(f, "      \"font_size\": %d,\n", s->font_size);
    fprintf(f, "      \"align\": %d,\n", s->align);
    fprintf(f, "      \"newline\": %d,\n", s->newline);
    fprintf(f, "      \"is_image\": %d,\n", s->is_image);
    fprintf(f, "      \"img_w\": %d,\n", s->img_w);
    fprintf(f, "      \"img_h\": %d\n", s->img_h);
    fputs("    }", f);
}

static void print_dialog_item(FILE *f, const TPDialogItem *it) {
    fputs("    {\n", f);
    fprintf(f, "      \"type\": ");   json_string(f, it->type);   fputs(",\n", f);
    fprintf(f, "      \"value\": ");  json_string(f, it->value);  fputs(",\n", f);
    fprintf(f, "      \"color\": ");  json_string(f, it->color);  fputs(",\n", f);
    fprintf(f, "      \"font_size\": %d,\n", it->font_size);
    fprintf(f, "      \"bold\": %d,\n", it->bold);
    fprintf(f, "      \"image\": ");  json_string(f, it->image);  fputs(",\n", f);
    fprintf(f, "      \"image_width\": %d,\n", it->image_width);
    fprintf(f, "      \"image_height\": %d,\n", it->image_height);
    fprintf(f, "      \"url\": ");    json_string(f, it->url);    fputs(",\n", f);
    fprintf(f, "      \"cmd\": ");    json_string(f, it->cmd);    fputs(",\n", f);
    fprintf(f, "      \"bg\": ");     json_string(f, it->bg);     fputs(",\n", f);
    /* webview item (type == "webview"); url is the field above. */
    fprintf(f, "      \"web_w\": %d,\n", it->web_w);
    fprintf(f, "      \"web_h\": %d,\n", it->web_h);
    fprintf(f, "      \"col_count\": %d,\n", it->col_count);
    fprintf(f, "      \"row_count\": %d,\n", it->row_count);

    fprintf(f, "      \"columns\": [");
    for (int c = 0; c < it->col_count; c++) {
        if (c) fputs(", ", f);
        json_string(f, it->columns[c]);
    }
    fputs("],\n", f);

    fputs("      \"rows\": [", f);
    for (int r = 0; r < it->row_count; r++) {
        fputs(r ? ", [" : "[", f);
        for (int c = 0; c < it->col_count; c++) {
            if (c) fputs(", ", f);
            json_string(f, it->cells[r][c]);
        }
        fputs("]", f);
    }
    fputs("],\n", f);

    fputs("      \"row_urls\": [", f);
    for (int r = 0; r < it->row_count; r++) {
        if (r) fputs(", ", f);
        json_string(f, it->row_urls[r]);
    }
    fputs("],\n", f);

    fputs("      \"row_cmds\": [", f);
    for (int r = 0; r < it->row_count; r++) {
        if (r) fputs(", ", f);
        json_string(f, it->row_cmds[r]);
    }
    fputs("]\n", f);

    fputs("    }", f);
}

/* Emit a comma-separated JSON array of N items on one logical block. */
static void print_array_start(FILE *f, const char *key) {
    fprintf(f, "  \"%s\": [", key);
}

static void print_array_item_sep(FILE *f, int i) {
    fputs(i ? ",\n" : "\n", f);
}

static void print_array_end(FILE *f, int count, int comma) {
    fputs(count ? "\n  ]" : "]", f);
    fputs(comma ? ",\n" : "\n", f);
}

static void print_result(FILE *f, const char *path, const TPScriptResult *r,
                         long long elapsed_ms, int refresh_ms,
                         const TPParamDecl *decls, int ndecls) {
    fputs("{\n", f);

    fprintf(f, "  \"script\": ");  json_string(f, path);  fputs(",\n", f);
    json_kv_int(f, "ok", r->ok, 1);
    json_kv_str(f, "error", r->error, 1);
    json_kv_int(f, "elapsed_ms", elapsed_ms, 1);
    json_kv_int(f, "refresh_ms", refresh_ms, 1);

    fputs("  \"params\": [", f);
    for (int i = 0; i < ndecls; i++) {
        print_array_item_sep(f, i);
        fputs("    { \"key\": ", f);   json_string(f, decls[i].key);
        fputs(", \"type\": ", f);      json_string(f, decls[i].type);
        fputs(", \"label\": ", f);     json_string(f, decls[i].label);
        fputs(" }", f);
    }
    print_array_end(f, ndecls, 1);

    json_kv_int(f, "clickable", r->clickable, 1);
    json_kv_int(f, "click_action", r->click_action, 1);
    json_kv_str(f, "click_url", r->click_url, 1);
    json_kv_str(f, "display", r->display, 1);

    fprintf(f, "  \"span_count\": %d,\n", r->rich.count);
    print_array_start(f, "spans");
    for (int i = 0; i < r->rich.count; i++) {
        print_array_item_sep(f, i);
        print_span(f, &r->rich.spans[i]);
    }
    print_array_end(f, r->rich.count, 1);

    /* Always emitted, even when click_action != TP_CLICK_DIALOG, so goldens
     * can compare dialog.items[] unconditionally. */
    fputs("  \"dialog\": {\n", f);
    fprintf(f, "    \"title\": ");       json_string(f, r->dialog.title);      fputs(",\n", f);
    fprintf(f, "    \"width\": %d,\n",   r->dialog.width);
    fprintf(f, "    \"height\": %d,\n",  r->dialog.height);
    fprintf(f, "    \"refresh\": %d,\n", r->dialog.refresh);
    fprintf(f, "    \"borderless\": %d,\n", r->dialog.borderless);
    fprintf(f, "    \"clickthrough\": %d,\n", r->dialog.clickthrough);
    fprintf(f, "    \"opacity\": %d,\n", r->dialog.opacity);
    fprintf(f, "    \"bg_color\": ");    json_string(f, r->dialog.bg_color);   fputs(",\n", f);
    fprintf(f, "    \"transparent_bg\": %d,\n", r->dialog.transparent_bg);
    fprintf(f, "    \"item_count\": %d,\n", r->dialog.item_count);
    fputs("    \"items\": [", f);
    for (int i = 0; i < r->dialog.item_count; i++) {
        print_array_item_sep(f, i);
        print_dialog_item(f, &r->dialog.items[i]);
    }
    fputs(r->dialog.item_count ? "\n    ]\n" : "]\n", f);
    fputs("  }\n", f);

    fputs("}\n", f);
}

/* ─── args ─── */

static char *read_file(const char *path, long *out_size) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0) { fclose(f); return NULL; }
    char *buf = (char *)malloc((size_t)size + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)size, f);
    fclose(f);
    buf[got] = '\0';
    if (out_size) *out_size = (long)got;
    return buf;
}

/* Resolve the optional args argument: literal JSON, a path, or NULL. */
static char *resolve_args(const char *arg) {
    if (!arg || !arg[0]) return NULL;
    if (arg[0] == '{' || arg[0] == '[') {
        char *copy = (char *)malloc(strlen(arg) + 1);
        if (copy) strcpy(copy, arg);
        return copy;
    }
    return read_file(arg, NULL);
}

static void usage(const char *argv0) {
    fprintf(stderr,
        "usage: %s <script.lua> [args_json]\n"
        "       %s --code \"<lua>\" [--response \"<raw>\"]\n"
        "options:\n"
        "  --budget <N>   instruction budget (0 disables the watchdog)\n"
        "  --no-header    skip @param / @refresh parsing\n"
        "  --quiet        omit the stderr banner\n",
        argv0, argv0);
}

int main(int argc, char **argv) {
    const char *script = NULL;
    const char *code = NULL;
    const char *response = NULL;
    const char *args_arg = NULL;
    long long budget = -1; /* -1 = engine default */
    int parse_header = 1;
    int quiet = 0;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "--code") == 0 && i + 1 < argc) {
            code = argv[++i];
        } else if (strcmp(a, "--response") == 0 && i + 1 < argc) {
            response = argv[++i];
        } else if (strcmp(a, "--budget") == 0 && i + 1 < argc) {
            budget = atoll(argv[++i]);
        } else if (strcmp(a, "--no-header") == 0) {
            parse_header = 0;
        } else if (strcmp(a, "--quiet") == 0) {
            quiet = 1;
        } else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else if (!script && !code) {
            script = a;
        } else if (!args_arg) {
            args_arg = a;
        } else {
            fprintf(stderr, "engine_cli: unexpected argument: %s\n", a);
            usage(argv[0]);
            return 2;
        }
    }

    if (!script && !code) {
        usage(argv[0]);
        return 2;
    }

    char *args_json = resolve_args(args_arg);

    TPEngine *e = tp_engine_create();
    if (!e) {
        fprintf(stderr, "engine_cli: tp_engine_create failed\n");
        free(args_json);
        return 1;
    }
    if (budget >= 0) tp_engine_set_instruction_budget(e, budget);

    TPParamDecl decls[32];
    int ndecls = 0;
    int refresh_ms = 0;

    if (script && parse_header) {
        ndecls = tp_parse_params(script, decls, 32);
        refresh_ms = tp_parse_refresh(script);
    }

    TPScriptResult result;
    long long t0 = tp_now_ms();

    int rc;
    if (code) {
        rc = tp_execute_template(e, code, response, &result);
    } else {
        rc = tp_execute_file(e, script, args_json, &result);
    }

    long long elapsed = tp_now_ms() - t0;

    print_result(stdout, script ? script : "<template>", &result, elapsed,
                 refresh_ms, decls, ndecls);

    if (!quiet) {
        fprintf(stderr, "[engine_cli] %s in %lld ms (ok=%d)\n",
                script ? script : "<template>", elapsed, result.ok);
    }

    tp_engine_destroy(e);
    free(args_json);

    return rc ? 0 : 1;
}
