-- webview_demo.lua - WebView2 嵌入示例
-- @bar_width 120

local bar = font("WebView", "#4FC3F7", 9)

local url = "https://raw.githubusercontent.com/bestK/taskpin/refs/heads/master/examples/webview_demo.html"
if sys.is_china() then
    url = sys.gh_proxy(url)
end

local info = dialog({
    title = "WebView Demo",
    width = 580, height = 460,
    borderless = true,
    transparent_bg = true,
    refresh = 1000,
    content = {
        { type = "webview", url = url, width = 580, height = 460 }
    }
})

return bar, true, info
