-- @param BASE_URL string API地址(如 https://api.example.com)
-- @param TOKEN string API令牌(sk-xxx)
-- newapi_balance.lua - 查询 NewAPI/OneAPI 账户余额

local BASE_URL = args.BASE_URL or "https://api.example.com"
local TOKEN = args.TOKEN or ""

if TOKEN == "" then
    return "[请配置TOKEN]", false, ""
end

local resp = http.get(BASE_URL .. "/api/user/self?access_token=" .. TOKEN)
if not resp then
    return "[请求失败]", false, ""
end

local data = json.decode(resp)
if not data or not data.success then
    -- 尝试 OneAPI 格式
    if data and data.data then
        local d = data.data
        local quota = d.quota or 0
        local used = d.used_quota or 0
        local remain = quota - used
        local text = string.format("余额:$%.2f 已用:$%.2f", remain / 500000, used / 500000)
        return text, true, BASE_URL .. "/topup"
    end
    return "[查询失败]", false, ""
end

-- NewAPI 格式
local d = data.data
local quota = d.quota or 0
local used = d.used_quota or 0
local remain = quota - used
local text = string.format("余额:$%.2f 已用:$%.2f", remain / 500000, used / 500000)
return text, true, BASE_URL .. "/topup"