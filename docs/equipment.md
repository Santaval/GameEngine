# Equipment

Tracks named upgrade levels for an entity — `engine`, `gun`, `shield`, or
anything else a scene or a script wants to name. The engine does not know
what these names mean; it is a growable keyed collection, nothing more.

| Component | Meaning |
| --- | --- |
| `EquipmentComponent` | A list of `(name, level)` pairs for one entity. |

**Scope of this document:** tracking and Lua manipulation only. No system in
this engine currently reads these levels — see
[Gotchas and limits](#gotchas-and-limits).

---

## Quick start

### In a scene file

```lua
{
  components = {
    -- ...
    equipment = {
      engine = 1,
      gun    = 3,
      shield = 4,
    },
  },
}
```

Keys are free-form — the loader accepts any string key with an integer
value. It sorts them alphabetically before storing them, so the HUD (or
anything else that iterates) sees a stable order regardless of how Lua
happened to walk the table.

### At runtime, from a script

```lua
set_equipment_level(this, "gun", 3)   -- creates the component if missing
local level = get_equipment_level(this, "gun")
```

---

## Lua API

| Function | Returns | Notes |
| --- | --- | --- |
| `set_equipment_level(e, name, level)` | — | Creates the component if it is missing (same pattern as `set_damage`). Overwrites the level if the tool already exists. |
| `get_equipment_level(e, name)` | `int` | `0` if the entity has no `EquipmentComponent` or does not have that tool. |
| `has_equipment(e, name)` | `bool` | |
| `upgrade_equipment(e, name, amount?)` | `int` | Adds `amount` (defaults to `1`) and returns the new level. Creates the tool at level `amount` if it was not there. |
| `remove_equipment(e, name)` | — | No-op if the entity or the tool is missing. |
| `get_equipment_count(e)` | `int` | `0` if the entity has no `EquipmentComponent`. |
| `get_equipment_at(e, index)` | `name, level` | **1-based.** Returns `"", 0` when `index` is out of range. |

All of these are guarded — safe to call on any entity, including one that
never had an `EquipmentComponent`.

### Iterating by index

`table.*` does not exist in this engine's Lua environment (only `base`,
`math` and `string` are opened), and no binding in this repo returns a
`sol::table` — a HUD calling into one every frame would allocate a table
plus N strings per frame. Instead, iterate by index, 1-based:

```lua
for i = 1, get_equipment_count(this) do
  local name, level = get_equipment_at(this, i)
  print(name, level)
end
```

---

## Recipes

**HUD that lists everything the player is carrying:**

```lua
for i = 1, get_equipment_count(this) do
  local name, level = get_equipment_at(this, i)
  draw_text(20, 130 + i * 22, string.format("%s: %d", name, level), "default", 180, 200, 255)
end
```

**A power-up that upgrades one tool on pickup:**

```lua
function on_damage(amount, source)
  -- treat "damage" from a gun-upgrade pickup as a level-up instead
  local new_level = upgrade_equipment(this, "gun")
  print("gun upgraded to " .. new_level)
end
```

---

## Levels over the ships

Every player ship gets an overlay drawn above it by
`assets/scripts/player/ship_overlay.lua`: name, `E<engine> S<shield> G<gun>`
and the health bar (red below a third). The local ship reads its own levels
with `get_equipment_level`; remote ships take them from the `spawn` state and
keep them current with the `player_stats` message sent after each upgrade.

---

## The upgrade menu

Equipment levels are consumed by a compact HUD overlay, toggled with **E**,
where the player spends inventory items to raise `engine`, `gun` and
`shield`. It keeps running while open — no pause — since the game is meant to
be multiplayer.

### Cost table

`assets/scripts/player/player_upgrades.lua` holds a data-driven table so it
is easy to retune:

```lua
player_upgrades_module.UPGRADES = {
  { equipment = "engine", label = "Engine", cost = { iron = 3 } },
  { equipment = "gun",    label = "Gun",    cost = { gunpowder = 2, iron = 1 } },
  { equipment = "shield", label = "Shield", cost = { plasma = 1, iron = 2 } },
}
```

Each cost is **per next level**: the actual price is `base x (current level +
1)`, so upgrades get steadily more expensive. `MAX_LEVEL` (10) caps every
tool.

### Level -> stat formulas

`player_upgrades_module.apply_stats(entity)` maps the current equipment
levels to real gameplay numbers, keeping today's values at the scene's
starting levels (engine 1, gun 3, shield 4):

| Tool | Formula | At the starting level |
| --- | --- | --- |
| `engine` L | `thrust = 60 + 40*L`, `set_max_speed(e, 60 + 40*L)` | 100 / 100 at L1 |
| `gun` L | `bullet_damage = 5 + 5*L`, `fire_rate = 0.5 + 0.5*L` | 20 dmg, 2 shots/s at L3 |
| `shield` L | `max_health = 60 + 10*L`, healed by the increase | 100 HP at L4 |

`apply_stats` writes directly into `player_movement_module.thrust` and
`player_shooting_module.*` — those modules are `require`d (and therefore
cached) by `player_upgrades.lua`, so the change is visible to `player.lua`
immediately. It runs once on the player's first `update()` (so the scene's
starting levels take effect) and again after every successful purchase.

### Where the code lives

| File | Role |
| --- | --- |
| `assets/scripts/player/player_upgrades.lua` | Cost table, `get_cost` / `can_afford` / `purchase` / `apply_stats`. |
| `assets/scripts/player/player_upgrade_menu.lua` | The overlay: open/close state, buy-key edge detection, feedback message, and the `draw_rect`/`draw_text` panel anchored top-right. |

---

## Gotchas and limits

**`set_equipment_level` creating the component on the fly is safe only
because no system calls `requireComponent<EquipmentComponent>()`.** If one
ever does, entities that receive the component *after* their first
`Registry::update()` will never be enrolled in it — system membership is
decided once, when an entity is first flushed into the registry. `health`
and `damage` get away with the same trick today because `DamageSystem` is
purely event-driven and never iterates its own entity list; a future
equipment-consuming system would need the same shape, or the component
added at spawn time.

**Lua table order is not guaranteed.** A scene's `equipment = { ... }` table
is walked with whatever order sol2/Lua gives its keys, which is not
deterministic. The loader sorts the result alphabetically by name before
storing it, so iteration order is stable from then on — but do not rely on
the order keys are *written* in the scene file matching the order you get
back.

**Entity ids are recycled.** Every getter here is guarded and returns a
neutral value (`0`, `false`, or `"", 0`) instead of reading a dead entity's
leftover data — same convention as `get_health` / `get_damage`.

---

## Where the code lives

| File | Role |
| --- | --- |
| `src/Components/EquipmentComponent.hpp` | The `(name, level)` list and why it is a vector, not a map. |
| `src/Binding/EquipmentBindings.hpp` | The Lua functions listed above. |
| `src/SceneManager/SceneLoader.cpp` | Parses the `equipment` scene table (`addEquipmentComponent`). |
