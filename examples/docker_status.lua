-- Docker 容器状态监控
-- @param DOCKER_HOST string Docker Host (默认 unix:///var/run/docker.sock)
-- @refresh 5000

local host = (args and args.DOCKER_HOST and args.DOCKER_HOST ~= "") and args.DOCKER_HOST or "http://localhost"
local use_socket = host:find("unix://") == 1

local function docker_api(path)
    local url
    if use_socket then
        url = "http://localhost" .. path
        local cmd = "curl -s --unix-socket /var/run/docker.sock " .. url
        local f = io.popen(cmd)
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        return data
    else
        url = host .. path
        return http.get(url)
    end
end

local raw = docker_api("/containers/json?all=true")
if not raw then
    return font("Docker ✗", "#FF4444", 10), false
end

local containers = json.decode(raw)
if not containers or type(containers) ~= "table" then
    return font("Docker ✗", "#FF4444", 10), false
end

local running, stopped, total = 0, 0, #containers
for _, c in ipairs(containers) do
    if c.State == "running" then running = running + 1
    else stopped = stopped + 1 end
end

local color = stopped > 0 and "#FFAA00" or "#33CC33"
local bar = font("🐳 ", nil, 10)
    .. font(tostring(running), "#33CC33", 10)
    .. font("/" .. tostring(total), "#888888", 9)

local rows = {}
for i = 1, math.min(#containers, 20) do
    local c = containers[i]
    local name = c.Names and c.Names[1] or "?"
    name = name:gsub("^/", "")
    local state = c.State or "?"
    local status = c.Status or ""
    local stateColor = state == "running" and "#33CC33" or "#FF4444"
    rows[i] = { name, state, status:sub(1, 20) }
end

local detail = dialog({
    title = "Docker Containers",
    width = 420, height = 360,
    refresh = 5,
    content = {
        { type = "text", value = "Containers: " .. running .. " running, " .. stopped .. " stopped", color = color, size = 11, bold = true },
        { type = "hr" },
        { type = "table", columns = {"Name", "State", "Status"}, rows = rows },
    }
})

return bar, true, detail
