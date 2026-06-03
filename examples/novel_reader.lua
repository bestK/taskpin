-- novel_reader.lua - 任务栏摸鱼小说阅读器
-- @param FILE file 小说文件路径(UTF-8 txt)
-- @param CHARS number 每次显示字数(默认20)
-- @refresh 5000
-- bar_width 推荐: 300+

local file_path = args.FILE or ""
local chars_per_page = tonumber(args.CHARS) or 20

log("novel_reader: FILE=" .. file_path)

if file_path == "" then
    return font("[请配置小说路径]", "#FF3333", 9), false
end

-- 进度文件 (和小说同目录)
local progress_file = file_path .. ".pos"

-- 读取进度
local function load_pos()
    local f = io.open(progress_file, "r")
    if not f then return 0 end
    local pos = tonumber(f:read("*a")) or 0
    f:close()
    return pos
end

-- 保存进度
local function save_pos(pos)
    local f = io.open(progress_file, "w")
    if f then f:write(tostring(pos)); f:close() end
end

-- 读取小说内容
local content = sys.read_file(file_path)
if not content or #content == 0 then
    log("novel_reader: 读取失败或为空", file_path)
    return font("[文件为空或不存在]", "#FF3333", 9), false
end

-- UTF-8 字符切片
local function utf8_sub(s, start, count)
    local i = start
    local len = #s
    local result = {}
    local n = 0
    while i <= len and n < count do
        local b = s:byte(i)
        local char_len = 1
        if b >= 0xF0 then char_len = 4
        elseif b >= 0xE0 then char_len = 3
        elseif b >= 0xC0 then char_len = 2
        end
        result[#result + 1] = s:sub(i, i + char_len - 1)
        i = i + char_len
        n = n + 1
    end
    return table.concat(result), i
end

local pos = load_pos()
if pos >= #content then pos = 0 end

-- 跳过换行
while pos < #content and (content:byte(pos + 1) == 10 or content:byte(pos + 1) == 13) do
    pos = pos + 1
end

local text, next_pos = utf8_sub(content, pos + 1, chars_per_page)
text = text:gsub("[\r\n]+", " ")

-- 自动翻页
save_pos(next_pos - 1)

-- 计算进度百分比
local percent = math.floor(pos / #content * 100)

-- 上一页的位置
local prev_pos = pos - (chars_per_page * 3)
if prev_pos < 0 then prev_pos = 0 end

-- 跳转命令 (写进度文件)
local cmd_prev = 'echo ' .. prev_pos .. ' > "' .. progress_file .. '"'
local cmd_25 = 'echo ' .. math.floor(#content * 0.25) .. ' > "' .. progress_file .. '"'
local cmd_50 = 'echo ' .. math.floor(#content * 0.50) .. ' > "' .. progress_file .. '"'
local cmd_75 = 'echo ' .. math.floor(#content * 0.75) .. ' > "' .. progress_file .. '"'
local cmd_reset = 'echo 0 > "' .. progress_file .. '"'

local bar = font(text, "#CCCCCC", 9)

local info = dialog({
    title = "Reader",
    width = 400, height = 300,
    refresh = 5000,
    content = {
        { type = "text", value = "摸鱼阅读器", color = "#D97757", size = 11, bold = true },
        { type = "hr" },
        { type = "text", value = text, color = "#EEEEEE", size = 11 },
        { type = "hr" },
        { type = "text", value = "进度: " .. percent .. "%", color = "#888888", size = 9 },
        { type = "button", value = "<< 上一页", cmd = cmd_prev, bg_color = "#333333", color = "#4FC3F7" },
        { type = "button", value = "跳到 25%", cmd = cmd_25, bg_color = "#333333", color = "#AAAAAA" },
        { type = "button", value = "跳到 50%", cmd = cmd_50, bg_color = "#333333", color = "#AAAAAA" },
        { type = "button", value = "跳到 75%", cmd = cmd_75, bg_color = "#333333", color = "#AAAAAA" },
        { type = "button", value = "重置进度", cmd = cmd_reset, bg_color = "#333333", color = "#FF6666" },
    }
})

return bar, true, info
