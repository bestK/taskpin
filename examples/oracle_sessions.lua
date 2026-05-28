-- @param EXPORTER_URLS string Exporter地址(格式: 别名=URL 逗号分隔,如 生产=http://db1:9161,测试=http://db2:9161)
-- oracle_sessions.lua - 从多个 Oracle Exporter 提取数据库会话数

local URLS = args.EXPORTER_URLS or "http://localhost:9161"

local function parse_metrics(resp)
    local sessions_cur = 0
    local sessions_limit = 0

    for line in resp:gmatch("[^\n]+") do
        local val
        val = line:match('oracledb_resource_current_utilization{resource_name="sessions"}%s+([%d%.e%+]+)')
        if val then sessions_cur = tonumber(val) or 0 end

        val = line:match('oracledb_resource_limit_value{resource_name="sessions"}%s+([%d%.e%+]+)')
        if val then sessions_limit = tonumber(val) or 0 end
    end

    return sessions_cur, sessions_limit
end

local results = {}
for entry in URLS:gmatch("[^,]+") do
    entry = entry:match("^%s*(.-)%s*$")  -- trim
    -- 支持 别名=URL 或 纯URL
    local name, url = entry:match("^(.-)=(.+)$")
    if not name or name == "" then
        url = entry
        name = url:match("//([^:/]+)") or url
    end
    local resp = http.get(url .. "/metrics")
    if resp then
        local cur, limit = parse_metrics(resp)
        table.insert(results, string.format("%s:%d/%d", name, cur, limit))
    else
        table.insert(results, name .. ":ERR")
    end
end

local text = table.concat(results, " | ")
if text == "" then text = "[无数据]" end
return text, false, ""