-- Demo de puertas, interiores y zonas (issue #62): el barrio.
-- WASD o flechas para andar, Shift corre, E / Enter interactua con la puerta,
-- F alterna el flag house.chayo.open (depuracion), 0 vuelve a la escena principal.
-- Pensado para 480x270 logico (pixel_perfect). Teclas SDL: Right 1073741903,
-- Left 1073741904, Down 1073741905, Up 1073741906, LShift 1073742049, RShift 1073742053.
scene = {
    sprites = {
        [0] =
        { assetId = "hero", filePath = "sprites/hero.png", atlas = "sprites/hero.json" },
    },
    fonts = {
        [0] =
        { fontId = "default", filePath = "@common/fonts/DejaVuSansMono.ttf", fontSize = 10 },
    },
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
        { name = "interact", key = 101 },   -- e
        { name = "interact_alt", key = 13 }, -- Enter
        { name = "debug_toggle", key = 102 }, -- f
        { name = "back", key = 48 },        -- 0
    },
    entities = {
        [0] =
        {
            -- Entidad auxiliar: controlador de mapa (puertas, zonas, fundido)
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/town_scene.lua" },
            },
        },
        {
            components = {
                transform = { position = { x = 312, y = 292 }, scale = { x = 1, y = 1 } },
                rigid_body = {},
                sprite = { assetId = "hero", width = 16, height = 16 },
                animation = { atlas = "hero", tag = "idle_down" },
                box_collider = { width = 10, height = 8, offset_x = 3, offset_y = 8, solid = true, mover = true },
                script = { path = "scripts/town_player.lua" },
            },
        },
    },
}
