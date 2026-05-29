-- @param BASE_URL string 禅道地址
-- @param ACCOUNT string 账号
-- @param PASSWORD string 密码
-- @refresh 60000
-- zentao_task.lua - 禅道未完成任务显示

local BASE_URL = args.BASE_URL or "https://zentao.example.com"
local ACCOUNT  = args.ACCOUNT or ""
local PASSWORD = args.PASSWORD or ""

local DONE = { done = true, closed = true, cancel = true }

local function login()
    http.get(BASE_URL .. "/user-login.html")
    local r = http.post(BASE_URL .. "/user-login.json",
        "account=" .. ACCOUNT .. "&password=" .. PASSWORD .. "&keepLogin=on")
    if not r then return false end
    local d = json.decode(r)
    return d and d.status == "success"
end

local function get_tasks()
    local r = http.get(BASE_URL .. "/my-task-assignedTo.json")
    if not r then log("禅道: 请求失败"); return {} end
    log("禅道: 原始响应长度", #r)
    local outer = json.decode(r)
    if not outer then log("禅道: JSON解析失败"); return {} end
    if not outer.data then log("禅道: 无data字段"); return {} end
    log("禅道: data内容", outer.data:sub(1, 500))
    local data = json.decode(outer.data)
    if not data then log("禅道: data解析失败"); return {} end
    if not data.tasks then
        log("禅道: 无tasks字段, 可用字段:")
        for k, _ in pairs(data) do log("  ", k) end
        return {}
    end
    log("禅道: tasks类型", type(data.tasks))
    return data.tasks
end

if ACCOUNT == "" then
    return font("[请配置参数]", "#FF3333", 9), false
end

if not login() then
    log("禅道: 登录失败", ACCOUNT)
    return font("[登录失败]", "#FF3333", 9), false
end
log("禅道: 登录成功", ACCOUNT)

local tasks = get_tasks()
local active = {}
for k, t in pairs(tasks) do
    if type(t) == "table" then
        log("禅道: 任务", k, t.name or "?", "status=" .. (t.status or "nil"))
        if t.status and not DONE[t.status] then
            active[#active + 1] = t
        end
    end
end

local count = #active
log("禅道: 获取到 " .. count .. " 个待办任务")
for _, t in ipairs(active) do
    log("  [P" .. (t.pri or "?") .. "] " .. (t.name or "未命名") .. " (" .. (t.status or "") .. ")")
end
local color = count == 0 and "#33CC33" or "#FFAA00"
local bar = font("禅道(" .. count .. ")", color, 9)

-- 构建任务表格（带行按钮）
local content = {
    { type = "text", value = "我的任务 (" .. count .. ")", color = "#D97757", size = 12, bold = true },
    { type = "hr" },
}

if count == 0 then
    content[#content + 1] = { type = "text", value = "没有待办任务", color = "#33CC33", size = 10 }
else
    local rows = {}
    for i, t in ipairs(active) do
        if i > 20 then break end
        local pri = t.pri and tostring(t.pri) or "-"
        local name = t.name or "未命名"
        if #name > 24 then name = name:sub(1, 24) .. ".." end
        local status = t.status or ""
        local task_url = BASE_URL .. "/task-view-" .. (t.id or "0") .. ".html"
        rows[#rows + 1] = { pri, name, status, url = task_url }
    end
    content[#content + 1] = {
        type = "table",
        columns = { "P", "任务", "状态" },
        rows = rows,
    }
end

local info = dialog({
    title = "禅道任务",
    width = 420, height = 320,
    refresh = 60,
    content = content,
})

return bar, true, info