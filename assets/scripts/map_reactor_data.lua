-- =====================================================================
--  Datos del Reactor Remains (solo datos y funciones puras, sin motor):
--  - ASSETS: hoja de cada sprite (assetId de la escena y tamano del frame).
--  - TEMPLATES: circulos de colision de cada pieza, medidos sobre la mascara
--    alfa del arte. Estan en coordenadas normalizadas: origen en el centro de
--    la imagen, +y hacia abajo, unidad = lado de la pieza dibujada (el alto en
--    las piezas del casco, el ancho en el anillo; la recta hull_01 mide 1.5).
--    El nucleo aparte: CORE_RADIUS.
--    Los extremos son los del ARTE: los centros de los circulos se meten un
--    radio hacia dentro para que el hueco de colision sea el hueco visual.
--  - hull_layout / ring_layout: donde va cada pieza (px respecto al centro del
--    sitio). Son valores de partida: se afinan a ojo con los colliders (tecla C).
--  Ver map_reactor.lua, que lo expande con la semilla del sector.
-- =====================================================================

local cfg = require("map_config")

local R = cfg.REACTOR

local data = {}

-- Tamano del frame de cada imagen y su assetId en scenes/aval_cup.lua
data.ASSETS = {
  hull_01 = { assetId = "reactor-hull-01", w = 1536, h = 1024 },
  hull_02 = { assetId = "reactor-hull-02", w = 1254, h = 1254 },
  hull_03 = { assetId = "reactor-hull-03", w = 1254, h = 1254 },
  hull_04 = { assetId = "reactor-hull-04", w = 1254, h = 1254 },
  ring = { assetId = "reactor-ring", w = 1254, h = 1254 },
}

-- Orden fijo de las variantes: pairs() no lo es y rompe el determinismo
data.VARIANTS = { "ring", "hull" }

-- Separacion entre circulos vecinos de una linea o arco, en radios: menor que 2
-- para que se solapen y no queden muescas por las que se cuele una nave
data.STEP = 1.25

-- Formas de cada plantilla:
--   line: capsula del punto (x1,y1) al (x2,y2) del arte con semigrosor hw
--   grid: rejilla nx x ny de circulos de radio r dentro de la caja del arte
--   arc: arco de centro (0,0), radio de la linea central R y semigrosor hw,
--        de `from` a `to` grados (0 = +x, horario en pantalla); un circulo
--        cada step grados como maximo
data.TEMPLATES = {
  -- Anillo (D x D): cuatro arcos, cuatro huecos. gaps: angulo (grados) del
  -- centro de cada hueco, para las pruebas y el director
  ring = {
    shapes = {
      { kind = "arc", R = 0.40, hw = 0.075, from = 12, to = 82, step = 10 },
      { kind = "arc", R = 0.40, hw = 0.075, from = 102, to = 176, step = 10 },
      { kind = "arc", R = 0.40, hw = 0.075, from = 192, to = 266, step = 10 },
      { kind = "arc", R = 0.40, hw = 0.075, from = 290, to = 358, step = 10 },
    },
    gaps = { 5, 92, 184, 278 },
    gap_radius = 0.40,
  },
  -- Recta (1.5S x S)
  hull_01 = {
    shapes = { { kind = "line", x1 = -0.735, y1 = 0, x2 = 0.735, y2 = 0, hw = 0.24 } },
  },
  -- Esquina en L: brazo vertical a la izquierda y brazo horizontal abajo
  hull_02 = {
    shapes = {
      { kind = "line", x1 = -0.315, y1 = -0.44, x2 = -0.315, y2 = 0.30, hw = 0.135 },
      { kind = "line", x1 = -0.40, y1 = 0.28, x2 = 0.44, y2 = 0.28, hw = 0.12 },
    },
  },
  -- Bloque con el borde derecho irregular (el que da a un hueco)
  hull_03 = {
    shapes = { { kind = "grid", x1 = -0.49, y1 = -0.41, x2 = 0.36, y2 = 0.44, nx = 3, ny = 3, r = 0.16 } },
  },
  -- Union en T: barra arriba y pie hacia abajo
  hull_04 = {
    shapes = {
      { kind = "line", x1 = -0.49, y1 = -0.16, x2 = 0.49, y2 = -0.16, hw = 0.15 },
      { kind = "line", x1 = 0.01, y1 = 0.0, x2 = 0.01, y2 = 0.41, hw = 0.13 },
    },
  },
}

-- Radio del collider del nucleo, en unidades de core_size
data.CORE_RADIUS = 0.3

-- Casco: un recinto cuadrado (semi-lado HALF al centro del muro) de cuatro
-- lados iguales girados 90 grados (molinete). Se define el lado de abajo y las
-- demas se obtienen girando (side = 0..3) todo el lado junto con su esquina:
--   corner: hull_02 con sus brazos pegados a la pared izquierda y de abajo
--   straight: hull_01 desde el brazo de la esquina hacia el centro
--   cap: hull_03 girado 180 grados contra la esquina del otro lado; su borde
--        irregular queda de cara al hueco
--   gap: el hueco entre la recta y el bloque (punto medio)
-- Los extremos se calculan con las medidas del arte de las plantillas, asi
-- que las piezas encajan para cualquier hull_piece. Las piezas se solapan
-- OVERLAP px para que no quede una rendija
-- Cada pieza: { asset, x, y, rot (cuartos de vuelta), w, h }
data.HULL_HALF = 1200
local OVERLAP = 10

function data.hull_layout()
  local S = R.hull_piece
  local H = data.HULL_HALF

  -- Esquina inferior izquierda
  local cornerX, cornerY = -H + 0.315 * S, H - 0.28 * S
  local armEnd = cornerX + 0.44 * S            -- fin del brazo horizontal
  local armStart = H - 0.72 * S                -- inicio del brazo de la esquina vecina

  local straightX = armEnd - OVERLAP + 0.735 * S
  local capX = armStart + OVERLAP - 0.49 * S
  local gapLeft = straightX + 0.735 * S        -- borde derecho de la recta
  local gapRight = capX - 0.36 * S             -- borde irregular del bloque
  local width = gapRight - gapLeft

  local side = {
    pieces = {
      { asset = "hull_02", x = cornerX, y = cornerY, rot = 0, w = S, h = S },
      { asset = "hull_01", x = straightX, y = H, rot = 0, w = 1.5 * S, h = S },
      { asset = "hull_03", x = capX, y = H, rot = 2, w = S, h = S },
    },
    gap = { x = (gapLeft + gapRight) / 2, y = H },
    gap_width = width,
  }

  -- Cobertura suelta dentro del recinto (fuera no cabe: un sector de borde solo
  -- deja ~1500 px de radio libre antes de la franja de tormenta)
  local cover = {
    { asset = "hull_04", x = -520, y = -380, rot = 0, w = S, h = S },
    { asset = "hull_04", x = 480, y = 440, rot = 1, w = S, h = S },
  }

  return side, cover
end

-- Anillo: una sola pieza centrada
function data.ring_layout()
  local D = R.ring_size
  return { { asset = "ring", x = 0, y = 0, rot = 0, w = D, h = D } }
end

return data
