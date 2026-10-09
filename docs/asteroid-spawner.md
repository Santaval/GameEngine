# Asteroid spawner

Generators placed in a ring just **outside** the map keep the asteroid field
alive: every few seconds each one launches an asteroid that flies across the
map. Everything is in Lua; the engine has no notion of a spawner.

| File | Role |
| --- | --- |
| [`assets/scripts/asteroid_config.lua`](../assets/scripts/asteroid_config.lua) | Shared module: `FIELD`, sprite sheet, health, damage, sizes, types and loot. `pickAsteroidType()` returns the type and its index. |
| [`assets/scripts/asteroid_field.lua`](../assets/scripts/asteroid_field.lua) | `asteroid_state(cx, cy, scale, velocity, kind?)`: the spawn state of an asteroid (`pos`, `vel`, `rot`, `kind`, `scale`, `world = true`); `spawn_drifting(cx, cy, vx, vy, scale?, kind?)`: `net_spawn`s a drifting asteroid and registers it in `drifting_asteroids` (used by the generators and by splitting). |
| [`assets/scripts/prefabs/asteroid.lua`](../assets/scripts/prefabs/asteroid.lua) | Prefab: builds the asteroid entity from that state alone. |
| [`assets/scripts/asteroid_spawner.lua`](../assets/scripts/asteroid_spawner.lua) | The "director": seeds the initial field and runs the generators. Host only. |
| [`assets/scripts/asteroid.lua`](../assets/scripts/asteroid.lua) | Per-asteroid runtime script: hooks, far-outside despawn, ring steering, ship bounce. |
| [`assets/scripts/pickup.lua`](../assets/scripts/pickup.lua), [`loot_net.lua`](../assets/scripts/loot_net.lua) | Loot pickups and how they are granted once (see [lua-api.md](lua-api.md#loot-flow-loot_netlua)). |
| [`assets/scripts/scenes/scene_01.lua`](../assets/scripts/scenes/scene_01.lua), [`solar_system.lua`](../assets/scripts/scenes/solar_system.lua) | Build the initial field **states** into the global `scene_initial_asteroids` and register the director. |

---

## Multiplayer: the host owns the world

Asteroids are **host-owned world entities** (see [lua-api.md](lua-api.md#world-entities-world--true)).
The scene no longer lists asteroids as entities. It stores their spawn states in
`scene_initial_asteroids`, and the director creates them with
`net_spawn("asteroid.lua", state)` (`state.world = true`). Offline,
`net_is_host()` is `true` and `net_spawn` just builds the entity locally, so
single player behaves as before.

- **Host only.** `update()` does nothing on a client that is not the host. A
  client that was not the host when the scene started never seeds the field,
  even if it becomes host later: the field already exists (it arrived in the
  snapshot), so it only starts running the generators.
- **Seeding.** Offline, all of `scene_initial_asteroids` is created in one frame.
  Online it is throttled to `SEED_RATE` (30) asteroids per second, because the
  relay rate-limits at 120 messages per second. The Saturn ring uses the same
  throttle.
- **Prefab.** `prefabs/asteroid.lua` derives the sprite frame, health, loot and
  gravity from `kind` and `scale`, so a late joiner (or the new host) rebuilds
  any asteroid from its snapshot entry. Ring rocks (`state.ring`) have no
  gravity and steer along their lane on every client.
- **Counting.** `MAX_ALIVE` is checked against the global `drifting_asteroids`.
  Every asteroid with `despawn_far = true` writes its netId there from its own
  `update()`, on every client, so a new host starts with the right count.
  Ids that no longer resolve with `find_by_net_id` are pruned.
- **Generators are lazy.** They are built on the first frame in which this client
  is the host, so after a host migration the new host keeps spawning.
- **Despawn.** Only the owner checks `isFarOutside` and calls `net_despawn`
  (plain kill, no `on_death`, no loot). Non-hosts wait for that despawn.
- **Loot and fragments.** `asteroid_on_death` runs its effects only
  `if is_local(this)`. Anything an asteroid creates when it dies (loot pickups
  and split fragments) must be spawned by the owner with `net_spawn`
  and `world = true`; never with `create_entity`.
- **Splitting.** When a rock dies with `scale >= SPLIT.MIN_SCALE` (0.6, in
  `asteroid_config.lua`), `split()` in `asteroid.lua` replaces it with 2-3
  fragments of the same `kind`, each `0.45..0.6` of the parent's scale (never
  below `ASTEROID_SCALE.min`). They leave in an even fan from the parent's
  centre with the parent's velocity plus `30..60` px/s outward, and are placed
  one body radius out so they don't overlap. A rock that splits drops **no**
  loot; fragments too small to split drop their own (so mostly the smallest
  rocks give loot). Fragments large enough can split again. Ram kills split too
  (the ram only clears the parent's loot, which `split` doesn't use). `vanish`
  (eaten by a planet, despawned far away) sets `dead` first, so it never
  splits. Fragments are created with `field.spawn_drifting`, the same builder
  the generators use: they have `despawn_far = true`, so they **count toward
  `MAX_ALIVE`** (the cap only stops the generators; a split may briefly exceed
  it). Ring rock fragments have no `ring`/`slot`: they drift away and the ring
  refills the slot as usual.
- If the host quits mid-seeding, the unseeded part of the initial field is not
  created by the new host.

## How it works

The scene has an invisible **director** entity: it has only a `script`
component (`ScriptSystem` needs nothing else). Its `update()`:

1. Returns immediately if this client is not the host.
2. Seeds the initial field (see above).
3. Waits until `player_entity` exists, because before that neither the player
   position nor the camera can be trusted.
4. On the first frame, builds `GENERATORS_PER_SIDE * 4` generators,
   `SPAWN_MARGIN` px outside each side of `FIELD`. Each one has its own random
   timer, so they don't fire together.
5. Each frame it ticks every timer down. When a timer runs out, it is reset to
   a random value in `SPAWN_INTERVAL` and the generator tries to spawn.

A spawn is **skipped** (the generator just waits for its next turn) when:

- there are already `MAX_ALIVE` spawned asteroids,
- any player (the local ship or one in `player_ships`) is within
  `PLAYER_SAFE_RADIUS` of the generator, or
- the generator is on screen, using the camera rect grown by `SCREEN_MARGIN`.
  This covers a player parked at the map edge looking outward.

Each asteroid aims at a **random point inside `FIELD`**. Its direction is
random, but it always crosses the map instead of drifting off into the void.

Spawned asteroids work exactly like the ones from the scene: same health,
damage, loot and pickups. When one gets `DESPAWN_MARGIN` px past the edge of
`FIELD` (or out of `scene_bounds`), its loot is emptied and it is removed, so
it leaves no pickups where nobody will collect them.

## Tunables

All of these are at the top of `asteroid_spawner.lua`:

| Constant | Default | Meaning |
| --- | --- | --- |
| `SPAWN_MARGIN` | `150` | How far outside `FIELD` the generators sit. |
| `GENERATORS_PER_SIDE` | `3` | Generators per side (12 in total). |
| `SPAWN_INTERVAL` | `2..6` s | Random delay between spawns, per generator. |
| `SPAWN_SPEED` | `30..90` px/s | Speed of each spawned asteroid. |
| `MAX_ALIVE` | `40` | Cap on live spawned asteroids. Asteroids from the initial field don't count toward it. |
| `PLAYER_SAFE_RADIUS` | `500` | No spawning this close to the player. |
| `SCREEN_MARGIN` | `150` | Extra margin around the screen. Keep it at least half the largest asteroid (`96 * 3 / 2`). |
| `SEED_RATE` | `30` | Online only: initial asteroids created per second. |
| `DESPAWN_MARGIN` | `600` | In `asteroid.lua`. Distance past `FIELD` at which an asteroid is removed. Must be greater than `SPAWN_MARGIN`. |

Balance values (health, damage, types, loot) are in `asteroid_config.lua` and
apply to both the initial field and spawned asteroids.

## Gotchas

- **Per-entity script state.** `asteroid.lua` runs once per asteroid, so its
  chunk-level `local`s (`despawn_far`, `ring`, `dead`) are per entity and come
  from `spawn_state`. `this` is not the entity while the chunk loads; use it
  inside `update()` and the hooks. The hooks are file-local and are picked up by
  `SceneLoader` through the `on_damage` / `on_death` / `on_collision` globals,
  so there is no shared `asteroid_on_*` anymore.
- **`on_death` can fire twice.** `kill()` is deferred, so a bullet and a
  despawn can land in the same frame. Each asteroid has its own `dead` flag, so
  it drops loot only once.
- **Scene globals.** `drifting_asteroids`, `ring_slots` and `player_ships` are
  reset by the scene on load; do not rely on them across scenes.
- **Collision is O(n²).** See [README.md](README.md#what-is-not-here-yet).
  `MAX_ALIVE` is what keeps the spawner from slowing the game down.
