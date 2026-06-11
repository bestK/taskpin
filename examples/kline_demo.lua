-- kline_demo.lua - BTC/USDT K-Line chart
-- @name BTC K-Line

local bar
if __bar_lua then
    local fn = load("return " .. __bar_lua)
    if fn then bar = fn() end
end
if not bar then bar = "BTC ..." end

return bar, true, dialog({
    title = "BTC/USDT",
    width = 800, height = 500,
    borderless = true,
    transparent_bg = true,
    content = {
        { type = "webview", url = "file:///examples/kline_demo.html" }
    }
})
