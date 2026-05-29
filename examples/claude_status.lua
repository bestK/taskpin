-- claude_status.lua - Claude Code 状态指示器
-- bar_width 推荐: 160+

local github_base = "https://raw.githubusercontent.com/bestK/taskpin/refs/heads/master/examples/"

-- 检测是否在中国，加 GitHub 代理前缀
local function is_china()
    local geo = http.get("https://api.ip.sb/geoip")
    if not geo then return false end
    local info = json.decode(geo)
    return info and info.country_code == "CN"
end

local proxy = is_china() and "https://gh-proxy.com/" or ""
local claude_icon = proxy .. github_base .. "claude.png"
local claude_spinner = proxy .. github_base .. "claude_spinner.gif"

-- 查找最新 session jsonl
local function find_latest_session()
    local home = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
    local base = home .. "\\.claude\\projects"
    return sys.find_newest(base, ".jsonl")
end

-- 读取文件最后一行 (纯 Lua io, 从末尾回扫)
local function read_last_line(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    if not size or size == 0 then f:close(); return nil end
    local chunk = math.min(size, 65536)
    f:seek("set", size - chunk)
    local data = f:read(chunk)
    f:close()
    if not data then return nil end
    local last
    for line in data:gmatch("[^\n]+") do last = line end
    return last
end

-- 判断文件是否超过 30 秒未更新
local function is_stale(path)
    local mtime = sys.file_mtime(path)
    if not mtime then return true end
    return (os.time() - mtime) > 30
end

-- 解析状态
local function detect_status(path)
    if not path then return "offline", "未连接" end
    if is_stale(path) then return "idle", "休息中" end

    local line = read_last_line(path)
    if not line then return "idle", "休息中" end

    local event = json.decode(line)
    if not event then return "unknown", "..." end

    local etype = event.type
    if etype == "user" then
        return "thinking", "想一想"
    elseif etype == "assistant" then
        local msg = event.message
        if msg and msg.content then
            for _, block in ipairs(msg.content) do
                if block.type == "tool_use" then
                    local name = block.name or "working"
                    return "tool", name
                end
            end
        end
        return "done", "写好了"
    elseif etype == "system" then
        return "idle", "休息中"
    end
    return "unknown", "..."
end

-- 执行检测
local session_path = find_latest_session()
local status, detail = detect_status(session_path)

-- 状态颜色
local colors = {
    thinking = "#FFAA00",
    tool     = "#4FC3F7",
    done     = "#33CC33",
    idle     = "#888888",
    offline  = "#FF3333",
    unknown  = "#888888",
}
local color = colors[status] or "#888888"

-- 构建 bar
local bar
local working = (status == "thinking" or status == "tool")
if working then
    bar = icon(claude_icon, 16, 16)
        .. font(" ", nil, 9)
        .. icon(claude_spinner, 14, 14)
        .. font(" " .. detail, color, 8)
else
    bar = icon(claude_icon, 16, 16)
        .. font(" " .. detail, color, 9)
end

-- 对话框
local session_name = session_path and session_path:match("([^\\/]+)%.jsonl$") or "-"
local info = dialog({
    title = "Claude",
    width = 340, height = 180,
    refresh = 3,
    content = {
        { type = "text", value = "Claude Code", color = "#D97757", size = 12, bold = true },
        { type = "hr" },
        { type = "text", value = detail, color = color, size = 11 },
        { type = "text", value = session_name, color = "#666666", size = 9 },
    }
})

return bar, true, info