-- dino_runner.lua - Chrome Dino Game on TaskPin bar
-- @realtime
-- @bar_width 360

local VK_SPACE = 0x20
local VK_UP    = 0x26

local GROUND = "▁"
local WIDTH = 40
local DINO_POS = 4
local JUMP_HEIGHT = 5
local JUMP_DURATION_MS = 500

if not _G._dino or not _G._dino.last_time then
    math.randomseed(os.time())
    _G._dino = {
        y = 0,
        jumping = false,
        jump_start = 0,
        obstacles = {},
        score = 0,
        speed = 12,
        alive = true,
        next_spawn = 1.5,
        high_score = 0,
        last_time = os.clock(),
        spawn_timer = 0,
    }
end

local g = _G._dino
local now = os.clock()
local dt = now - g.last_time
g.last_time = now
if dt > 0.2 then dt = 0.05 end

-- Input
local jump_pressed = false
if sys.key_triggered then
    local sp = sys.key_triggered(VK_SPACE)
    local up = sys.key_triggered(VK_UP)
    jump_pressed = sp or up
elseif sys.key_pressed then
    jump_pressed = sys.key_pressed(VK_SPACE) or sys.key_pressed(VK_UP)
end
-- Debug: show key state in score area
local dbg = jump_pressed and "J" or "."

if not g.alive then
    if not g.death_time then g.death_time = now end
    if jump_pressed and (now - g.death_time) > 1.0 then
        g.alive = true
        g.y = 0
        g.jumping = false
        g.obstacles = {}
        g.score = 0
        g.speed = 12
        g.spawn_timer = 0
        g.next_spawn = 1.5
        g.death_time = nil
    end
    local bar = font("GAME OVER ", "#FF3333", 9)
        .. font("Score:" .. math.floor(g.high_score) .. " ", "#FFAA00", 9)
        .. font("[Space] Restart", "#888888", 8)
    return bar, false
end

-- Jump
if jump_pressed and not g.jumping then
    g.jumping = true
    g.jump_start = now
end

-- Physics: parabolic arc based on real time
if g.jumping then
    local elapsed = (now - g.jump_start) * 1000
    local t = elapsed / JUMP_DURATION_MS * 2 - 1
    g.y = JUMP_HEIGHT * (1 - t * t)
    if elapsed >= JUMP_DURATION_MS then
        g.y = 0
        g.jumping = false
    end
end

-- Spawn obstacles
g.spawn_timer = g.spawn_timer + dt
if g.spawn_timer >= g.next_spawn then
    g.spawn_timer = 0
    local kind = math.random(1, 5)
    local flying = (kind >= 4)
    g.obstacles[#g.obstacles + 1] = { x = WIDTH + 2, kind = kind, flying = flying }
    g.next_spawn = 0.8 + math.random() * 1.0
end

-- Move obstacles
local new_obs = {}
for _, obs in ipairs(g.obstacles) do
    obs.x = obs.x - g.speed * dt
    if obs.x > -2 then
        new_obs[#new_obs + 1] = obs
    end
end
g.obstacles = new_obs

-- Collision
for _, obs in ipairs(g.obstacles) do
    local ox = math.floor(obs.x)
    if ox >= DINO_POS - 1 and ox <= DINO_POS + 1 then
        if obs.flying then
            if g.y > 1 then
                g.alive = false
                if g.score > g.high_score then g.high_score = g.score end
            end
        else
            if g.y < 2 then
                g.alive = false
                if g.score > g.high_score then g.high_score = g.score end
            end
        end
    end
end

-- Score & speed
g.score = g.score + dt * 2
g.speed = 12 + g.score / 20

-- Render
local sky = {}
local ground_arr = {}
for i = 1, WIDTH do sky[i] = " "; ground_arr[i] = GROUND end

-- Background
local bg_phase = math.floor(now * 2) % WIDTH
local sun_pos = ((WIDTH - 5) - math.floor(bg_phase / 3)) % WIDTH + 1
local cloud1_pos = ((WIDTH - 12) - math.floor(bg_phase / 2)) % WIDTH + 1
local cloud2_pos = ((WIDTH - 25) - math.floor(bg_phase / 2)) % WIDTH + 1
local is_night = (math.floor(g.score / 100) % 2 == 1)

if sun_pos >= 1 and sun_pos <= WIDTH then sky[sun_pos] = is_night and "🌙" or "☀" end
if cloud1_pos >= 1 and cloud1_pos <= WIDTH then sky[cloud1_pos] = "☁" end
if cloud2_pos >= 1 and cloud2_pos <= WIDTH then sky[cloud2_pos] = "☁" end

-- Place obstacles
for _, obs in ipairs(g.obstacles) do
    local ox = math.floor(obs.x)
    if ox >= 1 and ox <= WIDTH then
        if obs.flying then
            sky[ox] = (obs.kind == 4) and "🦅" or "🕊️"
        else
            ground_arr[ox] = "🌵"
        end
    end
end

-- Render with crab
local dino_in_sky = (g.y > 1)

local sky_pre, sky_post = "", ""
local gnd_pre, gnd_post = "", ""
for i = 1, WIDTH do
    if i < DINO_POS then
        sky_pre = sky_pre .. sky[i]
        gnd_pre = gnd_pre .. ground_arr[i]
    elseif i > DINO_POS then
        sky_post = sky_post .. sky[i]
        gnd_post = gnd_post .. ground_arr[i]
    end
end

local bar
if dino_in_sky then
    bar = font(dbg .. tostring(math.floor(g.score)) .. " ", "#FFAA00", 8)
        .. font(sky_pre, "#555555", 7)
        .. font("🦀", "#FF6347", 7)
        .. font(sky_post, "#555555", 7)
        .. font("\n")
        .. font("   ", nil, 8)
        .. font(gnd_pre .. GROUND .. gnd_post, "#66BB6A", 7)
else
    bar = font(dbg .. tostring(math.floor(g.score)) .. " ", "#FFAA00", 8)
        .. font(sky_pre .. " " .. sky_post, "#555555", 7)
        .. font("\n")
        .. font("   ", nil, 8)
        .. font(gnd_pre, "#66BB6A", 7)
        .. font("🦀", "#FF6347", 7)
        .. font(gnd_post, "#66BB6A", 7)
end

return bar, false
