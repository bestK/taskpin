#ifndef TASKPIN_CJSON_UTILS_H
#define TASKPIN_CJSON_UTILS_H

#include "cJSON.h"

/*
 * Query a cJSON tree using a JSONPath-like expression.
 * Supports: $.key.key[N].key
 * Returns a pointer into the existing tree (do NOT free it separately).
 * Returns NULL if the path does not resolve.
 */
cJSON *cjson_path_query(cJSON *root, const char *path);

/*
 * Render a cJSON node's value to a string buffer (for scalar display).
 * Returns the number of characters written (excluding null terminator).
 */
int cjson_node_to_string(cJSON *node, char *buf, int buf_size);

#endif
