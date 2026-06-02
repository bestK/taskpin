-- image_dialog_demo.lua - 图文混排对话框演示
-- @refresh 5000
-- bar_width 推荐: 120+

local github_base = "https://raw.githubusercontent.com/bestK/taskpin-plugins/master/"

local function is_china()
    local geo = http.get("https://api.ip.sb/geoip")
    if not geo then return false end
    local info = json.decode(geo)
    return info and info.country_code == "CN"
end

local proxy = is_china() and "https://gh-proxy.com/" or ""
local claude_png = proxy .. github_base .. "claude.png"

local bar = font("Demo", "#AAAAAA", 9)

local info = dialog({
    title = "Image Demo",
    width = 340, height = 220,
    refresh = 5000,
    content = {
        { type = "text", value = "Claude Code", color = "#D97757", size = 12, bold = true,
          image = claude_png, image_width = 20, image_height = 20 },
        { type = "hr" },
        { type = "text", value = "图文混排：图片在文字左边", color = "#CCCCCC", size = 10,
          image = claude_png, image_width = 14, image_height = 14 },
        { type = "text", value = "纯文字行，没有图片", color = "#888888", size = 10 },
        { type = "image", source = claude_png, width = 64, height = 64 },
        { type = "text", value = "上面是独立图片块", color = "#666666", size = 9 },
    }
})

return bar, true, info
