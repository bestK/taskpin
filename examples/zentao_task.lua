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
    if not r then return {} end
    local outer = json.decode(r)
    if not outer or not outer.data then return {} end
    local data = json.decode(outer.data)
    if not data or not data.tasks then return {} end
    return data.tasks
end

if ACCOUNT == "" then
    return font("[请配置参数]", "#FF3333", 9), false
end

if not login() then
    return font("[登录失败]", "#FF3333", 9), false
end

local tasks = get_tasks()
local active = {}
for _, t in pairs(tasks) do
    if type(t) == "table" and t.status and not DONE[t.status] then
        active[#active + 1] = t
    end
end

local count = #active
local color = count == 0 and "#33CC33" or "#FFAA00"
local bar = font("禅道(" .. count .. ")", color, 9)

-- 构建任务按钮列表
local content = {
    { type = "text", value = "我的任务 (" .. count .. ")", color = "#D97757", size = 12, bold = true },
    { type = "hr" },
}

if count == 0 then
    content[#content + 1] = { type = "text", value = "没有待办任务", color = "#33CC33", size = 10 }
else
    for i, t in ipairs(active) do
        if i > 8 then break end
        local name = t.name or "未命名"
        local pri = t.pri and ("[P" .. t.pri .. "] ") or ""
        local task_url = BASE_URL .. "/task-view-" .. (t.id or "0") .. ".html"
        content[#content + 1] = { type = "button", value = pri .. name, url = task_url }
    end
end

local info = dialog({
    title = "禅道任务",
    width = 420, height = 320,
    refresh = 60,
    content = content,
})

return bar, true, info