-- claude_status.lua - Claude Code 状态指示器
-- @refresh 3000
-- @require 1.4.0
-- @version 1.0.0
-- @bar_width 200

local sep = package.config:sub(1, 1)
local home = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
local claude_dir = home .. sep .. ".claude"

local github_base = "https://raw.githubusercontent.com/bestK/taskpin-plugins/master/"

-- 检测是否在中国，加 GitHub 代理前缀（只执行一次）
if _G._claude_proxy == nil then
    local geo = http.get("https://api.ip.sb/geoip")
    local info = geo and json.decode(geo)
    _G._claude_proxy = (info and info.country_code == "CN") and "https://gh-proxy.com/" or ""
end
local proxy = _G._claude_proxy
local claude_icon = proxy .. github_base .. "claude.png"
local claude_spinner = proxy .. github_base .. "claude_spinner.gif"

-- 查找最新 session jsonl
local function find_latest_session()
    local base = claude_dir .. sep .. "projects"
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

-- Hook 管理
local settings_path = claude_dir .. sep .. "settings.json"

local function read_settings()
    local raw = sys.read_file(settings_path)
    if not raw then return nil end
    return json.decode(raw)
end

local function find_taskpin_hook(cfg)
    if not cfg or not cfg.hooks then return nil, nil end
    local arr = cfg.hooks.PermissionRequest
    if type(arr) ~= "table" then return nil, nil end
    for i, entry in ipairs(arr) do
        if entry.hooks then
            for _, h in ipairs(entry.hooks) do
                if h.command and h.command:find("taskpin", 1, true) then
                    return i, entry
                end
            end
        end
    end
    return nil, nil
end

local function is_hook_installed()
    return find_taskpin_hook(read_settings()) ~= nil
end

local function install_hook()
    local raw = sys.read_file(settings_path)
    local cfg = raw and json.decode(raw) or {}
    if not cfg.hooks then cfg.hooks = {} end
    if type(cfg.hooks.PermissionRequest) ~= "table" then cfg.hooks.PermissionRequest = {} end
    if find_taskpin_hook(cfg) then return end
    cfg.hooks.PermissionRequest[#cfg.hooks.PermissionRequest + 1] = {
        matcher = ".*",
        hooks = {{
            type = "command",
            command = sys.exe_path(),
            args = {"--source", "claude-code", "--event", "permission", "--wait"},
            timeout = 120
        }}
    }
    sys.write_file(settings_path, json.encode(cfg, true))
end

local function uninstall_hook()
    local raw = sys.read_file(settings_path)
    if not raw then return end
    local cfg = json.decode(raw)
    if not cfg then return end
    local idx = find_taskpin_hook(cfg)
    if not idx then return end
    table.remove(cfg.hooks.PermissionRequest, idx)
    if #cfg.hooks.PermissionRequest == 0 then
        cfg.hooks.PermissionRequest = nil
    end
    sys.write_file(settings_path, json.encode(cfg, true))
end

-- 按钮响应内容
local function hook_response(behavior)
    return '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"' .. behavior .. '"}}}'
end

local function btn_allow()
    local b = button("允许", nil, "#000000", "#2E7D32", 8)
    b.margin = 4
    b.response = hook_response("allow")
    return b
end

local function btn_deny()
    local b = button("拒绝", nil, "#000000", "#C62828", 8)
    b.response = hook_response("deny")
    return b
end

-- 执行检测
local session_path = find_latest_session()
local status, detail = detect_status(session_path)
local ai_title = session_path and read_ai_title(session_path)

-- event 驱动
local is_permission = (event and event.source == "claude-code" and event.name == "permission")
local permission_cmd = ""
local permission_desc = ""

if event then
    log("event:", event.source, event.name, json.encode(event))
end

if event and event.source == "claude-code" and event.name == "install-hook" then
    install_hook()
    event.clear()
elseif event and event.source == "claude-code" and event.name == "uninstall-hook" then
    uninstall_hook()
    event.clear()
elseif is_permission then
    status = "permission"
    local ti = event.tool_input or {}
    local tname = event.tool_name or ""

    if tname == "AskUserQuestion" and type(ti.questions) == "table" and #ti.questions > 0 then
        status = "question"
        detail = "等待回答"
        local q = ti.questions[1]
        if q then
            permission_cmd = q.question or ""
            permission_desc = q.header or ""
        end
    else
        permission_cmd = ti.command or ti.file_path or ti.query or tname
        permission_desc = ti.description or ""
        detail = "等待确认"
    end
end

-- 状态颜色
local colors = {
    working    = "#4FC3F7",
    permission = "#FF6600",
    question   = "#FFD700",
    idle       = "#888888",
    offline    = "#FF3333",
}
local color = colors[status] or "#888888"

-- 构建 bar
local bar
local title_text = ai_title or detail

if status == "question" then
    local ti = event.tool_input or {}
    local questions = ti.questions or {}
    local q = questions[1]
    bar = icon(claude_icon, 16, 16)
        .. font(" " .. (q and q.question or ""), "#FFFFFF", 8)
        .. font("\n")

    if q and type(q.options) == "table" then
        for oi, opt in ipairs(q.options) do
            if oi > 1 then bar = bar .. font(" ", nil, 3) end
            local b = button(opt.label, nil, "#000000", "#1565C0", 7)
            -- 构建 updatedInput 把选中答案注入
            local answers = {}
            answers[q.question] = opt.label
            local updated_input = { questions = questions, answers = answers }
            b.response = json.encode({
                hookSpecificOutput = {
                    hookEventName = "PermissionRequest",
                    decision = {
                        behavior = "allow",
                        updatedInput = updated_input
                    }
                }
            })
            bar = bar .. b
        end
    end
elseif is_permission then
    bar = icon(claude_icon, 16, 16)
        .. font(" " .. permission_cmd, "#FFFFFF", 8)
        .. btn_allow()
        .. font(" ", nil, 4)
        .. btn_deny()
        .. font("\n")
        .. font("  " .. permission_desc, "#888888", 7)
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
local hook_installed = is_hook_installed()
local exe = sys.exe_path()
local exe_escaped = exe:gsub("\\", "\\\\")

local dialog_content = {
    { type = "text", value = ai_title or "Claude Code", color = "#D97757", size = 12, bold = true },
    { type = "hr" },
    { type = "text", value = "状态: " .. detail, color = color, size = 10 },
    { type = "text", value = "会话: " .. session_name, color = "#666666", size = 9 },
    { type = "hr" },
    { type = "text", value = "Hook: " .. (hook_installed and "已安装" or "未安装"), color = hook_installed and "#33CC33" or "#888888", size = 9 },
}

if hook_installed then
    dialog_content[#dialog_content + 1] = {
        type = "button", value = "卸载 Hook",
        cmd = '"' .. exe_escaped .. '" --source claude-code --event uninstall-hook',
        bg = "#333333", color = "#C62828", size = 10
    }
else
    dialog_content[#dialog_content + 1] = {
        type = "button", value = "安装 Hook",
        cmd = '"' .. exe_escaped .. '" --source claude-code --event install-hook',
        bg = "#333333", color = "#2E7D32", size = 10
    }
end

local info = dialog({
    title = "Claude",
    width = 340, height = 240,
    refresh = 3000,
    content = dialog_content,
})

return bar, not is_permission, info
