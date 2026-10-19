-- all_items.lua — Phase 6 dialog fixture.
-- Exercises EVERY DialogItem type plus the row/button action paths that no
-- example script reaches (row_urls/row_cmds are empty in every shipped
-- example). Captured through engine_cli so the golden is real engine output,
-- not hand-written JSON.
local bar = font("All", "#FFFFFF", 9)

local info = dialog({
    title = "All Items",
    width = 360, height = 300,
    refresh = 0,
    borderless = false,
    clickthrough = false,
    opacity = 255,
    content = {
        { type = "text", value = "Plain text", color = "#CCCCCC", size = 10 },
        { type = "text", value = "Bold short hex", color = "#ABC", size = 12, bold = true },
        { type = "text", value = "Inline icon", color = "#D97757", size = 10,
          image = "https://example.com/icon.png", image_width = 16, image_height = 16 },
        { type = "hr" },
        { type = "table",
          columns = { "Name", "State" },
          rows = {
              { "alpha", "up" },
              { "beta", "down", url = "https://example.com/beta" },
              { "gamma", "flat", cmd = "echo gamma" },
          } },
        { type = "image", source = "https://example.com/pic.png", width = 48, height = 48 },
        { type = "button", value = "Open site", url = "https://example.com/", bg = "#333333", color = "#4FC3F7" },
        { type = "button", value = "Run command", cmd = "echo hello", bg = "#333333", color = "#FF6666" },
    }
})

return bar, true, info
