-- @param API_URL string API地址
-- @param INTERVAL string 刷新间隔(ms)
-- example.lua - TaskPin Lua脚本示例
-- 演示如何使用 http.get, json.decode, args, 以及多返回值

local url = args.API_URL or "https://httpbin.org/json"

-- 发起 HTTP GET 请求
local resp = http.get(url)
if not resp then
    return "[请求失败]", false, ""
end

-- 解析 JSON
local data = json.decode(resp)
if not data then
    return resp, false, ""
end

-- 构造显示文本
local text = "OK"
if data.slideshow then
    text = data.slideshow.title or "untitled"
elseif data.name then
    text = data.name
end

-- 返回: 显示文本, 是否可点击, 点击URL
return text, true, url