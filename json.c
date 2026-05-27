#include "json.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

/* ─── allocator ─── */

static JsonNode *node_alloc(JsonType type) {
    JsonNode *n = (JsonNode *)calloc(1, sizeof(JsonNode));
    if (n) n->type = type;
    return n;
}

/* ─── lexer helpers ─── */

static const char *skip_ws(const char *p) {
    while (*p && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) p++;
    return p;
}

static char *parse_string_raw(const char **pp) {
    const char *p = *pp;
    if (*p != '"') return NULL;
    p++;
    const char *start = p;
    /* find end, handle escapes */
    int len = 0;
    const char *s = start;
    while (*s && *s != '"') {
        if (*s == '\\') s++;
        s++; len++;
    }
    char *out = (char *)malloc(len + 1);
    int i = 0;
    p = start;
    while (*p && *p != '"') {
        if (*p == '\\') {
            p++;
            switch (*p) {
            case '"': out[i++] = '"'; break;
            case '\\': out[i++] = '\\'; break;
            case '/': out[i++] = '/'; break;
            case 'n': out[i++] = '\n'; break;
            case 'r': out[i++] = '\r'; break;
            case 't': out[i++] = '\t'; break;
            case 'b': out[i++] = '\b'; break;
            case 'f': out[i++] = '\f'; break;
            default: out[i++] = *p; break;
            }
        } else {
            out[i++] = *p;
        }
        p++;
    }
    out[i] = '\0';
    if (*p == '"') p++;
    *pp = p;
    return out;
}

/* ─── recursive parser ─── */

static JsonNode *parse_value(const char **pp);

static JsonNode *parse_object(const char **pp) {
    const char *p = *pp;
    p++; /* skip '{' */
    JsonNode *obj = node_alloc(JSON_OBJECT);
    JsonNode *tail = NULL;

    p = skip_ws(p);
    while (*p && *p != '}') {
        p = skip_ws(p);
        char *key = parse_string_raw(&p);
        p = skip_ws(p);
        if (*p == ':') p++;
        p = skip_ws(p);

        JsonNode *val = parse_value(&p);
        if (val) {
            val->key = key;
            if (!obj->children) obj->children = val;
            else tail->next = val;
            tail = val;
        } else {
            free(key);
        }

        p = skip_ws(p);
        if (*p == ',') p++;
    }
    if (*p == '}') p++;
    *pp = p;
    return obj;
}

static JsonNode *parse_array(const char **pp) {
    const char *p = *pp;
    p++; /* skip '[' */
    JsonNode *arr = node_alloc(JSON_ARRAY);
    JsonNode *tail = NULL;

    p = skip_ws(p);
    while (*p && *p != ']') {
        JsonNode *val = parse_value(&p);
        if (val) {
            if (!arr->children) arr->children = val;
            else tail->next = val;
            tail = val;
        }
        p = skip_ws(p);
        if (*p == ',') p++;
        p = skip_ws(p);
    }
    if (*p == ']') p++;
    *pp = p;
    return arr;
}

static JsonNode *parse_value(const char **pp) {
    const char *p = skip_ws(*pp);
    JsonNode *node = NULL;

    if (*p == '"') {
        node = node_alloc(JSON_STRING);
        node->str_val = parse_string_raw(&p);
    } else if (*p == '{') {
        node = parse_object(&p);
    } else if (*p == '[') {
        node = parse_array(&p);
    } else if (*p == 't' && strncmp(p, "true", 4) == 0) {
        node = node_alloc(JSON_BOOL);
        node->bool_val = 1;
        p += 4;
    } else if (*p == 'f' && strncmp(p, "false", 5) == 0) {
        node = node_alloc(JSON_BOOL);
        node->bool_val = 0;
        p += 5;
    } else if (*p == 'n' && strncmp(p, "null", 4) == 0) {
        node = node_alloc(JSON_NULL);
        p += 4;
    } else if (*p == '-' || isdigit((unsigned char)*p)) {
        node = node_alloc(JSON_NUMBER);
        char *end;
        node->num_val = strtod(p, &end);
        p = end;
    }

    *pp = p;
    return node;
}

JsonNode *json_parse(const char *src) {
    if (!src) return NULL;
    const char *p = src;
    return parse_value(&p);
}

/* ─── free ─── */

void json_free(JsonNode *root) {
    if (!root) return;
    json_free(root->children);
    json_free(root->next);
    free(root->key);
    if (root->type == JSON_STRING) free(root->str_val);
    free(root);
}

/* ─── JSONPath query (subset: $.key.key[N].key) ─── */

JsonNode *json_path_query(JsonNode *root, const char *path) {
    if (!root || !path) return NULL;
    const char *p = path;
    if (*p == '$') p++;
    JsonNode *cur = root;

    while (*p && cur) {
        if (*p == '.') p++;
        if (*p == '[') {
            p++;
            int idx = atoi(p);
            while (*p && *p != ']') p++;
            if (*p == ']') p++;
            if (cur->type != JSON_ARRAY) return NULL;
            JsonNode *c = cur->children;
            for (int i = 0; i < idx && c; i++) c = c->next;
            cur = c;
        } else {
            /* key name */
            const char *start = p;
            while (*p && *p != '.' && *p != '[') p++;
            int klen = (int)(p - start);
            if (klen == 0) break;
            if (cur->type != JSON_OBJECT) return NULL;
            JsonNode *c = cur->children;
            while (c) {
                if (c->key && (int)strlen(c->key) == klen && strncmp(c->key, start, klen) == 0)
                    break;
                c = c->next;
            }
            cur = c;
        }
    }
    return cur;
}

/* ─── node to string ─── */

int json_node_to_string(JsonNode *node, char *buf, int buf_size) {
    if (!node || !buf || buf_size <= 0) return 0;
    switch (node->type) {
    case JSON_NULL:   return snprintf(buf, buf_size, "null");
    case JSON_BOOL:   return snprintf(buf, buf_size, "%s", node->bool_val ? "true" : "false");
    case JSON_NUMBER: {
        double v = node->num_val;
        if (v == (int)v) return snprintf(buf, buf_size, "%d", (int)v);
        return snprintf(buf, buf_size, "%g", v);
    }
    case JSON_STRING: return snprintf(buf, buf_size, "%s", node->str_val ? node->str_val : "");
    case JSON_ARRAY:  return snprintf(buf, buf_size, "[...]");
    case JSON_OBJECT: return snprintf(buf, buf_size, "{...}");
    }
    return 0;
}