-- Home Assistant 设备状态监控
-- @param HA_URL string Home Assistant 地址 (如 http://192.168.1.100:8123)
-- @param HA_TOKEN string 长期访问令牌
-- @param ENTITIES string 实体ID (逗号分隔, 如 sensor.temperature,light.living_room)
-- @refresh 10000

local ha_url = (args and args.HA_URL and args.HA_URL ~= "") and args.HA_URL or ""
local token = (args and args.HA_TOKEN and args.HA_TOKEN ~= "") and args.HA_TOKEN or ""
local entities_str = (args and args.ENTITIES and args.ENTITIES ~= "") and args.ENTITIES or ""

if ha_url == "" or token == "" then
    return font("HA: config needed", "#888", 9), false
end

local entities = {}
for e in entities_str:gmatch("[^,]+") do
    entities[#entities + 1] = e:match("^%s*(.-)%s*$")
end

local function ha_api(path)
    local cmd = string.format("curl -sL -H 'Authorization: Bearer %s' -H 'Content-Type: application/json' '%s%s'", token, ha_url, path)
    local f = io.popen(cmd)
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local rows = {}
local first_state = ""
local ok_count, total_count = 0, 0

if #entities > 0 then
    for _, entity_id in ipairs(entities) do
        local raw = ha_api("/api/states/" .. entity_id)
        if raw then
            local state = json.decode(raw)
            if state and state.state then
                total_count = total_count + 1
                local friendly = state.attributes and state.attributes.friendly_name or entity_id
                local val = state.state
                local unit = state.attributes and state.attributes.unit_of_measurement or ""
                if val ~= "unavailable" and val ~= "unknown" then ok_count = ok_count + 1 end
                if first_state == "" then first_state = friendly .. ": " .. val .. unit end
                rows[#rows + 1] = { friendly:sub(1, 20), val .. " " .. unit, entity_id:match("^(.-)%.") or "" }
            end
        end
    end
else
    local raw = ha_api("/api/states")
    if raw then
        local states = json.decode(raw)
        if states and type(states) == "table" then
            for i = 1, math.min(#states, 15) do
                local s = states[i]
                total_count = total_count + 1
                local friendly = s.attributes and s.attributes.friendly_name or s.entity_id
                local val = s.state or "?"
                if val ~= "unavailable" then ok_count = ok_count + 1 end
                rows[#rows + 1] = { friendly:sub(1, 20), val:sub(1, 15), (s.entity_id or ""):match("^(.-)%.") or "" }
            end
            if #states > 0 then
                first_state = ok_count .. "/" .. total_count .. " online"
            end
        end
    end
end

if total_count == 0 then
    return font("HA ✗", "#FF4444", 10), false
end

local color = ok_count == total_count and "#33CC33" or "#FFAA00"
local bar = font("🏠 " .. first_state:sub(1, 30), color, 10)

local detail = dialog({
    title = "Home Assistant",
    width = 400, height = 340,
    refresh = 10,
    content = {
        { type = "text", value = "Home Assistant", color = "#4FC3F7", size = 12, bold = true },
        { type = "text", value = ok_count .. "/" .. total_count .. " entities online", color = color, size = 10 },
        { type = "hr" },
        { type = "table", columns = {"Device", "State", "Type"}, rows = rows },
    }
})

return bar, true, detail
