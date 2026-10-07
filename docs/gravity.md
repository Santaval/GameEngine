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

Planets have no collider, so bodies pass through them (collision is a
follow-up).

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
