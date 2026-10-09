# Aval Cup map

Foundation of the Aval Cup map (issue #16): a fixed world split into sectors
and chunks, a deterministic seed shared by every client, and culling so only
the chunks near the local player are simulated. Biomas and real content
(issue #17) and spawn rules (issue #28) come later: today every chunk holds
**placeholder** static asteroids so seeding, culling and destroy-sync can be
exercised end to end.

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
| `hash(seed, cx, cy)` | 32-bit integer, see below |
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
- `rng(state)` is mulberry32 seeded with that hash. `next()` is `integer / 2^32`.

`tests/map_determinism.lua` checks that the same seed gives the same world, a
different seed a different one, and the grid helpers.

## Chunk content (placeholder)

`map_chunks.generate_chunk(seed, cx, cy)` is a pure function of its arguments.
It draws `PLACEHOLDER_ROCKS` asteroids per chunk by rejection sampling
(`ROCK_MIN_GAP`, `ROCK_SCALE`, a fixed number of tries per rock), keeps them out
of the `STORM_BAND` strip at the world edge, and returns spawn states:
`pos`, `vel = 0`, `rot`, `kind` (`pickAsteroidType(rng:next())`), `scale`,
`world = true`, `cull = true` and `chunk_id = "cx:cy:i"`.
`generate_world(seed)` returns `{ ["cx:cy"] = states }` for the 10 x 10 chunks.

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
| `PLACEHOLDER_ROCKS` | 4..8 | Rocks per chunk |
| `ROCK_MIN_GAP` | 300 | Min gap between rocks (px) |
| `ROCK_SCALE` | 0.6..1.5 | Rock scale range |

The minimap in `solar_hud.lua` shows the 5 x 5 sector grid, the storm band as an
inset outline and the current sector when `scene_map` is set.

## Known gap

Chunk rocks are not synchronized once they exist. If a ship bump nudges a
static rock, its position is not reconciled between clients, so copies can
drift apart. Only destruction is synchronized.
