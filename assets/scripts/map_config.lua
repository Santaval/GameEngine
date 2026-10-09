-- =====================================================================
--  Configuracion del mapa de la Aval Cup: solo datos. Todos los ajustes
--  del mapa viven aqui (ver docs/aval-cup.md); el resto de modulos
--  (map_grid, map_chunks, aval_cup_world, solar_hud) los leen de este archivo.
-- =====================================================================

local config = {}

-- Rejilla del mundo: WORLD_SIZE px por lado = SECTORS x SECTORS sectores de
-- SECTOR_SIZE px, cada uno en CHUNKS_PER_SECTOR x CHUNKS_PER_SECTOR chunks de
-- CHUNK_SIZE px. Un chunk es la unidad que se genera desde la semilla
config.WORLD_SIZE = 20000
config.SECTORS = 5
config.SECTOR_SIZE = 4000
config.CHUNKS_PER_SECTOR = 2
config.CHUNK_SIZE = 2000

-- Franja del borde del mundo (px) que consume la tormenta: no hay contenido
config.STORM_BAND = 500

-- Tormenta del borde (ver map_storm.lua y docs/aval-cup.md)
--   damage / tick: HP por golpe mientras se esta dentro y segundos entre golpes
--   tile_size: px de mundo por tesela (STORM_BAND es multiplo)
--   tile_frame / edge_frame: frames en la hoja (w, h, y de la fila, paso en x,
--     cantidad); el borde tiene lo solido abajo y lo irregular arriba
--   edge_height / edge_overlap: alto (px de mundo) de la tira de borde y la
--     fraccion que asoma hacia la zona segura
--   fps / alpha: animacion y opacidad; tint_alpha: tinte rojo de pantalla
config.STORM = {
  damage = 4, tick = 1.0,
  tile_size = 250,
  tile_frame = { w = 313, h = 313, y = 0, step = 313.5, count = 4 },
  edge_frame = { w = 313, h = 178, y = 134, step = 313.5, count = 4 },
  edge_height = 90, edge_overlap = 0.5,
  fps = 6, alpha = 235,
  tint_alpha = 60,
}

-- Tormentas errantes (ver map_storm.lua, wandering_storm.lua y docs/aval-cup.md)
--   count: tormentas vivas a la vez (el host las repone)
--   radius / speed: radio (px, 1-2 chunks de ancho) y velocidad (px/s) al nacer
--   turn_rate: giro maximo del rumbo (rad/s), paseo aleatorio del duenio
--   damage / tick: dano por tiempo dentro de la nube
--   push_speed / push_accel / front_pad: la mitad delantera empuja a las naves
--     a al menos push_speed (px/s) a lo largo del rumbo, ganando push_accel
--     (px/s^2) como maximo; front_pad es el margen (px) mas alla del radio
--   spawn_clear: distancia minima a PLAYER_SPAWN de las tormentas iniciales
--   edge_height: alto (px de mundo) del anillo irregular
--   tile_alpha / icon_size: opacidad de las teselas e icono del minimapa (px)
config.WANDERING_STORM = {
  count = 2,
  radius = { min = 1000, max = 2000 },
  speed = { min = 35, max = 55 },
  turn_rate = 0.05,
  damage = 3, tick = 1.0,
  push_speed = 110,
  push_accel = 220,
  front_pad = 250,
  spawn_clear = 4000,
  edge_height = 260,
  tile_alpha = 215, icon_size = 14,
}

-- Solo se simulan y se dibujan los chunks a esta distancia (en chunks) del
-- jugador local; el resto duerme (CullComponent, set_active_area)
config.UPDATE_RADIUS_CHUNKS = 2

-- Portales
config.STABLE_PORTAL_PAIRS = 12
config.NEXUS_COUNT = 1
config.PORTAL_CLEAR_RADIUS = 600
config.PORTAL_COOLDOWN = 4
config.PORTAL_EXIT_WARNING = 0.75

-- Portales estables (ver map_portals.lua, map_portal_world.lua y docs/aval-cup.md)
--   pair_sectors: distancia entre los dos extremos de un par, en sectores
--     (Chebyshev, min..max)
--   planet_factor: un extremo queda a al menos planet_factor x range del planeta
--   spacing: distancia minima (px) entre dos extremos cualquiera
--   spawn_clear: distancia minima (px) a PLAYER_SPAWN
--   tries: intentos por par antes de saltarlo
--   enter_radius: distancia (px) a la que la nave (o la bala) entra al portal
--   pull_radius / pull_accel: tiron suave (px, px/s^2) hacia un extremo cercano
--   exit_offset: la nave sale a esta distancia (px) del extremo, sobre su eje
--   min_exit_speed: velocidad minima (px/s) a la salida
--   storm_warn_pad: margen (px) para avisar con el halo si una errante se acerca
--   draw_size / flash_size / halo_size / warp_size: tamano (px de mundo) del
--     portal, el destello de salida, el halo y la distorsion
--   warp_time: duracion (s) de la distorsion; fps: animacion de portal y halo
--   icon_size: lado (px) del icono del minimapa
--   sheets: hojas de sprites (ancho, alto, frames), en fila y a todo el alto
config.PORTAL = {
  pair_sectors = { min = 2, max = 4 },
  planet_factor = 1.5,
  spacing = 1500,
  spawn_clear = 1500,
  tries = 300,
  enter_radius = 70,
  pull_radius = 250, pull_accel = 140,
  exit_offset = 120,
  min_exit_speed = 150,
  storm_warn_pad = 1200,
  draw_size = 220, flash_size = 260, halo_size = 300, warp_size = 160,
  warp_time = 0.4,
  fps = 10,
  icon_size = 5,
  sheets = {
    stable = { w = 2172, h = 724, count = 8 },
    flash = { w = 2172, h = 724, count = 6 },
    halo = { w = 1983, h = 793, count = 4 },
    warp = { w = 1881, h = 836, count = 6 },
    unstable = { w = 2172, h = 724, count = 8 },
    open = { w = 1983, h = 793, count = 10 },
    collapse = { w = 2172, h = 724, count = 10 },
    nexus = { w = 1774, h = 887, count = 8 },
  },
}
config.UNSTABLE_PORTAL_LIFE = { min = 45, max = 75 }

-- Portales inestables (#23): entidades del host (net_spawn world = true), de
-- ida y a un destino al azar. Viven UNSTABLE_PORTAL_LIFE segundos
--   per_players / count: el host mantiene ceil(jugadores / per_players) x una
--     tirada de count.min..count.max (se vuelve a tirar en cada spawn)
--   flicker_time: los ultimos segundos de vida parpadea
--   open_time / collapse_time: duracion (s) de la animacion de apertura (aun
--     no se puede entrar) y de la de cierre (portal-collapse)
--   enter_radius: distancia (px) a la que la nave entra; la bala se destruye
--   draw_size / icon_size: tamano (px de mundo) del portal y (px) del icono
--     del minimapa
--   spawn_interval: espera (s) del host entre un spawn y el siguiente
--   spawn_clear / tries: distancia minima (px) a PLAYER_SPAWN e intentos de
--     encontrar un punto valido (portals.valid_point)
config.UNSTABLE_PORTAL = {
  per_players = 10, count = { min = 1, max = 2 },
  flicker_time = 10,
  open_time = 1.0, collapse_time = 1.0,
  enter_radius = 50,
  draw_size = 130, icon_size = 8,
  spawn_interval = { min = 8, max = 15 },
  spawn_clear = 1500, tries = 60,
}

-- Nexus (#23): un portal en el sector central con 4 bocas; el angulo con que
-- se entra elige la salida (una por direccion E, S, O, N, ver map_portals.lua)
--   draw_size: ancho (px de mundo) de un frame; enter_radius / pull_radius:
--     entrada y tiron (px)
--   exit_sectors: distancia (Chebyshev, en sectores) de cada salida al centro
--   icon_size: lado (px) del icono del minimapa
--   tries: intentos por punto antes de dar el nexus por fallido
config.NEXUS = {
  draw_size = 420, enter_radius = 110, pull_radius = 350,
  exit_sectors = 2,
  icon_size = 10,
  tries = 300,
}

-- Colapso de portal (#23): tras `warning` segundos de aviso un par estable se
-- cierra y se abre uno nuevo en otro sector (siempre hay STABLE_PORTAL_PAIRS)
--   reserve_pairs: sitios de repuesto que genera map_portals.lua
config.PORTAL_COLLAPSE = {
  warning = 15,
  reserve_pairs = 6,
}

-- Eventos y tormenta (segundos)
config.EVENT_INTERVAL = { min = 60, max = 120 }
config.STORM_CONTRACTION_INTERVAL = { min = 180, max = 240 }
config.STORM_CONTRACTION_SAFE_RADIUS = 1500

-- Contraccion de la tormenta (#25, ver map_storm_contraction.lua y
-- docs/aval-cup.md). El sector elegido pasa por tres fases, contadas desde el
-- inicio del evento: aviso (sin dano, contorno del sector y circulo final),
-- cierre (el radio seguro baja de start_radius a STORM_CONTRACTION_SAFE_RADIUS)
-- y espera (se mantiene cerrado). Zona de tormenta = dentro del sector y mas
-- lejos del centro que el radio seguro
--   warning / shrink / hold: duracion (s) de cada fase; su suma es la del evento
--   damage / tick: dano por tiempo dentro de la zona de tormenta
--   start_radius: radio inicial (px), la media diagonal del sector (cubre todo)
--   edge_height / tile_alpha: alto (px de mundo) del anillo irregular y
--     opacidad de las teselas
--   highlight / highlight_alpha: color (r, g, b) y opacidad del contorno del
--     sector y del circulo final; ring_dot_spacing: separacion (px) de sus puntos
--   crate_clear: distancia minima (px) de la caja al cuerpo de un planeta
--   crate_tries: intentos de buscar un punto libre para la caja
config.STORM_CONTRACTION = {
  warning = 30, shrink = 60, hold = 15,
  damage = 5, tick = 1.0,
  start_radius = config.SECTOR_SIZE * math.sqrt(2) / 2,
  edge_height = 260, tile_alpha = 225,
  highlight = { 150, 30, 60 }, highlight_alpha = 200,
  ring_dot_spacing = 40,
  crate_clear = 400, crate_tries = 40,
}

-- Caja de loot alto (#25; #27 le suma la animacion de apertura): una entidad del host que se recoge
-- por contacto con el flujo de loot_net.lua
--   size: ancho (px de mundo) del dibujo
--   sheet: hoja de frames en fila; frame_w px de ancho cada uno, count frames,
--     y src_y / src_h: franja vertical de la hoja que ocupa la caja
--   radius: radio del collider, en px del frame (el motor lo escala)
--   loot: items (de asteroid_config.lua) y cantidad que suelta
config.LOOT_CRATE_PAL = {
  size = 72,
  sheet = { frame_w = 362, count = 6, src_y = 189, src_h = 308 },
  radius = 140,
  loot = { iron = 30, gunpowder = 15, plasma = 8 },
}

-- Contenedores de suministros (#27, ver map_supply.lua, map_supply_world.lua y
-- docs/aval-cup.md): una caja por sector deep_void o debris (1 por cada 4
-- chunks), lejos de los planetas. Da un recurso al azar y reaparece tras abrirse.
-- Se abre por contacto con el mismo flujo de loot_net.lua que la caja de Pal
--   size / sheet / radius: como LOOT_CRATE_PAL (supply_crate.png tiene la misma
--     hoja: frame 0 cerrada, frames 1..5 la apertura)
--   biomes: sectores donde sale
--   items / quantity: recurso (de asteroid_config.lua) al azar y cantidad
--     min..max que suelta cada vez
--   respawn: segundos hasta que reaparece tras abrirse
--   planet_clear: distancia minima (px) al pozo de gravedad de un planeta
--   rock_clear: holgura (px) entre el borde de la caja y el de una roca
--   edge_pad: margen (px) al borde del sector; tries: intentos de colocacion
--   open_fps: velocidad de la animacion de apertura (frames 1..5)
config.SUPPLY_CRATE = {
  size = 56,
  sheet = { frame_w = 362, count = 6, src_y = 189, src_h = 308 },
  radius = 110,
  biomes = { "deep_void", "debris" },
  items = { "iron", "gunpowder", "plasma" },
  quantity = { min = 8, max = 20 },
  respawn = 90,
  planet_clear = 400,
  rock_clear = 120,
  edge_pad = 400,
  tries = 40,
  open_fps = 10,
}

-- Orbes de muerte (#28, ver map_death_drop.lua, death_orb.lua y docs/aval-cup.md):
-- al morir una nave suelta fraction de cada mineral de su bodega en orbes que
-- crea el host. Cada color sigue el de su mineral (hierro azul, polvora roja,
-- plasma verde)
--   fraction: parte de cada mineral que cae (se redondea hacia abajo)
--   radius: los orbes aparecen al azar a esta distancia (px) del punto de muerte
--   ttl: segundos de vida del orbe; pasado ese tiempo su duenio lo borra
--   push / push_time: velocidad (px/s) min..max con que salen hacia afuera y
--     segundos que tarda en frenarse hasta quedar quieto
--   per_orb / max_orbs: unidades de mineral por orbe y tope de orbes por mineral
--     (el resto se reparte entre ellos)
--   size / frame_w / frame_h / frames / fps: ancho (px de mundo) con que se
--     dibuja el frame de la hoja (orb_*.png, 2172x724, 4 frames de 543x724 en
--     fila), tamano del frame en la hoja, cantidad y velocidad del pulso
--   radius_px: radio del collider en px del frame (el motor lo escala)
--   magnet_radius: distancia (px) a la que el orbe vuela hacia la nave
--   orbs: assetId del orbe de cada mineral
config.DEATH_DROP = {
  fraction = 0.6,
  radius = 300, ttl = 30,
  push = { min = 40, max = 90 }, push_time = 1.0,
  per_orb = 5, max_orbs = 8,
  size = 48, frame_w = 543, frame_h = 724, frames = 4, fps = 8,
  radius_px = 150,
  magnet_radius = 200,
  orbs = { iron = "orb-protection", gunpowder = "orb-weapon", plasma = "orb-propulsion" },
}

-- Aparicion de la nave (#28, ver map_spawn.lua y docs/aval-cup.md): al cargar la
-- escena (y al reiniciar tras morir) la nave sale en un punto valido con un
-- portal estable a la vista
--   biomes: sectores donde puede salir
--   portal_min / portal_max: distancia (px) al extremo de portal estable elegido
--   player_clear: distancia minima (px) a cualquier otra nave viva
--   top_clear / top_n: distancia minima (px) a los top_n primeros del ranking
--     (gancho map_ranking_top(), lo define #29; sin el, la regla no se aplica)
--   tries: intentos antes de relajar las reglas (primero el top, luego las
--     naves y al final PLAYER_SPAWN)
--   wait: segundos de espera para que lleguen las naves del snapshot
config.SPAWN = {
  biomes = { "deep_void", "debris" },
  portal_min = 350, portal_max = 900,
  player_clear = 2 * config.CHUNK_SIZE,
  top_clear = 8000, top_n = 3,
  tries = 60,
  wait = 1.0,
}

-- Escudo de aparicion (#28): la nave no recibe dano durante `time` s o hasta que
-- dispara. Se dibuja spawn_shield.png (2172x724, 6 frames de 362 de ancho en
-- fila; el anillo ocupa la franja src_y / src_h) sobre la nave
--   size: lado (px de mundo) del dibujo; fps / alpha: animacion y opacidad
config.SPAWN_SHIELD = {
  time = 5,
  size = 150,
  sheet = { frame_w = 362, count = 6, src_y = 162, src_h = 362 },
  fps = 10, alpha = 200,
}

-- Ranking en vivo (#29): el total de minerales del inventario de cada jugador
--   size: filas del top; send_interval: s minimos entre dos avisos rank_score
--   al cambiar el total; heartbeat: s tras los que se reenvia aunque no cambie;
--   stale: s sin noticias tras los que se descarta a un jugador
--   panel: ranking_panel.png (1182x1330) estirado a w x h arriba a la derecha
--   (top: y; alpha; header_frac / body_frac: fraccion de h que ocupan la
--   cabecera y el borde superior del cuerpo, donde empiezan las filas)
--   row_h: separacion entre filas; name_chars: letras del nombre
--   icon_size: icono del lider en el minimapa (icon_leader.png, 1254x1254)
--   crown_size / crown_gap: corona (leader_crown.png, 1254x1254) y px que
--   quedan entre su borde de abajo y la esquina sup-izq de la nave
config.RANKING = {
  size = 10,
  send_interval = 0.5,
  heartbeat = 5,
  stale = 15,
  panel = { w = 260, h = 290, margin = 20, top = 62, alpha = 235, header_frac = 0.12, body_frac = 0.125 },
  row_h = 20,
  name_chars = 10,
  icon_size = 16,
  crown_size = 32,
  crown_gap = 70,
}

-- Biomas: cada sector tiene uno (ver map_biomes.lua). weight es la
-- probabilidad relativa de salir. Dos sectores contiguos (vecinos ortogonales,
-- sin diagonales) no repiten bioma salvo BIOME_REPEAT_OK. El sector central
-- es siempre uno de CENTER_BIOMES (lo elige map_biomes antes que el resto).
-- Solo planetary: la megaestructura del reactor no puede caer en la aparicion
config.BIOMES = {
  { id = "debris", name = "Debris", weight = 35 },
  { id = "planetary", name = "Planetary", weight = 20 },
  { id = "dense_belt", name = "Dense Belt", weight = 15 },
  { id = "deep_void", name = "Deep Void", weight = 15 },
  { id = "nebula", name = "Nebula", weight = 10 },
  { id = "reactor", name = "Reactor", weight = 5 },
}
config.BIOME_REPEAT_OK = "debris"
config.CENTER_BIOMES = { "planetary" }

-- Color de cada bioma en el minimapa (r, g, b)
config.BIOME_COLORS = {
  debris = { 120, 110, 100 },
  planetary = { 60, 140, 200 },
  dense_belt = { 160, 110, 60 },
  deep_void = { 30, 30, 50 },
  nebula = { 150, 80, 170 },
  reactor = { 200, 70, 60 },
}

-- Tamanos de roca (escala aplicada al frame del sprite)
config.ROCK_SIZES = {
  large = { min = 1.0, max = 1.5 },
  medium = { min = 0.6, max = 1.0 },
  small = { min = 0.3, max = 0.6 },
}

-- Rocas grandes por chunk (en dense_belt, LARGE_ROCKS_DENSE) y separacion
-- minima entre sus centros (px, Poisson-disk)
config.LARGE_ROCKS = { min = 4, max = 6 }
config.LARGE_ROCKS_DENSE = { min = 10, max = 14 }
config.LARGE_SPACING = 300

-- Rocas medianas o pequenas por chunk (mitad y mitad; ninguna en deep_void) y
-- separacion minima entre ellas (px)
config.SMALL_ROCKS = { min = 6, max = 10 }
config.SMALL_SPACING = 120

-- Intentos por roca: fijo, para que el resultado sea determinista
config.ROCK_TRIES = 30

-- Rocas a la deriva: probabilidad por roca, velocidad (px/s) e intentos de
-- encontrar un rumbo que no cruce la gravedad de ningun planeta. No se
-- duermen con el culling (ver docs/aval-cup.md)
config.DRIFT = { chance = 0.2, speed = { min = 20, max = 40 }, tries = 12 }

-- Pecios: probabilidad por chunk, solo en estos biomas (una roca grande del
-- chunk pasa a ser un pecio que suelta recursos extra)
config.WRECK_CHANCE = 1 / 3
config.WRECK_BIOMES = { "debris", "reactor" }

-- Reactor Remains (ver map_reactor.lua y map_reactor_data.lua): una
-- megaestructura por sector reactor, con huecos por los que pasa una nave.
--   variants: pesos de las variantes (ring = anillo, hull = casco modular)
--   ring_size: lado (px dibujados) del sprite del anillo
--   hull_piece: lado (px dibujados) de las piezas cuadradas del casco; la
--     recta (hull_01) se dibuja 1.5 veces mas ancha que alta
--   core_size / core_frame / core_cols: nucleo animado (px dibujados, lado de
--     un frame de la hoja y frames por fila)
--   clear_pad: ninguna roca a menos de radio de la estructura + clear_pad px
--   wrecks: pecios por chunk del sector reactor (las rocas grandes del chunk
--     que pasan a pecio; reemplaza a WRECK_CHANCE en esos chunks)
--   ship_clearance: holgura minima (px) entre el borde de un collider y el
--     centro de un hueco (la usa la prueba del mapa)
--   min_gap: ancho minimo (px) de los huecos del casco
--   pulse: Pulso del Reactor. radius/max_push/min_push: alcance (px) y
--     velocidad (px/s) que se suma hacia afuera, max_push pegado al nucleo
--     y min_push como suelo; charge: segundos de carga antes del empuje;
--     wave_time: segundos que tarda la onda en llegar al radio; warn_radius:
--     a esta distancia sale el aviso (el director de eventos, #24, lo dispara)
config.REACTOR = {
  variants = { ring = 1, hull = 1 },
  ring_size = 2800,
  hull_piece = 520,
  core_size = 600,
  core_frame = 362,
  core_cols = 4,
  clear_pad = 250,
  wrecks = { min = 1, max = 2 },
  ship_clearance = 120,
  min_gap = 350,
  pulse = {
    radius = 1800, max_push = 450, min_push = 120,
    charge = 2.0, wave_time = 0.6,
    warn_radius = 2400,
  },
}

-- Senal de Pal (#26, ver map_pal_signal.lua y docs/aval-cup.md): una caja de
-- loot alto (LOOT_CRATE_PAL) con un haz de luz vertical que se ve en el mundo y
-- un icono en el minimapa de todos. Se coloca entre dos zonas con jugadores
-- para provocar el combate
--   duration: segundos que dura el evento (la caja se borra al acabar)
--   crate_clear / crate_tries: distancia minima (px) de la caja al cuerpo de un
--     planeta e intentos de buscar un punto libre
--   edge_pad: margen (px) de la caja al borde del sector
--   beam: haz de pal_beacon.png (1086x1448, 6 frames de 181x1448 en fila, la
--     base del haz abajo): w x h son los px de mundo con que se dibuja (su base
--     queda en el centro de la caja) y frame_w / frame_h / count la hoja
--   fps / alpha: velocidad de la animacion y opacidad del haz
config.PAL_SIGNAL = {
  duration = 90,
  crate_clear = 400, crate_tries = 40,
  edge_pad = 500,
  beam = { w = 64, h = 512, frame_w = 181, frame_h = 1448, count = 6 },
  fps = 8, alpha = 220,
}

-- Lluvia de escombros (#26, ver map_debris_rain.lua): asteroides del host que
-- cruzan un sector con un rumbo comun. Fases contadas desde el inicio:
-- aviso (flechas en el borde de la pantalla), lluvia (caen rocas) y cola
-- (ya no caen, las ultimas siguen su camino); la suma es la del evento
--   warning / rain / tail: duracion (s) de cada fase
--   rate: asteroides por segundo durante la lluvia
--   speed / scale: rango de velocidad (px/s) y de escala de cada roca; con la
--     velocidad alta el choque hace dano completo (IMPACT_FULL_SPEED)
--   spread: desvio aleatorio (rad) del rumbo de cada roca
--   ttl: segundos de vida de la roca; pasado ese tiempo su duenio la borra
--   arrow_size / arrow_margin / arrow_count: lado (px) de las flechas de aviso,
--     su margen al borde de la pantalla y cuantas salen
--   warn_pad: la nave local ve las flechas dentro del sector ampliado en estos
--     px por cada lado
config.DEBRIS_RAIN = {
  warning = 5, rain = 20, tail = 5,
  rate = 3,
  speed = { min = 320, max = 420 },
  scale = { min = 0.25, max = 0.5 },
  spread = 0.08,
  ttl = 25,
  arrow_size = 48, arrow_margin = 24, arrow_count = 3,
  warn_pad = 2000,
}

-- Planeta sobrecargado (#26, ver map_overcharged.lua y player_mining.lua): un
-- planeta con mineral rinde mult veces mas mientras dura el evento
--   duration: segundos que dura el evento
--   mult: multiplicador del mineral minado
--   sheet: aura_overcharged.png (2172x724, 6 frames de 362 de ancho en fila);
--     el anillo de cada frame ocupa la franja vertical src_y / src_h
--   size_factor: diametro del aura = 2 * body_radius * size_factor
--   fps / alpha: velocidad de la animacion y opacidad del aura
--   ring_dot_spacing: separacion (px) de los puntos del anillo pulsante
--   colors: color (r, g, b) del anillo segun el mineral (draw_image no tine,
--     asi que el aura va en blanco y el color lo pone el anillo)
config.OVERCHARGED = {
  duration = 60, mult = 2,
  sheet = { frame_w = 362, count = 6, src_y = 181, src_h = 362 },
  size_factor = 2.5,
  fps = 8, alpha = 200,
  ring_dot_spacing = 30,
  colors = { iron = { 80, 160, 255 }, gunpowder = { 255, 80, 60 }, plasma = { 90, 255, 120 } },
}

-- Director de eventos (#24, ver map_event_director.lua y docs/aval-cup.md): el
-- host lanza eventos por sector ocupado cada EVENT_INTERVAL s y la contraccion
-- de la tormenta cada STORM_CONTRACTION_INTERVAL s
--   per_players: tope de eventos activos = max(1, ceil(jugadores x events /
--     players))
--   retry: segundos hasta reintentar un sector (o la contraccion) que no
--     encontro nada elegible o topo con el limite
--   banner_time / banner: segundos que se ve cada aviso y su caja en pantalla
--     (ancho, alto y distancia al borde de arriba, px); banner_src: la tira
--     dentro de event_banner.png (1983x793, con margen transparente)
--   icon_size: lado (px) del icono del minimapa
--   types: nombre, color (r, g, b), icono del minimapa (sin icono se dibuja un
--     cuadrado del color) y duracion (s) de cada tipo. El Pulso y el Colapso
--     duran lo que dura su efecto + un margen; la Contraccion, la suma de sus
--     fases; la Senal, la Lluvia y el Planeta sobrecargado, lo de PAL_SIGNAL,
--     DEBRIS_RAIN y OVERCHARGED
config.EVENTS = {
  per_players = { events = 3, players = 10 },
  retry = 5,
  banner_time = 4,
  banner = { w = 640, h = 80, y = 40 },
  banner_src = { x = 10, y = 270, w = 1964, h = 245 },
  icon_size = 12,
  types = {
    reactor_pulse = {
      name = "PULSO DEL REACTOR", color = { 255, 70, 50 },
      duration = config.REACTOR.pulse.charge + config.REACTOR.pulse.wave_time + 4,
    },
    portal_collapse = {
      name = "COLAPSO DE PORTAL", color = { 199, 125, 255 }, icon = "icon-portal-unstable",
      duration = config.PORTAL_COLLAPSE.warning + config.UNSTABLE_PORTAL.collapse_time,
    },
    storm_contraction = {
      name = "CONTRACCION DE TORMENTA", color = { 150, 30, 60 }, icon = "icon-event-contraction",
      duration = config.STORM_CONTRACTION.warning + config.STORM_CONTRACTION.shrink
        + config.STORM_CONTRACTION.hold,
    },
    pal_signal = {
      name = "SENAL DE PAL", color = { 255, 255, 255 }, icon = "icon-event-pal-signal",
      duration = config.PAL_SIGNAL.duration,
    },
    debris_rain = {
      name = "LLUVIA DE ESCOMBROS", color = { 255, 90, 90 }, icon = "icon-event-debris",
      duration = config.DEBRIS_RAIN.warning + config.DEBRIS_RAIN.rain + config.DEBRIS_RAIN.tail,
    },
    overcharged_planet = {
      name = "PLANETA SOBRECARGADO", color = { 80, 200, 255 },
      duration = config.OVERCHARGED.duration,
    },
  },
}

-- Planetas de los sectores Planetary: cuantos por sector, separacion entre
-- centros (multiplo de la suma de sus range) e intentos de colocacion.
-- Regla de borde: pedir >= 1 chunk (2000 px) al borde del sector solo deja el
-- centro libre y no caben 1-3 planetas, asi que se exige que TODO el pozo de
-- gravedad quede dentro del sector: centro a >= range + PLANET_EDGE_PAD
config.PLANETS_PER_SECTOR = { min = 1, max = 3 }
config.PLANET_SPACING_FACTOR = 2.5
config.PLANET_TRIES = 40
config.PLANET_EDGE_PAD = 100

-- Punto de aparicion de la nave (centro del mundo, ver scenes/aval_cup.lua) y
-- margen (px) que deja libre alrededor: ningun pozo de gravedad lo cubre, para
-- que nadie nazca dentro de un planeta. El sector central es
-- siempre Planetary (CENTER_BIOMES)
config.PLAYER_SPAWN = { x = config.WORLD_SIZE / 2, y = config.WORLD_SIZE / 2 }
config.SPAWN_CLEAR_PAD = 300

-- Rol de cada planeta (peso relativo). Solo mining mantiene el mineral; el
-- comportamiento de merchant y tech llega en otros issues
config.PLANET_ROLES = {
  { id = "mining", weight = 3 },
  { id = "merchant", weight = 1 },
  { id = "tech", weight = 1 },
}

-- Fondos por bioma (assetId de la escena). El fondo se repite en teselas de
-- BG_TILE px, se mueve al BG_PARALLAX de la velocidad de la camara y se
-- mezcla con el del sector vecino en BG_BLEND px a cada lado del borde
config.BIOME_BACKGROUNDS = { debris = "bg-default", planetary = "bg-default", dense_belt = "bg-dense-belt",
  deep_void = "bg-void", nebula = "bg-nebula", reactor = "bg-reactor" }
config.BG_TILE = 1024
config.BG_PARALLAX = 0.2
config.BG_BLEND = 800

-- Nebulosa: ruido de valor con celdas de `cell` px; por encima de `threshold`
-- cuenta como nube (~70% del sector). edge_pad: la densidad cae hacia el borde
-- del sector (bordes irregulares). Nubes cada cloud_spacing px; las de delante
-- (front) se dibujan sobre las naves con paralaje front_parallax
config.NEBULA = {
  cell = 900,
  threshold = 0.42,
  edge_pad = 600,
  cloud_spacing = 700,
  cloud_size = { min = 1100, max = 1500 },
  back_alpha = 150, front_alpha = 70, front_parallax = 1.12,
  vignette_fade = 0.5,
}

-- Comprueba que la rejilla es coherente; se llama al cargar el modulo
function config.validate()
  assert(config.SECTOR_SIZE * config.SECTORS == config.WORLD_SIZE,
    "map_config: SECTOR_SIZE * SECTORS debe ser WORLD_SIZE")
  assert(config.CHUNK_SIZE * config.CHUNKS_PER_SECTOR == config.SECTOR_SIZE,
    "map_config: CHUNK_SIZE * CHUNKS_PER_SECTOR debe ser SECTOR_SIZE")
  assert(config.STORM_BAND % config.STORM.tile_size == 0,
    "map_config: STORM_BAND debe ser multiplo de STORM.tile_size")
end

config.validate()

return config
