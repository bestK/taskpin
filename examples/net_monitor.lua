-- Net Monitor: show top processes with active network connections
-- Uses sys.net_processes() to display process name, connections, and IO speed
-- Recommended bar_width: 300+

local procs = sys.net_processes() or {}

local function fmt_speed(bytes)
    bytes = bytes or 0
    if bytes > 1048576 then return string.format("%.1fM/s", bytes / 1048576) end
    if bytes > 1024 then return string.format("%.1fK/s", bytes / 1024) end
    return string.format("%dB/s", math.floor(bytes))
end

-- Sort by download speed descending
table.sort(procs, function(a, b) return (a.download or 0) > (b.download or 0) end)

-- Show top 5 processes
local lines = {}
local max_show = math.min(#procs, 5)

for i = 1, max_show do
    local p = procs[i]
    local name = p.name or "?"
    if #name > 14 then name = name:sub(1, 12) .. ".." end
    local dl = fmt_speed(p.download)
    local ul = fmt_speed(p.upload)
    local conn = p.connections or 0

    table.insert(lines,
        font(name, "#E0E0E0", 9)
        .. font(" [" .. conn .. "]", "#888", 8)
        .. font("  ↓" .. dl, "#4FC3F7", 8)
        .. font(" ↑" .. ul, "#81C784", 8)
    )
end

if #lines == 0 then
    return font("No active connections", "#888", 9)
end

return table.concat(lines, font("\n"))