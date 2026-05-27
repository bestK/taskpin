-- @param BASE_URL string 禅道地址
-- @param ACCOUNT string 账号
-- @param PASSWORD string 密码
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
    return "[请配置参数]", false, ""
end

if not login() then
    return "[登录失败]", false, ""
end

local tasks = get_tasks()
local names = {}
local count = 0
for _, t in pairs(tasks) do
    if type(t) == "table" and t.status and not DONE[t.status] then
        count = count + 1
        if t.name then names[#names + 1] = t.name end
    end
end

local text
if count == 0 then
    text = "禅道:无任务"
else
    text = "禅道(" .. count .. "):" .. table.concat(names, " | ")
end
return text, true, BASE_URL .. "/my-task-assignedTo.html"