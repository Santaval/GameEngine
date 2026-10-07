# Gravity

Bodies pull on each other through a **mass** property. Taking part is opt-in:
only entities with a `GravityComponent` are involved, so anything without it
(minerals, pickups, ...) is never affected.

## The model

Each body has two independent flags:

| Field | Default | Meaning |
| --- | --- | --- |
| `mass` | `1` | Strength of the pull. Only matters if `attracts` is true. |
| `attracts` | `false` | The body is a **source**: it pulls other bodies. |
| `affected` | `true` | The body is a **receiver**: others pull it. Also needs a `rigid_body`. |
| `range` | `0` | Maximum reach of its pull in px. `0` means unlimited. |

Splitting sources from receivers keeps the asteroid field stable: asteroids are
affected by planets but do not pull each other into clumps.

## Planets swallow asteroids

Planets have a circle collider (`PLANET_BODY_RADIUS` in `scene_01.lua`). When
an asteroid touches one it vanishes with no loot drop: `asteroid_on_collision`
in `asteroid.lua` checks `is_gravity_source(other)` and calls
`asteroid_vanish`, the same helper the spawner uses for off-map cleanup. The
spawner's live count stays correct because `on_death` still runs. The ship,
bullets and pickups still pass through planets.

## The formula

For every receiver and every source (except itself):

```
d     = source_center - receiver_center
a     = G * M * d / (|d|^2 + SOFTENING^2)^(3/2)
velocity += a * dt
```

- `G = 1000` is a game constant, not a physical one.
- `SOFTENING = 40` px keeps the pull finite near the center of a source, so a
  body crossing a planet is not flung out.
- A source is skipped if `range > 0` and the receiver is farther than `range`.
- The receiver's own mass does not matter (as in real gravity).

Centers are `position + (w/2, h/2) * scale`, using the circle collider size if
there is one, otherwise the sprite size.

## Frame order

`GravitySystem` runs right **before** `MovementSystem`. It only changes
`velocity`, so `max_speed` still caps the result: the ship's `max_speed = 100`
limits how fast it can fall.

As with every system, an entity joins only in the frame it is created, so
`add_gravity` must be called right after `create_entity`.

## Tuning

Values live in Lua, no rebuild needed.

| Where | Value | Notes |
| --- | --- | --- |
| `scene_01.lua` `PLANETS` | iron `mass 3000 / range 700` | About 33 px/s^2 at 300 px from a 3000-mass planet. |
| | gunpowder `2000 / 600` | |
| | plasma `4500 / 800` | |
| `asteroid_config.lua` `GRAVITY` | `ASTEROID_MASS_PER_SCALE = 20` | Stored, unused while asteroids do not attract. |
| | `BULLET.mass = 1`, `SHIP.mass = 10` | |

## Who takes part

Planets (sources), the player ship, asteroids (scene and spawner) and bullets
(player and enemy) are receivers. Mineral pickups have no gravity component, so
the magnet keeps working and nothing else moves them.

Bullet sprites do not rotate to follow their curved path.

## Danger zones

`max_speed` stays on everywhere, autopilot included: it is what makes planets
dangerous. A ship can only climb away while its thrust beats gravity, so each
planet has zones relative to the ship's **current** thrust
(`player_movement.thrust`, which grows with the engine level):

| Zone | `gravity / thrust` | Meaning |
| --- | --- | --- |
| safe | `< 0.6` | Free flight. |
| warning | `0.6 – 1` | Escape is still possible, slowly. |
| no return | `>= 1` | Gravity beats full thrust: the ship will crash. |

Iron planet at engine level 1 (thrust 100): warning from r ≈ 218, no return
from r ≈ 166, surface at r = 110. A green dashed ring marks the edge of each
planet's gravity (`range`), visible from `1.5 * range` away. Within a planet's
`range`, a yellow (warning) and a red (no return) dashed ring are drawn too, and the HUD shows the
current zone in its colour. Code: [`player/player_gravity_zones.lua`](../assets/scripts/player/player_gravity_zones.lua).

## Planet damage

Touching a planet's body costs the ship `damage` HP (per planet in
`scene_01.lua` `PLANETS`, 15 by default) at most every 0.5 s, from the
player's `on_collision`. Planets get no `damage` component on purpose: that
would also hit asteroids through `DamageSystem` and could drop their loot
before `asteroid_vanish` clears it.

## Mining

While the ship is inside a planet's gravity (`range`) and the planet has a
`mineral`, it mines automatically; no key, no autopilot, the player keeps full
control. Pure Lua: [`player/player_mining.lua`](../assets/scripts/player/player_mining.lua).

- Planets come from the global `scene_planets`, which the scene publishes
  (Lua cannot list entities) with `x, y` centre, `mass`, `range`,
  `body_radius`, `damage`, `mineral` and `mine_interval`. The nearest planet
  whose `range` contains the ship is mined.
- Every `mine_interval` seconds it adds 1 `mineral` to the inventory
  (`PLANETS` in `scene_01.lua`: iron → `iron`, gunpowder → `gunpowder`,
  plasma → `plasma`, every 2 s). `add_item` clamps to the cargo capacity; when
  it adds nothing the HUD shows "Bodega llena".
- A dotted beam in the mineral's colour runs from the surface to the ship, and
  each unit pops a rising "+1 <mineral>" label. Leaving the range stops mining
  and resets the timer.

`player_gravity_zones.lua` keeps its own copy of `G` and `SOFTENING`: if they
change in `GravitySystem.hpp`, update them there too.
