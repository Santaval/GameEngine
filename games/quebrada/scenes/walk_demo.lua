-- Demo del walker (issue #61): movimiento top-down, 4 direcciones, camara y NPC.
-- WASD o flechas para andar, Shift para correr, 0 vuelve al demo de efectos.
-- El NPC que patrulla es la Llorona (audio espacial, issue #63): acercate y oye el
-- paneo; 1 activa/desactiva la mentira de distancia.
-- Una tecla por nombre de accion: WASD y flechas son nombres distintos.
-- Pensado para 480x270 logico (pixel_perfect). Teclas SDL: Right 1073741903,
-- Left 1073741904, Down 1073741905, Up 1073741906, LShift 1073742049, RShift 1073742053.

local function walker(x, y, script)
    return {
        components = {
            transform = { position = { x = x, y = y }, scale = { x = 1, y = 1 } },
            rigid_body = {},
            sprite = { assetId = "dummy", width = 24, height = 38 },
            animation = { atlas = "dummy", tag = "idle_down" },
            box_collider = { width = 14, height = 8, offset_x = 5, offset_y = 28, solid = true, mover = true },
            script = { path = "scripts/" .. script .. ".lua" },
        },
    }
end

scene = {
    sprites = {
        [0] =
        { assetId = "hero", filePath = "sprites/hero.png", atlas = "sprites/hero.json" },
        { assetId = "dummy", filePath = "sprites/dummy.png", atlas = "sprites/dummy.json" },
    },
    fonts = {},
    sounds = {
        [0] =
        -- La Llorona (issue #63): el NPC la emite con volumen y paneo por distancia
        { assetId = "llorona", filePath = "sounds/llorona.mp3", stream = true },
        -- Pasos por superficie (issue #65); este demo no tiene mapa: todo es lastre
        { assetId = "step_lastre_walk", filePath = "sounds/sfx/sfx_step_lastre_walk.mp3" },
        { assetId = "step_lastre_run", filePath = "sounds/sfx/sfx_step_lastre_run.mp3" },
        { assetId = "step_zacate_walk", filePath = "sounds/sfx/sfx_step_zacate_walk.mp3" },
        { assetId = "step_zacate_run", filePath = "sounds/sfx/sfx_step_zacate_run.mp3" },
        { assetId = "step_madera_walk", filePath = "sounds/sfx/sfx_step_madera_walk.mp3" },
        { assetId = "step_madera_run", filePath = "sounds/sfx/sfx_step_madera_run.mp3" },
        { assetId = "step_concreto_walk", filePath = "sounds/sfx/sfx_step_concreto_walk.mp3" },
        { assetId = "step_concreto_run", filePath = "sounds/sfx/sfx_step_concreto_run.mp3" },
    },
    -- Ducking por defecto (issue #64): mientras la Llorona (bus voice) suena, musica y ambiente bajan
    audio = { duck = { amount = 0.35, fade_ms = 300 } },
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
        { name = "lie", key = 49 },         -- 1: mentira de distancia de la Llorona
        { name = "music_vol", key = 109 },  -- m: volumen de la musica (bus music)
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
