#include "cjson_utils.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

cJSON *cjson_path_query(cJSON *root, const char *path) {
    if (!root || !path) return NULL;

    const char *p = path;
    /* Skip leading "$" or "$." */
    if (*p == '$') {
        p++;
        if (*p == '.') p++;
    }

    cJSON *cur = root;

    while (*p && cur) {
        if (*p == '.') {
            p++;
            continue;
        }

        if (*p == '[') {
            /* Array index access */
            p++;
            int idx = 0;
            while (*p >= '0' && *p <= '9') {
                idx = idx * 10 + (*p - '0');
                p++;
            }
            if (*p == ']') p++;
            cur = cJSON_GetArrayItem(cur, idx);
        } else {
            /* Object key access */
            const char *start = p;
            while (*p && *p != '.' && *p != '[') p++;
            int len = (int)(p - start);
            char key[256];
            if (len >= (int)sizeof(key)) len = (int)sizeof(key) - 1;
            memcpy(key, start, len);
            key[len] = '\0';
            cur = cJSON_GetObjectItem(cur, key);
        }
    }

    return cur;
}

int cjson_node_to_string(cJSON *node, char *buf, int buf_size) {
    if (!node || buf_size <= 0) return 0;
    buf[0] = '\0';

    if (cJSON_IsString(node)) {
        int len = (int)strlen(node->valuestring);
        if (len >= buf_size) len = buf_size - 1;
        memcpy(buf, node->valuestring, len);
        buf[len] = '\0';
        return len;
    }
    if (cJSON_IsNumber(node)) {
        double d = node->valuedouble;
        int n;
        if (d == (int)d)
            n = snprintf(buf, buf_size, "%d", (int)d);
        else
            n = snprintf(buf, buf_size, "%g", d);
        return (n > 0 && n < buf_size) ? n : 0;
    }
    if (cJSON_IsBool(node)) {
        const char *s = cJSON_IsTrue(node) ? "true" : "false";
        int len = (int)strlen(s);
        if (len >= buf_size) len = buf_size - 1;
        memcpy(buf, s, len);
        buf[len] = '\0';
        return len;
    }
    if (cJSON_IsNull(node)) {
        if (buf_size >= 5) {
            memcpy(buf, "null", 4);
            buf[4] = '\0';
            return 4;
        }
        return 0;
    }
    /* For arrays/objects, use cJSON_PrintUnformatted */
    char *printed = cJSON_PrintUnformatted(node);
    if (printed) {
        int len = (int)strlen(printed);
        if (len >= buf_size) len = buf_size - 1;
        memcpy(buf, printed, len);
        buf[len] = '\0';
        free(printed);
        return len;
    }
    return 0;
}
