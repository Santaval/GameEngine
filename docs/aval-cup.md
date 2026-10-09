# Aval Cup map

Foundation of the Aval Cup map (issue #16): a fixed world split into sectors
and chunks, a deterministic seed shared by every client, and culling so only
the chunks near the local player are simulated. Issue #17 adds biomes per
sector and the procedural content of each chunk (asteroids, drifting rocks,
planets and wrecks). Spawn rules (issue #28) come later.

Scene: `assets/scripts/scenes/aval_cup.lua` (menu option "A - Aval Cup").
Director: `assets/scripts/aval_cup_world.lua`.

## Grid

All numbers live in `assets/scripts/map_config.lua`; nothing else hardcodes them.

| Level | Size | Count |
| --- | --- | --- |
| World | 20 000 x 20 000 px | 1 |
| Sector | 4 000 px (`SECTOR_SIZE`) | 5 x 5 (`SECTORS`) |
| Chunk | 2 000 px (`CHUNK_SIZE`) | 2 x 2 per sector (`CHUNKS_PER_SECTOR`), 10 x 10 in total |

`map_config.validate()` asserts `SECTOR_SIZE * SECTORS == WORLD_SIZE` and
`CHUNK_SIZE * CHUNKS_PER_SECTOR == SECTOR_SIZE` when the module loads.

Helpers in `map_grid.lua` (all read `map_config`):

| Function | Returns |
| --- | --- |
| `world_to_sector(x, y)` | `sx, sy` in `0..SECTORS-1`, clamped to the world |
| `world_to_chunk(x, y)` | `cx, cy` in `0..9`, clamped to the world |
| `sector_bounds(sx, sy)` / `chunk_bounds(cx, cy)` | `x, y, w, h` in world px |
| `chunk_key(cx, cy)` | `"cx:cy"` |
| `hash(seed, cx, cy, salt?)` | 32-bit integer, see below |
| `pick_weighted(r, list)` | Element of `list` (`{weight = n, ...}`) picked with rng `r`, and its index |
| `rng(state)` | object with `next()` in `[0,1)`, `range(a,b)` and `int(a,b)` (inclusive) |
| `active_bounds(x, y)` | `minX, minY, maxX, maxY`: the chunks within `UPDATE_RADIUS_CHUNKS` of the chunk containing `(x, y)`, clamped to the world |

## Seed lifecycle

1. The host (or the player, offline) picks a seed with `random_seed()` and stores
   it with `net_set_match_seed(seed)`. This is done by `aval_cup_world.lua` the
   first time it runs and finds no seed.
2. `DamageSync` keeps the seed next to `pvp` in the room settings. Online,
   `setMatchSeed` broadcasts `room_settings {pvp, seed}`.
3. A late joiner gets it in the `settings` of the host's `snapshot`
   (`{pvp, seed}`), so `net_room_settings().seed` is set on every client.
4. Clients without a seed build nothing and show "Sincronizando mapa..".
5. The seed is cleared only on disconnect (`resetSettings`), so the host
   restarting the scene (ENTER after game over) keeps the same map. Going back
   to the menu disconnects, so the next game gets a new seed.

`0` means "unset": valid seeds are `1..0xFFFFFFFF`.

## Hash and RNG

Map generation never uses `math.random` (it is C `rand()`: not portable, and the
stream is shared with the rest of the game). `map_grid.lua` does integer math
only, masking every step with `& 0xFFFFFFFF`:

- `hash(seed, cx, cy)` mixes the three integers with murmur3's `fmix32`.
  An optional fourth argument `salt` adds one more `fmix32` round, so each
  generation concern gets its own independent stream (`SALT_BIOME`,
  `SALT_PLANET`, `SALT_ROCKS`, `SALT_DRIFT`, `SALT_WRECK`, `SALT_NEBULA`, `SALT_REACTOR`, `SALT_PORTAL`, `SALT_NEXUS`, `SALT_SUPPLY`). Without a salt the
  result is bit-identical to the original hash.
- `rng(state)` is mulberry32 seeded with that hash. `next()` is `integer / 2^32`.

`tests/map_determinism.lua` checks that the same seed gives the same world, a
different seed a different one, the grid helpers, and the content rules below
(biomes, planets, spacing, drift, wrecks) over many seeds.

## Biomes

Every sector has a biome, assigned by `map_biomes.assign(seed)` from a single
rng (`hash(seed, 0, 0, SALT_BIOME)`). The weights are in `BIOMES`:

| Biome | Weight | Content |
| --- | --- | --- |
| `debris` | 35 | Default field; can have wrecks |
| `planetary` | 20 | 1-3 planets |
| `dense_belt` | 15 | 10-14 large rocks per chunk instead of 4-6 |
| `deep_void` | 15 | Large rocks only, no medium/small ones |
| `nebula` | 10 | Same rocks as debris (visuals come later) |
| `reactor` | 5 | One [Reactor Remains](#reactor-remains) megastructure and 1-2 wrecks per chunk |

Rules:

- The **center sector** (2, 2) is picked first, among `CENTER_BIOMES` (only
  `planetary`, so the spawn point never lands on a reactor structure).
- The other sectors follow in reading order. Each one picks (by weight) among
  the biomes that none of its **orthogonal** neighbours already assigned has:
  up, down, left and right. Diagonal neighbours may repeat. `debris`
  (`BIOME_REPEAT_OK`) is always allowed, so there is always a valid choice.
- `map_biomes.layout(seed)` returns `{ biomes = grid[sx][sy], planets = list }`
  and is memoized per seed (every chunk asks for it). The director publishes
  `biomes` as the global `map_biomes`, and the minimap tints each sector with
  `BIOME_COLORS`.

## Asteroids

`map_chunks.generate_chunk(seed, cx, cy)` is a pure function of its arguments.
It keeps the content out of the `STORM_BAND` strip at the world edge and
returns spawn states: `pos`, `vel`, `rot`, `kind`
(`pickAsteroidType(rng:next())`), `scale`, `world = true`, `cull = true` and
`chunk_id = "cx:cy:i"`. `generate_world(seed)` returns
`{ ["cx:cy"] = states }` for the 10 x 10 chunks.

| Size | Scale | Per chunk | Min spacing (centres) |
| --- | --- | --- | --- |
| Large | 1.0..1.5 | 4-6 (`LARGE_ROCKS`), 10-14 in `dense_belt` | 300 (`LARGE_SPACING`) |
| Medium | 0.6..1.0 | 6-10 medium + small, half each (`SMALL_ROCKS`); none in `deep_void` | 120 (`SMALL_SPACING`) |
| Small | 0.3..0.6 | (same) | 120 |

Medium and small rocks keep `max(SMALL_SPACING, rA + rB + 20)` from large rocks.

Rocks are placed with **Poisson-disk sampling** (dart throwing):
`asteroid_field.poisson_points` throws up to `ROCK_TRIES` (30, fixed so the
result is deterministic) darts per rock, with the scale sampled per try, and
rejects a dart that is too close to a previous rock or inside a planet's
gravity well (`planet.range + rock radius`). It uses only the rng it is given,
never `math.random`. The sampling rect is **inset by `min_dist / 2`** on every
side, so the spacing also holds across chunk borders. A rock that finds no
spot after 30 tries is dropped, so a chunk can hold fewer rocks than the roll.

Rocks, drift and wrecks each use their own rng stream (different salts), so
retuning one does not reshuffle the others.

## Drift and dust

Each rock drifts with probability `DRIFT.chance` (0.2), at a speed in
`DRIFT.speed` (20-40 px/s). The generator tries up to `DRIFT.tries` (12) random
angles and keeps the first whose **ray** (the infinite half-line from the rock)
stays farther than `planet.range + radius` from every planet centre, so a
drifting rock never enters a gravity well. If no angle works the rock stays
static. A drifting rock has `vel`, `drift = true`, `despawn_far = true` and **no
`cull`**: it is simulated everywhere, so it does not freeze when you look away.
The host deletes it when it leaves `scene_bounds` and broadcasts the
destruction through the usual `map_rock_destroyed` path.

Every client gives a drifting rock a **dust trail** (`drift-dust`, an 8-frame
32x32 strip): a local entity placed behind the rock, opposite to its velocity,
rotated to the heading and animated. `asteroid.lua` destroys it in `on_death`
(which also runs when the director calls `destroy_entity`) and in `vanish`.
`DUST_ANGLE_OFFSET` aligns the diagonal of the art with the heading; tune it by
eye if the art changes.

## Planets

`planetary` sectors hold `PLANETS_PER_SECTOR` (1-3) planets, picked by
`map_biomes.planets(seed, grid)` with an rng per sector
(`hash(seed, sx, sy, SALT_PLANET)`). Each planet takes a template from
`solar_system_config.BODIES` (everything but the Sun) and derives its scale,
mass and range with `solar_system_config.planet_from_body` (the same formulas as
`build_planets`). It is named `"<template> <sx>-<sy>"` and carries its `role`
and `sector`. Placement is rejection sampling (`PLANET_TRIES`): centres at least
`PLANET_SPACING_FACTOR` (2.5) x the sum of their ranges apart. A sector can end
up with fewer planets than rolled, but always at least one (the sector centre
is the fallback).

**Edge rule.** Asking for the planet to be at least one chunk (2000 px) from the
sector edge would only leave the sector centre free in a 4000 px sector, so 1-3
planets could not fit. Instead the whole gravity well stays inside the sector:
the centre is at least `range + PLANET_EDGE_PAD` (100) from every sector edge.
No gravity well may cover the player spawn (`PLAYER_SPAWN`, the world centre):
planets keep `range + SPAWN_CLEAR_PAD` (300) away from it. If the centre
sector's first planet finds no spot, the smallest body is placed just outside
that margin, to the right of the spawn.

Roles (`PLANET_ROLES`, weights 3:1:1): `mining`, `merchant`, `tech`. Only
`mining` planets keep `mineral` and `mine_interval` and can be mined.
**Merchant and tech planets are only tagged**: their behaviour comes in later
issues. The director creates each planet with `spawn_local("planet.lua", p)`
(no cull, no script) and appends it to `scene_planets`, which the minimap and the
gravity zones read.

## Wrecks

In `debris` and `reactor` chunks, with probability `WRECK_CHANCE` (1/3), one
large rock becomes a wreck (`state.wreck` is an index in `WRECK_TYPES`: cargo
hull or robot arm). A wreck never drifts, has 2.5x health and is drawn from its
own 96x96 sheet (frame 0, collider radius `WRECK_SHEET.bodyRadius`). When shot
dead (not rammed by a ship) the host drops the type's `bonus` pickups **in
addition to** the normal split into fragments (plain rocks of the same kind).

## Local rocks and destroy sync

Chunk rocks are **local entities**: every client builds them from the seed with
`spawn_local("asteroid.lua", state)`, with no netId and no `spawn` message. The
whole map is generated at load. Only the changes travel:

- The **host** is authoritative. In `asteroid.lua`, a rock with a `chunk_id` is
  owned by whoever `net_is_host()`. When one dies on the host, the global
  `map_world_destroyed(id)` (defined by the director) records the id in
  `map_destroyed` and sends the custom message `map_rock_destroyed {id}`.
- Clients drop `map_rock_destroyed` unless `from == net_host_id()`, record the id
  and destroy their copy if it is alive. A rock that dies on a client by itself
  is just marked dead: no loot and no split. Fragments and pickups come from the
  host through the normal `net_spawn` path.
- A late joiner's `snapshot_request` makes the host send `map_destroyed {ids}`
  (direct, batches of 400 ids, under the relay's 12 KB limit). The joiner
  merges the ids and skips those rocks when it builds the world.
- `map_destroyed` is reset by the scene file on every load; it is also what a
  new host keeps after migration, since every client records the ids.
- `asteroid.lua` calls `map_rock_gone(id)` when a rock dies so the director never
  holds a stale entity id (ids are recycled).

See [multiplayer-protocol.md](multiplayer-protocol.md) for the messages.

## Culling

`CullComponent` (scene component `cull = true`) marks an entity as sleeping when
its position is outside the active area. `set_active_area(minX, minY, maxX, maxY)`
sets that area and `clear_active_area()` turns it off (it is also turned off on
every scene load). `aval_cup_world.lua` sets it each frame from
`map_grid.active_bounds(player center)`; while the player is dead the last area
is kept.

Sleeping entities are skipped by the script, animation, gravity, movement,
collision, render and collider-overlay systems. Network sync, damage and text
systems are untouched: chunk rocks are not networked and damage only reacts to
collisions.

## Config table

| Key | Value | Meaning |
| --- | --- | --- |
| `WORLD_SIZE` | 20000 | World side (px) |
| `SECTORS`, `SECTOR_SIZE` | 5, 4000 | Sector grid |
| `CHUNKS_PER_SECTOR`, `CHUNK_SIZE` | 2, 2000 | Chunk grid |
| `STORM_BAND` | 500 | Edge strip consumed by the storm (no content) |
| `STORM` | table | Border storm: `damage` 4, `tick` 1 s, `tile_size` 250, sprite frames, `edge_height` 90, `edge_overlap` 0.5, `fps` 6, `alpha`, `tint_alpha` |
| `WANDERING_STORM` | table | Wandering Storms: `count` 2, `radius` 1000..2000, `speed` 35..55, `turn_rate`, `damage` 3, `tick` 1 s, `push_speed` 110, `push_accel` 220, `front_pad`, `spawn_clear`, `edge_height`, `tile_alpha`, `icon_size` |
| `UPDATE_RADIUS_CHUNKS` | 2 | Chunks around the player that are simulated |
| `STABLE_PORTAL_PAIRS` | 12 | Stable portal pairs |
| `NEXUS_COUNT` | 1 | Portals (not used yet) |
| `PORTAL_CLEAR_RADIUS` | 600 | No large rocks within this radius of a portal end |
| `PORTAL_COOLDOWN` | 4 | Seconds before a ship can enter a portal again |
| `PORTAL_EXIT_WARNING` | 0.75 | Seconds the exit flashes before the ship arrives |
| `PORTAL` | table | Stable portals: `pair_sectors` 2..4, `planet_factor` 1.5, `spacing` 1500, `spawn_clear` 1500, `tries` 300, `enter_radius` 70, `pull_radius` 250, `pull_accel` 140, `exit_offset` 120, `min_exit_speed` 150, `storm_warn_pad` 1200, draw sizes, `warp_time`, `fps`, `icon_size`, `sheets` (sprite sheet sizes and frame counts) |
| `UNSTABLE_PORTAL_LIFE` | 45..75 | Portals (not used yet) |
| `EVENT_INTERVAL` | 60..120 | Seconds between events in an occupied sector (see [Event director](#event-director)) |
| `EVENTS` | table | Event director: `per_players` (3 events per 10 players), `retry` 5 s, `banner_time` 4 s, `banner` (640x80 at y 40), `banner_src` (strip inside `event_banner.png`), `icon_size` 12, `types` (name, colour, optional minimap icon and duration of each of the 6 event types) |
| `STORM_CONTRACTION_INTERVAL` | 180..240 | Seconds between storm contractions (see [Storm Contraction](#storm-contraction)) |
| `STORM_CONTRACTION_SAFE_RADIUS` | 1500 | Radius (px) of the final safe circle of a contraction |
| `STORM_CONTRACTION` | table | `warning` 30 s, `shrink` 60 s, `hold` 15 s, `damage` 5, `tick` 1 s, `start_radius` (sector half-diagonal), `edge_height` 260, `tile_alpha` 225, `highlight` colour and alpha, `ring_dot_spacing`, `crate_clear` 400, `crate_tries` 40 |
| `LOOT_CRATE_PAL` | table | High-loot crate: `size` 72, `sheet` (frame width, count and the `src_y` / `src_h` strip of the crate), collider `radius`, `loot` (30 iron, 15 gunpowder, 8 plasma) |
| `PAL_SIGNAL` | table | Pal Signal: `duration` 90 s, `crate_clear` 400, `crate_tries` 40, `edge_pad` 500, `beam` (draw `w` x `h` 64x512 px and the `pal_beacon.png` sheet: `frame_w` 181, `frame_h` 1448, `count` 6), `fps` 8, `alpha` 220 |
| `DEBRIS_RAIN` | table | Debris Rain: `warning` 5 s, `rain` 20 s, `tail` 5 s, `rate` 3 rocks/s, `speed` 320..420, `scale` 0.25..0.5, `spread` 0.08 rad, `ttl` 25 s, `arrow_size` 48, `arrow_margin` 24, `arrow_count` 3, `warn_pad` 2000 |
| `OVERCHARGED` | table | Overcharged Planet: `duration` 60 s, `mult` 2, `sheet` (aura frame width, count and the `src_y` / `src_h` band), `size_factor` 1.6, `fps` 8, `alpha` 200, `ring_dot_spacing` 30, `colors` per mineral |
| `DEATH_DROP_FRACTION` | 0.6 | Players (not used yet) |
| `SPAWN_SHIELD` | 5 | Players (not used yet) |
| `BIOMES` | see [Biomes](#biomes) | Id, name and weight of each biome |
| `BIOME_REPEAT_OK`, `CENTER_BIOMES` | `debris`, `planetary` | Adjacency exception and centre sector pool |
| `BIOME_COLORS` | per biome | Minimap tint |
| `ROCK_SIZES` | 1.0..1.5 / 0.6..1.0 / 0.3..0.6 | Scale of large / medium / small rocks |
| `LARGE_ROCKS`, `LARGE_ROCKS_DENSE` | 4..6, 10..14 | Large rocks per chunk |
| `LARGE_SPACING` | 300 | Min distance between large rocks (px) |
| `SMALL_ROCKS`, `SMALL_SPACING` | 6..10, 120 | Medium and small rocks per chunk and spacing |
| `ROCK_TRIES` | 30 | Darts per rock |
| `DRIFT` | 0.2, 20..40, 12 | Chance, speed (px/s) and heading tries |
| `WRECK_CHANCE`, `WRECK_BIOMES` | 1/3, `debris`/`reactor` | Wrecks per chunk |
| `PLANETS_PER_SECTOR` | 1..3 | Planets per Planetary sector |
| `PLANET_SPACING_FACTOR`, `PLANET_TRIES`, `PLANET_EDGE_PAD` | 2.5, 40, 100 | Planet placement |
| `PLAYER_SPAWN`, `SPAWN_CLEAR_PAD` | world centre, 300 | Spawn point kept clear of gravity wells |
| `PLANET_ROLES` | mining 3, merchant 1, tech 1 | Role weights |
| `REACTOR.variants` | ring 1, hull 1 | Weights of the structure variants |
| `REACTOR.ring_size`, `hull_piece` | 2800, 520 | Drawn size (px) of the ring and of the square hull pieces (the straight is 1.5x wider) |
| `REACTOR.core_size`, `core_frame`, `core_cols` | 600, 362, 4 | Core sprite: drawn size, frame side in the sheet, frames per row |
| `REACTOR.clear_pad` | 250 | No rocks within `site.radius + clear_pad` |
| `REACTOR.wrecks` | 1..2 | Wrecks per reactor chunk (replaces `WRECK_CHANCE` there) |
| `REACTOR.ship_clearance`, `min_gap` | 120, 350 | Min clearance from a gap point to any collider; min hull gap width (tests) |
| `REACTOR.pulse` | see [Reactor Pulse](#reactor-pulse) | Radius, push, charge, wave time, warning radius |

The minimap in `solar_hud.lua` shows the biome of each sector as a tint, the
5 x 5 sector grid, the storm band as an inset outline, the planets and the
current sector or nearest planet when `scene_map` is set.

## Reactor Remains

Every `reactor` sector gets one collidable megastructure at its centre, built by
`map_reactor.sites(seed)` (pure function of the seed, memoized per seed, own
stream `hash(seed, sx, sy, SALT_REACTOR)`, no `math.random`). A site is
`{ index, sx, sy, x, y, variant, rot, pieces, colliders, core, radius, gaps }`:

- `variant`: `ring` (one 2800 px ring with four gaps) or `hull` (square
  enclosure of modular pieces), picked by `REACTOR.variants`. `rot` is a
  multiple of 90 degrees.
- `pieces`: the drawn sprites (`reactor_hull_01..04`, `reactor_ring`).
- `colliders`: invisible circles (`{x, y, r}`) placed along the art. The engine
  only has circle colliders, so the templates (alpha-mask measurements, in
  normalized piece units) live in `map_reactor_data.lua` as data to tune.
  Press **C** in game to see them.
- `gaps`: the world point at the middle of each gap. The hull has four, each at
  least `min_gap` (350 px) wide; the ring has four narrower ones (about 270 px).
  The map test checks that no collider circle is closer than `ship_clearance`
  to a gap point.
- `radius`: the farthest collider edge from the centre. `map_reactor.blocks`
  and the rock generator keep rocks out of `radius + clear_pad`, and drifting
  rocks never cross that disc (the site counts as a pseudo-planet in
  `ray_is_clear`).
- `core`: the animated core (`reactor-pulse` sheet) at the centre.

The `hull` layout is a four-fold pinwheel of one side: `hull_02` corner,
`hull_01` straight, a gap, and a `hull_03` block turned 180 degrees so its
jagged edge faces the gap, plus two detached `hull_04` pieces inside the
enclosure as cover. Outer extent stays within 1500 px of the centre so it fits
a sector next to the storm band.

Loot: a reactor chunk turns `REACTOR.wrecks` (1-2) distinct large rocks into
wrecks with probability 1 (capped by the number of large rocks the chunk got).

`map_reactor_world.lua` (a director after `aval_cup_world.lua`) builds every
site once with `spawn_local`, in this order: pieces
(`prefabs/reactor_piece.lua`, no collider), colliders
(`prefabs/reactor_collider.lua`) and the core (`prefabs/reactor_core.lua`). All
of them have `cull = true`. It publishes the site list as the global
`reactor_sites` (the minimap draws a marker per site; Wandering Storms #21 can
anchor to it).

Collision: each collider runs `reactor_hull.lua`. A local ship (it has an
inventory) and a rock (it has loot) get their velocity reflected off the circle
normal (restitution 0.4; the ship also gets a minimum outward speed of 60). A
bullet is recognised as "has damage and gravity, no health, loot or inventory"
and is destroyed locally (`destroy_entity`, never `net_despawn`). The hull has
no health, so ships and bullets cannot hurt it. Each collider carries the same
`damage` component as an asteroid (`ASTEROID_DAMAGE` with `IMPACT_MIN_SPEED` /
`IMPACT_FULL_SPEED`), so ramming it hard hurts through the usual
`DamageSystem` impact path.

### Reactor Pulse

A radial wave pushes everything near a site outward. Phases per site: idle
(core frames 0-1), charge (`pulse.charge` seconds, core frames 2-3, red warning
ring and the text "PULSO DEL REACTOR" if the ship is within `warn_radius`) and
wave (core frames 4-7 and an expanding dotted ring over `wave_time`).

At the end of the charge every client adds `max_push * (1 - d / radius)` px/s
outward velocity (at least `min_push`, for `d < radius`) to:

- its own ship (owner-authoritative, replication carries it);
- the chunk rocks near the site (`map_rocks_near(x, y, r)`, defined by
  `aval_cup_world.lua`; each client pushes its local copy);
- the net asteroids in `drifting_asteroids` that it owns (`is_local`).

`set_velocity` is not capped by `max_speed`. A ship pushed into a rock or the
hull takes impact damage; nothing new is needed.

Trigger: only the host fires pulses. The [event director](#event-director)
does it through the registry: `map_reactor_world.lua` registers
`map_event_types.reactor_pulse`, whose `pick(sx, sy)` returns the first idle site
in that sector (`{ i, x, y }`) and whose `fire(p)` calls the global
`reactor_pulse_fire(i)`. That function sends `reactor_pulse {i}` and starts the
charge locally. The debug key **K** (`debug_pulse`, nearest site to the ship)
calls it directly. Clients start the charge on `reactor_pulse` only if `from ==
net_host_id()` (and never their own). There is no per-site timer any more.

## Biome visuals

`map_visuals.lua` (a director) draws everything with `draw_image`.

- **Backgrounds**: each biome has a tiled background (`BIOME_BACKGROUNDS`,
  `BG_TILE`) that scrolls at `BG_PARALLAX` of the camera speed. Within
  `BG_BLEND` px of a sector border the backgrounds of the neighbouring sectors
  crossfade with continuous bilinear weights (0.5 / 0.5 on the border).
- **Nebula**: `map_nebula.lua` computes a 2-octave value noise (`NEBULA.cell`)
  scaled by a falloff towards the sector border (`edge_pad`); above
  `threshold` the point is inside the cloud (about 70% of the sector, with
  irregular edges). Clouds are placed on a jittered grid from the seed, so all
  clients see the same ones. Back clouds are world-anchored; about a third are
  front clouds drawn over the ships with a higher parallax.
- **Vignette**: while the local ship is inside a cloud, `nebula-vignette` fades
  in/out over `vignette_fade` seconds. `local_in_nebula` is a global flag.
- **Minimap**: `solar_hud.lua` draws other players as red dots, except those
  inside a nebula cloud; the local ship is always shown.

## Storm

The map edge is a permanent Storm band of `STORM_BAND` (500 px) on every side.
There is no global Death Zone: the only circle in the code, `scene_bounds`, just
culls fragments that leave the world.

- Inside the band (or outside the world) the local ship takes `STORM.damage`
  (4) HP every `STORM.tick` (1 s). The first hit lands one tick after entering;
  leaving resets the timer. Damage uses `set_health`, so it is owner-only.
- Visuals: animated `storm-tile` fill on the back layer plus `storm-edge` strips
  along the inner rectangle `[STORM_BAND, WORLD_SIZE - STORM_BAND]^2`, ragged
  side facing the safe area. While inside, a red tint and a "TORMENTA" warning
  are shown, and the global `local_in_storm` is set.
- Code: `map_storm_world.lua` (director) uses the shared, stateless
  `map_storm.lua` so Wandering Storms (#21) and Storm Contraction (#25) can reuse it:
  `in_border(x, y)`, `new_damage()`, `tick_damage(state, entity, inside, dt)`,
  `frame(clock)`, `src(frame_cfg, i)`, `draw_fill(camX, camY, sw, sh, frame, inside_fn)`,
  `draw_edge_segment(x1, y1, x2, y2, inward_angle, camX, camY, sw, sh, frame)`,
  `draw_tint(w, h, alpha)`. #21 adds optional `damage, tick` to `tick_damage`,
  optional `ox, oy, alpha` to `draw_fill`, `draw_edge_ring(cx, cy, r, height, ...)`,
  `wandering()` and `in_wandering(x, y, pad?)`.

### Wandering Storms

Round Oxblood clouds 1-2 chunks across (`WANDERING_STORM.radius` 1000..2000)
that drift slowly over the map and force players to keep moving.

- Lifecycle: the host keeps `WANDERING_STORM.count` (2) alive from
  `map_storm_world.lua` with `net_spawn("wandering_storm.lua", {pos, vel, radius, world = true})`.
  The first ones appear at a random interior point at least `spawn_clear` from
  `PLAYER_SPAWN`; replacements enter from a random edge, heading to the middle of
  the map. The owner random-walks the heading (`turn_rate`) and despawns the
  storm once it is well outside the world. They are `world = true`, so late
  joiners get them from the snapshot and, if the host leaves, the new host keeps
  moving and refilling them (the count comes from `wandering_storms`, which every
  client fills). The entity has no sprite: its transform position is the cloud
  centre, and the radius travels in the spawn state.
- Damage: while the local ship is inside, `WANDERING_STORM.damage` (3) HP every
  `tick` (1 s), on a separate timer from the border storm.
- Front push: ships in the front half of the cloud (up to `front_pad` beyond the
  radius) are accelerated (`push_accel`) up to `push_speed` along the heading.
- Visuals: `storm-tile` fill that moves with the cloud plus a ragged
  `storm-edge` ring facing outward. Tint and "TORMENTA" show inside either storm.
- Minimap: a faint outline of the cloud and the `icon-storm` icon, drawn on the
  `"hud"` image layer so it sits above the minimap panel.
- Portals (#22): `storm.in_wandering(x, y, pad?)` tells whether a point is inside
  any wandering storm; `map_portal_world.lua` uses the list from `storm.wandering()`.

## Portals

12 permanent two-way pairs let players cross the map on purpose (issue #22).

- Placement: `map_portals.lua` is a pure function of the seed
  (`portals.sites(seed)`, stream `hash(seed, 0, 0, SALT_PORTAL)`, no
  `math.random`), so every client gets the same pairs. For each pair it picks the
  sector of end A among the Deep Void and Debris sectors (so at least one end is
  always there) and the sector of end B at 2..4 sectors from A (Chebyshev
  distance); then a random point in each, kept `PORTAL_CLEAR_RADIUS` away from the
  sector edges. A point is valid when it is inside the world minus the storm
  band, clear of Reactor Remains structures (`reactor.blocks`), at least
  `planet_factor` x `range` from every planet (1.5 gravity radii), at least
  `spawn_clear` from `PLAYER_SPAWN` and at least `spacing` from every other end.
  After `tries` failed attempts the pair is skipped and a line is printed. Each
  end has a random exit axis. `portals.blocks(ends, x, y, radius)` is used by
  `map_chunks.lua` so no rock spawns within `PORTAL_CLEAR_RADIUS` of an end, and
  the ends count as obstacles for drifting rocks.
- Entering: within `pull_radius` of an open end the ship feels a light pull
  (`pull_accel`). Within `enter_radius` (and off cooldown) it enters: it is
  parked on the portal with no input for `PORTAL_EXIT_WARNING` (0.75 s) while the
  destination flashes. It then appears `exit_offset` px out of the other end,
  along its axis, with the same speed (at least `min_exit_speed`). The cooldown
  (`PORTAL_COOLDOWN`, 4 s) starts on exit and a box near the bottom of the
  screen shows it. A chaser who enters right behind exits right behind: same
  delay, same exit point.
- Bullets: a bullet that touches an open end comes out of the other with the
  same speed along its axis, with no delay. Each bullet hops only once
  (`bullet_lifetime.lua` calls the global `portal_bullet_step`).
- Storms: a pair is closed (portals dimmed, no pull or entry, bullets pass by)
  while a Wandering Storm covers either end. If a storm is within
  `storm_warn_pad` of an end, the opposite end shows the bordeaux
  `portal-warning-halo`.
- Networking: the owner of the ship applies the teleport and sends
  `teleport { netId, x, y, vx, vy }`; other clients move their copy and call
  `net_reset_correction`, so it is not smoothed as drift. On entry the owner
  also sends `portal_warn { pair, side }` so every client flashes the exit. See
  [multiplayer-protocol.md](multiplayer-protocol.md).
- Visuals: `portal-stable` (8 frames, rotated to the axis; the art's notch points
  up, so the angle is `deg(axis) + 90`), `portal-exit-flash` (6 frames over the
  warning time), `portal-warning-halo` (4 frames), `portal-warp` (6 frames,
  distortion on entry and exit). The sheets are not the sizes in the issue: the
  real ones are in `PORTAL.sheets` and frames are drawn keeping their proportion.
- Minimap: a violet square per end with the pair number next to it (`small` font).
- Code-drawn: `icon_portal_pair.png` and `portal_cooldown.png` do not exist, so
  the minimap icon and the cooldown box are drawn with `draw_rect`/`draw_text`.
- Code: `map_portal_world.lua` (director, publishes `portal_sites` and
  `local_portal_transit`; `player.lua` skips shooting and thrust while it is set).

### Unstable portals

Issue #23. One-way portals to a random destination, owned by the host.

- Count: the host keeps `ceil(players / per_players)` (10 players per step)
  times a 1..2 roll alive (`UNSTABLE_PORTAL`), re-rolled after each spawn, with
  `spawn_interval` (8-15 s) between spawns. The count comes from the shared
  `unstable_portals` table, so a migrated host does not duplicate them.
- Entity: `prefabs/unstable_portal.lua` (invisible, transform only) spawned with
  `net_spawn("unstable_portal.lua", { pos, life, world = true })` at a point that
  passes `portals.valid_point` and is `spawn_clear` from `PLAYER_SPAWN`. Its
  script (`unstable_portal.lua`) counts `life` down (45-75 s,
  `UNSTABLE_PORTAL_LIFE`) and writes `unstable_portals[netId] = {x, y, life, age}`
  on every client; the owner despawns it `collapse_time` after `life` hits 0.
- Phases: `portal-open` for `open_time` (not enterable), `portal-unstable`
  looping with an irregular frame order, flicker (alpha) for the last
  `flicker_time` (10 s), then `portal-collapse` over `collapse_time`.
- Entering: within `enter_radius` (50 px) while open (a half-strength pull
  applies). The destination is picked locally with `math.random` among points
  that pass `portals.valid_point` (world band, no Reactor Remains, planets or
  spawn nearby) with a random axis. Nobody knows it before coming out: no exit
  flash and no `portal_warn`. Same transit, `teleport` event and cooldown.
- Bullets: `portal_bullet_step` checks unstable portals first; a bullet within
  `enter_radius` of an open one is destroyed (`destroy_entity`, local, returns
  `"destroyed"`; `bullet_lifetime.lua` stops there). This applies even to a bullet
  that already hopped.
- Late join: `portal_state.unstable` carries the remaining life per netId; the
  joiner stores it in `unstable_portal_life_fix`, which each script applies once.
- Minimap: `icon-portal-unstable` at `icon_size`.
- Sheets (not the sizes in the issue): `portal-unstable` 2172x724, 8 frames;
  `portal-open` 1983x793, 10; `portal-collapse` 2172x724, 10; all in
  `PORTAL.sheets`.

### Nexus

- Placement: `portals.sites(seed).nexus`, stream `SALT_NEXUS` (9), after the
  pairs. A valid point (same rules, `spawn_clear` from the spawn, `spacing` from
  other ends) in the center sector, then 4 exits, one per direction (E, S, W,
  N): each a valid point in a sector at Chebyshev distance `exit_sectors` (2)
  from the center in that direction (e.g. east: column center+2, any row). Each
  exit's axis points away from the nexus. If anything fails after `tries`
  attempts the nexus is skipped and a line is printed (`nexus = nil`).
- Entering: pull within `pull_radius`, entry within `enter_radius`, same transit
  as a stable end. The angle of the ship around the nexus center picks the mouth:
  bucket `floor((a + pi/4) / (pi/2)) % 4` = E, S, W, N (y points down), and the
  ship leaves by the exit of that direction. Bullets do the same, with no delay.
  The exit flashes on every client via `portal_warn { nexus = dir }`.
- Visuals: `nexus` sheet (1774x887, 8 frames, drawn unrotated at `draw_size`).
  Minimap: `icon-nexus` (the exits are not shown).

### Portal Collapse

- Reserve sites: after the 12 pairs, `map_portals.lua` builds `reserve_pairs` (6)
  more pairs from the same stream (so the 12 stay identical) in `reserve`. All
  ends, reserves and nexus points are in `ends_all`, which `map_chunks.lua`
  uses so reserve sites are already clear of rocks.
- Flow: the pair starts a `warning` (15 s). While warning it draws as
  `portal-unstable` and flickers (faster in the last 3 s) but is still usable;
  within 2000 px of an end a centered "COLAPSO DE PORTAL" and the seconds show,
  and the minimap square blinks. At 0 on every client: `portal-collapse` plays
  on both old ends, the pair is removed, its site goes to the back of the queue,
  and the first site that shares no sector with the old ends opens with the
  same pair id (the minimap still shows 12 numbered pairs). It plays
  `portal-open` and cannot be entered for `open_time`. Pairs are resolved in id
  order, so every client gets the same result.
- Trigger: the [event director](#event-director) fires it through the registry.
  `map_portal_world.lua` registers `map_event_types.portal_collapse`: `pick(sx,
  sy)` picks at random a pair that is open (`open == 0`), not collapsing and has
  an end in that sector (`{ pair, x, y }`), and `fire(p)` calls the global
  `portal_collapse_fire(id)` (host only, random pair if no id). Key `L`
  (`debug_collapse`, host only) fires one by hand. There is no timer here any more.
- Networking: `portal_collapse { pair }` (host to all, ignored unless from the
  host and not from ourselves). On `snapshot_request` the host sends
  `portal_state { history, pending, unstable }` straight to the joiner: the
  ordered ids of finished collapses (replayed instantly, no effects), the
  warnings in progress with their time left, and the unstable portals' life.
  Every client records the history, so a migrated host has the same state.
- Visuals: `portal-collapse` (also used for unstable portals) and `portal-open`.

## Event director

`map_event_director.lua` (invisible director, script only) keeps the map alive.
Only the host fires events; every client keeps the same state, so a migrated
host carries on.

- Types: `EVENTS.types` knows all 6 (Reactor Pulse, Portal Collapse, Storm
  Contraction, Pal Signal, Debris Rain, Overcharged Planet) with name, colour,
  optional minimap icon and duration. A type only fires once its script
  registers a hook. Today `reactor_pulse`, `portal_collapse`, `storm_contraction`, `pal_signal`,
  `debris_rain` and `overcharged_planet` do (the last three through
  `map_event_world.lua`), all without touching the director.
- Hook contract, global `map_event_types[type]` (the script sets
  `map_event_types = map_event_types or {}` first):
  `pick(sx, sy) -> params | nil` (host: an eligible target in that sector;
  `params` must include `x, y` for the minimap icon), `fire(params) -> bool`
  (host: start the gameplay, it may send its own net message) and optional
  `on_start(ev)` / `on_end(ev)` that run on EVERY client.
- Sector rule: each sector occupied by a ship (the local one plus every
  `player_ships`) has a timer that starts at `EVENT_INTERVAL` and counts down
  only while the sector is occupied. At 0 the host picks at random among the
  registered types (except Storm Contraction) that are not the last one fired in
  that sector, are not already active there and have a target (`pick`). If it
  starts one the timer resets to `EVENT_INTERVAL`; if nothing is eligible or the
  cap is reached, it retries in `EVENTS.retry` (5 s).
- Cap: `max(1, ceil(players * 3 / 10))` active events (1 with one player).
- Storm Contraction: its own timer (`STORM_CONTRACTION_INTERVAL`). At 0, if the
  type is not registered it just resets. Otherwise the host fires it in a random
  occupied sector whose last event was not a contraction, only if none is
  active and the cap allows; on failure it retries in 5 s.
- Events live in the global `map_events` (`id -> { id, type, sx, sy, params, t }`,
  `t` = seconds left). Every client counts `t` down; the host ends the event at 0.
  The id is `<playerId>#<n>` so ids are unique across hosts.
- Net (custom types, see [multiplayer-protocol.md](multiplayer-protocol.md)):
  `event_start`, `event_end` (host to all) and `event_state` (host to a joiner,
  answering `snapshot_request`: active events and the last type per sector, no
  banners; buffered if it arrives before `map_seed`). Clients accept them only
  from the host and never their own.
- Banner: one at a time for `banner_time` (4 s, 0.3 s fades), centred at the top:
  the `event_banner.png` strip (`banner_src` crops its transparent padding),
  "PAL ENTERTAINMENTS" and "<NAME>  -  SECTOR (sx,sy)" in the event colour (the
  16 px font if the title would not fit the box). The reactor and portal
  warnings sit lower, at 20% of the screen height.
- Minimap: each active event blinks the outline of its sector in the event
  colour and draws its icon at `params.x, params.y` (sector centre if absent);
  types without an icon get a filled square.
- Debug key **J** (`debug_event`, host only): sets the timer of the local ship's
  sector to 0. The normal rules still apply (cap, last type, target).

## Storm Contraction

Issue #25. `map_storm_contraction.lua` (required by `map_storm_world.lua`)
registers `map_event_types.storm_contraction`. The [event director](#event-director)
schedules it (own timer, one at a time, counts toward the cap); this module only
supplies the gameplay and visuals.

- Phases, from `elapsed = duration - ev.t` (so every client, a joiner included,
  sees the same one; no extra net messages). `EVENTS.types.storm_contraction.duration`
  is `warning + shrink + hold` = 105 s:
  - `warning` (30 s): no damage. The sector outline blinks in the world and the
    final safe circle (`STORM_CONTRACTION_SAFE_RADIUS`) shows as a dotted ring.
    A ship inside the sector sees "CONTRACCION EN Ns".
  - `shrink` (60 s): the safe radius goes linearly from `start_radius` (the
    sector half-diagonal, so the circle covers the whole sector) to 1500.
  - `hold` (15 s): stays at 1500 px. When the event ends the storm clears.
- Storm area: inside the sector rectangle AND farther from the sector centre than
  the current radius. Damage (`damage` every `tick` s), storm tiles (aligned to the
  sector corner), the irregular edge ring (pieces outside the sector are skipped
  through the `filter` of `storm.draw_edge_ring`) and the screen tint apply only
  there; nothing changes outside the chosen sector. The damage is its own
  accumulator in `map_storm_world.lua` and shares the tint and "TORMENTA" text
  with the border and wandering storms.
- Hook: `pick(sx, sy)` returns `{ x, y, cx, cy }` (`cx, cy` the sector centre;
  `x, y` the crate spot and minimap icon). The spot is the centre, or, if a
  planet's body plus `crate_clear` covers it, a random point (up to
  `crate_tries`) inside the final circle; with none it returns nil and the sector
  is skipped. `fire(p)` (host) spawns the crate and stores its netId in
  `p.crate` (the director copies params after `fire`, so every client gets it).
  `on_end(ev)` (host) despawns the crate if nobody opened it.
- Crate: `prefabs/loot_crate_pal.lua` + `loot_crate.lua`, a still world entity
  (frame 0 of `loot_crate_pal.png`) carrying `LOOT_CRATE_PAL.loot`. The local ship
  that touches it gets the loot through the pickup flow of `loot_net.lua`
  (single delivery, `pickup_request` if the crate is remote). No magnet. The
  opening animation is drawn by `map_supply_world.lua` (see
  [Supply containers](#supply-containers)).

### Pal Signal

Issue #26. `map_pal_signal.lua` (loaded by `map_event_world.lua`) registers
`map_event_types.pal_signal`. A high-loot crate (the one of Storm Contraction,
shared through `map_event_crate.lua`) with a light beam on top, to pull players
into a fight. Lasts `PAL_SIGNAL.duration` (90 s).

- `pick(sx, sy)` (host) takes the centroid of the ships in the sector (A) and the
  centroid of the most populated OTHER occupied sector (B). The target is the
  midpoint of A and B clamped into the sector shrunk by `edge_pad`; with no B it
  is the sector centre. If a planet's body plus `crate_clear` covers it, it tries
  up to `crate_tries` random points within 1500 px (clamped to the sector). With
  none it returns nil. Returns `{ x, y }`, which the minimap icon uses on every
  client (`solar_hud.lua`).
- `fire(p)` (host) spawns the crate and stores its netId in `p.crate`;
  `on_end(ev)` (host) despawns it if nobody opened it.
- Visuals: `step` draws, every frame and from `map_events` (so a late joiner
  sees it without `on_start`), `pal_beacon.png` animated (`fps` 8) on the
  `front` layer, `beam.w` x `beam.h` px of world with its base on the crate
  centre. Off-screen beams are skipped.

### Debris Rain

Issue #26. `map_debris_rain.lua` registers `map_event_types.debris_rain`. Phases
from `elapsed = duration - ev.t` (same on every client), `duration` =
`warning + rain + tail` = 30 s:

- `warning` (5 s): a ship within `warn_pad` (2000 px) of the sector bounds sees
  `arrow_count` blinking `debris-arrow` images on the screen edge the rocks come
  from, pointing along the heading; a ship inside the sector also sees
  "LLUVIA DE ESCOMBROS EN Ns".
- `rain` (20 s): the arrows stay, steady and dimmer. Only the host spawns rocks,
  `rate` per second (a per-event accumulator, dropped when the event ends).
- `tail` (5 s): no new rocks; the last ones finish crossing.
- `pick(sx, sy)` returns `{ x, y, angle }`: the sector centre and a random heading.
  `fire` just returns true.
- Rocks: each one starts `0.75 * SECTOR_SIZE` upstream of the sector centre, with
  a lateral offset of up to half a sector, heading jittered by `spread`, speed
  `speed` and scale `scale`. They are normal host-owned `asteroid.lua` entities
  (`net_spawn`, replicated, split and drop loot as usual). At 320..420 px/s they
  are above `IMPACT_FULL_SPEED`, so the usual `ImpactDamage` path hurts on impact.
- `state.ttl` (new field of `asteroid.lua`, documented in `prefabs/asteroid.lua`):
  the owner removes the rock without loot after `ttl` (25 s). Not
  `despawn_far`, so these rocks do not count for the drifting-rock cap.

### Overcharged Planet

Issue #26. `map_overcharged.lua` registers `map_event_types.overcharged_planet`.
For `OVERCHARGED.duration` (60 s) a mining planet yields `mult` (x2).

- `pick(sx, sy)` (host): a random planet of `scene_planets` with a mineral whose
  centre is in the sector and that no active event already targets. Returns
  `{ x, y }` (planet centre); `fire` returns true.
- `overcharged.multiplier(planet)` is 1, or `mult` if an active `map_events` entry
  of this type has `params.x / params.y` equal to the planet's. It is derived from
  `map_events`, so it holds for late joiners and after a host migration, and is
  1 when `map_events` is nil (other scenes). `player/player_mining.lua` uses it:
  `add_item(entity, mineral, n)`, popup "+n mineral" and "Minando X (x2)".
  Only the mined amount changes; the mining interval does not.
- Visuals (`step`): `aura_overcharged.png` animated (`fps` 8, drawn white because
  `draw_image` cannot tint), centred on the planet, diameter
  `2 * body_radius * size_factor`, `front` layer; plus a dotted ring expanding
  from `1.1 * body_radius` to the gravity `range` and fading, in the colour of
  the mineral (blue iron, red gunpowder, green plasma) via `zones.draw_ring`.

## Supply containers

Issue #27. Still world crates that give one random resource and come back after
being opened. They share the crate script (`loot_crate.lua`) and the pickup flow
of `loot_net.lua` with the Pal crate, so only the owner (the host) decides who
gets the loot and two players opening at once cannot both receive it.

- Placement: `map_supply.lua`, `supply.slots(seed)` (pure and memoized, no
  `math.random`). One crate at most per sector whose biome is in
  `SUPPLY_CRATE.biomes` (`deep_void`, `debris`), i.e. 1 per 4 chunks. Stream
  `hash(seed, sx, sy, SALT_SUPPLY)` (10): up to `tries` (40) darts inside the
  sector, `edge_pad` (400) from its border and outside `STORM_BAND`. A dart is
  rejected within `planet.range + planet_clear` (400) of a planet, within
  `rock radius + crate radius + rock_clear` (120) of any rock of the sector's 4
  chunks (radius = `ASTEROID_SHEET.bodyRadius * scale`), or inside a portal
  end's clear zone. With no valid dart the sector has no crate. Slots are
  `{ slot = "sx:sy", x, y }`.
- Crate: `prefabs/supply_crate.lua` (`supply_crate.png`, same 6-frame sheet as the
  Pal crate: frame 0 closed, 1..5 opening). State: `pos`, `world`, `kind =
  "supply"`, `slot`, `item`, `quantity`; the loot is `{ [item] = quantity }`, so
  a late joiner or a new host rebuilds it from the spawn state. Item from
  `SUPPLY_CRATE.items` (iron, gunpowder, plasma), quantity `8..20`.
- Registry: every crate adds itself each frame to the global `loot_crates`
  (`key -> { e, x, y, kind, slot }`; key = netId, or the entity offline, where
  `get_net_id` is nil). The Pal crate is tagged `kind = "pal"` in
  `map_event_crate.lua`.
- Respawn (`map_supply_world.lua`, host only, wrapped in `pcall`): each frame it
  spawns the crate of every slot that has no live crate, if it was never opened
  or `respawn` (90 s) have passed since `supply_opened[slot]`. It waits 1 s after
  the seed arrives so snapshot or adopted crates register first.
- Opening: `loot_net.grant` calls the global `loot_crate_opened(e)` just before
  `net_despawn` (only the owner gets there, so once per crate). The owner plays
  the animation, records `supply_opened[slot]` and sends `crate_opened { x, y,
  kind, slot }`. Clients accept it only from the host, play the animation and
  record the slot too.
- Animation: local list of openings drawn with `draw_image` (screen coordinates,
  `front` layer, `src` rect of frames 1..5 at `open_fps` 10), then the last frame
  fades out over 0.4 s. Works for both crate kinds.
- Late joiners / migration: on `snapshot_request` the host sends `supply_state {
  opened = slot -> seconds since opened }`; the joiner fills `supply_opened`
  with it. Every client keeps the open times, so a new host after a migration
  keeps the respawn timers (crates that exist are adopted as live).

## Known gap

Chunk rocks are not synchronized once they exist. If a ship bump nudges a
static rock, its position is not reconciled between clients, so copies can
drift apart. Only destruction is synchronized.

Drifting rocks are simulated everywhere (they are not culled), so clients that
were present from the start stay roughly in step. But a late joiner builds them
at their seed position, so for them they are out of sync with older clients
until they leave the world.
