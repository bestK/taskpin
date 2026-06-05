-- webview_link_test.lua - 测试 webview 内链接点击
-- @bar_width 100

local bar = font("LinkTest", "#4FC3F7", 9)

local info = dialog({
    title = "WebView Link Test",
    title_bg_color = "#1a1a2e",
    title_color = "#4FC3F7",
    width = 400, height = 300,
    content = {
        { type = "webview", url = "https://www.baidu.com", width = 400, height = 260 }
    }
})

return bar, true, info
