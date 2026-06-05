#include "i18n.h"
#include "cJSON.h"
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
} I18nEntry;

static I18nEntry s_entries[I18N_MAX_ENTRIES];
static int s_count = 0;
static char s_lang[32] = "en";
static WCHAR s_fallback[I18N_MAX_VAL];

static void i18n_load_file(const WCHAR *path) {
    FILE *f = _wfopen(path, L"rb");
    if (!f) return;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len <= 0 || len > 512 * 1024) { fclose(f); return; }
    char *buf = (char *)malloc(len + 1);
    fread(buf, 1, len, f);
    buf[len] = '\0';
    fclose(f);

    cJSON *root = cJSON_Parse(buf);
    free(buf);
    if (!root) return;

    cJSON *item = NULL;
    cJSON_ArrayForEach(item, root) {
        if (s_count >= I18N_MAX_ENTRIES) break;
        if (!item->string || !cJSON_IsString(item)) continue;
        I18nEntry *e = &s_entries[s_count];
        strncpy(e->key, item->string, I18N_MAX_KEY - 1);
        e->key[I18N_MAX_KEY - 1] = '\0';
        MultiByteToWideChar(CP_UTF8, 0, item->valuestring, -1,
                            e->val, I18N_MAX_VAL);
        s_count++;
    }
    cJSON_Delete(root);
}

static BOOL i18n_download_file(const WCHAR *dir, const char *filename) {
    /* Ensure lang/ directory exists */
    CreateDirectoryW(dir, NULL);

    /* Build URL: try proxy for China, direct otherwise */
    char url[512];
    WCHAR wurl[512];
    int out_len = 0;
    char *resp = NULL;

    /* Try direct first */
    snprintf(url, sizeof(url), "%s%s", I18N_REPO_BASE, filename);
    MultiByteToWideChar(CP_UTF8, 0, url, -1, wurl, 512);
    resp = http_get_sync(wurl, &out_len);

    /* If failed, try proxy */
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

    /* Validate it's valid JSON */
    cJSON *test = cJSON_Parse(resp);
    if (!test) { free(resp); return FALSE; }
    cJSON_Delete(test);

    /* Write to file */
    WCHAR file_w[64];
    MultiByteToWideChar(CP_UTF8, 0, filename, -1, file_w, 64);
    WCHAR path[MAX_PATH];
    wsprintfW(path, L"%s\\%s", dir, file_w);
    FILE *f = _wfopen(path, L"wb");
    if (!f) { free(resp); return FALSE; }
    fwrite(resp, 1, out_len, f);
    fclose(f);
    free(resp);
    return TRUE;
}

void i18n_init(void) {
    WCHAR lang_w[LOCALE_NAME_MAX_LENGTH];
    GetUserDefaultLocaleName(lang_w, LOCALE_NAME_MAX_LENGTH);
    WideCharToMultiByte(CP_UTF8, 0, lang_w, -1, s_lang, sizeof(s_lang), NULL, NULL);

    WCHAR exe_dir[MAX_PATH];
    GetModuleFileNameW(NULL, exe_dir, MAX_PATH);
    PathRemoveFileSpecW(exe_dir);

    WCHAR lang_dir[MAX_PATH];
    wsprintfW(lang_dir, L"%s\\lang", exe_dir);

    char base[8];
    strncpy(base, s_lang, 7);
    base[7] = '\0';
    char *dash = strchr(base, '-');
    if (dash) *dash = '\0';

    /* Try download latest lang files (overwrites local) */
    char filename[64];
    snprintf(filename, sizeof(filename), "%s.json", s_lang);
    i18n_download_file(lang_dir, filename);
    if (strcmp(base, s_lang) != 0) {
        snprintf(filename, sizeof(filename), "%s.json", base);
        i18n_download_file(lang_dir, filename);
    }

    /* Load from local files */
    WCHAR lang_path[MAX_PATH];
    WCHAR lang_file[64];
    MultiByteToWideChar(CP_UTF8, 0, s_lang, -1, lang_file, 64);

    wsprintfW(lang_path, L"%s\\%s.json", lang_dir, lang_file);
    i18n_load_file(lang_path);

    if (s_count == 0) {
        WCHAR base_w[8];
        MultiByteToWideChar(CP_UTF8, 0, base, -1, base_w, 8);
        wsprintfW(lang_path, L"%s\\%s.json", lang_dir, base_w);
        i18n_load_file(lang_path);
    }

    if (s_count == 0 && strncmp(s_lang, "en", 2) != 0) {
        i18n_download_file(lang_dir, "en.json");
        wsprintfW(lang_path, L"%s\\en.json", lang_dir);
        i18n_load_file(lang_path);
    }
}

const WCHAR *tr(const char *key) {
    if (!key) return L"";
    for (int i = 0; i < s_count; i++) {
        if (strcmp(s_entries[i].key, key) == 0)
            return s_entries[i].val;
    }
    /* Fallback: convert key to wide string */
    MultiByteToWideChar(CP_UTF8, 0, key, -1, s_fallback, I18N_MAX_VAL);
    return s_fallback;
}

const char *i18n_lang(void) {
    return s_lang;
}
