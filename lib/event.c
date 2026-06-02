#include "event.h"
#include "json.h"
#include "logger.h"
#include "lua/lua.h"
#include "lua/lauxlib.h"
#include <string.h>
#include <stdio.h>

TaskPinEvent g_event;
static CRITICAL_SECTION s_event_cs;

void event_init(void) {
    InitializeCriticalSection(&s_event_cs);
    memset(&g_event, 0, sizeof(g_event));
}

void event_set(const char *source, const char *name, const char *json) {
    EnterCriticalSection(&s_event_cs);
    memset(&g_event, 0, sizeof(g_event));
    if (source) strncpy(g_event.source, source, EVENT_SOURCE_LEN - 1);
    if (name) strncpy(g_event.name, name, EVENT_NAME_LEN - 1);
    if (json) strncpy(g_event.params_json, json, EVENT_JSON_LEN - 1);
    g_event.active = TRUE;
    LeaveCriticalSection(&s_event_cs);
}

void event_clear(void) {
    EnterCriticalSection(&s_event_cs);
    g_event.active = FALSE;
    g_event.source[0] = '\0';
    g_event.name[0] = '\0';
    g_event.params_json[0] = '\0';
    LeaveCriticalSection(&s_event_cs);
}

static int l_event_clear(lua_State *ls) {
    (void)ls;
    event_clear();
    return 0;
}

static void json_node_to_lua(lua_State *ls, JsonNode *node) {
    if (!node) { lua_pushnil(ls); return; }
    switch (node->type) {
        case JSON_STRING: lua_pushstring(ls, node->str_val); break;
        case JSON_NUMBER: lua_pushnumber(ls, node->num_val); break;
        case JSON_BOOL:   lua_pushboolean(ls, node->bool_val); break;
        case JSON_NULL:   lua_pushnil(ls); break;
        case JSON_OBJECT: {
            lua_newtable(ls);
            JsonNode *c = node->children;
            while (c) {
                if (c->key) {
                    json_node_to_lua(ls, c);
                    lua_setfield(ls, -2, c->key);
                }
                c = c->next;
            }
            break;
        }
        case JSON_ARRAY: {
            lua_newtable(ls);
            JsonNode *c = node->children;
            int idx = 1;
            while (c) {
                json_node_to_lua(ls, c);
                lua_rawseti(ls, -2, idx++);
                c = c->next;
            }
            break;
        }
    }
}

void event_push_lua(void *L) {
    lua_State *ls = (lua_State *)L;
    EnterCriticalSection(&s_event_cs);
    if (!g_event.active) {
        LeaveCriticalSection(&s_event_cs);
        lua_pushnil(ls);
        lua_setglobal(ls, "event");
        return;
    }
    logger_write(LOG_DEBUG, "event push_lua: source=%s name=%s params=%s", g_event.source, g_event.name, g_event.params_json);
    lua_newtable(ls);
    lua_pushstring(ls, g_event.source);
    lua_setfield(ls, -2, "source");
    lua_pushstring(ls, g_event.name);
    lua_setfield(ls, -2, "name");

    /* Parse params_json and merge fields into the event table */
    if (g_event.params_json[0]) {
        JsonNode *root = json_parse(g_event.params_json);
        if (root && root->type == JSON_OBJECT) {
            JsonNode *child = root->children;
            while (child) {
                if (child->key) {
                    json_node_to_lua(ls, child);
                    lua_setfield(ls, -2, child->key);
                }
                child = child->next;
            }
        }
        if (root) json_free(root);
    }
    LeaveCriticalSection(&s_event_cs);
    lua_pushcfunction(ls, l_event_clear);
    lua_setfield(ls, -2, "clear");
    lua_setglobal(ls, "event");
}

void event_get_response_file(char *out, int out_size) {
    out[0] = '\0';
    EnterCriticalSection(&s_event_cs);
    if (g_event.active && g_event.params_json[0]) {
        JsonNode *root = json_parse(g_event.params_json);
        if (root) {
            JsonNode *rf = json_path_query(root, "$.response_file");
            if (rf && rf->type == JSON_STRING)
                strncpy(out, rf->str_val, out_size - 1);
            json_free(root);
        }
    }
    LeaveCriticalSection(&s_event_cs);
}

void event_send_ipc(const char *source, const char *name, const char *json) {
    logger_write(LOG_INFO, "event send: source=%s name=%s params=%s", source, name ? name : "", json ? json : "");
    /* Pack: "source\0name\0json" */
    char buf[EVENT_SOURCE_LEN + EVENT_NAME_LEN + EVENT_JSON_LEN + 4];
    int off = 0;
    int slen = (int)strlen(source) + 1;
    int nlen = (int)strlen(name) + 1;
    int jlen = json ? (int)strlen(json) + 1 : 1;
    if (slen + nlen + jlen > (int)sizeof(buf)) return;
    memcpy(buf + off, source, slen); off += slen;
    memcpy(buf + off, name, nlen); off += nlen;
    if (json) { memcpy(buf + off, json, jlen); off += jlen; }
    else { buf[off] = '\0'; off += 1; }

    /* Bar is a child of Shell_TrayWnd after embedding, so search there */
    HWND target = NULL;
    HWND hTaskbar = FindWindowW(L"Shell_TrayWnd", NULL);
    if (hTaskbar)
        target = FindWindowExW(hTaskbar, NULL, L"TaskPinBarClass", NULL);
    if (!target)
        target = FindWindowW(L"TaskPinBarClass", NULL);
    if (!target) return;

    COPYDATASTRUCT cds;
    cds.dwData = COPYDATA_EVENT_ID;
    cds.cbData = (DWORD)off;
    cds.lpData = buf;
    SendMessageW(target, WM_COPYDATA, 0, (LPARAM)&cds);
}

void event_receive(const void *data, int len) {
    const char *p = (const char *)data;
    const char *end = p + len;
    const char *source = p;
    while (p < end && *p) p++;
    if (p >= end) return;
    p++;
    const char *name = p;
    while (p < end && *p) p++;
    if (p >= end) { logger_write(LOG_INFO, "event recv: source=%s name=%s", source, name); event_set(source, name, NULL); return; }
    p++;
    const char *json = p;
    logger_write(LOG_INFO, "event recv: source=%s name=%s params=%s", source, name, json);
    event_set(source, name, json);
}
