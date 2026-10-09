-- Prueba del mapa (issues #16, #17 y #19): determinismo, biomas, planetas y
-- contenido de los chunks y megaestructuras del reactor. Se corre desde la raiz del repo:
--   lua5.3 tests/map_determinism.lua
-- Sin motor: solo map_config, map_grid, map_biomes, map_chunks, map_reactor y
-- los config.

package.path = "./assets/scripts/?.lua;" .. package.path

-- math.random no puede intervenir en la generacion del mapa: si alguien lo usa,
-- la prueba falla en vez de pasar por casualidad
math.random = function()
  error("math.random no se debe usar en la generacion del mapa")
end

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. " (esperado " .. tostring(b) .. ", obtenido " .. tostring(a) .. ")")
end

local cfg = require("map_config")
local grid = require("map_grid")
local chunks = require("map_chunks")
local biomes = require("map_biomes")
local reactor = require("map_reactor")
local solar = require("solar_system_config")
local asteroid_cfg = require("asteroid_config")

-- Serializa todo el mundo a un string: posiciones, tipos, escalas, rotaciones,
-- velocidades, pecios, deriva, ids y planetas
local function serialize(world, seed)
  local keys = {}
  for key in pairs(world) do keys[#keys + 1] = key end
  -- Orden estable sin table.sort: insercion simple
  for i = 2, #keys do
    local v, j = keys[i], i - 1
    while j >= 1 and keys[j] > v do
      keys[j + 1] = keys[j]
      j = j - 1
    end
    keys[j + 1] = v
  end

  local parts = {}
  for _, key in ipairs(keys) do
    for _, s in ipairs(world[key]) do
      parts[#parts + 1] = string.format("%s|%.6f,%.6f|k%d|s%.6f|r%.6f|v%.6f,%.6f|w%s|d%s|c%s",
        s.chunk_id, s.pos.x, s.pos.y, s.kind, s.scale, s.rot, s.vel.x, s.vel.y,
        tostring(s.wreck), tostring(s.drift), tostring(s.cull))
    end
  end
  -- Los planetas tambien forman parte del mundo
  for _, p in ipairs(biomes.layout(seed).planets) do
    parts[#parts + 1] = string.format("%s|%.6f,%.6f|%s|%d", p.name, p.x, p.y, p.role, p.range)
  end
  -- Y las megaestructuras del reactor
  for _, site in ipairs(reactor.sites(seed)) do
    parts[#parts + 1] = string.format("%s|%.6f,%.6f|%d|%.6f|%d|%d", site.variant, site.x, site.y,
      #site.colliders, site.radius, #site.pieces, #site.gaps)
  end
  return table.concat(parts, ";")
end

-- Misma semilla -> mismo mundo; otra semilla -> otro mundo
local a = serialize(chunks.generate_world(12345), 12345)
local b = serialize(chunks.generate_world(12345), 12345)
local c = serialize(chunks.generate_world(54321), 54321)
check(#a > 0, "el mundo no esta vacio")
check(a == b, "generate_world(12345) es identico en dos llamadas")
check(a ~= c, "una semilla distinta da un mundo distinto")

-- Cada roca esta dentro del mundo y todos los chunks existen
local world = chunks.generate_world(12345)
local total = 0
local CHUNKS = cfg.SECTORS * cfg.CHUNKS_PER_SECTOR
for cy = 0, CHUNKS - 1 do
  for cx = 0, CHUNKS - 1 do
    local list = world[grid.chunk_key(cx, cy)]
    check(list ~= nil, "existe el chunk " .. cx .. ":" .. cy)
    total = total + #list
    for _, s in ipairs(list) do
      check(s.pos.x >= 0 and s.pos.x < cfg.WORLD_SIZE and s.pos.y >= 0 and s.pos.y < cfg.WORLD_SIZE,
        "roca dentro del mundo: " .. s.chunk_id)
      check(s.world == true, "roca con world: " .. s.chunk_id)
    end
  end
end
check(total > 0, "se generaron rocas")

-- Hash y RNG
eq(grid.hash(1, 2, 3), grid.hash(1, 2, 3), "hash estable")
check(grid.hash(1, 2, 3) ~= grid.hash(1, 3, 2), "hash distingue cx de cy")
check(grid.hash(1, 2, 3) ~= grid.hash(2, 2, 3), "hash depende de la semilla")
check(grid.hash(1, 2, 3) <= 0xFFFFFFFF, "hash cabe en 32 bits")
local r1, r2 = grid.rng(99), grid.rng(99)
for _ = 1, 50 do
  local v = r1.next()
  check(v >= 0 and v < 1, "next() en [0,1)")
  eq(v, r2.next(), "rng reproducible")
end
local r3 = grid.rng(7)
for _ = 1, 200 do
  local n = r3.int(3, 5)
  check(n >= 3 and n <= 5 and math.type(n) == "integer", "int(3,5) entero en rango")
end

-- Ayudantes de rejilla
local sx, sy = grid.world_to_sector(19999, 0)
eq(sx, 4, "world_to_sector x"); eq(sy, 0, "world_to_sector y")
sx, sy = grid.world_to_sector(99999, -5)
eq(sx, 4, "world_to_sector recorta x"); eq(sy, 0, "world_to_sector recorta y")
local cx, cy = grid.world_to_chunk(2000, 3999)
eq(cx, 1, "world_to_chunk x"); eq(cy, 1, "world_to_chunk y")
local bx, by, bw, bh = grid.sector_bounds(2, 2)
eq(bx, 8000, "sector_bounds x"); eq(by, 8000, "sector_bounds y")
eq(bw, 4000, "sector_bounds w"); eq(bh, 4000, "sector_bounds h")
eq(grid.chunk_key(3, 7), "3:7", "chunk_key")
local minX, minY, maxX, maxY = grid.active_bounds(0, 0)
eq(minX, 0, "active_bounds minX"); eq(minY, 0, "active_bounds minY")
eq(maxX, 6000, "active_bounds maxX"); eq(maxY, 6000, "active_bounds maxY")
minX, minY, maxX, maxY = grid.active_bounds(10000, 10000)
eq(minX, 6000, "active_bounds centro minX"); eq(maxX, 16000, "active_bounds centro maxX")

-- ---------------------------------------------------------------------
--  Biomas, planetas y contenido de los chunks (issue #17)
-- ---------------------------------------------------------------------

local SEEDS = 200
local valid = {}
for _, b in ipairs(cfg.BIOMES) do valid[b.id] = true end
local function contains(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end
local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- La sal no cambia el hash sin sal y si lo cambia con sal
eq(grid.hash(1, 2, 3, nil), grid.hash(1, 2, 3), "hash sin sal igual")
check(grid.hash(1, 2, 3, 1) ~= grid.hash(1, 2, 3), "hash con sal distinto")
check(grid.hash(1, 2, 3, 1) ~= grid.hash(1, 2, 3, 2), "sales distintas dan hashes distintos")
-- Valores fijos del hash sin sal (calculados antes de anadir la sal)
eq(grid.hash(12345, 4, 7), 1997987304, "hash(12345,4,7) no cambia")
eq(grid.hash(0, 0, 0), 3502349708, "hash(0,0,0) no cambia")

-- Biomas: ids validos, centro planetary y vecinos ortogonales distintos
-- salvo debris (las diagonales pueden repetir)
for seed = 1, SEEDS do
  local layout = biomes.layout(seed)
  local bg = layout.biomes
  local mid = cfg.SECTORS // 2
  check(contains(cfg.CENTER_BIOMES, bg[mid][mid]), "centro dentro de CENTER_BIOMES, semilla " .. seed)
  eq(bg[mid][mid], "planetary", "el centro es siempre planetary, semilla " .. seed)
  for sy = 0, cfg.SECTORS - 1 do
    for sx = 0, cfg.SECTORS - 1 do
      check(valid[bg[sx][sy]], "bioma valido, semilla " .. seed)
      for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
        local o = bg[sx + d[1]] and bg[sx + d[1]][sy + d[2]]
        if o ~= nil and o == bg[sx][sy] and o ~= cfg.BIOME_REPEAT_OK then
          check(false, string.format("vecinos repetidos %s en (%d,%d), semilla %d", o, sx, sy, seed))
        end
      end
    end
  end

  -- Planetas: 1-3 por sector Planetary y ninguno fuera; separacion y pozo dentro del sector
  local perSector = {}
  for _, p in ipairs(layout.planets) do
    local k = p.sector.x .. ":" .. p.sector.y
    perSector[k] = (perSector[k] or 0) + 1
    check(bg[p.sector.x][p.sector.y] == "planetary", "planeta solo en Planetary, semilla " .. seed)
    local bx, by, bw, bh = grid.sector_bounds(p.sector.x, p.sector.y)
    check(p.x - p.range >= bx and p.x + p.range <= bx + bw
      and p.y - p.range >= by and p.y + p.range <= by + bh,
      "pozo de gravedad dentro del sector, semilla " .. seed)
    check(p.role == "mining" or p.mineral == nil, "solo mining mantiene mineral")
    check(dist(p.x, p.y, cfg.PLAYER_SPAWN.x, cfg.PLAYER_SPAWN.y) >= p.range + cfg.SPAWN_CLEAR_PAD - 1e-6,
      "ningun pozo cubre la aparicion, semilla " .. seed)
  end
  for sy = 0, cfg.SECTORS - 1 do
    for sx = 0, cfg.SECTORS - 1 do
      local n = perSector[sx .. ":" .. sy] or 0
      if bg[sx][sy] == "planetary" then
        check(n >= cfg.PLANETS_PER_SECTOR.min and n <= cfg.PLANETS_PER_SECTOR.max,
          "1-3 planetas por sector Planetary, semilla " .. seed)
      else
        check(n == 0, "sin planetas fuera de Planetary, semilla " .. seed)
      end
    end
  end
  for i = 1, #layout.planets do
    for j = i + 1, #layout.planets do
      local a, b = layout.planets[i], layout.planets[j]
      if a.sector.x == b.sector.x and a.sector.y == b.sector.y then
        check(dist(a.x, a.y, b.x, b.y) >= cfg.PLANET_SPACING_FACTOR * (a.range + b.range) - 1e-6,
          "separacion entre planetas, semilla " .. seed)
      end
    end
  end
end

-- build_planets no cambia tras sacar planet_from_body (Tierra: valores conocidos)
local earth = solar.find_planet(solar.build_planets(), "Tierra")
eq(earth.scale, 3.0, "Tierra scale"); eq(earth.body_radius, 66.0, "Tierra body_radius")
eq(earth.mass, 1500, "Tierra mass"); eq(earth.range, 510, "Tierra range")
eq(earth.x, 23800.0, "Tierra x"); eq(earth.mineral, "iron", "Tierra mineral")
eq(earth.mine_interval, 2, "Tierra mine_interval")

-- Chunks: cuenta por bioma, separacion global, planetas, deriva y pecios
local bodyRadius = asteroid_cfg.ASTEROID_SHEET.bodyRadius
local CELL = cfg.CHUNK_SIZE
local drift_total, rock_total = 0, 0
for seed = 1, 5 do
  local layout = biomes.layout(seed)
  local w = chunks.generate_world(seed)
  local sites = reactor.sites(seed)
  local function bucket(map, x, y, item)
    local key = math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
    map[key] = map[key] or {}
    table.insert(map[key], item)
  end
  local function near(map, x, y, fn)
    local gx, gy = math.floor(x / CELL), math.floor(y / CELL)
    for ix = gx - 1, gx + 1 do
      for iy = gy - 1, gy + 1 do
        for _, o in ipairs(map[ix .. ":" .. iy] or {}) do fn(o) end
      end
    end
  end

  for cy = 0, CHUNKS - 1 do
    for cx = 0, CHUNKS - 1 do
      local sx, sy = grid.world_to_sector(cx * cfg.CHUNK_SIZE, cy * cfg.CHUNK_SIZE)
      local biome = layout.biomes[sx][sy]
      local list = w[grid.chunk_key(cx, cy)]
      local nLarge, nSmall = 0, 0
      for _, s in ipairs(list) do
        local scale = s.scale
        local x = s.pos.x + asteroid_cfg.ASTEROID_SHEET.frameSize * scale / 2
        local y = s.pos.y + asteroid_cfg.ASTEROID_SHEET.frameSize * scale / 2
        local radius = bodyRadius * scale
        if scale >= cfg.ROCK_SIZES.large.min then
          nLarge = nLarge + 1
        else
          nSmall = nSmall + 1
        end

        rock_total = rock_total + 1
        for _, p in ipairs(layout.planets) do
          check(dist(x, y, p.x, p.y) >= p.range + radius, "roca fuera del pozo de un planeta: " .. s.chunk_id)
        end

        if s.drift then
          drift_total = drift_total + 1
          local speed = math.sqrt(s.vel.x ^ 2 + s.vel.y ^ 2)
          check(speed >= cfg.DRIFT.speed.min - 1e-6 and speed <= cfg.DRIFT.speed.max + 1e-6, "velocidad de deriva")
          check(s.cull ~= true and s.despawn_far == true, "la deriva no se duerme y se borra al salir")
          check(not s.wreck, "un pecio no deriva")
          local ux, uy = s.vel.x / speed, s.vel.y / speed
          for _, p in ipairs(layout.planets) do
            local rx, ry = p.x - x, p.y - y
            local t = rx * ux + ry * uy
            local d = t < 0 and dist(x, y, p.x, p.y) or dist(rx, ry, t * ux, t * uy)
            check(d > p.range + radius, "el rumbo de una roca no cruza un planeta: " .. s.chunk_id)
          end
          for _, site in ipairs(sites) do
            local rx, ry = site.x - x, site.y - y
            local t = rx * ux + ry * uy
            local d = t < 0 and dist(x, y, site.x, site.y) or dist(rx, ry, t * ux, t * uy)
            check(d > site.radius + cfg.REACTOR.clear_pad + radius,
              "el rumbo de una roca no cruza un sitio del reactor: " .. s.chunk_id)
          end
        else
          check(s.cull == true, "roca estatica con cull: " .. s.chunk_id)
          eq(s.vel.x, 0, "roca estatica sin velocidad")
        end

        if s.wreck then
          check(biome == "debris" or biome == "reactor", "pecio solo en debris/reactor: " .. s.chunk_id)
          check(scale >= cfg.ROCK_SIZES.large.min, "pecio grande: " .. s.chunk_id)
          check(asteroid_cfg.WRECK_TYPES[s.wreck] ~= nil, "pecio valido")
        end
      end

      local largeMax = (biome == "dense_belt" and cfg.LARGE_ROCKS_DENSE or cfg.LARGE_ROCKS).max
      local largeMin = (biome == "dense_belt" and cfg.LARGE_ROCKS_DENSE or cfg.LARGE_ROCKS).min
      check(nLarge <= largeMax, "rocas grandes <= maximo en " .. cx .. ":" .. cy)
      if biome == "deep_void" then
        eq(nSmall, 0, "sin rocas pequenas en deep_void " .. cx .. ":" .. cy)
      else
        check(nSmall <= cfg.SMALL_ROCKS.max, "rocas pequenas <= maximo en " .. cx .. ":" .. cy)
      end

      -- Lejos del borde del mundo y de cualquier pozo: salen todas las rocas
      local bx, by, bw, bh = grid.chunk_bounds(cx, cy)
      local clear = cx > 0 and cy > 0 and cx < CHUNKS - 1 and cy < CHUNKS - 1
      for _, p in ipairs(layout.planets) do
        if p.x + p.range > bx and p.x - p.range < bx + bw and p.y + p.range > by and p.y - p.range < by + bh then
          clear = false
        end
      end
      -- Ni donde una megaestructura del reactor quita rocas
      for _, site in ipairs(sites) do
        local reach = site.radius + cfg.REACTOR.clear_pad
        if site.x + reach > bx and site.x - reach < bx + bw and site.y + reach > by and site.y - reach < by + bh then
          clear = false
        end
      end
      if clear then
        check(nLarge >= largeMin, "rocas grandes >= minimo en " .. cx .. ":" .. cy)
        if biome ~= "deep_void" then
          check(nSmall >= cfg.SMALL_ROCKS.min, "rocas pequenas >= minimo en " .. cx .. ":" .. cy)
        end
      end
    end
  end

  -- Separacion en todo el mundo (no solo por chunk), con cubos de CELL px
  local all = {}
  for _, list in pairs(w) do
    for _, s in ipairs(list) do
      local scale = s.scale
      local cxp = s.pos.x + asteroid_cfg.ASTEROID_SHEET.frameSize * scale / 2
      local cyp = s.pos.y + asteroid_cfg.ASTEROID_SHEET.frameSize * scale / 2
      all[#all + 1] = { x = cxp, y = cyp, large = scale >= cfg.ROCK_SIZES.large.min, id = s.chunk_id }
    end
  end
  local grid_map = {}
  for _, o in ipairs(all) do bucket(grid_map, o.x, o.y, o) end
  for _, o in ipairs(all) do
    near(grid_map, o.x, o.y, function(q)
      if q ~= o and q.id < o.id then
        local d = dist(o.x, o.y, q.x, q.y)
        if o.large and q.large then
          check(d >= cfg.LARGE_SPACING - 1e-6, "separacion entre rocas grandes: " .. o.id .. " " .. q.id)
        elseif not o.large and not q.large then
          check(d >= cfg.SMALL_SPACING - 1e-6, "separacion entre rocas pequenas: " .. o.id .. " " .. q.id)
        end
      end
    end)
  end
end

-- Aproximadamente una de cada cinco rocas deriva (DRIFT.chance = 0.2)
local share = drift_total / rock_total
check(share >= 0.1 and share <= 0.3, "proporcion de deriva en [0.1, 0.3]: " .. share)

-- Se generan pecios
local wrecks = 0
for seed = 1, 20 do
  for _, list in pairs(chunks.generate_world(seed)) do
    for _, s in ipairs(list) do if s.wreck then wrecks = wrecks + 1 end end
  end
end
check(wrecks > 0, "se generan pecios")

-- ---------------------------------------------------------------------
--  Reactor Remains (issue #19): sitios, rocas, pecios y huecos
-- ---------------------------------------------------------------------

local RC = cfg.REACTOR

-- Firma de un sitio: todo lo que depende de la semilla
local function site_signature(site)
  local parts = { site.variant, site.sx, site.sy, string.format("%.6f,%.6f,%.6f", site.x, site.y, site.rot) }
  for _, p in ipairs(site.pieces) do
    parts[#parts + 1] = string.format("%s,%.6f,%.6f,%.6f,%.6f,%.6f", p.asset, p.x, p.y, p.w, p.h, p.rot)
  end
  for _, c in ipairs(site.colliders) do
    parts[#parts + 1] = string.format("%.6f,%.6f,%.6f", c.x, c.y, c.r)
  end
  for _, g in ipairs(site.gaps) do
    parts[#parts + 1] = string.format("%.6f,%.6f", g.x, g.y)
  end
  return table.concat(parts, ";")
end

-- Determinismo: la cache guarda pocas semillas, asi que tras pedir otras la
-- semilla 77 se calcula de nuevo desde cero
local seed77 = {}
for i, site in ipairs(reactor.sites(77)) do seed77[i] = site_signature(site) end
for other = 1000, 1020 do reactor.sites(other) end
local again = reactor.sites(77)
eq(#again, #seed77, "mismo numero de sitios al recalcular")
for i, site in ipairs(again) do eq(site_signature(site), seed77[i], "sitio " .. i .. " identico al recalcular") end

local variantsSeen, siteTotal = {}, 0
local halfSector = cfg.SECTOR_SIZE / 2
for seed = 1, SEEDS do
  local layout = biomes.layout(seed)
  local sites = reactor.sites(seed)

  -- Exactamente un sitio por sector reactor, en orden de lectura
  local expected = {}
  for sy = 0, cfg.SECTORS - 1 do
    for sx = 0, cfg.SECTORS - 1 do
      if layout.biomes[sx][sy] == "reactor" then expected[#expected + 1] = { sx, sy } end
    end
  end
  eq(#sites, #expected, "un sitio por sector reactor, semilla " .. seed)
  for i, site in ipairs(sites) do
    siteTotal = siteTotal + 1
    variantsSeen[site.variant] = true
    check(expected[i] ~= nil and site.sx == expected[i][1] and site.sy == expected[i][2],
      "sitios en orden de lectura, semilla " .. seed)
    eq(site.index, i, "indice del sitio")
    local bx, by, bw, bh = grid.sector_bounds(site.sx, site.sy)
    eq(site.x, bx + bw / 2, "el sitio esta en el centro del sector (x)")
    eq(site.y, by + bh / 2, "el sitio esta en el centro del sector (y)")
    check(site.variant == "ring" or site.variant == "hull", "variante valida")
    check(#site.pieces > 0 and #site.colliders > 0, "el sitio tiene piezas y colliders")
    eq(#site.gaps, 4, "cuatro huecos por sitio")
    eq(site.core.x, site.x, "el nucleo esta en el centro (x)")
    check(site.core.size == RC.core_size, "tamano del nucleo")

    -- Todo cabe en el sector sin tocar la franja de tormenta
    local minX, maxX = math.max(bx, cfg.STORM_BAND), math.min(bx + bw, cfg.WORLD_SIZE - cfg.STORM_BAND)
    local minY, maxY = math.max(by, cfg.STORM_BAND), math.min(by + bh, cfg.WORLD_SIZE - cfg.STORM_BAND)
    local radius = 0
    for _, c in ipairs(site.colliders) do
      check(c.x - c.r >= minX and c.x + c.r <= maxX and c.y - c.r >= minY and c.y + c.r <= maxY,
        "collider dentro del sector y de la franja de tormenta, semilla " .. seed)
      radius = math.max(radius, dist(c.x, c.y, site.x, site.y) + c.r)
    end
    check(math.abs(site.radius - radius) < 1e-6, "radio del sitio = circulo mas lejano")

    -- Se puede pasar por los huecos: ningun circulo a menos de ship_clearance
    -- del centro del hueco. En el casco ademas el hueco mide al menos min_gap
    for _, g in ipairs(site.gaps) do
      local nearest = math.huge
      for _, c in ipairs(site.colliders) do
        nearest = math.min(nearest, dist(c.x, c.y, g.x, g.y) - c.r)
      end
      check(nearest >= RC.ship_clearance, string.format(
        "hueco libre (%.1f px de holgura), semilla %d sitio %d", nearest, seed, i))
      if site.variant == "hull" then
        check(nearest * 2 >= RC.min_gap, string.format(
          "hueco del casco de al menos %d px (holgura %.1f), semilla %d", RC.min_gap, nearest, seed))
      end
    end
  end

  -- blocks: un disco sobre el centro del sitio esta vedado, uno lejos no
  for _, site in ipairs(sites) do
    check(reactor.blocks(sites, site.x, site.y, 1), "blocks en el centro del sitio")
    check(not reactor.blocks(sites, site.x + site.radius + RC.clear_pad + 10, site.y, 1),
      "blocks fuera de la zona vedada")
  end
end
check(siteTotal > 0, "se generan sitios de reactor")
check(variantsSeen.ring and variantsSeen.hull, "salen las dos variantes del reactor")

-- Rocas y pecios alrededor de los sitios
local reactorChunks, wreckChunks = 0, 0
for seed = 1, 40 do
  local layout = biomes.layout(seed)
  local sites = reactor.sites(seed)
  if #sites > 0 then
    local w = chunks.generate_world(seed)
    for cy = 0, CHUNKS - 1 do
      for cx = 0, CHUNKS - 1 do
        local sx, sy = grid.world_to_sector(cx * cfg.CHUNK_SIZE, cy * cfg.CHUNK_SIZE)
        local list = w[grid.chunk_key(cx, cy)]
        local nLarge, nWreck = 0, 0
        for _, s in ipairs(list) do
          local half = asteroid_cfg.ASTEROID_SHEET.frameSize * s.scale / 2
          local x, y = s.pos.x + half, s.pos.y + half
          local radius = asteroid_cfg.ASTEROID_SHEET.bodyRadius * s.scale
          for _, site in ipairs(sites) do
            check(dist(x, y, site.x, site.y) >= site.radius + RC.clear_pad,
              "ninguna roca dentro de la zona del reactor: " .. s.chunk_id)
          end
          if s.scale >= cfg.ROCK_SIZES.large.min then nLarge = nLarge + 1 end
          if s.wreck then nWreck = nWreck + 1 end
        end

        if layout.biomes[sx][sy] == "reactor" then
          reactorChunks = reactorChunks + 1
          -- Entre wrecks.min y wrecks.max pecios, sin pasar de las rocas grandes
          local lo, hi = math.min(RC.wrecks.min, nLarge), math.min(RC.wrecks.max, nLarge)
          check(nWreck >= lo and nWreck <= hi, string.format(
            "pecios del chunk reactor %d:%d entre %d y %d (hay %d)", cx, cy, lo, hi, nWreck))
          if nWreck > 0 then wreckChunks = wreckChunks + 1 end
        end
      end
    end
  end
end
check(reactorChunks > 0, "se generan chunks de sector reactor")
check(wreckChunks > 0, "hay pecios en los chunks del reactor")


if failures == 0 then
  print("map_determinism: all passed")
else
  print("map_determinism: " .. failures .. " failures")
  os.exit(1)
end
