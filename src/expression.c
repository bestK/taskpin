#include "ui.h"

void extract_fields(const char *raw, const WCHAR *expr, WCHAR *out, int out_size) {
    out[0] = L'\0';
    if (!expr || !expr[0]) {
        MultiByteToWideChar(CP_UTF8, 0, raw, -1, out, out_size);
        return;
    }

    char expr8[CFG_MAX_EXPR];
    WideCharToMultiByte(CP_UTF8, 0, expr, -1, expr8, CFG_MAX_EXPR, NULL, NULL);

    JsonNode *root = json_parse(raw);

    char result[FETCH_BUF_SIZE] = {0};
    int rpos = 0;
    const char *p = expr8;

    while (*p && rpos < FETCH_BUF_SIZE - 2) {
        if (*p == '$' && *(p + 1) == '.') {
            const char *start = p;
            p += 2;
            while (*p && *p != ' ' && *p != '\t' && *p != ',' &&
                   *p != '\n' && *p != '\r') p++;
            int pathlen = (int)(p - start);
            char path[512];
            if (pathlen >= 512) pathlen = 511;
            memcpy(path, start, pathlen);
            path[pathlen] = '\0';

            if (root) {
                JsonNode *node = json_path_query(root, path);
                if (node) {
                    rpos += json_node_to_string(node, result + rpos, FETCH_BUF_SIZE - rpos);
                } else {
                    int copylen = pathlen;
                    if (rpos + copylen >= FETCH_BUF_SIZE) copylen = FETCH_BUF_SIZE - rpos - 1;
                    memcpy(result + rpos, start, copylen);
                    rpos += copylen;
                }
            } else {
                int copylen = pathlen;
                if (rpos + copylen >= FETCH_BUF_SIZE) copylen = FETCH_BUF_SIZE - rpos - 1;
                memcpy(result + rpos, start, copylen);
                rpos += copylen;
            }
        } else {
            result[rpos++] = *p++;
        }
    }
    result[rpos] = '\0';
    if (root) json_free(root);

    MultiByteToWideChar(CP_UTF8, 0, result, -1, out, out_size);
}