-- Entry scene of Quebrada (loaded by `make run-quebrada`).
-- Also a demo of Aseprite atlas animations (#45): sprites/fx.png + fx.json.
-- Keys 1-4 restart each effect from its first frame.
local hello = require("hello")
local ui = require("ui_helpers")

print("[quebrada] " .. hello.greet())

local function effect(x, tag, script, loop)
    return {
        components = {
            transform = { position = { x = x, y = 300 }, scale = { x = 4, y = 4 } },
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
    },
    entities = {
        [0] =
        effect(200, "burst", "fx_burst", false),   -- once, uneven durations (press 1)
        effect(450, "spin", "fx_spin", true),      -- forward, 100/200/100/300 ms (press 2)
        effect(700, "spin_rev", "fx_spin_rev", true), -- reverse (press 3)
        effect(950, "glow", "fx_glow", true),      -- pingpong (press 4)
    },
}
