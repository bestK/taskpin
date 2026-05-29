-- hud_clock.lua - 桌面悬浮时钟 (无边框 + 半透明 + 点击穿透)
-- @refresh 1000
-- bar_width 推荐: 100+

local bar = font(os.date("%H:%M"), "#FFFFFF", 10)

local info = dialog({
    title = "Clock",
    width = 200, height = 80,
    refresh = 1,
    borderless = true,
    clickthrough = true,
    opacity = 180,
    content = {
        { type = "text", value = os.date("%H:%M:%S"), color = "#FFFFFF", size = 24, bold = true },
        { type = "text", value = os.date("%Y-%m-%d %A"), color = "#AAAAAA", size = 10 },
    }
})

return bar, true, info
