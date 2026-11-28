-- Demo de puertas, interiores y zonas (issue #62): interior de la casa.
-- WASD o flechas para andar, Shift corre, E / Enter interactua con la puerta,
-- F alterna el flag unlock.house.chayo (depuracion), 0 vuelve a la escena principal,
-- N alterna dia / noche (ambiente, issue #65; al amanecer pasa al dia siguiente, issue #70), F3 abre el overlay de flags y misiones (issue #51).
-- Mama tiene la historia "El chequelo" (issue #68): E la escucha; Espacio pausa, Retroceso o Q detienen.
-- Pensado para 480x270 logico (pixel_perfect). Teclas SDL: Right 1073741903,
-- Left 1073741904, Down 1073741905, Up 1073741906, LShift 1073742049, RShift 1073742053.
scene = {
    sprites = {
        [0] =
        { assetId = "hero", filePath = "sprites/hero.png", atlas = "sprites/hero.json" },
        { assetId = "dummy", filePath = "sprites/dummy.png", atlas = "sprites/dummy.json" },
    },
    fonts = {
        [0] =
        { fontId = "default", filePath = "@common/fonts/DejaVuSansMono.ttf", fontSize = 10 },
        { fontId = "dialogue", filePath = "@common/fonts/DejaVuSansMono.ttf", fontSize = 16 },
    },
    -- Pasos por superficie y ambiente de la casa (issue #65)
    sounds = {
        [0] =
        { assetId = "step_lastre_walk", filePath = "sounds/sfx/sfx_step_lastre_walk.mp3" },
        { assetId = "step_lastre_run", filePath = "sounds/sfx/sfx_step_lastre_run.mp3" },
        { assetId = "step_zacate_walk", filePath = "sounds/sfx/sfx_step_zacate_walk.mp3" },
        { assetId = "step_zacate_run", filePath = "sounds/sfx/sfx_step_zacate_run.mp3" },
        { assetId = "step_madera_walk", filePath = "sounds/sfx/sfx_step_madera_walk.mp3" },
        { assetId = "step_madera_run", filePath = "sounds/sfx/sfx_step_madera_run.mp3" },
        { assetId = "step_concreto_walk", filePath = "sounds/sfx/sfx_step_concreto_walk.mp3" },
        { assetId = "step_concreto_run", filePath = "sounds/sfx/sfx_step_concreto_run.mp3" },
        { assetId = "amb_casa_day", filePath = "sounds/amb/amb_casa_day.mp3", stream = true },
        { assetId = "amb_casa_night", filePath = "sounds/amb/amb_casa_night.mp3", stream = true },
        { assetId = "sfx_libreta_new", filePath = "sounds/sfx/sfx_new.mp3" }, -- aviso "Nuevo" (issue #80)
        -- Grabacion completa de la leyenda (issue #68): en streaming
        { assetId = "story_chequelo", filePath = "sounds/stories/chequelo.mp3", stream = true },
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
        { name = "toggle_time", key = 110 }, -- n: dia / noche
        { name = "tool1", key = 49 },  -- 1-4: elegir herramienta (issue #53)
        { name = "tool2", key = 50 },
        { name = "tool3", key = 51 },
        { name = "tool4", key = 52 },
        { name = "tool_use", key = 120 }, -- x: usar la herramienta elegida
        { name = "debug_overlay", key = 1073741884 }, -- F3: overlay de flags y misiones
        { name = "libreta", key = 9 },       -- Tab: libreta (issue #80)
        { name = "libreta_alt", key = 108 }, -- l
        { name = "story_pause", key = 32 },      -- Espacio: pausa / reanudar la historia
        { name = "story_stop", key = 8 },        -- Retroceso: detener (Esc cierra el motor)
        { name = "story_stop_alt", key = 113 },  -- q
    },
    entities = {
        [0] =
        {
            -- Entidad auxiliar: controlador de mapa (puertas, zonas, fundido)
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/house_scene.lua" },
            },
        },
        {
            components = {
                transform = { position = { x = 88, y = 104 }, scale = { x = 1, y = 1 } },
                rigid_body = {},
                sprite = { assetId = "dummy", width = 24, height = 38 },
                animation = { atlas = "dummy", tag = "idle_down" },
                box_collider = { width = 14, height = 8, offset_x = 5, offset_y = 28, solid = true, mover = true },
                script = { path = "scripts/house_player.lua" },
            },
        },
    },
}
