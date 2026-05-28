#ifndef TASKPIN_JSON_H
#define TASKPIN_JSON_H

#include <windows.h>

/* Minimal JSON parser — tree structure */

typedef enum {
    JSON_NULL, JSON_BOOL, JSON_NUMBER, JSON_STRING, JSON_ARRAY, JSON_OBJECT
} JsonType;

typedef struct JsonNode {
    JsonType type;
    char *key;              /* key if inside object, NULL otherwise */
    union {
        int    bool_val;
        double num_val;
        char  *str_val;
    };
    struct JsonNode *children;   /* first child (array/object) */
    struct JsonNode *next;       /* sibling */
} JsonNode;

/* Parse UTF-8 JSON string into tree. Returns root node or NULL on error. */
JsonNode *json_parse(const char *src);

/* Free entire tree */
void json_free(JsonNode *root);

/* Extract value by JSONPath expression (subset: $.key.key[0].key)
   Returns pointer to node, or NULL if not found. */
JsonNode *json_path_query(JsonNode *root, const char *path);

/* Render node value as UTF-8 string into buf. Returns bytes written (excl NUL). */
int json_node_to_string(JsonNode *node, char *buf, int buf_size);

/* Build a "path" string for a given node by walking up (requires parent tracking).
   Simpler: build path during tree traversal in UI code. */

#endif