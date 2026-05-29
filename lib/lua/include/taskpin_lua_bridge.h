#ifndef taskpin_lua_bridge_h
#define taskpin_lua_bridge_h

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

// Wrappers for macros that Swift cannot call directly

static inline void tp_lua_pop(lua_State *L, int n) { lua_settop(L, -(n)-1); }
static inline void tp_lua_newtable(lua_State *L) { lua_createtable(L, 0, 0); }
static inline int tp_lua_isnil(lua_State *L, int idx) { return lua_type(L, idx) == LUA_TNIL; }
static inline int tp_lua_isstring(lua_State *L, int idx) { return lua_type(L, idx) == LUA_TSTRING; }
static inline int tp_lua_istable(lua_State *L, int idx) { return lua_type(L, idx) == LUA_TTABLE; }
static inline int tp_lua_isnumber(lua_State *L, int idx) { return lua_type(L, idx) == LUA_TNUMBER; }
static inline const char *tp_lua_tostring(lua_State *L, int idx) { return lua_tolstring(L, idx, NULL); }
static inline int tp_lua_rawlen(lua_State *L, int idx) { return (int)lua_rawlen(L, idx); }
static inline int tp_lua_pcall(lua_State *L, int nargs, int nresults, int errfunc) { return lua_pcallk(L, nargs, nresults, errfunc, 0, NULL); }
static inline int tp_luaL_dofile(lua_State *L, const char *fn) { return luaL_loadfile(L, fn) || lua_pcallk(L, 0, LUA_MULTRET, 0, 0, NULL); }
static inline int tp_luaL_dostring(lua_State *L, const char *s) { return luaL_loadstring(L, s) || lua_pcallk(L, 0, LUA_MULTRET, 0, 0, NULL); }
static inline void tp_lua_pushcfunction(lua_State *L, lua_CFunction f) { lua_pushcclosure(L, f, 0); }
static inline int tp_lua_upvalueindex(int i) { return LUA_REGISTRYINDEX - i; }
static inline const char *tp_luaL_tolstring(lua_State *L, int idx, size_t *len) { return luaL_tolstring(L, idx, len); }

#endif
