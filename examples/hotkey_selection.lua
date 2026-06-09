-- hotkey_selection.lua - 快捷键获取选中内容演示
-- @hotkey Ctrl+8
-- @bar_width 160
-- @param HOTKEY string 快捷键(默认 Ctrl+Shift+Q, 冲突请修改)

if not selection then
    return font("📋 选词就绪", "#888", 9), true, nil, "按 Ctrl+Shift+Q 获取选中内容"
end

if selection.type == "text" and selection.text ~= "" then
    local text = selection.text
    local preview = #text > 40 and text:sub(1, 40) .. "..." or text
    local char_count = #text
    local word_count = 0
    for _ in text:gmatch("%S+") do word_count = word_count + 1 end

    local bar = font("📋 ", nil, 9) .. font(preview, "#4FC3F7", 9)

    local info = dialog({
        title = "选中内容",
        width = 420, height = 280,
        content = {
            { type = "text", value = "选中文本", color = "#4FC3F7", size = 12, bold = true },
            { type = "hr" },
            { type = "text", value = text, size = 9 },
            { type = "hr" },
            { type = "text", value = "字符: " .. char_count .. "  词: " .. word_count, color = "#888", size = 9 },
        }
    })
    return bar, true, info, "选中: " .. preview

elseif selection.type == "files" and selection.files then
    local count = #selection.files
    local bar = font("📁 " .. count .. " 个文件", "#81C784", 9)

    local rows = {}
    for i, f in ipairs(selection.files) do
        if i > 10 then break end
        local name = f:match("([^\\/]+)$") or f
        rows[#rows + 1] = { tostring(i), name }
    end

    local info = dialog({
        title = "选中文件",
        width = 400, height = 300,
        content = {
            { type = "text", value = "选中 " .. count .. " 个文件", color = "#81C784", size = 12, bold = true },
            { type = "hr" },
            { type = "table", columns = {"#", "文件名"}, rows = rows },
        }
    })
    return bar, true, info, count .. " 个文件"

elseif selection.type == "image" then
    return font("🖼️ 图片已捕获", "#CE93D8", 9), true, nil, "图片: " .. selection.image

else
    return font("📋 无选中内容", "#888", 9), true, nil, "未检测到选中内容"
end
