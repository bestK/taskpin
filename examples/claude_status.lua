-- claude_status.lua - Claude Code 状态指示器
-- @refresh 3000
-- @require 1.4.0
-- @version 1.1.0
-- @bar_width 200
--
-- 基于 Claude Code Hooks 文档:
-- 事件: PreToolUse, PostToolUse, PermissionRequest, Stop, Notification 等
-- Hook 输出格式: {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow|deny","updatedInput":{...}}}}

local sep = package.config:sub(1, 1)
local home = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
local claude_dir = home .. sep .. ".claude"
local settings_path = claude_dir .. sep .. "settings.json"

local github_base = "https://raw.githubusercontent.com/bestK/taskpin-plugins/master/"

if _G._claude_proxy == nil then
    local geo = http.get("https://api.ip.sb/geoip")
    local info = geo and json.decode(geo)
    _G._claude_proxy = (info and info.country_code == "CN") and "https://gh-proxy.com/" or ""
end
local proxy = _G._claude_proxy
local claude_icon = proxy .. github_base .. "claude.png"
local claude_spinner = proxy .. github_base .. "claude_spinner.gif"

--- Session 检测（带缓存） ---

-- 全局缓存结构
_G._claude_cache = _G._claude_cache or {}
local cache = _G._claude_cache

local function find_latest_session()
    local now = os.time()
    -- 目录扫描每 10s 最多一次（event 驱动时跳过缓存）
    if not event and cache.session_path and cache.session_scan_at and (now - cache.session_scan_at) < 10 then
        return cache.session_path
    end
    cache.session_path = sys.find_newest(claude_dir .. sep .. "projects", ".jsonl")
    cache.session_scan_at = now
    return cache.session_path
end

-- 从尾部搜索 ai-title，带 size 缓存
local function read_ai_title(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    if not size or size == 0 then f:close(); return nil end

    -- 文件未增长时直接返回缓存
    if cache.title_path == path and cache.title_size == size then
        f:close()
        return cache.title_value
    end

    -- 先读最后 16KB（title 通常靠近尾部），未找到再扩大到 64KB
    local title
    for _, chunk_size in ipairs({16384, 65536}) do
        local chunk = math.min(size, chunk_size)
        f:seek("set", size - chunk)
        local data = f:read(chunk)
        if data then
            for line in data:gmatch("[^\n]+") do
                if line:find('"ai-title"', 1, true) then
                    local ev = json.decode(line)
                    if type(ev) == "table" and ev.type == "ai-title" and ev.aiTitle then
                        title = ev.aiTitle
                    end
                end
            end
        end
        if title then break end
    end
    f:close()

    cache.title_path = path
    cache.title_size = size
    cache.title_value = title
    return title
end

local function detect_status(path)
    if not path then return "offline", "未连接" end
    local mtime = sys.file_mtime(path)
    if not mtime or (os.time() - mtime) > 30 then
        return "idle", "休息中"
    end
    return "working", "工作中"
end

--- Hook 管理 ---
-- Claude Code hooks 格式参考:
-- settings.json -> hooks.PreToolUse / hooks.PermissionRequest
-- matcher: 工具名或正则 (".*" = 所有工具)
-- hook output: {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow|deny"}}}

local function read_settings()
    local raw = sys.read_file(settings_path)
    return raw and json.decode(raw)
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
    -- mtime 缓存: settings.json 未变时跳过解析
    local mtime = sys.file_mtime(settings_path)
    if cache.hook_mtime == mtime and cache.hook_installed ~= nil then
        return cache.hook_installed
    end
    local result = find_taskpin_hook(read_settings()) ~= nil
    cache.hook_mtime = mtime
    cache.hook_installed = result
    return result
end

local function install_hook()
    local raw = sys.read_file(settings_path)
    local cfg = raw and json.decode(raw) or {}
    cfg.hooks = cfg.hooks or {}
    cfg.hooks.PermissionRequest = cfg.hooks.PermissionRequest or {}
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
    cache.hook_mtime = nil
end

local function uninstall_hook()
    local cfg = read_settings()
    if not cfg then return end
    local idx = find_taskpin_hook(cfg)
    if not idx then return end
    table.remove(cfg.hooks.PermissionRequest, idx)
    if #cfg.hooks.PermissionRequest == 0 then
        cfg.hooks.PermissionRequest = nil
    end
    if not next(cfg.hooks) then cfg.hooks = nil end
    sys.write_file(settings_path, json.encode(cfg, true))
    cache.hook_mtime = nil
end

--- Hook 响应构建 ---

local function hook_response(behavior)
    return json.encode({
        hookSpecificOutput = {
            hookEventName = "PermissionRequest",
            decision = { behavior = behavior }
        }
    })
end

local function question_response(questions, answers)
    return json.encode({
        hookSpecificOutput = {
            hookEventName = "PermissionRequest",
            decision = {
                behavior = "allow",
                updatedInput = { questions = questions, answers = answers }
            }
        }
    })
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

--- 状态检测与事件处理 ---

local session_path = find_latest_session()
local status, detail = detect_status(session_path)
local ai_title = session_path and read_ai_title(session_path)

local permission_cmd = ""
local permission_desc = ""
local in_input_mode = (input_mode == true)
input_mode = nil

if event and event.source == "claude-code" then
    log.debug("event:", event.source, event.name, json.encode(event))

    if event.name == "install-hook" then
        install_hook()
        event.clear()
    elseif event.name == "uninstall-hook" then
        uninstall_hook()
        event.clear()
    elseif event.name == "permission" then
        local ti = event.tool_input or {}
        local tname = event.tool_name or ""

        if tname == "AskUserQuestion" and type(ti.questions) == "table" and #ti.questions > 0 then
            status = "question"
            detail = "等待回答"
            local q = ti.questions[1]
            permission_cmd = q and q.question or ""
            permission_desc = q and q.header or ""
        else
            status = "permission"
            detail = "等待确认"
            permission_cmd = ti.command or ti.file_path or ti.query or tname
            permission_desc = ti.description or ""
        end
    end
end

--- 状态颜色 ---

local colors = {
    working    = "#4FC3F7",
    permission = "#FF6600",
    question   = "#FFD700",
    idle       = "#888888",
    offline    = "#FF3333",
}
local color = colors[status] or "#888888"

--- 构建 Bar ---

local bar
local title_text = ai_title or detail

if status == "question" then
    local ti = event.tool_input or {}
    local questions = ti.questions or {}
    local q = questions[1]

    if in_input_mode then
        bar = icon(claude_icon, 16, 16)
            .. font(" ", nil, 4)
            .. input("otherAnswer", "Type your answer...", 320, 28, "#222", "#FFF", "#555")
        local submit = button(" OK ", nil, "#000000", "#2E7D32", 7)
        submit.margin = 6
        submit.response = question_response(questions, { [q.question] = "{otherAnswer}" })
        bar = bar .. submit
    elseif q and type(q.options) == "table" then
        bar = icon(claude_icon, 16, 16)
            .. font(" " .. (q.question or ""), "#FFFFFF", 8)
        for _, opt in ipairs(q.options) do
            local b = button(" " .. opt.label .. " ", nil, "#000000", "#1565C0", 7)
            b.response = question_response(questions, { [q.question] = opt.label })
            bar = bar .. b
        end
        local other_btn = button(" Other ", nil, "#000000", "#555555", 7)
        other_btn.patch_local = '{"input_mode":"true"}'
        bar = bar .. other_btn
    else
        bar = icon(claude_icon, 16, 16)
            .. font(" " .. permission_cmd, "#FFD700", 8)
    end

elseif status == "permission" then
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

--- 对话框 ---

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
    { type = "text", value = "Hook: " .. (hook_installed and "已安装" or "未安装"),
      color = hook_installed and "#33CC33" or "#888888", size = 9 },
    { type = "button",
      value = hook_installed and "卸载 Hook" or "安装 Hook",
      cmd = '"' .. exe_escaped .. '" --source claude-code --event ' .. (hook_installed and "uninstall-hook" or "install-hook"),
      bg_color = "#333333",
      color = hook_installed and "#C62828" or "#2E7D32",
      size = 10, width = 140, height = 30, align = "center" },
}

local info = dialog({
    title = "Claude",
    width = 340, height = 240,
    refresh = 3000,
    content = dialog_content,
})

local blocking = (status == "permission" or status == "question")
return bar, not blocking, not blocking and info or nil
