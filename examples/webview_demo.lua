-- webview_demo.lua - WebView2 嵌入示例
-- @bar_width 120

local bar = font("WebView", "#4FC3F7", 9)

local info = dialog({
    title = "WebView Demo",
    width = 580, height = 460,
    borderless = true,
    transparent_bg = true,
    refresh = 1000,
    content = {
        { type = "webview", url = "https://raw.githubusercontent.com/bestK/taskpin/refs/heads/master/examples/webview_demo.html", width = 580, height = 460 }
    }
})

return bar, true, info
