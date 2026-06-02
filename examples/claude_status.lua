-- claude_status.lua - Claude Code 状态指示器
-- @refresh 3000
-- bar_width 推荐: 权限模式 260+, 普通模式 160+

local github_base = "https://raw.githubusercontent.com/bestK/taskpin-plugins/master/"

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

-- 读取文件尾部 N 字节
local function read_tail(path, max_bytes)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    if not size or size == 0 then f:close(); return nil end
    local chunk = math.min(size, max_bytes or 65536)
    f:seek("set", size - chunk)
    local data = f:read(chunk)
    f:close()
    return data
end

-- 从文件尾部回扫找 ai-title
local function read_ai_title(path)
    local data = read_tail(path, 131072)
    if not data then return nil end
    local title
    for line in data:gmatch("[^\n]+") do
        if line:find('"ai-title"', 1, true) then
            local ev = json.decode(line)
            if type(ev) == "table" and ev.type == "ai-title" and ev.aiTitle then
                title = ev.aiTitle
            end
        end
    end
    return title
end

-- 判断文件是否超过 N 秒未更新
local function is_stale(path, seconds)
    local mtime = sys.file_mtime(path)
    if not mtime then return true end
    return (os.time() - mtime) > (seconds or 30)
end

-- 判断工作状态（仅通过文件活跃度）
local function detect_status(path)
    if not path then return "offline", "未连接" end
    if is_stale(path, 30) then return "idle", "休息中" end
    return "working", "工作中"
end

-- 按钮响应内容
local allow_json = '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
local deny_json = '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'

local function btn_allow()
    local b = button("允许", nil, "#000000", "#2E7D32", 8)
    b.margin = 4
    b.response = allow_json
    return b
end

local function btn_deny()
    local b = button("拒绝", nil, "#000000", "#C62828", 8)
    b.response = deny_json
    return b
end

-- 执行检测
local session_path = find_latest_session()
local status, detail = detect_status(session_path)
local ai_title = session_path and read_ai_title(session_path)

-- event 驱动：hook 推送 permission 事件时覆盖状态
local is_permission = (event and event.source == "claude-code" and event.name == "permission")
local permission_desc = ""
if is_permission then
    status = "permission"
    -- tool_input.description 由 hook stdin 透传到 event params
    local desc = event.tool_input and event.tool_input.description
    local tname = event.tool_name or ""
    permission_desc = desc or tname
    detail = "等待确认"
end

-- 状态颜色
local colors = {
    working    = "#4FC3F7",
    permission = "#FF6600",
    idle       = "#888888",
    offline    = "#FF3333",
}
local color = colors[status] or "#888888"

-- 构建 bar
local bar
local title_text = ai_title or detail

if is_permission then
    local ptext = permission_desc ~= "" and permission_desc or title_text
    bar = icon(claude_icon, 16, 16)
        .. font(" ", nil, 6)
        .. icon(claude_spinner, 14, 14)
        .. font(" " .. ptext, color, 8)
        .. font("  ", nil, 6)
        .. btn_allow()
        .. font(" ", nil, 4)
        .. btn_deny()
elseif status == "working" then
    bar = icon(claude_icon, 16, 16)
        .. font(" ", nil, 9)
        .. icon(claude_spinner, 14, 14)
        .. font(" " .. title_text, color, 8)
else
    bar = icon(claude_icon, 16, 16)
        .. font(" " .. title_text, color, 9)
end

-- 对话框
local session_name = session_path and session_path:match("([^\\/]+)%.jsonl$") or "-"

local dialog_content = {
    { type = "text", value = ai_title or "Claude Code", color = "#D97757", size = 12, bold = true },
    { type = "hr" },
    { type = "text", value = "状态: " .. detail, color = color, size = 10 },
    { type = "text", value = "会话: " .. session_name, color = "#666666", size = 9 },
}

if is_permission then
    dialog_content[#dialog_content + 1] = { type = "hr" }
    dialog_content[#dialog_content + 1] = {
        type = "button", value = "允许",
        response = allow_json,
        bg = "#000000", color = "#2E7D32", size = 11
    }
    dialog_content[#dialog_content + 1] = {
        type = "button", value = "拒绝",
        response = deny_json,
        bg = "#000000", color = "#C62828", size = 11
    }
end

local info = dialog({
    title = "Claude",
    width = 340, height = is_permission and 260 or 200,
    refresh = 3,
    content = dialog_content,
})

return bar, not is_permission, info
