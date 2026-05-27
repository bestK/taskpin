-- @param BASE_URL string API地址(如 https://api.example.com)
-- @param TOKEN string API令牌(sk-xxx)
-- @param USER_ID string 用户ID
-- newapi_balance.lua - 查询 NewAPI 账户余额

local BASE_URL = args.BASE_URL or "https://api.example.com"
local TOKEN = args.TOKEN or ""
local USER_ID = args.USER_ID or ""

if TOKEN == "" then
    return "[请配置TOKEN]", false, ""
end

local headers = "Authorization: Bearer " .. TOKEN .. "\r\nContent-Type: application/json"
if USER_ID ~= "" then
    headers = headers .. "\r\nNew-Api-User: " .. USER_ID
end

local resp = http.get(BASE_URL .. "/api/user/self", nil, headers)
if not resp then
    return "[请求失败]", false, ""
end

local data = json.decode(resp)
if not data or not data.success or not data.data then
    return "[查询失败]", false, ""
end

local d = data.data
local quota = d.quota or 0
local used = d.used_quota or 0
local total = (quota + used) / 500000
local remaining = quota / 500000
local group = d.group or "default"

local text = string.format("%s $%.2f/$%.2f", group, remaining, total)
return text, true, BASE_URL .. "/console/topup"