-- Entry scene of Quebrada (loaded by `make run-quebrada`).
-- `require` resolves from games/quebrada/scripts/ and engine/common/scripts/.
local hello = require("hello")
local ui = require("ui_helpers")

print("[quebrada] " .. hello.greet())

scene = {
    sprites = {},
    fonts = {},
    keys = {},
    entities = {},
}
