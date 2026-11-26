-- Entry scene of Quebrada (loaded by `./engine --game quebrada`).
-- `require` resolves from assets/quebrada/scripts/ and assets/common/scripts/.
local hello = require("hello")
local ui = require("ui_helpers")

print("[quebrada] " .. hello.greet())

scene = {
    sprites = {},
    fonts = {},
    keys = {},
    entities = {},
}
