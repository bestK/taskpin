import Foundation
import CLua

// Use tp_ prefixed bridge functions for Lua macros

class LuaRunner {
    private var L: OpaquePointer

    init() {
        L = luaL_newstate()
        luaL_openlibs(L)
        registerAPIs()
    }

    deinit { lua_close(L) }

    struct ScriptResult {
        var spans: [SpanItem] = []
        var clickable: Bool = false
        var dialogSpec: DialogSpec? = nil
    }

    struct SpanItem {
        var text: String = ""
        var color: String? = nil
        var fontSize: Int = 0
        var isImage: Bool = false
        var imageSource: String = ""
        var imageWidth: Int = 16
        var imageHeight: Int = 16
    }

    struct DialogSpec {
        var title: String = ""
        var width: Int = 400
        var height: Int = 300
        var refresh: Int = 0
        var borderless: Bool = false
        var items: [DialogSpecItem] = []
    }

    struct DialogSpecItem {
        var type: String = "text"
        var value: String = ""
        var color: String? = nil
        var fontSize: Int = 0
        var bold: Bool = false
        var image: String? = nil
        var imageWidth: Int = 16
        var imageHeight: Int = 16
        var url: String? = nil
        var cmd: String? = nil
        var columns: [String] = []
        var rows: [[String]] = []
        var rowUrls: [String?] = []
    }

    // MARK: - Execute

    func execute(file: String, args: [String: String] = [:]) -> ScriptResult? {
        lua_newtable(L)
        for (key, value) in args {
            lua_pushstring(L, value)
            lua_setfield(L, -2, key)
        }
        lua_setglobal(L, "args")

        if luaL_dofile(L, file) != LUA_OK {
            let err = String(cString: lua_tostring(L, -1))
            print("[TaskPin] Lua error: \(err)")
            lua_settop(L, 0)
            return nil
        }

        let nresults = lua_gettop(L)
        var result = ScriptResult()

        if nresults >= 1 { result.spans = parseSpans(at: 1) }
        if nresults >= 2 { result.clickable = lua_toboolean(L, 2) != 0 }
        if nresults >= 3 && lua_istable(L, 3) != 0 {
            lua_getfield(L, 3, "_dialog")
            let isDialog = lua_toboolean(L, -1) != 0
            lua_pop(L, 1)
            if isDialog { result.dialogSpec = parseDialogSpec(at: 3) }
        }

        lua_settop(L, 0)
        return result
    }

    // MARK: - Parse Spans

    private func parseSpans(at idx: Int32) -> [SpanItem] {
        if lua_isstring(L, idx) != 0 {
            return [SpanItem(text: String(cString: lua_tostring(L, idx)))]
        }
        guard lua_istable(L, idx) != 0 else { return [] }

        lua_getfield(L, idx, "__is_span")
        let isSingle = lua_toboolean(L, -1) != 0
        lua_pop(L, 1)
        if isSingle { return [parseSingleSpan(at: idx)] }

        lua_getfield(L, idx, "__is_spanlist")
        let isList = lua_toboolean(L, -1) != 0
        lua_pop(L, 1)
        if isList {
            var spans: [SpanItem] = []
            let len = Int(lua_rawlen(L, idx))
            for i in 1...len {
                lua_rawgeti(L, idx, lua_Integer(i))
                spans.append(parseSingleSpan(at: -1))
                lua_pop(L, 1)
            }
            return spans
        }
        return []
    }

    private func parseSingleSpan(at idx: Int32) -> SpanItem {
        var span = SpanItem()
        lua_getfield(L, idx, "__is_image")
        let isImage = lua_toboolean(L, -1) != 0
        lua_pop(L, 1)

        if isImage {
            span.isImage = true
            lua_getfield(L, idx, "img_source")
            if lua_isstring(L, -1) != 0 { span.imageSource = String(cString: lua_tostring(L, -1)) }
            lua_pop(L, 1)
            lua_getfield(L, idx, "img_w")
            if lua_isnil(L, -1) == 0 { span.imageWidth = Int(lua_tointeger(L, -1)) }
            lua_pop(L, 1)
            lua_getfield(L, idx, "img_h")
            if lua_isnil(L, -1) == 0 { span.imageHeight = Int(lua_tointeger(L, -1)) }
            lua_pop(L, 1)
        } else {
            lua_getfield(L, idx, "text")
            if lua_isstring(L, -1) != 0 { span.text = String(cString: lua_tostring(L, -1)) }
            lua_pop(L, 1)
            lua_getfield(L, idx, "color")
            if lua_isstring(L, -1) != 0 { span.color = String(cString: lua_tostring(L, -1)) }
            lua_pop(L, 1)
            lua_getfield(L, idx, "size")
            if lua_isnil(L, -1) == 0 { span.fontSize = Int(lua_tointeger(L, -1)) }
            lua_pop(L, 1)
        }
        return span
    }

    // MARK: - Parse Dialog

    private func parseDialogSpec(at idx: Int32) -> DialogSpec {
        var spec = DialogSpec()
        lua_getfield(L, idx, "title")
        if lua_isstring(L, -1) != 0 { spec.title = String(cString: lua_tostring(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "width")
        if lua_isnil(L, -1) == 0 { spec.width = Int(lua_tointeger(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "height")
        if lua_isnil(L, -1) == 0 { spec.height = Int(lua_tointeger(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "refresh")
        if lua_isnil(L, -1) == 0 { spec.refresh = Int(lua_tointeger(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "borderless")
        spec.borderless = lua_toboolean(L, -1) != 0
        lua_pop(L, 1)

        lua_getfield(L, idx, "content")
        if lua_istable(L, -1) != 0 {
            let n = Int(lua_rawlen(L, -1))
            for i in 1...max(n, 1) {
                if n == 0 { break }
                lua_rawgeti(L, -1, lua_Integer(i))
                if lua_istable(L, -1) != 0 { spec.items.append(parseDialogItem(at: -1)) }
                lua_pop(L, 1)
            }
        }
        lua_pop(L, 1)
        return spec
    }

    private func parseDialogItem(at idx: Int32) -> DialogSpecItem {
        var item = DialogSpecItem()
        lua_getfield(L, idx, "type")
        if lua_isstring(L, -1) != 0 { item.type = String(cString: lua_tostring(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "value")
        if lua_isstring(L, -1) != 0 { item.value = String(cString: lua_tostring(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "color")
        if lua_isstring(L, -1) != 0 { item.color = String(cString: lua_tostring(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "size")
        if lua_isnil(L, -1) == 0 { item.fontSize = Int(lua_tointeger(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "bold")
        item.bold = lua_toboolean(L, -1) != 0
        lua_pop(L, 1)
        lua_getfield(L, idx, "image")
        if lua_isstring(L, -1) != 0 { item.image = String(cString: lua_tostring(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "url")
        if lua_isstring(L, -1) != 0 { item.url = String(cString: lua_tostring(L, -1)) }
        lua_pop(L, 1)
        lua_getfield(L, idx, "cmd")
        if lua_isstring(L, -1) != 0 { item.cmd = String(cString: lua_tostring(L, -1)) }
        lua_pop(L, 1)
        return item
    }

    // MARK: - Register APIs

    private func registerAPIs() {
        luaL_newmetatable(L, "TaskPin.Span")
        let concatFn: @convention(c) (OpaquePointer?) -> Int32 = { L in
            guard let L = L else { return 0 }
            lua_newtable(L)
            lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_spanlist")
            luaL_getmetatable(L, "TaskPin.Span"); lua_setmetatable(L, -2)
            let result = lua_gettop(L)
            for side: Int32 in [1, 2] {
                if lua_istable(L, side) != 0 {
                    lua_getfield(L, side, "__is_spanlist")
                    let isList = lua_toboolean(L, -1) != 0
                    lua_pop(L, 1)
                    if isList {
                        let len = Int(lua_rawlen(L, side))
                        let dlen = Int(lua_rawlen(L, result))
                        for i in 1...max(len, 1) {
                            if len == 0 { break }
                            lua_rawgeti(L, side, lua_Integer(i))
                            lua_rawseti(L, result, lua_Integer(dlen + i))
                        }
                    } else {
                        let dlen = Int(lua_rawlen(L, result))
                        lua_pushvalue(L, side)
                        lua_rawseti(L, result, lua_Integer(dlen + 1))
                    }
                } else if lua_isstring(L, side) != 0 {
                    lua_newtable(L)
                    lua_pushvalue(L, side); lua_setfield(L, -2, "text")
                    lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span")
                    let dlen = Int(lua_rawlen(L, result))
                    lua_rawseti(L, result, lua_Integer(dlen + 1))
                }
            }
            return 1
        }
        lua_pushcclosure(L, concatFn, 0); lua_setfield(L, -2, "__concat")
        lua_pop(L, 1)

        let fontFn: @convention(c) (OpaquePointer?) -> Int32 = { L in
            guard let L = L else { return 0 }
            lua_newtable(L)
            if lua_isstring(L, 1) != 0 { lua_pushvalue(L, 1); lua_setfield(L, -2, "text") }
            if lua_gettop(L) >= 3 && lua_isstring(L, 2) != 0 { lua_pushvalue(L, 2); lua_setfield(L, -2, "color") }
            if lua_gettop(L) >= 4 && lua_isnil(L, 3) == 0 { lua_pushvalue(L, 3); lua_setfield(L, -2, "size") }
            lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span")
            luaL_getmetatable(L, "TaskPin.Span"); lua_setmetatable(L, -2)
            return 1
        }

        let iconFn: @convention(c) (OpaquePointer?) -> Int32 = { L in
            guard let L = L else { return 0 }
            lua_newtable(L)
            if lua_isstring(L, 1) != 0 { lua_pushvalue(L, 1); lua_setfield(L, -2, "img_source") }
            let w = lua_gettop(L) >= 2 ? lua_tointeger(L, 2) : 16
            let h = lua_gettop(L) >= 3 ? lua_tointeger(L, 3) : 16
            lua_pushinteger(L, w); lua_setfield(L, -2, "img_w")
            lua_pushinteger(L, h); lua_setfield(L, -2, "img_h")
            lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_image")
            lua_pushboolean(L, 1); lua_setfield(L, -2, "__is_span")
            luaL_getmetatable(L, "TaskPin.Span"); lua_setmetatable(L, -2)
            return 1
        }

        let dialogFn: @convention(c) (OpaquePointer?) -> Int32 = { L in
            guard let L = L else { return 0 }
            if lua_istable(L, 1) != 0 { lua_pushboolean(L, 1); lua_setfield(L, 1, "_dialog") }
            lua_pushvalue(L, 1)
            return 1
        }

        let logFn: @convention(c) (OpaquePointer?) -> Int32 = { L in
            guard let L = L else { return 0 }
            var parts: [String] = []
            for i: Int32 in 1...lua_gettop(L) {
                luaL_tolstring(L, i, nil)
                if lua_isstring(L, -1) != 0 { parts.append(String(cString: lua_tostring(L, -1))) }
                lua_pop(L, 1)
            }
            print("[TaskPin] \(parts.joined(separator: "\t"))")
            return 0
        }

        let jsonDecodeFn: @convention(c) (OpaquePointer?) -> Int32 = { L in
            guard let L = L, lua_isstring(L, 1) != 0 else { lua_pushnil(L); return 1 }
            let str = String(cString: lua_tostring(L, 1))
            guard let data = str.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { lua_pushnil(L); return 1 }
            LuaRunner.pushJSON(L, obj)
            return 1
        }

        let httpGetFn: @convention(c) (OpaquePointer?) -> Int32 = { L in
            guard let L = L, lua_isstring(L, 1) != 0 else { lua_pushnil(L); return 1 }
            let urlStr = String(cString: lua_tostring(L, 1))
            guard let url = URL(string: urlStr) else { lua_pushnil(L); return 1 }
            var result: String? = nil
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data { result = String(data: data, encoding: .utf8) }
                sem.signal()
            }.resume()
            sem.wait()
            if let r = result { lua_pushstring(L, r) } else { lua_pushnil(L) }
            return 1
        }

        lua_pushcclosure(L, fontFn, 0); lua_setglobal(L, "font")
        lua_pushcclosure(L, iconFn, 0); lua_setglobal(L, "icon")
        lua_pushcclosure(L, dialogFn, 0); lua_setglobal(L, "dialog")
        lua_pushcclosure(L, logFn, 0); lua_setglobal(L, "log")

        lua_newtable(L)
        lua_pushcclosure(L, jsonDecodeFn, 0); lua_setfield(L, -2, "decode")
        lua_setglobal(L, "json")

        lua_newtable(L)
        lua_pushcclosure(L, httpGetFn, 0); lua_setfield(L, -2, "get")
        lua_setglobal(L, "http")
    }

    static func pushJSON(_ L: OpaquePointer?, _ obj: Any) {
        guard let L = L else { return }
        switch obj {
        case let dict as [String: Any]:
            lua_newtable(L)
            for (key, val) in dict { lua_pushstring(L, key); pushJSON(L, val); lua_settable(L, -3) }
        case let arr as [Any]:
            lua_newtable(L)
            for (i, val) in arr.enumerated() { lua_pushinteger(L, lua_Integer(i + 1)); pushJSON(L, val); lua_settable(L, -3) }
        case let str as String: lua_pushstring(L, str)
        case let num as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(num) { lua_pushboolean(L, num.boolValue ? 1 : 0) }
            else { lua_pushnumber(L, lua_Number(num.doubleValue)) }
        default: lua_pushnil(L)
        }
    }
}
