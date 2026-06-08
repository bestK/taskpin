-- websocket_demo.lua - WebSocket 连接演示
-- @refresh 500
-- @bar_width 200

-- 使用全局变量保持连接跨刷新周期存活
if not _G._ws_demo then
    _G._ws_demo = websocket.connect("wss://ws.postman-echo.com/raw", {
        reconnect = true
    })
    _G._ws_last_send = 0
    _G._ws_last_msg = nil
    _G._ws_count = 0
end

local ws = _G._ws_demo
if not ws then
    return font("WS 创建失败", "#FF3333", 9), false
end

local connected = ws:is_connected()

-- 每 5 秒发送一次
local now = os.time()
if connected and (now - _G._ws_last_send) >= 5 then
    _G._ws_count = _G._ws_count + 1
    ws:send("ping #" .. _G._ws_count)
    _G._ws_last_send = now
end

-- 非阻塞接收
local msg = ws:recv()
if msg then
    _G._ws_last_msg = msg
end

-- 状态显示
local status_color = connected and "#4FC3F7" or "#FF6600"
local status_icon = connected and "●" or "○"
local display = _G._ws_last_msg or (connected and "已连接，等待回显..." or "连接中...")

if #display > 28 then display = display:sub(1, 28) .. "..." end

local bar = font(status_icon .. " ", status_color, 10)
    .. font(display, "#FFFFFF", 9)

local info = dialog({
    title = "WebSocket Demo",
    width = 380, height = 240,
    refresh = 1000,
    content = {
        { type = "text", value = "WebSocket Echo 测试", color = "#4FC3F7", size = 12, bold = true },
        { type = "hr" },
        { type = "text", value = "地址: ws.postman-echo.com/raw", size = 9, color = "#888888" },
        { type = "text", value = "状态: " .. (connected and "已连接" or "未连接(重连中)"), color = status_color, size = 10 },
        { type = "text", value = "已发送: " .. _G._ws_count .. " 条", size = 9 },
        { type = "text", value = "最新回复: " .. (_G._ws_last_msg or "-"), size = 9 },
    }
})

return bar, true, info
