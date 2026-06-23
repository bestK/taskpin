-- asxs_billing_state.lua - ASXS 计费状态 + 服务可用性
-- @name ASXS 状态
-- @refresh 30000
-- @bar_width 220
-- @param token string Bearer Token

local billing_url = "https://api.asxs.top/api/me/billing/state"
local status_url = "https://api.asxs.top/api/me/status/dashboard?period=1h"
local logs_url = "https://api.asxs.top/api/me/amp/request-logs?page=1&pageSize=20&includeTotal=false"

local token = args.token or sys.env("ASXS_TOKEN")
if not token or token == "" then
    return font("ASXS: 缺少 token", "#F44336", 9), true, nil, "请在参数 token 或环境变量 ASXS_TOKEN 中填写 Bearer Token"
end

if token:sub(1, 7) ~= "Bearer " then
    token = "Bearer " .. token
end

local headers = table.concat({
    "Accept: */*",
    "Accept-Language: zh-CN",
    "Authorization: " .. token,
    "Cache-Control: no-cache",
    "Content-Type: application/json",
    "Pragma: no-cache",
    "Referer: https://api.asxs.top/",
    "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}, "\r\n")

-- 计费状态
local billing = nil
local resp = http.get(billing_url, nil, headers)
if resp then
    local ok, data = pcall(json.decode, resp)
    if ok and type(data) == "table" then
        billing = data
    end
end

-- 服务状态
local status_data = nil
local status_err = nil
local resp2 = http.get(status_url, nil, headers)
if resp2 then
    local ok, data = pcall(json.decode, resp2)
    if ok and type(data) == "table" then
        status_data = data
    else
        status_err = "解析失败"
    end
else
    status_err = "请求失败"
end

-- === 构建任务栏显示 ===
local bar_parts = {}

-- 计费部分
if billing then
    local sub = billing.subscription or {}
    local win = billing.windows and billing.windows[1] or {}
    local plan = sub.planName or "未知"
    local state = sub.status or "unknown"
    local limit = (win.limitMicros or 0) / 1000000
    local left = (win.leftMicros or 0) / 1000000
    local percent = 0
    if limit > 0 then percent = left * 100 / limit end
    local bcolor = "#4CAF50"
    if state ~= "active" then bcolor = "#F44336"
    elseif percent <= 10 then bcolor = "#FF9800" end
    bar_parts[#bar_parts + 1] = font(string.format("%s %.1f%%", plan, percent), bcolor, 9)
else
    bar_parts[#bar_parts + 1] = font("计费: 请求失败", "#F44336", 9)
end

-- 服务可用性概要
if status_data then
    local groups = status_data.groups or {}
    local ok_count, err_count = 0, 0
    for _, g in ipairs(groups) do
        for _, item in ipairs(g.items or {}) do
            if item.latest and item.latest.status == "operational" then
                ok_count = ok_count + 1
            else
                err_count = err_count + 1
            end
        end
    end
    local scolor = "#4CAF50"
    if err_count == ok_count + err_count and err_count > 0 then scolor = "#F44336"
    elseif err_count > 0 then scolor = "#FF9800" end
    bar_parts[#bar_parts + 1] = font(string.format(" | %d/%d", ok_count, ok_count + err_count), scolor, 9)
else
    bar_parts[#bar_parts + 1] = font(" | 服务: 请求失败", "#F44336", 9)
end

-- === 构建 Dialog ===
local function value_or_dash(value)
    if value == nil or value == "" then
        return "-"
    end
    return tostring(value)
end

local function short_time(value)
    if not value or value == "" then
        return "-"
    end
    return value:gsub("T", " "):gsub("%.%d+Z$", ""):gsub("Z$", "")
end

local function append_dialog_content(dlg_content)
    -- 计费详情
    if billing then
        local sub = billing.subscription or {}
        local win = billing.windows and billing.windows[1] or {}
        local plan = sub.planName or "未知套餐"
        local state = sub.status or "unknown"
        local expires = sub.expiresAt or "未知"
        local balance = billing.balanceUsd or "0.000000"
        local limit = (win.limitMicros or 0) / 1000000
        local used = (win.usedMicros or 0) / 1000000
        local left = (win.leftMicros or 0) / 1000000
        local percent = 0
        if limit > 0 then percent = used * 100 / limit end

        dlg_content[#dlg_content + 1] = { type = "text", value = plan, color = "#4FC3F7", size = 14, bold = true }
        dlg_content[#dlg_content + 1] = { type = "hr" }
        dlg_content[#dlg_content + 1] = { type = "table",
            columns = { "项目", "值" },
            col_widths = { 120, 0 },
            rows = {
                { "状态", state },
                { "余额", "$" .. balance },
                { "今日额度", string.format("%.2f", limit) },
                { "已用", string.format("%.2f (%.2f%%)", used, percent) },
                { "剩余", string.format("%.2f", left) },
                { "到期", expires },
            } }
    else
        dlg_content[#dlg_content + 1] = { type = "text", value = "计费状态: 请求失败", color = "#F44336", size = 14, bold = true }
        dlg_content[#dlg_content + 1] = { type = "hr" }
    end

    -- 服务状态
    if status_data then
        local groups = status_data.groups or {}
        local all_items = {}
        for _, g in ipairs(groups) do
            for _, item in ipairs(g.items or {}) do
                item.group_name = g.groupName
                all_items[#all_items + 1] = item
            end
        end

        local ok_count, err_count = 0, 0
        for _, item in ipairs(all_items) do
            if item.latest and item.latest.status == "operational" then
                ok_count = ok_count + 1
            else
                err_count = err_count + 1
            end
        end

        local scolor = "#4CAF50"
        if err_count == #all_items and err_count > 0 then scolor = "#F44336"
        elseif err_count > 0 then scolor = "#FF9800" end

        dlg_content[#dlg_content + 1] = { type = "hr" }
        dlg_content[#dlg_content + 1] = { type = "text", value = string.format("服务状态 · %d/%d 正常", ok_count, #all_items), color = scolor, size = 14, bold = true }
        dlg_content[#dlg_content + 1] = { type = "hr" }

        local rows = {}
        for _, item in ipairs(all_items) do
            local status = item.latest and item.latest.status or "unknown"
            local stext = status == "operational" and "正常" or (status == "error" and "故障" or status)
            local avail = item.availability and item.availability.availabilityPct or 0
            local succ = item.requestSuccess and item.requestSuccess.successRatePct or 0
            rows[#rows + 1] = {
                item.name,
                stext,
                string.format("%.0f%%", avail),
                string.format("%.0f%%", succ)
            }
        end

        dlg_content[#dlg_content + 1] = { type = "table",
            columns = { "服务", "状态", "可用率", "成功率" },
            col_widths = { 0, 70, 70, 70 },
            rows = rows }
    else
        dlg_content[#dlg_content + 1] = { type = "hr" }
        dlg_content[#dlg_content + 1] = { type = "text", value = "服务状态: " .. (status_err or "未知"), color = "#F44336", size = 14, bold = true }
    end
end

local info = dialog({
    title = "ASXS 状态",
    width = 760,
    height = 680,
    render = function()
        local dlg_content = {}
        append_dialog_content(dlg_content)

        local logs = nil
        local logs_err = nil
        local resp3 = http.get(logs_url, nil, headers)
        if resp3 then
            local ok, data = pcall(json.decode, resp3)
            if ok and type(data) == "table" then
                logs = data.items or {}
            else
                logs_err = "解析失败"
            end
        else
            logs_err = "请求失败"
        end

        dlg_content[#dlg_content + 1] = { type = "hr" }
        dlg_content[#dlg_content + 1] = { type = "text", value = "最近请求 · 前 5 条", color = "#4FC3F7", size = 14, bold = true }
        dlg_content[#dlg_content + 1] = { type = "hr" }

        if logs then
            local rows = {}
            local count = math.min(5, #logs)
            for i = 1, count do
                local item = logs[i]
                rows[#rows + 1] = {
                    short_time(item.createdAt),
                    value_or_dash(item.status),
                    value_or_dash(item.mappedModel or item.originalModel),
                    value_or_dash(item.channelName or item.provider),
                    item.latencyMs and (tostring(item.latencyMs) .. " ms") or "-",
                    item.costUsd and ("$" .. tostring(item.costUsd)) or "-"
                }
            end

            if #rows > 0 then
                dlg_content[#dlg_content + 1] = { type = "table",
                    columns = { "时间", "状态", "模型", "通道", "延迟", "费用" },
                    col_widths = { 150, 70, 130, 90, 80, 80 },
                    rows = rows }
            else
                dlg_content[#dlg_content + 1] = { type = "text", value = "暂无请求日志", color = "#9E9E9E", size = 11 }
            end
        else
            dlg_content[#dlg_content + 1] = { type = "text", value = "请求日志: " .. (logs_err or "未知"), color = "#F44336", size = 12 }
        end

        return dlg_content
    end
})

-- 合并 bar_parts 中的 font span
local bar_text = bar_parts[1]
for i = 2, #bar_parts do
    bar_text = bar_text .. bar_parts[i]
end

return bar_text, true, info
