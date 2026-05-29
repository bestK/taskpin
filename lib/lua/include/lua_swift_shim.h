#ifndef lua_swift_shim_h
#define lua_swift_shim_h

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static inline void lua_newtable_s(lua_State *L) { lua_createtable(L, 0, 0); }
static inline void lua_pop_s(lua_State *L, int n) { lua_settop(L, -(n)-1); }
static inline int lua_isnil_s(lua_State *L, int idx) { return lua_type(L, idx) == LUA_TNIL; }
static inline int lua_isstring_s(lua_State *L, int idx) { return lua_type(L, idx) == LUA_TSTRING || lua_type(L, idx) == LUA_TNUMBER; }
static inline int lua_istable_s(lua_State *L, int idx) { return lua_type(L, idx) == LUA_TTABLE; }
static inline void lua_pushcclosure_s(lua_State *L, lua_CFunction fn, int n) { lua_pushcclosure(L, fn, n); }
static inline int lua_rawlen_s(lua_State *L, int idx) { return (int)lua_rawlen(L, idx); }
static inline int luaL_dofile_s(lua_State *L, const char *fn) { return luaL_loadfile(L, fn) || lua_pcall(L, 0, LUA_MULTRET, 0); }

#endif
