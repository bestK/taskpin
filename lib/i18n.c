#include "i18n.h"
#include "json.h"
#include "httputil.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shlwapi.h>

#define I18N_MAX_ENTRIES 256
#define I18N_MAX_KEY     64
#define I18N_MAX_VAL     512
#define I18N_REPO_BASE   "https://raw.githubusercontent.com/bestK/taskpin/master/lang/"
#define I18N_REPO_PROXY  "https://gh-proxy.com/https://raw.githubusercontent.com/bestK/taskpin/master/lang/"

typedef struct {
    char key[I18N_MAX_KEY];
    WCHAR val[I18N_MAX_VAL];
    char  val8[I18N_MAX_VAL * 3]; /* UTF-8 for ImGui */
} I18nEntry;

static I18nEntry s_entries[I18N_MAX_ENTRIES];
static int s_count = 0;
static char s_lang[32] = "en";
static WCHAR s_fallback[I18N_MAX_VAL];
static char s_fallback8[I18N_MAX_VAL * 3];

static void i18n_load_file(const WCHAR *path) {
    FILE *f = _wfopen(path, L"rb");
    if (!f) return;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len <= 0 || len > 512 * 1024) { fclose(f); return; }
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) { fclose(f); return; }
    fread(buf, 1, (size_t)len, f);
    buf[len] = '\0';
    fclose(f);

    JsonNode *root = json_parse(buf);
    free(buf);
    if (!root) return;

    for (JsonNode *item = root->children; item; item = item->next) {
        if (s_count >= I18N_MAX_ENTRIES) break;
        if (!item->key || item->type != JSON_STRING || !item->str_val) continue;
        I18nEntry *e = &s_entries[s_count];
        strncpy(e->key, item->key, I18N_MAX_KEY - 1);
        e->key[I18N_MAX_KEY - 1] = '\0';
        MultiByteToWideChar(CP_UTF8, 0, item->str_val, -1, e->val, I18N_MAX_VAL);
        e->val[I18N_MAX_VAL - 1] = L'\0';
        strncpy(e->val8, item->str_val, sizeof(e->val8) - 1);
        e->val8[sizeof(e->val8) - 1] = '\0';
        s_count++;
    }
    json_free(root);
}

#ifndef DEV_MODE
static BOOL i18n_download_file(const WCHAR *dir, const char *filename) {
    CreateDirectoryW(dir, NULL);

    char url[512];
    WCHAR wurl[512];
    int out_len = 0;
    char *resp = NULL;

    snprintf(url, sizeof(url), "%s%s", I18N_REPO_BASE, filename);
    MultiByteToWideChar(CP_UTF8, 0, url, -1, wurl, 512);
    resp = http_get_sync(wurl, &out_len);

    if (!resp || out_len <= 0) {
        free(resp);
        snprintf(url, sizeof(url), "%s%s", I18N_REPO_PROXY, filename);
        MultiByteToWideChar(CP_UTF8, 0, url, -1, wurl, 512);
        resp = http_get_sync(wurl, &out_len);
    }

    if (!resp || out_len <= 0) {
        free(resp);
        return FALSE;
    }

    JsonNode *test = json_parse(resp);
    if (!test) { free(resp); return FALSE; }
    json_free(test);

    WCHAR file_w[64];
    MultiByteToWideChar(CP_UTF8, 0, filename, -1, file_w, 64);
    WCHAR path[MAX_PATH];
    wsprintfW(path, L"%s\\%s", dir, file_w);
    FILE *f = _wfopen(path, L"wb");
    if (!f) { free(resp); return FALSE; }
    fwrite(resp, 1, (size_t)out_len, f);
    fclose(f);
    free(resp);
    return TRUE;
}
#endif

void i18n_init(void) {
    s_count = 0;

    WCHAR lang_w[LOCALE_NAME_MAX_LENGTH];
    GetUserDefaultLocaleName(lang_w, LOCALE_NAME_MAX_LENGTH);
    WideCharToMultiByte(CP_UTF8, 0, lang_w, -1, s_lang, sizeof(s_lang), NULL, NULL);

    WCHAR exe_dir[MAX_PATH];
    GetModuleFileNameW(NULL, exe_dir, MAX_PATH);
    PathRemoveFileSpecW(exe_dir);

    WCHAR lang_dir[MAX_PATH];
    wsprintfW(lang_dir, L"%s\\lang", exe_dir);

    /* Also try CWD/lang for dev launches. */
    WCHAR cwd_lang[MAX_PATH];
    GetCurrentDirectoryW(MAX_PATH, cwd_lang);
    lstrcatW(cwd_lang, L"\\lang");

    WCHAR lang_path[MAX_PATH];

    /* zh-CN / zh → zh-CN.json; en-* → en-US.json */
    const char *file = "en-US.json";
    if (strncmp(s_lang, "zh", 2) == 0)
        file = "zh-CN.json";
    else if (strncmp(s_lang, "en", 2) == 0)
        file = "en-US.json";

#ifndef DEV_MODE
    i18n_download_file(lang_dir, file);
#endif

    WCHAR file_w[64];
    MultiByteToWideChar(CP_UTF8, 0, file, -1, file_w, 64);

    wsprintfW(lang_path, L"%s\\%s", lang_dir, file_w);
    i18n_load_file(lang_path);

    if (s_count == 0) {
        wsprintfW(lang_path, L"%s\\%s", cwd_lang, file_w);
        i18n_load_file(lang_path);
    }

    if (s_count == 0 && strcmp(file, "en-US.json") != 0) {
#ifndef DEV_MODE
        i18n_download_file(lang_dir, "en-US.json");
#endif
        wsprintfW(lang_path, L"%s\\en-US.json", lang_dir);
        i18n_load_file(lang_path);
        if (s_count == 0) {
            wsprintfW(lang_path, L"%s\\en-US.json", cwd_lang);
            i18n_load_file(lang_path);
        }
    }
}

const WCHAR *tr(const char *key) {
    if (!key) return L"";
    for (int i = 0; i < s_count; i++) {
        if (strcmp(s_entries[i].key, key) == 0)
            return s_entries[i].val;
    }
    MultiByteToWideChar(CP_UTF8, 0, key, -1, s_fallback, I18N_MAX_VAL);
    return s_fallback;
}

const char *tr8(const char *key) {
    if (!key) return "";
    for (int i = 0; i < s_count; i++) {
        if (strcmp(s_entries[i].key, key) == 0)
            return s_entries[i].val8;
    }
    /* Fallback to key itself (ASCII-ish) */
    strncpy(s_fallback8, key, sizeof(s_fallback8) - 1);
    s_fallback8[sizeof(s_fallback8) - 1] = '\0';
    return s_fallback8;
}

const char *i18n_lang(void) {
    return s_lang;
}
