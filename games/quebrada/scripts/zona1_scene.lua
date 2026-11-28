-- Controlador de la escena de la zona 1 (scenes/zona1.lua, issue #78): la iglesia y su calle de adoquin.
-- Triggers de la noche del chequelo y emisores de sonido los atiende town_controller.
-- La puerta de la casa de mama (door_mama, al fondo del lastre) lleva al interior y vuelve aqui por exit_mama (house_scene.lua tiene zona1 en `scenes`).
local ws = require("world_state")
local missions = require("missions")
local npc = require("npc_placeholder")

update = require("town_controller").make_update({
  map = "maps/zona1.tmx",
  tile_map = true,
  world_debug = false,
  scenes = {
    ["maps/zona1.tmx"] = "scenes/zona1.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
    ["maps/house_paula.tmx"] = "scenes/house_paula.lua",
  },
  -- Entrada desde el lanzador (tecla z): si la mision aun no se decidio, la deja aceptada como si
  -- mama ya hubiera hablado (los hooks reales ponen la noche y flags). Si ya esta decidida, usa F3.
  on_start = function()
    -- Placeholder de mama (issue #56), a un costado del jugador que nace en x = 4632, y = 1788
    npc.spawn({ id = "mama", x = 4680, y = 1788, dir = "down" })
    if not ws.has("zona1.demo_start") then return end
    ws.set("zona1.demo_start", nil)
    if missions.state("chequelo") == "none" then
      missions.offer("chequelo")
      missions.accept("chequelo")
      ws.set("mama.avisada", true)
    end
  end,
})
