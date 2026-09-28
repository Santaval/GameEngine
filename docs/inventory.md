# Inventory

Tracks named item quantities for an entity — `mineral`, or anything else a
scene or a script wants to name — plus an optional total capacity. Like
[Equipment](equipment.md), the engine does not know what these names mean; it
is a growable keyed collection of counts, nothing more.

| Component | Meaning |
| --- | --- |
| `InventoryComponent` | A list of `(name, quantity)` pairs for one entity, plus a capacity. |

**Scope of this document:** tracking, Lua manipulation and the mineral pickup
gameplay built on top of it — see [Recipes](#recipes) and
[Gotchas and limits](#gotchas-and-limits).

---

## Quick start

### In a scene file

```lua
inventory = {
  capacity = 50,        -- optional, 0 or omitted = unlimited
  items = {
    mineral = 0,
  },
}
```

Both keys are optional. Item keys are free-form — the loader accepts any
string key with an integer value greater than `0`. It sorts them
alphabetically before storing them, same as `equipment`, so the HUD sees a
stable order regardless of how Lua happened to walk the table.

### At runtime, from a script

```lua
add_item(this, "mineral", 1)          -- creates the component if missing
local count = get_item_count(this, "mineral")
```

---

## Lua API

| Function | Returns | Notes |
| --- | --- | --- |
| `has_inventory(e)` | `bool` | Used by pickups to decide who is allowed to collect. |
| `add_item(e, name, qty?)` | `int` | Adds up to `qty` (defaults to `1`; `<= 0` adds nothing). Creates the component (unlimited) if missing. Clamped to the free space left under `capacity`, if any. Returns the amount actually added; a brand-new entry only appears if that amount is greater than `0`. |
| `remove_item(e, name, qty?)` | `int` | Removes up to `qty` (defaults to `1`), never more than what is held. Erases the entry once it hits `0`. Returns the amount actually removed. |
| `update_item_count(e, name, count)` | `int` | Sets the **absolute** quantity, not a delta. Creates the component (unlimited) if missing. `count <= 0` erases the entry. With `capacity > 0`, clamps so the total never exceeds the cap without touching other items. A new entry appends in insertion order. Returns the quantity that actually landed. |
| `get_item_count(e, name)` | `int` | `0` if the component or the item is missing. |
| `has_item(e, name, qty?)` | `bool` | `get_item_count(e, name) >= qty` (`qty` defaults to `1`). |
| `get_inventory_total(e)` | `int` | Sum of every item's quantity. `0` if the component is missing. |
| `get_inventory_capacity(e)` | `int` | `0` = unlimited, or if the component is missing. |
| `set_inventory_capacity(e, cap)` | — | Creates the component if missing. Lowering it below the current total does **not** drop items — see [Gotchas](#gotchas-and-limits). |
| `get_inventory_count(e)` | `int` | Number of distinct item entries, `0` if the component is missing. |
| `get_inventory_at(e, index)` | `name, quantity` | **1-based.** Returns `"", 0` when `index` is out of range. |
| `clear_inventory(e)` | — | Empties every item. Keeps the capacity. No-op if the component is missing. |

All of these are guarded — safe to call on any entity, including one that
never had an `InventoryComponent`.

### Iterating by index

Same reason as `equipment`: `table.*` does not exist in this engine's Lua
environment (only `base`, `math` and `string` are opened). Iterate by index,
1-based:

```lua
for i = 1, get_inventory_count(this) do
  local name, quantity = get_inventory_at(this, i)
  print(name, quantity)
end
```

---

## Recipes

**HUD that shows total cargo and a line per item:**

```lua
local total, capacity = get_inventory_total(this), get_inventory_capacity(this)
draw_text(20, y, string.format("Cargo: %d / %d", total, capacity), "default", 180, 255, 180)

for i = 1, get_inventory_count(this) do
  local name, qty = get_inventory_at(this, i)
  draw_text(20, y + i * 22, string.format("%s: %d", name, qty), "default", 180, 255, 180)
end
```

This is exactly what `player.lua` does, right below the equipment lines.

**Mineral pickup — a destroyed asteroid drops a mineral entity that collects
itself on contact** (`assets/scripts/asteroid.lua`):

```lua
function on_death()
  local x, y = get_position(this)
  mineral = create_entity()
  add_transform(mineral, x, y, 1, 1, 0)
  add_sprite(mineral, "mineral", 16, 16, 0, 0)
  add_rigid_body(mineral, 0, 0, 0, 0, 0)
  add_circle_collider(mineral, 8, 16, 16)
  set_on_collision(mineral, collect_mineral)
end

function collect_mineral(other)
  if not has_inventory(other) then return end  -- asteroids/bullets don't collect
  if add_item(other, "mineral", 1) > 0 then destroy_entity(this) end  -- full: stays afloat
end
```

`collect_mineral` is a plain global, not `on_collision` — see
[Gotchas](#gotchas-and-limits) for why that distinction matters here.

---

## Gotchas and limits

**Capacity `0` means unlimited**, not "empty". `set_inventory_capacity(this,
0)` and never calling it at all behave the same way.

**Lowering `capacity` never drops items.** `set_inventory_capacity` only
changes the number future `add_item` / `update_item_count` calls are clamped
against; it never rewrites `items`. An entity can end up carrying more than
its current capacity if the cap was lowered after the fact — that state is
intentional, not a bug, and `get_inventory_total(e) > get_inventory_capacity(e)`
is a valid thing to check for.

**Scene `items` are not clamped to `capacity`.** `addInventoryComponent`
trusts whatever the scene author wrote; `capacity` is only enforced by the
Lua-facing mutators (`add_item`, `update_item_count`) from that point on. A
scene that starts an entity over its own cap gets exactly that.

**`on_collision` fires every frame two colliders keep overlapping**, not
once per contact (`CollisionSystem` emits a `CollisionEvent` per overlapping
pair, every frame, same as it always has for damage). A pickup has to either
destroy itself on success (`destroy_entity`, as `collect_mineral` does) or
otherwise guard against being processed dozens of times while the two
entities drift past each other.

**Why `collect_mineral` is not named `on_collision`.** `asteroid.lua` is the
script file loaded for *every* asteroid entity via the scene's `script`
component. If the pickup hook were the global `on_collision`, every asteroid
would pick it up too (`SceneLoader::addScriptComponent` reads whatever global
`on_collision` is defined after running the file) and asteroids would start
colliding with each other. `set_on_collision(mineral, collect_mineral)`
attaches the hook to the one runtime-created mineral entity instead, leaving
every asteroid's own `on_collision` at `lua_nil`.

**Entity ids are recycled.** Every getter here is guarded and returns a
neutral value (`0`, `false`, or `"", 0`) instead of reading a dead entity's
leftover data — same convention as `get_health` / `get_equipment_level`.

---

## Where the code lives

| File | Role |
| --- | --- |
| `src/Components/InventoryComponent.hpp` | The `(name, quantity)` list, the capacity field, and why it is a vector, not a map. |
| `src/Binding/InventoryBindings.hpp` | The Lua functions listed above. |
| `src/SceneManager/SceneLoader.cpp` | Parses the `inventory` scene table (`addInventoryComponent`). |
| `src/Components/ScriptComponent.hpp` | The `on_collision` hook used by pickups. |
| `src/Binding/ScriptBindings.hpp` | `set_on_collision`, for hooking runtime-created entities like the mineral. |
| `src/Systems/ScriptSystem.hpp` | Subscribes to `CollisionEvent` and calls `on_collision` on both sides of a hit. |
| `src/Binding/EntityBindings.hpp` | `destroy_entity`, used by pickups to remove themselves. |
| `assets/scripts/asteroid.lua` | The mineral-drop-and-pickup gameplay. |
