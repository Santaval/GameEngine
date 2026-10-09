-- =====================================================================
--  Sistema solar: datos del mapa principal (ver docs/solar-system.md)
--  Lo usan la escena (scenes/solar_system.lua), el anillo de Saturno
--  (saturn_ring.lua) y el minimapa (solar_hud.lua).
--
--  Escala comprimida: distancia al Sol = AU_OFFSET + AU_SCALE * sqrt(AU),
--  tamano = SIZE_SCALE * radio_tierra^SIZE_EXPONENT. Mantiene el orden y el
--  aspecto real sin que los planetas exteriores queden a minutos de vuelo.
--  Los planetas estan quietos, cada uno en su propio angulo.
-- =====================================================================

local config = {}

-- El Sol va en el centro del mapa para que todas las coordenadas sean positivas
config.SUN_CENTER = { x = 20000, y = 20000 }
config.MAP_RADIUS = 19500

config.AU_OFFSET = 1200
config.AU_SCALE = 2600
config.SIZE_SCALE = 3
config.SIZE_EXPONENT = 0.45

-- Los png de planetas son de 48x48 con el cuerpo dibujado en un radio de 22
config.PLANET_FRAME = 48
config.PLANET_BODY_RADIUS = 22

-- Masa y range por defecto: mass = MASS_PER_SCALE * scale,
-- range = RANGE_PER_BODY * radio_del_cuerpo + RANGE_EXTRA
config.MASS_PER_SCALE = 500
config.RANGE_PER_BODY = 4
config.RANGE_EXTRA = 250

-- Mineral que da minar dentro de la gravedad del planeta y cada cuantos segundos
config.MINE_INTERVAL = 2
-- Vida que quita apoyarse en un planeta cada 0.5 s
config.PLANET_DAMAGE = 15

function config.au_to_px(au)
  return config.AU_OFFSET + config.AU_SCALE * math.sqrt(au)
end

function config.scale_for(earth_radii)
  return math.floor(config.SIZE_SCALE * earth_radii ^ config.SIZE_EXPONENT * 10 + 0.5) / 10
end

-- au: distancia real; radius: radio real en radios terrestres; angle: grados
-- (0 = derecha, sentido horario porque y crece hacia abajo).
-- mass / range / damage opcionales pisan los valores por defecto
config.BODIES = {
  -- El Sol usa su propio png de 96x96 (cuerpo de radio 44) para que no se vea
  -- tan pixelado a ese tamano
  { name = "Sol", assetId = "planet-sun", au = 0, radius = 109, angle = 0,
    mass = 60000, range = 2000, damage = 50, frame = 96, frame_body_radius = 44 },
  { name = "Mercurio", assetId = "planet-iron", au = 0.39, radius = 0.38, angle = 250, mineral = "iron" },
  { name = "Venus", assetId = "planet-gunpowder", au = 0.72, radius = 0.95, angle = 135, mineral = "gunpowder" },
  { name = "Tierra", assetId = "planet-iron", au = 1.0, radius = 1.0, angle = 0, mineral = "iron" },
  { name = "Marte", assetId = "planet-iron", au = 1.52, radius = 0.53, angle = 300, mineral = "iron" },
  { name = "Jupiter", assetId = "planet-plasma", au = 5.2, radius = 11.2, angle = 60, mineral = "plasma" },
  { name = "Saturno", assetId = "planet-plasma", au = 9.58, radius = 9.45, angle = 165, mineral = "plasma" },
  { name = "Urano", assetId = "planet-gunpowder", au = 19.2, radius = 4.0, angle = 235, mineral = "gunpowder" },
  { name = "Neptuno", assetId = "planet-gunpowder", au = 30.1, radius = 3.9, angle = 330, mineral = "gunpowder" },
}

-- Cinturones: anillos alrededor del Sol, en px desde su centro.
-- density = asteroides por cada 1000x1000 px de area del anillo.
-- El Kuiper real empieza en Neptuno (30 AU); se corre hacia afuera para que
-- no pise la gravedad de Neptuno
config.BELTS = {
  { name = "Cinturon principal", inner = config.au_to_px(2.2), outer = config.au_to_px(3.3),
    density = 8, generators = 6 },
  { name = "Cinturon de Kuiper", inner = 16500, outer = 18500, density = 0.8, generators = 6 },
}

-- Velocidad de deriva (px/s) de las rocas de los cinturones: casi tangente al
-- Sol, con un poco de desvio para que no parezcan un riel
config.BELT_SPEED = { min = 1, max = 8 }
config.BELT_DRIFT_ANGLE = 0.3

-- Anillo de Saturno, en multiplos del radio del cuerpo
config.SATURN_RING = {
  planet = "Saturno",
  inner = 1.4,
  outer = 2.1,
  rocks = 90,
  scale = { min = 0.2, max = 0.45 },
  -- rad/s; positivo = sentido horario en pantalla
  angular_speed = 0.12,
  -- Segundos hasta que un hueco del anillo vuelve a tener roca
  respawn_time = 30,
}

-- La nave arranca del lado de la Tierra que mira al Sol, fuera de su gravedad
config.PLAYER_SPAWN = { planet = "Tierra", altitude = 140 }
config.SAFE_ZONE_RADIUS = 250

-- Datos de un cuerpo de BODIES que no dependen de su posicion: scale, frame,
-- frame_body_radius, body_radius, mass, range, damage, mineral y mine_interval
-- (los usan build_planets y los planetas de los biomas, ver map_biomes.lua)
function config.planet_from_body(b)
  local frame = b.frame or config.PLANET_FRAME
  local frame_body_radius = b.frame_body_radius or config.PLANET_BODY_RADIUS
  -- scale_for esta pensado para los png de 48: un png mas grande se escala menos
  local scale = config.scale_for(b.radius) * config.PLANET_FRAME / frame
  local body_radius = frame_body_radius * scale

  return {
    scale = scale,
    frame = frame,
    frame_body_radius = frame_body_radius,
    body_radius = body_radius,
    mass = b.mass or math.floor(config.MASS_PER_SCALE * config.scale_for(b.radius) / 10 + 0.5) * 10,
    range = b.range or math.floor((config.RANGE_PER_BODY * body_radius + config.RANGE_EXTRA) / 10 + 0.5) * 10,
    damage = b.damage or config.PLANET_DAMAGE,
    mineral = b.mineral,
    mine_interval = b.mineral and config.MINE_INTERVAL or nil,
  }
end

-- Cuerpos con x, y, scale, mass, range, body_radius... en el formato que
-- esperan player_gravity_zones / player_mining (scene_planets)
function config.build_planets()
  local planets = {}
  for _, b in ipairs(config.BODIES) do
    local p = config.planet_from_body(b)
    local dist = b.au > 0 and config.au_to_px(b.au) or 0
    local angle = math.rad(b.angle)

    p.name = b.name
    p.assetId = b.assetId
    p.x = config.SUN_CENTER.x + dist * math.cos(angle)
    p.y = config.SUN_CENTER.y + dist * math.sin(angle)
    p.angle = angle
    p.distance = dist
    planets[#planets + 1] = p
  end
  return planets
end

function config.find_planet(planets, name)
  for _, p in ipairs(planets) do
    if p.name == name then return p end
  end
  return nil
end

-- Avisa por consola si dos gravedades quedan demasiado cerca o si una pisa
-- un cinturon (pasa si se tocan angulos o distancias)
function config.validate(planets)
  local ok = true
  for i = 1, #planets do
    local a = planets[i]
    for j = i + 1, #planets do
      local b = planets[j]
      local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
      if d < a.range + b.range + 200 then
        print(string.format("[solar] AVISO: %s y %s demasiado cerca (%d px)", a.name, b.name, d))
        ok = false
      end
    end
    if a.distance > 0 then
      for _, belt in ipairs(config.BELTS) do
        if a.distance + a.range > belt.inner and a.distance - a.range < belt.outer then
          print(string.format("[solar] AVISO: la gravedad de %s pisa el %s", a.name, belt.name))
          ok = false
        end
      end
    end
  end
  return ok
end

return config
