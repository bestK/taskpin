-- GitHub Actions CI 状态监控
-- @param REPO string 仓库 (格式: owner/repo)
-- @param TOKEN string GitHub Token (ghp_xxx)
-- @refresh 30000

local repo = args and args.REPO or ""
local token = args and args.TOKEN or ""

if repo == "" then
    return font("GH: no repo", "#888", 9), false
end

local headers = "Authorization: token " .. token .. "\nAccept: application/vnd.github.v3+json"
local url = "https://api.github.com/repos/" .. repo .. "/actions/runs?per_page=10&status=completed"
local url_active = "https://api.github.com/repos/" .. repo .. "/actions/runs?per_page=5&status=in_progress"

local function fetch(u)
    local cmd = string.format("curl -sL -H 'Authorization: token %s' -H 'Accept: application/vnd.github.v3+json' '%s'", token, u)
    local f = io.popen(cmd)
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local active_raw = fetch(url_active)
local active_runs = {}
if active_raw then
    local d = json.decode(active_raw)
    if d and d.workflow_runs then active_runs = d.workflow_runs end
end

local raw = fetch(url)
if not raw then
    return font("GH ✗", "#FF4444", 10), false
end

local data = json.decode(raw)
if not data or not data.workflow_runs then
    return font("GH ✗", "#FF4444", 10), false
end

local runs = data.workflow_runs
local in_progress = #active_runs

local bar
if in_progress > 0 then
    bar = font("⚡ " .. in_progress .. " running", "#FFAA00", 10)
else
    local latest = runs[1]
    if latest then
        local conclusion = latest.conclusion or "unknown"
        local icon_str = conclusion == "success" and "✓" or (conclusion == "failure" and "✗" or "?")
        local c = conclusion == "success" and "#33CC33" or (conclusion == "failure" and "#FF4444" or "#888888")
        bar = font(icon_str .. " " .. (latest.name or "CI"):sub(1, 20), c, 10)
    else
        bar = font("GH: no runs", "#888", 9)
    end
end

local rows = {}
for i = 1, math.min(#active_runs, 3) do
    local r = active_runs[i]
    rows[#rows + 1] = { "▶ " .. (r.name or "?"):sub(1, 25), "running", r.head_branch or "" }
end
for i = 1, math.min(#runs, 12) do
    local r = runs[i]
    local conclusion = r.conclusion or "?"
    local icon_str = conclusion == "success" and "✓" or (conclusion == "failure" and "✗" or "○")
    rows[#rows + 1] = { icon_str .. " " .. (r.name or "?"):sub(1, 25), conclusion, r.head_branch or "" }
end

local detail = dialog({
    title = "GitHub CI - " .. repo,
    width = 440, height = 380,
    refresh = 30,
    content = {
        { type = "text", value = repo, color = "#4FC3F7", size = 12, bold = true },
        { type = "text", value = in_progress > 0 and (in_progress .. " workflows running") or "All quiet", color = in_progress > 0 and "#FFAA00" or "#33CC33", size = 10 },
        { type = "hr" },
        { type = "table", columns = {"Workflow", "Result", "Branch"}, rows = rows },
    }
})

return bar, true, detail
