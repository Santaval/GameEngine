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
  `SALT_PLANET`, `SALT_ROCKS`, `SALT_DRIFT`, `SALT_WRECK`). Without a salt the
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
| `reactor` | 5 | Can have wrecks |

Rules:

- The **center sector** (2, 2) is picked first, between `CENTER_BIOMES`
  (`planetary` and `reactor`, weights 20:5).
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
| `UPDATE_RADIUS_CHUNKS` | 2 | Chunks around the player that are simulated |
| `STABLE_PORTAL_PAIRS`, `NEXUS_COUNT` | 12, 1 | Portals (not used yet) |
| `PORTAL_CLEAR_RADIUS` | 600 | Portals (not used yet) |
| `PORTAL_COOLDOWN` | 4 | Portals (not used yet) |
| `PORTAL_EXIT_WARNING` | 0.75 | Portals (not used yet) |
| `UNSTABLE_PORTAL_LIFE` | 45..75 | Portals (not used yet) |
| `EVENT_INTERVAL` | 60..120 | Events (not used yet) |
| `STORM_CONTRACTION_INTERVAL` | 180..240 | Storm (not used yet) |
| `STORM_CONTRACTION_SAFE_RADIUS` | 1500 | Storm (not used yet) |
| `DEATH_DROP_FRACTION` | 0.6 | Players (not used yet) |
| `SPAWN_SHIELD` | 5 | Players (not used yet) |
| `BIOMES` | see [Biomes](#biomes) | Id, name and weight of each biome |
| `BIOME_REPEAT_OK`, `CENTER_BIOMES` | `debris`, `planetary`/`reactor` | Adjacency exception and centre sector pool |
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

The minimap in `solar_hud.lua` shows the biome of each sector as a tint, the
5 x 5 sector grid, the storm band as an inset outline, the planets and the
current sector or nearest planet when `scene_map` is set.

## Known gap

Chunk rocks are not synchronized once they exist. If a ship bump nudges a
static rock, its position is not reconciled between clients, so copies can
drift apart. Only destruction is synchronized.

Drifting rocks are simulated everywhere (they are not culled), so clients that
were present from the start stay roughly in step. But a late joiner builds them
at their seed position, so for them they are out of sync with older clients
until they leave the world.
