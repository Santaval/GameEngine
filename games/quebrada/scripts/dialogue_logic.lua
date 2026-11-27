-- Logica pura del dialogo (issue #50): UTF-8 sin la libreria utf8 (el motor no la abre),
-- ajuste de linea por palabras, paginado, maquina de escribir y maquina de estados.
local M = {}

local CHAR_PAT = "[\1-\127\194-\244][\128-\191]*"

-- Lista de caracteres UTF-8 de s
function M.chars(s)
  local out = {}
  for ch in s:gmatch(CHAR_PAT) do out[#out + 1] = ch end
  return out
end

-- Cantidad de caracteres UTF-8
function M.len(s)
  local n = 0
  for _ in s:gmatch(CHAR_PAT) do n = n + 1 end
  return n
end

-- Los primeros n caracteres (nunca corta un caracter multibyte)
function M.prefix(s, n)
  if n <= 0 then return "" end
  local count = 0
  for pos in s:gmatch("()" .. CHAR_PAT) do
    count = count + 1
    if count > n then return s:sub(1, pos - 1) end
  end
  return s
end

-- Une partes con "\n" (table.concat no esta disponible)
local function join(parts)
  local s = ""
  for i = 1, #parts do s = s .. (i > 1 and "\n" or "") .. parts[i] end
  return s
end

-- Parte una palabra mas ancha que max_w por caracteres; devuelve el resto
local function break_word(word, max_w, measure, out)
  local cur = ""
  for _, ch in ipairs(M.chars(word)) do
    local c2 = cur .. ch
    if cur ~= "" and measure(c2) > max_w then
      out[#out + 1] = cur
      cur = ch
    else
      cur = c2
    end
  end
  return cur
end

-- Ajuste voraz por palabras. measure(s) -> ancho. "\n" es salto de parrafo.
function M.wrap(text, max_w, measure)
  local lines = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local cur = ""
    for word in para:gmatch("%S+") do
      local cand = (cur == "") and word or (cur .. " " .. word)
      if measure(cand) <= max_w then
        cur = cand
      else
        if cur ~= "" then lines[#lines + 1] = cur end
        if measure(word) <= max_w then
          cur = word
        else
          cur = break_word(word, max_w, measure, lines)
        end
      end
    end
    lines[#lines + 1] = cur
  end
  return lines
end

-- Agrupa lineas en paginas de per_page lineas; cada pagina es un string con "\n"
function M.paginate(lines, per_page)
  local pages = {}
  local i = 1
  while i <= #lines do
    local chunk = {}
    for k = i, math.min(i + per_page - 1, #lines) do chunk[#chunk + 1] = lines[k] end
    pages[#pages + 1] = join(chunk)
    i = i + per_page
  end
  if #pages == 0 then pages[1] = "" end
  return pages
end

-- Seleccion de opcion con tope (sin dar la vuelta)
function M.move(sel, dir, n)
  local s = sel + dir
  if s < 1 then s = 1 end
  if s > n then s = n end
  return s
end

-- Estado de una linea de dialogo. phase: reveal -> wait | choose -> done
function M.new(pages, nchoices, cps)
  return { pages = pages, page = 1, shown = 0, phase = "reveal",
           sel = 1, nchoices = nchoices or 0, cps = cps or 40 }
end

function M.visible(st)
  return M.prefix(st.pages[st.page], math.floor(st.shown))
end

-- inp = { confirm, up, down } (flancos). Devuelve evento: "page" | "done" | "chosen", idx
-- La primera pulsacion en "reveal" solo salta la revelacion (no avanza tambien)
function M.step(st, dt, inp)
  if st.phase == "reveal" then
    local total = M.len(st.pages[st.page])
    st.shown = st.shown + st.cps * dt
    if inp.confirm then st.shown = total end -- saltar la revelacion
    if st.shown >= total then
      st.shown = total
      if st.page == #st.pages and st.nchoices > 0 then
        st.phase = "choose"
        st.sel = 1
      else
        st.phase = "wait"
      end
    end
    return nil
  elseif st.phase == "wait" then
    if inp.confirm then
      if st.page < #st.pages then
        st.page = st.page + 1
        st.shown = 0
        st.phase = "reveal"
        return "page"
      end
      st.phase = "done"
      return "done"
    end
  elseif st.phase == "choose" then
    if inp.up then st.sel = M.move(st.sel, -1, st.nchoices) end
    if inp.down then st.sel = M.move(st.sel, 1, st.nchoices) end
    if inp.confirm then
      st.phase = "done"
      return "chosen", st.sel
    end
  end
  return nil
end

return M
