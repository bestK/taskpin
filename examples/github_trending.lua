-- github_trending.lua - GitHub Trending 热门仓库
-- @refresh 300000
-- @bar_width 160
-- @param LANG string 语言过滤(空=全部)
-- @param SINCE string 时间范围(daily/weekly/monthly)

local lang = args.LANG or ""
local since = args.SINCE or "daily"

local url = "https://github.com/trending"
if lang ~= "" then url = url .. "/" .. lang end
url = url .. "?since=" .. since

local html = http.get(url)
if not html then
    return font("Trending 离线", "#FF3333", 9), false
end

local repos = {}
for full_name in html:gmatch('<h2[^>]*>%s*<a[^>]*href="/([^"]+)"') do
    if #repos < 10 and not full_name:find("login") and not full_name:find("sponsors") then
        repos[#repos + 1] = { name = full_name, desc = "" }
    end
end

local descs = {}
for d in html:gmatch('<p class="col%-9[^"]*">%s*(.-)%s*</p>') do
    descs[#descs + 1] = d:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end
for i, r in ipairs(repos) do
    if descs[i] then r.desc = descs[i] end
end

local stars = {}
for s in html:gmatch('(%d[%d,]*) stars today') do
    stars[#stars + 1] = s
end

if #repos == 0 then
    return font("Trending 解析失败", "#FF9900", 9), false
end

local count = #repos
local period_label = { daily = "今日", weekly = "本周", monthly = "本月" }
local bar = font("🔥 " .. (period_label[since] or since) .. " Top " .. count, "#F9826C", 9)

local rows = {}
for i, r in ipairs(repos) do
    local star = stars[i] or ""
    local desc = r.desc
    if #desc > 50 then desc = desc:sub(1, 50) .. "..." end
    rows[#rows + 1] = { "⭐" .. star, r.name, desc, url = "https://github.com/" .. r.name, btn_text = "Open" }
end

local info = dialog({
    title = "GitHub Trending",
    width = 500, height = 380,
    refresh = 300000,
    content = {
        { type = "text", value = "🔥 GitHub Trending (" .. (lang ~= "" and lang or "All") .. " / " .. (period_label[since] or since) .. ")", color = "#F9826C", size = 12, bold = true },
        { type = "hr" },
        { type = "table",
          columns = { "Stars", "Repo", "Description" },
          col_widths = { 60, 180, 0 },
          rows = rows },
    }
})

return bar, true, info