-- Logica pura de consecuencias (issue #70): seleccion de comentarios y validacion.
-- Sin motor, sin os ni io.
local M = {}

function M.key_seen(id) return "comment." .. id .. ".seen" end

-- Entradas de `who` cuyo `when` se cumple (check) y que no son `once` ya vistas (seen(id)).
-- Devuelve lines (planas, en orden), matched (las entradas).
function M.pick(entries, who, check, seen)
  local lines, matched = {}, {}
  for _, e in ipairs(entries or {}) do
    if e.who == who and not (e.once and seen(e.id)) and check(e.when) then
      for _, l in ipairs(e.lines or {}) do lines[#lines + 1] = l end
      matched[#matched + 1] = e
    end
  end
  return lines, matched
end

-- errors (graves) y warns de la lista de entradas
function M.validate(entries)
  local errors, warns = {}, {}
  local ids = {}
  for i, e in ipairs(entries or {}) do
    local tag = "#" .. i .. " " .. tostring(e.id)
    if type(e.id) ~= "string" or e.id == "" then
      errors[#errors + 1] = "entrada " .. i .. ": falta id"
    elseif ids[e.id] then
      errors[#errors + 1] = tag .. ": id repetido"
    else
      ids[e.id] = true
    end
    if type(e.who) ~= "string" or e.who == "" then
      errors[#errors + 1] = tag .. ": falta who (valor de la propiedad npc)"
    end
    local tw = type(e.when)
    if not (e.when == nil or tw == "function" or tw == "string" or tw == "boolean") then
      errors[#errors + 1] = tag .. ": when debe ser function, texto o boolean"
    end
    if type(e.lines) ~= "table" or #e.lines == 0 then
      errors[#errors + 1] = tag .. ": lines vacio"
    else
      for k, l in ipairs(e.lines) do
        if type(l) ~= "table" or type(l.text) ~= "string" or l.text == "" then
          errors[#errors + 1] = tag .. ": linea " .. k .. " sin text"
        elseif not l.speaker then
          warns[#warns + 1] = tag .. ": linea " .. k .. " sin speaker"
        end
      end
    end
    if e.when == nil then warns[#warns + 1] = tag .. ": sin when (siempre se cumple)" end
  end
  return errors, warns
end

return M
