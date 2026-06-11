-- kline_demo.lua - BTC/USDT K-Line chart
-- @name BTC K-Line

return "BTC ...", true, dialog({
    title = "BTC/USDT",
    width = 800, height = 500,
    borderless = true,
    transparent_bg = true,
    content = {
        { type = "webview", url = "file:///examples/kline_demo.html" }
    }
})
