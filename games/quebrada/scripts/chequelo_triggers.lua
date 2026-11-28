-- Triggers de la noche del chequelo en zona1 (issue #78). Los llama triggers.lua; la tabla
-- de cada trigger tiene on_enter(g) y/o on_exit(g). Los `sets` y la `line` del TMX los aplica
-- triggers.lua despues del handler. Docs: games/quebrada/docs/zona1.md
local ws = require("world_state")
local missions = require("missions")
local logic = require("triggers_logic")

local M = {}

-- Flags de la caminata: se limpian al empezar para poder repetirla (p. ej. tras F3)
local WALK_FLAGS = {
  "chequelo.on_road", "chequelo.off_road", "chequelo.light_appears", "chequelo.detour",
  "chequelo.detour_cafetal", "chequelo.detour_door", "chequelo.arrived", "chequelo.silbidos",
}

-- Primer desvio: no cambia si ya hay uno; los desvios no terminan la noche
local function detour(kind)
  if not ws.get("chequelo.detour") then ws.set("chequelo.detour", kind) end
end

-- La puerta de la iglesia: empieza la noche (accepted -> night_active, de noche y tarjeta de titulo)
M.walk_start = {
  on_enter = function()
    for _, f in ipairs(WALK_FLAGS) do ws.set(f, nil) end
    missions.start_night("chequelo")
  end,
}

-- Estar en el camino; salir de el despues de que aparece la luz = off_road
M.road = {
  on_enter = function() ws.set("chequelo.on_road", true) end,
  on_exit = function()
    ws.set("chequelo.on_road", nil)
    if ws.has("chequelo.light_appears") and missions.state("chequelo") == "night_active" then
      ws.set("chequelo.off_road", true)
    end
  end,
}

M.detour_cafetal = { on_enter = function() detour("detour_cafetal") end }
M.detour_door = { on_enter = function() detour("detour_door") end }

-- Llegar a la puerta de mama termina la noche: amanece (on_complete) y autoguarda
M.house_arrival = {
  on_enter = function()
    ws.set("chequelo.arrived", true) -- antes de complete: el autoguardado ya lo incluye
    ws.set("regreso.pendiente", true) -- el amanecer espera a que mama reciba al jugador (chequelo_day)
    missions.complete("chequelo", logic.outcome(ws.get("chequelo.detour")))
    require("chequelo_day").go_home()
  end,
}

-- light_appears: flag y frase; la luz visible la dibuja companion_light.lua (issue #81); sin handler

return M
