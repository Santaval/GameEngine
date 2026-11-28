-- Controlador de la escena de la zona 1 (scenes/main.lua, issue #78): la iglesia y su calle de adoquin.
-- Triggers de la noche del chequelo y emisores de sonido los atiende town_controller.
-- La puerta de la casa de mama (door_mama, al fondo del lastre) lleva al interior y vuelve aqui por exit_mama (house_scene.lua tiene zona1 en `scenes`).
local ws = require("world_state")
local missions = require("missions")
local npc = require("npc_placeholder")
local home_hint = require("home_hint")
local blackout = require("blackout")
local night_npcs = require("night_npcs")
local silbido = require("silbido")
local day_npcs = require("day_npcs")

update = require("town_controller").make_update({
  map = "maps/zona1.tmx",
  tile_map = true,
  world_debug = false,
  companion = true, -- luz companera de la noche del chequelo (issue #81)
  back_scene = false, -- esta es la escena principal: la tecla 0 no vuelve a ningun lado
  scenes = {
    ["maps/zona1.tmx"] = "scenes/main.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
    ["maps/house_paula.tmx"] = "scenes/house_paula.lua",
  },
  -- Noche del chequelo: vecinos que apuran, guia de regreso a casa y sonidos del apagon (silbido, caballos)
  on_tick = function(dt, idx, map)
    night_npcs.tick(dt, idx, map)
    day_npcs.tick(dt)
    home_hint.tick(dt, idx)
    blackout.tick(dt)
    silbido.tick(dt)
  end,
  -- Entrada desde el lanzador (tecla z): si la mision aun no se decidio, la deja aceptada como si
  -- mama ya hubiera hablado (los hooks reales ponen la noche y flags). Si ya esta decidida, usa F3.
  on_start = function()
    if not ws.has("zona1.demo_start") then return end
    ws.set("zona1.demo_start", nil)
    -- Placeholder de mama (issue #56), a un costado del jugador que nace en x = 4632, y = 1788.
    -- Solo en el atajo del lanzador: en la partida real mama vive en su casa (issue #82)
    npc.spawn({ id = "mama", x = 4680, y = 1788, dir = "down" })
    if missions.state("chequelo") == "none" then
      missions.offer("chequelo")
      missions.accept("chequelo")
      ws.set("mama.avisada", true)
    end
  end,
})
