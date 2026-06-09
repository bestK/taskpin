-- animation_demo.lua - Animation effects showcase
-- @name Animation Demo

return "Animation", true, dialog({
    title = "Animation Demo",
    width = 340,
    height = 400,
    refresh = 50,
    render = function()
        local items = {}

        -- Title
        items[#items+1] = { type = "text", value = "Animation Demo", color = "#ffffff", size = 14, bold = true, align = "center" }
        items[#items+1] = { type = "hr" }

        -- 1. Blink
        if animation.blink("blink_dot", 600) then
            items[#items+1] = { type = "text", value = "● Blink: visible", color = "#ff6b6b" }
        else
            items[#items+1] = { type = "text", value = "○ Blink: hidden", color = "#555555" }
        end

        -- 2. Breathing color
        local t = animation.ping_pong("breath_pp", 2000)
        local r = math.max(0, math.floor(0x1a + (0x00 - 0x1a) * t))
        local g = math.max(0, math.floor(0x1a + (0xd4 - 0x1a) * t))
        local b = math.max(0, math.floor(0x2e + (0xff - 0x2e) * t))
        items[#items+1] = { type = "text", value = "◆ Breathing Color", color = string.format("#%02x%02x%02x", r, g, b), size = 11 }

        -- 3. Pulse text size
        local s = animation.pulse("size_pulse", 1500, 9, 14)
        items[#items+1] = { type = "text", value = "◈ Pulse Size", color = "#ffd93d", size = math.floor(s) }

        -- 4. Spinner
        local frames = {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"}
        local st = animation.loop("spin", 800)
        local idx = math.floor(st * #frames) + 1
        if idx > #frames then idx = #frames end
        items[#items+1] = { type = "text", value = frames[idx] .. " Loading spinner", color = "#6bcb77" }

        -- 5. Progress bar
        local p = animation.loop("progress_bar", 4000)
        local eased = animation.ease_in_out(p)
        local width = 24
        local filled = math.floor(width * eased)
        items[#items+1] = { type = "text", value = string.rep("━", filled) .. "●" .. string.rep("─", width - filled), color = "#4ecdc4", size = 10 }

        -- 6. Staggered list (items appear one by one, loop every 4s)
        local texts = {"→ First item", "→ Second item", "→ Third item", "→ Fourth item"}
        local cycle = animation.elapsed("stagger_cycle") % 4000
        local visible_count = math.floor(cycle / 300) + 1
        if visible_count > #texts then visible_count = #texts end
        for i = 1, visible_count do
            local brightness = math.min(255, 80 + i * 40)
            items[#items+1] = { type = "text", value = texts[i], color = string.format("#%02x%02x%02x", brightness, brightness, brightness) }
        end

        -- 7. Bounce
        local bt = animation.loop("bounce_loop", 2000)
        local bv = animation.bounce(bt)
        local dots = math.floor(bv * 10)
        items[#items+1] = { type = "text", value = string.rep("•", dots + 1) .. " bounce", color = "#a855f7" }

        return items
    end
})
