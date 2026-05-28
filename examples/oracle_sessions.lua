-- @param EXPORTER_URLS string Exporter地址(格式: 别名=URL 逗号分隔,如 生产=http://db1:9161,测试=http://db2:9161)
-- oracle_sessions.lua - 从多个 Oracle Exporter 提取数据库会话数
-- 使用 font() 富文本: 绿色=正常, 橙色=警告(>70%), 红色=危险(>90%)

local URLS = args.EXPORTER_URLS or "http://localhost:9161"

local function parse_metrics(resp)
    local cur, limit = 0, 0
    for line in resp:gmatch("[^\n]+") do
        local val
        val = line:match('oracledb_resource_current_utilization{resource_name="sessions"}%s+([%d%.e%+]+)')
        if val then cur = tonumber(val) or 0 end
        val = line:match('oracledb_resource_limit_value{resource_name="sessions"}%s+([%d%.e%+]+)')
        if val then limit = tonumber(val) or 0 end
    end
    return cur, limit
end

local function status_color(cur, limit)
    if limit <= 0 then return "#888888" end
    local pct = cur / limit
    if pct >= 0.9 then return "#FF3333" end
    if pct >= 0.7 then return "#FFAA00" end
    return "#33CC33"
end

local parts = {}
for entry in URLS:gmatch("[^,]+") do
    entry = entry:match("^%s*(.-)%s*$")
    local name, url = entry:match("^(.-)=(.+)$")
    if not name or name == "" then
        url = entry
        name = url:match("//([^:/]+)") or url
    end

    local resp = http.get(url .. "/metrics")
    if resp then
        local cur, limit = parse_metrics(resp)
        local color = status_color(cur, limit)
        table.insert(parts,
            font(name .. " ", "#AAAAAA")
            .. font(tostring(cur), color)
            .. font("/" .. limit, "#888888")
        )
    else
        table.insert(parts,
            font(name .. " ", "#AAAAAA") .. font("ERR", "#FF3333")
        )
    end
end

if #parts == 0 then
    return font("[无数据]", "#888888", 9), false, ""
end

local rows = 2
local cols = math.ceil(#parts / rows)
local line1 = {}
local line2 = {}
for c = 1, cols do
    local i1 = (c - 1) * rows + 1
    local i2 = (c - 1) * rows + 2
    if i1 <= #parts then table.insert(line1, parts[i1]) end
    if i2 <= #parts then table.insert(line2, parts[i2]) end
end

local sep = font("  ")
local output = line1[1]
for i = 2, #line1 do
    output = output .. sep .. line1[i]
end
if #line2 > 0 then
    output = output .. font("\n") .. line2[1]
    for i = 2, #line2 do
        output = output .. sep .. line2[i]
    end
end
return output, false, ""