-- Demo of the Aseprite atlas animations (#45). Each effect entity runs its own
-- update() built here: a key restarts a tag (edge-detected, is_action_activated
-- reports "held"), and a loop=false tag logs once when it finishes.
local M = {}

function M.make_update(action, tag, loop)
  local was_down = false
  local announced = false
  return function()
    local down = is_action_activated(action)
    if down and not was_down then
      play_animation(this, tag, loop)
      announced = false
      print("[fx] play_animation(" .. tag .. ", loop=" .. tostring(loop) .. ")")
    end
    was_down = down
    if not loop and not announced and animation_finished(this) then
      announced = true
      print("[fx] " .. tag .. " finished")
    end
  end
end

return M
