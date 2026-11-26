-- Demo del walker (issue #61): movimiento top-down, 4 direcciones, camara y NPC.
-- WASD o flechas para andar, Shift para correr, 0 vuelve al demo de efectos.
-- Una tecla por nombre de accion: WASD y flechas son nombres distintos.
-- Pensado para 480x270 logico (pixel_perfect). Teclas SDL: Right 1073741903,
-- Left 1073741904, Down 1073741905, Up 1073741906, LShift 1073742049, RShift 1073742053.

local function walker(x, y, script)
    return {
        components = {
            transform = { position = { x = x, y = y }, scale = { x = 1, y = 1 } },
            rigid_body = {},
            sprite = { assetId = "hero", width = 16, height = 16 },
            animation = { atlas = "hero", tag = "idle_down" },
            box_collider = { width = 10, height = 8, offset_x = 3, offset_y = 8, solid = true, mover = true },
            script = { path = "scripts/" .. script .. ".lua" },
        },
    }
end

scene = {
    sprites = {
        [0] =
        { assetId = "hero", filePath = "sprites/hero.png", atlas = "sprites/hero.json" },
    },
    fonts = {},
    keys = {
        [0] =
        { name = "walk_up", key = 119 },    -- w
        { name = "walk_up_alt", key = 1073741906 },
        { name = "walk_down", key = 115 },  -- s
        { name = "walk_down_alt", key = 1073741905 },
        { name = "walk_left", key = 97 },   -- a
        { name = "walk_left_alt", key = 1073741904 },
        { name = "walk_right", key = 100 }, -- d
        { name = "walk_right_alt", key = 1073741903 },
        { name = "run", key = 1073742049 },
        { name = "run_alt", key = 1073742053 },
        { name = "back", key = 48 },        -- 0
    },
    entities = {
        [0] =
        {
            -- Entidad auxiliar: muros estaticos y dibujo del mundo
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/walk_demo_world.lua" },
            },
        },
        walker(80, 60, "walk_demo_player"),
        walker(400, 380, "walk_demo_npc"),
    },
}
