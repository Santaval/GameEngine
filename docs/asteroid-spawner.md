# Asteroid spawner

Generators placed in a ring just **outside** the map keep the asteroid field
alive: every few seconds each one launches an asteroid that flies across the
map. Everything is in Lua; the engine has no notion of a spawner.

| File | Role |
| --- | --- |
| [`assets/scripts/asteroid_config.lua`](../assets/scripts/asteroid_config.lua) | Shared module: `FIELD`, sprite sheet, health, damage, sizes, types and loot. Used by the scene and by the spawner. |
| [`assets/scripts/asteroid_spawner.lua`](../assets/scripts/asteroid_spawner.lua) | The generators and the runtime asteroid factory. |
| [`assets/scripts/asteroid.lua`](../assets/scripts/asteroid.lua) | Asteroid hooks, exposed as `asteroid_on_damage` / `asteroid_on_death`. |
| [`assets/scripts/scenes/scene_01.lua`](../assets/scripts/scenes/scene_01.lua) | Builds the initial field and registers the spawner "director" entity. |

---

## How it works

The scene has an invisible **director** entity: it has only a `script`
component (`ScriptSystem` needs nothing else). Its `update()`:

1. Waits until `player_entity` exists, because before that neither the player
   position nor the camera can be trusted.
2. On the first frame, builds `GENERATORS_PER_SIDE * 4` generators,
   `SPAWN_MARGIN` px outside each side of `FIELD`. Each one has its own random
   timer, so they don't fire together.
3. Each frame it ticks every timer down. When a timer runs out, it is reset to
   a random value in `SPAWN_INTERVAL` and the generator tries to spawn.

A spawn is **skipped** (the generator just waits for its next turn) when:

- there are already `MAX_ALIVE` spawned asteroids,
- the player is within `PLAYER_SAFE_RADIUS` of the generator, or
- the generator is on screen, using the camera rect grown by `SCREEN_MARGIN`.
  This covers a player parked at the map edge looking outward.

Each asteroid aims at a **random point inside `FIELD`**. Its direction is
random, but it always crosses the map instead of drifting off into the void.

Spawned asteroids work exactly like the ones from the scene: same health,
damage, loot and pickups. When one gets `DESPAWN_MARGIN` px past the edge of
`FIELD`, its loot is emptied and it is destroyed, so it leaves no pickups
where nobody will collect them.

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
| `DESPAWN_MARGIN` | `600` | Distance past `FIELD` at which an asteroid is removed. Must be greater than `SPAWN_MARGIN`. |

Balance values (health, damage, types, loot) are in `asteroid_config.lua` and
apply to both the initial field and spawned asteroids.

## Gotchas

- **Hook order.** `add_script` recreates the `ScriptComponent`, so it is called
  **before** `set_on_damage` / `set_on_death`, never after.
- **Named hooks.** `SceneLoader` clears the global `on_death` / `on_damage`
  before loading each script, so runtime code can't rely on them later.
  `asteroid.lua` therefore also defines `asteroid_on_death` and
  `asteroid_on_damage`. If a scene has no static asteroids, the spawner
  `require`s `asteroid.lua` at runtime to get them.
- **`on_death` can fire twice.** `kill()` is deferred, so a bullet and a
  despawn can land in the same frame. Each spawned asteroid has its own `dead`
  flag, so it is counted (and drops loot) only once.
- **Collision is O(n²).** See [README.md](README.md#what-is-not-here-yet).
  `MAX_ALIVE` is what keeps the spawner from slowing the game down.
