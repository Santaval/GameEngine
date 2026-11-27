-- Entry scene of Quebrada (loaded by `make run-quebrada`).
-- Also a demo of Aseprite atlas animations (#45): sprites/fx.png + fx.json.
-- Laid out for a 480x270 logical size (pixel_perfect); fine at 1280x720 too.
-- Keys 1-4 restart each effect from its first frame. Key 5 opens the top-down
-- walker demo (#61), key 6 the doors/interiors/zones demo (#62); key 0 there
-- comes back here. Key 7 continues the saved game (#52). Key 8 opens the tileset demo (#55), key 9 the buildings demo (#71).
local hello = require("hello")
local ui = require("ui_helpers")

print("[quebrada] " .. hello.greet())

local function effect(x, tag, script, loop)
    return {
        components = {
            transform = { position = { x = x, y = 100 }, scale = { x = 2, y = 2 } },
            sprite = { assetId = "fx", width = 32, height = 32 },
            animation = { atlas = "fx", tag = tag, loop = loop },
            script = { path = "scripts/" .. script .. ".lua" },
        },
    }
end

scene = {
    sprites = {
        [0] =
        { assetId = "fx", filePath = "sprites/fx.png", atlas = "sprites/fx.json" },
    },
    fonts = {},
    keys = {
        [0] =
        { name = "fx1", key = 49 },
        { name = "fx2", key = 50 },
        { name = "fx3", key = 51 },
        { name = "fx4", key = 52 },
        { name = "walkdemo", key = 53 }, -- 5
        { name = "towndemo", key = 54 }, -- 6
        { name = "continue", key = 55 }, -- 7
        { name = "tilesdemo", key = 56 }, -- 8
        { name = "buildingsdemo", key = 57 }, -- 9
    },
    entities = {
        [0] =
        effect(40, "burst", "fx_burst", false),   -- once, uneven durations (press 1)
        effect(150, "spin", "fx_spin", true),      -- forward, 100/200/100/300 ms (press 2)
        effect(260, "spin_rev", "fx_spin_rev", true), -- reverse (press 3)
        effect(370, "glow", "fx_glow", true),      -- pingpong (press 4)
        {
            -- Press 5: load the walker demo
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/walk_demo_launch.lua" },
            },
        },
        {
            -- Press 6: load the doors / interiors / zones demo
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/town_demo_launch.lua" },
            },
        },
        {
            -- Press 8: load the town tileset demo (#55)
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/tiles_demo_launch.lua" },
            },
        },
        {
            -- Press 9: load the buildings demo (#71)
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/buildings_demo_launch.lua" },
            },
        },
        {
            -- Press 7: continue the saved game
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/continue_launch.lua" },
            },
        },
    },
}
