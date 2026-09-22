# Health & Damage

Generic hit points and contact damage for any entity. The engine knows nothing
about bullets, ships or asteroids — it only knows two components:

| Component | Meaning |
| --- | --- |
| `HealthComponent` | How much punishment this entity can take. |
| `DamageComponent` | How much damage this entity deals when it collides with something. |

Everything else — the numbers, who is destructible, whether a projectile dies on
impact — is configured from Lua.

**The core rule:** an entity **without** `HealthComponent` is indestructible.
Nothing can hurt it, and a projectile that hits it passes through without being
consumed.

---

## Requirements

Damage is driven by collisions, so both entities need what `CollisionSystem`
needs:

- a `transform`
- a `circle_collider`

An entity with `health` but no collider will never be hit by contact damage
(you can still change its HP from Lua with `set_health` / `heal`).

---

## Quick start

### In a scene file

Two new component tables are accepted inside `components`:

```lua
{
  components = {
    transform      = { position = { x = 400, y = 100 }, scale = { x = 0.2, y = 0.2 } },
    circle_collider = { radius = 170, width = 430, heigth = 650 },

    -- takes 100 damage before dying, with half a second of grace after each hit
    health = {
      max            = 100,
      current        = 100,   -- optional, defaults to max
      invulnerability = 0.5,  -- optional, seconds, defaults to 0
    },

    -- deals 20 damage on contact and survives the impact
    damage = {
      amount         = 20,
      destroy_on_hit = false, -- optional, defaults to false
    },
  },
}
```

### At runtime, from a script

```lua
local bullet = create_entity()
add_transform(bullet, px, py, 0.5, 0.5, rotation)
add_rigid_body(bullet, vx, vy, 0, 0)
add_circle_collider(bullet, 30, 64, 32, this)  -- `this` = owner, see Gotchas

-- 20 damage, and the bullet is destroyed by the impact
add_damage(bullet, 20, true)
```

---

## Lua API

### Health

| Function | Returns | Notes |
| --- | --- | --- |
| `add_health(e, max, invulnerability?)` | — | Starts at full HP. `invulnerability` in seconds, defaults to `0`. |
| `get_health(e)` | `int` | `0` if the entity has no `HealthComponent`. |
| `get_max_health(e)` | `int` | `0` if the entity has no `HealthComponent`. |
| `is_alive(e)` | `bool` | `true` for an entity with no `HealthComponent` — indestructible counts as alive. |
| `set_health(e, value)` | — | Clamped to `[0, max]`. **Ignores invulnerability.** Reaching `0` kills the entity and fires `on_death`. No-op if the entity has no `HealthComponent`. |
| `heal(e, amount)` | — | Shorthand for `set_health(e, get_health(e) + amount)`. Cannot revive an entity that is already at `0`. |

### Damage

| Function | Returns | Notes |
| --- | --- | --- |
| `add_damage(e, amount, destroy_on_hit?)` | — | `destroy_on_hit` defaults to `false`. |
| `get_damage(e)` | `int` | `0` if the entity has no `DamageComponent`. |
| `set_damage(e, amount)` | — | Adds the component if it is missing. Useful for power-ups. |

### Hooks

| Function | Notes |
| --- | --- |
| `set_on_damage(e, fn)` | Registers `fn(amount, source)` on an entity created at runtime. |
| `set_on_death(e, fn)` | Registers `fn()` on an entity created at runtime. |

---

## Script hooks

An entity with a `script` component can define either hook. The engine calls
them only if they exist — a script that defines neither is perfectly valid.

```lua
-- assets/scripts/player.lua

function update()
  -- ... called every frame
end

-- Called after HP has already been subtracted, so get_health(this)
-- is the value *after* the hit.
function on_damage(amount, source)
  print(string.format("-%d HP (%d left)", amount, get_health(this)))
end

-- Called immediately before the entity is removed.
function on_death()
  print("destroyed")
end
```

In all three, the affected entity arrives as the global `this`, the same
convention `update()` already uses. `source` in `on_damage` is the entity that
dealt the damage, or `nil` when the damage did not come from a collision.

For entities spawned at runtime (which never pass through the scene loader),
use the closure form instead:

```lua
local turret = create_entity()
add_health(turret, 200, 0.2)
set_on_death(turret, function()
  print("turret down")
end)
```

> **Note:** scripts define hooks as globals, and globals are shared across every
> script file. The loader clears `update`, `on_damage` and `on_death` before
> loading each file, so a script that defines only `update` will *not* inherit
> the `on_death` of whichever file was loaded before it.

---

## How a hit is resolved

Whenever `CollisionSystem` reports a collision between `a` and `b`, the
`DamageSystem` runs this twice — once in each direction, so both entities can
hurt each other in the same impact:

1. Does the **attacker** have a `DamageComponent`? If not, nothing happens.
2. Has that component already been spent this life? If so, nothing happens.
3. Does the **target** have a `HealthComponent`? If not, nothing happens — the
   attacker is *not* consumed, it simply passes through.
4. Apply the damage. This is skipped when the target is already at `0` HP, or
   when it is still inside its invulnerability window.
5. If `destroy_on_hit` is set, mark the attacker as spent and destroy it.

Two consequences worth knowing:

- **Step 5 runs even when step 4 was skipped.** A bullet that hits a target
  during its invulnerability window is still consumed — it connected, the target
  just shrugged it off. If you want bullets to pass through invulnerable
  targets, that is a change to `DamageSystem::resolve`.
- **`destroy_on_hit` is about being consumed, not about dying on contact.** An
  entity with `destroy_on_hit = false` keeps its damage forever and will hurt
  everything it touches, over and over.

### Invulnerability

After a successful hit, an entity ignores all contact damage for
`invulnerability` seconds. Without it, sustained contact applies damage on
*every single frame* — a ship grazing an asteroid would evaporate instantly.

The window is measured from a timestamp stored on the component, so it costs
nothing per frame and works for entities that receive health at any point in
their life.

`set_health` and `heal` bypass the window deliberately: scripted damage is
usually meant to land.

### The `spent` flag

`kill()` is deferred — an entity dies at the start of the next frame, not the
moment it is killed. Without a guard, a single bullet sitting between two
asteroids would damage both before disappearing. The `spent` flag makes a
`destroy_on_hit` entity deal its damage exactly once.

---

## Recipes

**A bullet** — dies on impact, hurts whatever it hits:

```lua
add_damage(bullet, 20, true)
```

**A destructible obstacle** — takes several shots, and hurts whatever runs into
it:

```lua
health = { max = 60, invulnerability = 0.5 },
damage = { amount = 20 },   -- no destroy_on_hit: it survives the crash
```

The `invulnerability` matters here: two obstacles that drift into each other
overlap for many consecutive frames, and without a grace window they would
grind each other to dust in a fraction of a second.

**A player ship** — destructible but never deals contact damage:

```lua
health = { max = 100, invulnerability = 0.5 },
-- no damage component at all
```

**A hazard that cannot be destroyed** — a laser wall, spikes, a black hole:

```lua
damage = { amount = 50 },
-- no health component: nothing can destroy it
```

**A health pickup** — collision-driven healing, done from a script:

```lua
function on_damage(amount, source)
  -- a "damage" of -10 would be odd; heal the collider instead
end
```

Simpler: give the pickup no damage component, and have the player's script
check proximity and call `heal(this, 25)`.

**A boss that changes phase** — read HP from `update()`:

```lua
function update()
  if get_health(this) * 2 < get_max_health(this) and not boss_enraged then
    boss_enraged = true
    set_damage(this, 40)
  end
end
```

**Difficulty tuning** — nothing is hardcoded in C++, so a single constant at the
top of a script changes the whole feel:

```lua
player_bullet_damage = 20
```

---

## Gotchas and limits

**Attach colliders at spawn.** `Registry::addComponent` only flips a bit in the
entity's signature; system membership is computed once, when the entity is
first flushed into the registry. Adding a `circle_collider` to an entity that is
already alive will *not* enrol it in `CollisionSystem`.

Health and damage are exempt from this: `DamageSystem` is purely event-driven
and never iterates its own entity list, so `add_health` and `add_damage` work at
any point in an entity's life — as long as it already had a collider.

**A projectile does not hit its owner.** Pass the shooter as the last argument
to `add_circle_collider`:

```lua
add_circle_collider(bullet, 30, 64, 32, this)
```

`CollisionSystem` skips that pair entirely, so no damage check ever runs for it.

**Death is deferred.** A killed entity is removed at the start of the next
frame. Until then it still appears in collision checks — which is exactly why
`health <= 0` and the `spent` flag are guarded against.

**Entity ids are recycled.** Never read a component without checking that the
entity actually has it; the getters in this API already do, and return a neutral
value instead.

**Projectiles that miss live forever.** Before this system, a bullet died
against the first collider it touched. Now it only dies against something with
health. A `LifetimeComponent` is the natural fix and does not exist yet.

**Collision detection is O(n²).** Every entity with a collider is tested against
every other one, every frame. This is unrelated to the damage system, but it is
the thing that will limit how many destructible entities a scene can hold.

---

## Where the code lives

| File | Role |
| --- | --- |
| `src/Components/HealthComponent.hpp` | HP, max HP, invulnerability window. |
| `src/Components/DamageComponent.hpp` | Damage amount, `destroyOnHit`, `spent`. |
| `src/Util/Damage.hpp` | `applyDamage` / `killWithHooks` — the only place HP is subtracted, and where the script hooks are called. |
| `src/Systems/DamageSystem.hpp` | Turns a `CollisionEvent` into damage. |
| `src/Binding/HealthBindings.hpp` | The Lua functions listed above. |
| `src/Binding/ScriptBindings.hpp` | `set_on_damage` / `set_on_death`. |
| `src/SceneManager/SceneLoader.cpp` | Parses the `health` and `damage` scene tables. |
