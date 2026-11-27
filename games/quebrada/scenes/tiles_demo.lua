-- Demo del tileset del pueblo (issue #55): maps/tiles_demo.tmx dibujado con load_tile_map.
-- Misma escena que town_demo.lua (controles y teclas iguales) pero con otro mapa y script.
-- Se abre con la tecla 8 en la escena principal.
-- (Texto original de town_demo.lua:) Demo de puertas, interiores y zonas (issue #62): el barrio.
-- WASD o flechas para andar, Shift corre, E / Enter interactua con la puerta,
-- F alterna el flag unlock.house.chayo (depuracion), 0 vuelve a la escena principal,
-- N alterna dia / noche (ambiente, issue #65; al amanecer pasa al dia siguiente, issue #70), F3 abre el overlay de flags y misiones (issue #51).
-- G enciende / apaga el foco del jugador (issue #67).
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
        { fontId = "dialogue", filePath = "@common/fonts/DejaVuSansMono.ttf", fontSize = 16 },
    },
    -- Pasos por superficie (issue #65) y ambiente por zona/hora (issue #65)
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
        -- Bucles de ambiente: en streaming (solo se decodifican al sonar)
        { assetId = "amb_pueblo_day", filePath = "sounds/amb/amb_pueblo_day.mp3", stream = true },
        { assetId = "sfx_libreta_new", filePath = "sounds/sfx/sfx_new.mp3" }, -- aviso "Nuevo" (issue #80)
        -- Grabacion de la leyenda para volver a oirla desde la libreta (issue #80)
        { assetId = "story_chequelo", filePath = "sounds/stories/chequelo.mp3", stream = true },
        { assetId = "amb_pueblo_night", filePath = "sounds/amb/amb_pueblo_night.mp3", stream = true },
        { assetId = "amb_monte_day", filePath = "sounds/amb/amb_monte_day.mp3", stream = true },
        { assetId = "amb_monte_night", filePath = "sounds/amb/amb_monte_night.mp3", stream = true },
        { assetId = "amb_quebrada_day", filePath = "sounds/amb/amb_quebrada_day.mp3", stream = true },
        { assetId = "amb_quebrada_night", filePath = "sounds/amb/amb_quebrada_night.mp3", stream = true },
        -- Sonidos de un disparo del ambiente (pasan cerca del jugador)
        { assetId = "moto_pass_01", filePath = "sounds/sfx/sfx_moto_pass_01.mp3" },
        { assetId = "moto_pass_02", filePath = "sounds/sfx/sfx_moto_pass_02.mp3" },
        { assetId = "moto_pass_03", filePath = "sounds/sfx/sfx_moto_pass_03.mp3" },
        { assetId = "moto_far_01", filePath = "sounds/sfx/sfx_moto_far_01.mp3" },
        { assetId = "dog_far_01", filePath = "sounds/sfx/sfx_dog_far_01.mp3" },
        { assetId = "dog_far_02", filePath = "sounds/sfx/sfx_dog_far_02.mp3" },
        { assetId = "dog_far_03", filePath = "sounds/sfx/sfx_dog_far_03.mp3" },
        { assetId = "dog_far_04", filePath = "sounds/sfx/sfx_dog_far_04.mp3" },
        { assetId = "rooster_far_01", filePath = "sounds/sfx/sfx_rooster_far_01.mp3" },
        { assetId = "rooster_far_02", filePath = "sounds/sfx/sfx_rooster_far_02.mp3" },
        { assetId = "dogs_chorus_far_01", filePath = "sounds/sfx/sfx_dogs_chorus_far_01.mp3" },
        { assetId = "dogs_chorus_far_02", filePath = "sounds/sfx/sfx_dogs_chorus_far_02.mp3" },
        { assetId = "dogs_chorus_far_03", filePath = "sounds/sfx/sfx_dogs_chorus_far_03.mp3" },
        { assetId = "owl_01", filePath = "sounds/sfx/sfx_owl_01.mp3" },
        { assetId = "owl_02", filePath = "sounds/sfx/sfx_owl_02.mp3" },
        { assetId = "owl_03", filePath = "sounds/sfx/sfx_owl_03.mp3" },
        { assetId = "owl_04", filePath = "sounds/sfx/sfx_owl_04.mp3" },
        { assetId = "wind_gust", filePath = "sounds/sfx/sfx_wind_gust.mp3" },
        { assetId = "cow_far_01", filePath = "sounds/sfx/sfx_cow_far_01.mp3" },
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
        { name = "story_pause", key = 32 },      -- Espacio: pausa / reanudar la historia (repeticion desde la libreta)
        { name = "story_stop", key = 8 },        -- Retroceso: detener
        { name = "story_stop_alt", key = 113 },  -- q
    },
    entities = {
        [0] =
        {
            -- Entidad auxiliar: controlador de mapa (puertas, zonas, fundido)
            components = {
                transform = { position = { x = 0, y = 0 } },
                script = { path = "scripts/tiles_scene.lua" },
            },
        },
        {
            components = {
                transform = { position = { x = 128, y = 172 }, scale = { x = 1, y = 1 } },
                rigid_body = {},
                sprite = { assetId = "hero", width = 16, height = 16 },
                animation = { atlas = "hero", tag = "idle_down" },
                box_collider = { width = 10, height = 8, offset_x = 3, offset_y = 8, solid = true, mover = true },
                script = { path = "scripts/town_player.lua" },
            },
        },
    },
}
