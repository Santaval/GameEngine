# Lua API Reference

Every function the engine exposes to Lua, as of today. They are all **global
functions** — there are no methods and no modules.

Registered in [`src/Systems/ScriptSystem.hpp`](../src/Systems/ScriptSystem.hpp),
implemented one domain per file under [`src/Binding/`](../src/Binding/).

> `e` in the signatures below is an **entity handle**, the opaque value returned
> by `create_entity()` or delivered to a script as the global `this`.

---

## Contents

- [The `this` global](#the-this-global)
- [Available Lua standard libraries](#available-lua-standard-libraries)
- [Entities](#entities)
- [Movement & physics](#movement--physics)
- [Gravity](#gravity)
- [Sprites & animation](#sprites--animation)
- [Colliders](#colliders)
- [Health & damage](#health--damage)
- [Equipment](#equipment)
- [Inventory](#inventory)
- [Loot](#loot)
- [Text & HUD](#text--hud)
- [Camera](#camera)
- [Input](#input)
- [Trajectory path](#trajectory-path)
- [Scripts & hooks](#scripts--hooks)
- [Game flow & scenes](#game-flow--scenes)
- [Network](#network)
- [Reading a component you don't have](#reading-a-component-you-dont-have)

---

## The `this` global

Before calling any script function, the engine sets the global `this` to the
entity being processed:

```lua
function update()
  local x, y = get_position(this)
end
```

`this` is only valid for the duration of the call. If you need an entity later,
store it in a global — globals are shared across **all** script files, so prefix
them to avoid collisions (`player_target`, not `target`).

## Available Lua standard libraries

Only four are opened: **`base`**, **`math`**, **`string`** and **`package`**.

That means `print`, `ipairs`, `pairs`, `math.*`, `string.format` and `require`
work, but **`table.*`, `os.*` and `io.*` do not exist**. Use `t[#t + 1] = v`
instead of `table.insert`, and `get_delta_time()` instead of `os.clock`.

`require("name")` searches `assets/scripts/` and `assets/scripts/player/`
(see `Game.cpp`). Modules are loaded once and cached, so `local` variables at
the top of a module persist across frames — `assets/scripts/player/` uses this
for cooldowns and key-edge state instead of globals.

---

## Entities

| Function | Returns | Notes |
| --- | --- | --- |
| `create_entity()` | entity | Created empty. It joins the systems on the next frame, once its components are in place. |
| `add_transform(e, x, y, scale_x, scale_y, rotation)` | — | All arguments required. `rotation` in **radians**. |
| `get_position(e)` | `x, y` | Two return values. |

> **`position` is the sprite's top-left corner, not its centre.** To place an
> entity centred on a point, subtract half its scaled size:
> `add_transform(e, cx - w * scale / 2, cy - h * scale / 2, scale, scale, 0)`.

| `destroy_entity(e)` | — | Kills the entity outright, without going through health. Runs `on_death` first, same as dying from damage; the actual removal is deferred to the next frame like any `kill()`. |

Entities also die by running out of health (see
[Health & damage](#health--damage)); `destroy_entity` is the way to remove one
that has no health at all, such as a pickup.

---

## Movement & physics

| Function | Returns | Notes |
| --- | --- | --- |
| `add_rigid_body(e, vx, vy, ax, ay, max_speed?)` | — | `max_speed` defaults to `0`. |
| `set_velocity(e, x, y)` | — | World space. |
| `get_velocity(e)` | `vx, vy` | |
| `get_speed(e)` | `number` | Magnitude of the velocity vector. |
| `set_acceleration(e, x, y)` | — | **Local space** — see below. |
| `get_acceleration(e)` | `ax, ay` | The stored local-space value. |
| `set_max_speed(e, max_speed)` | — | `0` or less means no limit. |
| `get_max_speed(e)` | `number` | |
| `set_rotation(e, rate)` | — | **A rate**: `rotation += rate * delta_time`. |
| `set_rotation_absolute(e, radians)` | — | Sets the angle directly. |
| `get_rotation(e)` | `number` | Radians. |
| `get_delta_time()` | `number` | Seconds elapsed in the previous frame. |

### Acceleration is in local space

`MovementSystem` rotates the acceleration vector by the entity's current
rotation before integrating it. So `set_acceleration(this, 0, -100)` means
*"thrust 100 units towards wherever my nose is pointing"*, not *"accelerate
upwards"*.

Velocity, in contrast, is accumulated in **world space** and never re-rotated —
turning the ship does not turn its existing momentum. That is what makes the
drifting feel right.

### Speed limiting

`max_speed` caps what the **acceleration** (engine thrust) can do: thrust never
takes the speed above `max_speed`, and if the entity is already faster (pushed
by gravity, a bounce, `set_velocity`…) thrust can steer or brake but not add
speed. External changes to the velocity are never clamped. Direction is
preserved when capping.
A value of `0` or less disables the limit entirely.

---

## Gravity

| Function | Returns | Notes |
| --- | --- | --- |
| `add_gravity(e, mass, attracts?, affected?, range?)` | — | Defaults: `attracts = false`, `affected = true`, `range = 0` (unlimited). Call it right after `create_entity`. |
| `has_gravity(e)` | `boolean` | |
| `get_mass(e)` | `number` | `0` if the entity has no gravity component. |
| `set_mass(e, mass)` | — | |
| `set_gravity_affected(e, affected)` | — | |
| `is_gravity_source(e)` | `boolean` | `true` if the entity attracts and has `mass > 0` (planets). `false` without the component. |

See [gravity.md](gravity.md) for the model.

---

## Sprites & animation

| Function | Returns | Notes |
| --- | --- | --- |
| `add_sprite(e, asset_id, width, height, src_x, src_y)` | — | `asset_id` must be registered in the scene's `sprites` list. `width`/`height` are the **source frame** size. |
| `set_sprite(e, asset_id)` | — | Swaps the texture, keeps the frame geometry. |
| `add_animation(e, num_frames, frame_speed_rate, is_loop)` | — | `frame_speed_rate` is frames per second. |

The rendered size is `width * scale.x` by `height * scale.y`, so scale lives on
the transform, not the sprite.

> **`add_animation` takes over `src_rect.x`.** `AnimationSystem` rewrites it
> every frame as `current_frame * width`. If you picked a specific frame of a
> spritesheet via `add_sprite`'s `src_x`, do **not** also add an animation — the
> two fight and the animation wins.

Rotation is applied by SDL around the **centre of the destination rectangle**.
That pivot is `position + (width / 2) * scale`, which is also where the collider
centre is computed — keeping the two consistent is why colliders use the full
frame size rather than the visible artwork's bounding box.

---

## Colliders

| Function | Returns | Notes |
| --- | --- | --- |
| `add_circle_collider(e, radius, width, height, owner?)` | — | `owner` is an entity; collisions between an entity and its owner are skipped. |
| `get_collider_center(e)` | `cx, cy` | World-space centre of the collider, same formula as `CollisionSystem` (`position + (width / 2, height / 2) * scale`). Falls back to the transform position without a collider, `0, 0` without a transform. |
| `toggle_colliders()` | — | Flips the debug overlay. |
| `set_show_colliders(v)` | — | |
| `is_showing_colliders()` | `bool` | |

Collision is circle-vs-circle. The centre is derived from the **frame** box:

```
centre = position + (width / 2, height / 2) * scale
radius = radius * scale.x        -- scale.x only, deliberately
```

So `width`/`height` are the sprite frame, and `radius` is in **unscaled sprite
units** — a radius of `170` on a ship scaled to `0.2` is 34 screen pixels.

### The `owner` argument

Pass the shooter when spawning a projectile:

```lua
add_circle_collider(bullet, 30, 64, 32, this)
```

`CollisionSystem` then skips that pair entirely, so a ship never shoots itself.
The debug overlay also draws owned colliders in a different colour.

---

## Health & damage

Summarised here; the full guide is in
[health-and-damage.md](health-and-damage.md).

| Function | Returns | Notes |
| --- | --- | --- |
| `add_health(e, max, invulnerability?, player?)` | — | Starts full. `invulnerability` in seconds, defaults to `0`. `player` (default `false`) marks a player ship protected when PvP is off. |
| `get_health(e)` / `get_max_health(e)` | `int` | `0` when the component is missing. |
| `is_alive(e)` | `bool` | `true` for an entity with no health — indestructible counts as alive. |
| `set_health(e, value)` | — | Clamped, ignores invulnerability, fires `on_death` at `0`. |
| `heal(e, amount)` | — | Cannot revive something already at `0`. |
| `set_max_health(e, value)` | — | Clamped to `>= 1`. Never kills — if `health` is above the new max, it is clamped down too, without firing `on_death`. |
| `add_damage(e, amount, destroy_on_hit?, player?)` | — | `destroy_on_hit` defaults to `false`. `player` (default `false`) marks a player weapon that does not hurt other players when PvP is off. |
| `get_damage(e)` / `set_damage(e, amount)` | `int` / — | `set_damage` adds the component if missing. |

**An entity with no health component is indestructible.**

In multiplayer only the owner of an entity changes its health: `set_health`,
`heal` and `set_max_health` do nothing on other machines, and `on_damage` there
is visual only. See [health-and-damage.md](health-and-damage.md#in-multiplayer).

---

## Equipment

Named upgrade levels tracked per entity (`engine`, `gun`, `shield`, or any
other name a scene or script picks). Tracking only — nothing consumes these
levels yet. Full guide in [equipment.md](equipment.md).

| Function | Returns | Notes |
| --- | --- | --- |
| `set_equipment_level(e, name, level)` | — | Creates the component if missing. Overwrites an existing level. |
| `get_equipment_level(e, name)` | `int` | `0` if the component or the tool is missing. |
| `has_equipment(e, name)` | `bool` | |
| `upgrade_equipment(e, name, amount?)` | `int` | Adds `amount` (defaults to `1`), returns the new level. Creates the tool if missing. |
| `remove_equipment(e, name)` | — | No-op if missing. |
| `get_equipment_count(e)` | `int` | `0` if the component is missing. |
| `get_equipment_at(e, index)` | `name, level` | **1-based.** `"", 0` out of range. |

`table.*` does not exist in this engine's Lua environment, so iterate by
index instead of expecting a table back:

```lua
for i = 1, get_equipment_count(this) do
  local name, level = get_equipment_at(this, i)
end
```

---

## Inventory

Named item quantities tracked per entity (`mineral`, or any other name a
scene or script picks), plus an optional total capacity. Full guide in
[inventory.md](inventory.md).

| Function | Returns | Notes |
| --- | --- | --- |
| `has_inventory(e)` | `bool` | |
| `add_item(e, name, qty?)` | `int` | `qty` defaults to `1`. Creates the component (unlimited) if missing. Clamped to remaining capacity, if any. Returns the amount actually added. |
| `remove_item(e, name, qty?)` | `int` | `qty` defaults to `1`, never removes more than what is held. Returns the amount actually removed. |
| `update_item_count(e, name, count)` | `int` | Sets the absolute quantity (not a delta). `count <= 0` erases the entry. Clamped to capacity. Returns the resulting count. |
| `get_item_count(e, name)` | `int` | `0` if missing. |
| `has_item(e, name, qty?)` | `bool` | `qty` defaults to `1`. |
| `get_inventory_total(e)` | `int` | Sum of every item's quantity. |
| `get_inventory_capacity(e)` / `set_inventory_capacity(e, cap)` | `int` / — | `0` = unlimited. Lowering it below the current total does not drop items. |
| `get_inventory_count(e)` / `get_inventory_at(e, index)` | `int` / `name, quantity` | Same 1-based convention as equipment. |
| `clear_inventory(e)` | — | Empties the items, keeps the capacity. |

Same iteration convention as equipment — no `table.*`, so walk it by index:

```lua
for i = 1, get_inventory_count(this) do
  local name, quantity = get_inventory_at(this, i)
end
```

---

## Loot

What an entity drops or hands over (name → quantity). Asteroids get it from
the scene (`loot = { ... }`) and read it in `on_death`; the pickups they spawn
get it through `set_loot` and hand it to whoever collects them.

| Function | Returns | Notes |
| --- | --- | --- |
| `has_loot(e)` | `bool` | |
| `get_loot_count(e)` / `get_loot_at(e, index)` | `int` / `name, quantity` | Same 1-based convention as inventory. |
| `set_loot(e, name, qty)` | — | Sets the absolute quantity. Creates the component if missing. `qty <= 0` erases the entry. |

---

## Text & HUD

| Function | Returns | Notes |
| --- | --- | --- |
| `draw_text(x, y, text, font_id?, r?, g?, b?, a?)` | — | **Screen** coordinates. Lasts one frame. |
| `draw_text_world(x, y, text, font_id?, r?, g?, b?, a?)` | — | **World** coordinates, scrolls with the camera. Lasts one frame. |
| `add_text(e, text, font_id?, r?, g?, b?, a?, offset_x?, offset_y?)` | — | A persistent label attached to the entity's transform. |
| `set_text(e, text)` | — | |
| `set_text_color(e, r, g, b, a?)` | — | |
| `draw_rect(x, y, w, h, r?, g?, b?, a?, filled?)` | — | **Screen** coordinates. `filled` defaults to `true`. Lasts one frame. |
| `draw_rect_world(x, y, w, h, r?, g?, b?, a?, filled?)` | — | **World** coordinates, scrolls with the camera. Lasts one frame. |

`font_id` defaults to `"default"`; colour channels default to `255`.

The `draw_*` calls push into a buffer that is flushed and cleared every frame,
so a HUD line has to be re-issued from `update()` each time:

```lua
draw_text(20, 20, string.format("Speed: %.1f", get_speed(this)), "default", 120, 220, 255)
```

`add_text` is the opposite — set it once and it follows the entity forever.

> **Font size is baked in at load time.** One `fontId` per size: register
> `debug-big` separately if you want 28px alongside the 16px `default`.

---

## Camera

| Function | Returns | Notes |
| --- | --- | --- |
| `center_camera_on(x, y)` | — | Puts the world point `(x, y)` in the middle of the screen. |
| `set_camera_position(x, y)` | — | Sets the camera's top-left corner. |
| `get_camera_position()` | `x, y` | |
| `get_screen_size()` | `w, h` | |

Nothing follows the player automatically — a script has to drive it:

```lua
local x, y = get_position(this)
center_camera_on(x, y)
```

---

## Input

| Function | Returns | Notes |
| --- | --- | --- |
| `is_action_activated(name)` | `bool` | Works for both keyboard and mouse actions. |
| `get_mouse_position()` | `x, y` | Screen coordinates. |
| `get_mouse_world_position()` | `x, y` | Screen position plus the camera offset. |

Action names come from the scene's `keys` and `mouse` tables — see
[scene-format.md](scene-format.md).

> **`is_action_activated` reports the key being *held*, not a press.** To react
> once per press, track the previous state yourself:
>
> ```lua
> local down = is_action_activated("toggle_path")
> if down and not player_toggle_was_down then
>   set_path_active(this, not is_path_active(this))
> end
> player_toggle_was_down = down
> ```

---

## Trajectory path

Draws a dashed, fading line predicting where the entity is heading, by
re-integrating its physics forward. Read-only — it never touches the real state.

| Function | Returns | Notes |
| --- | --- | --- |
| `add_path(e, active?)` | — | `active` defaults to `true`. |
| `set_path_active(e, active)` | — | Adds the component if it is missing. |
| `is_path_active(e)` | `bool` | `false` when the component is missing. |

Needs a transform and a rigid body to have anything to predict. Below ~5 units
of speed nothing is drawn, so a parked ship has no stub of a line.

---

## Scripts & hooks

| Function | Returns | Notes |
| --- | --- | --- |
| `add_script(e, fn)` | — | `fn` becomes the entity's `update`. |
| `set_on_damage(e, fn)` | — | `fn(amount, source)`. |
| `set_on_death(e, fn)` | — | `fn()`. |
| `set_on_collision(e, fn)` | — | `fn(other)`. Fires every frame the two colliders keep overlapping, not once per contact — see [inventory.md](inventory.md#gotchas-and-limits) for the pickup pattern this implies. |

A script file loaded through a scene defines its hooks as globals:

```lua
function update() end
function on_damage(amount, source) end
function on_death() end
function on_collision(other) end
```

For entities spawned at runtime, use the closure form instead:

```lua
local turret = create_entity()
add_health(turret, 200)
set_on_death(turret, function() print("turret down") end)
```

All three receive the affected entity as `this`. The engine calls only the hooks
that exist — defining none is fine.

---

## Game flow & scenes

| Function | Description |
| --- | --- |
| `load_scene(path)` | Switches to another scene file. **Deferred**: the current frame finishes normally and the new scene loads at the start of the next one. |
| `quit_game()` | Closes the game at the end of the current frame. |
| `get_window_size()` | Returns `w, h` of the window in pixels (for centering HUD/menus). |

Loading a scene is a full reset: every entity is destroyed, entity ids start at
0 again, the camera goes back to `(0, 0)`, the `player_entity` / `game_over`
globals are cleared, and every module loaded with `require` is unloaded so its
module-level locals (cooldowns, open menus...) start fresh. Textures and fonts
already loaded are kept and reused by id.

Flow used by the game: `scenes/menu.lua` (start screen) → `scenes/scene_01.lua`.
In scene_01, `player.lua`'s `on_death` sets `game_over = true` and
`game_director.lua` shows the game-over overlay (ENTER restarts, M returns to
the menu). Shared helpers for these screens live in `ui_helpers.lua`.

---

## Network

Multiplayer bindings (protocol: [multiplayer-protocol.md](multiplayer-protocol.md)).
They are always safe to call: without `--server` (or while disconnected) each
one returns the offline default below, so single-player scripts run unchanged.

### Session

| Function | Online | Offline |
| --- | --- | --- |
| `net_is_online()` | `true` once the server sent `welcome` | `false` |
| `net_my_id()` | Your player id | `""` |
| `net_is_host()` | `true` if you are the host | `true` |
| `net_peers()` | Array of the other players' ids | `{}` |

### Messaging

| Function | Description |
| --- | --- |
| `net_send(type, tbl [, to])` | Sends `tbl` (nested tables, arrays, numbers, strings, booleans) as a message of `type`. `to` is a player id for a direct message; without it the message goes to everyone but you. Returns `true` if it was sent, `false` offline or if the type is not allowed. |
| `net_on(type, fn)` | Registers `fn(data, from)`. `from` is the sender's player id. Several handlers per type are allowed. Offline it only registers (nothing ever fires). |

Handlers run on the main thread at the start of each frame, before scripts.
**Handlers are cleared on every scene load**, so register them from a script of
the new scene. A handler that raises an error is logged
(`[Net] lua handler for '<type>' failed: ...`) and does not affect the others.

Custom vs. protocol types:

- Any `type` that is not a protocol message name is a **custom message**: it
  travels as `{t = "custom", type = type, data = tbl}` and the receiving
  handler gets `tbl` as `data`. Type is 1-64 characters.
- If `type` is a protocol name (`state`, `fire`, `damage`, ...), `tbl` is merged
  into the message as its fields and the handler receives the whole message
  table as `data`. The server enforces the message's own rules.
- `hello`, `welcome`, `peer_joined`, `peer_left`, `host_changed` and `custom`
  cannot be sent with `net_send` (it logs and returns `false`). You can still
  listen to the session ones with `net_on`.

```lua
net_on("chat", function(data, from)
  print(from .. ": " .. data.text)
end)
net_send("chat", { text = "hola" })          -- everyone else
net_send("chat", { text = "psst" }, peer_id) -- one player
```

### Networked entities

| Function | Description |
| --- | --- |
| `net_spawn(script_path, state_tbl)` | Builds the entity from a prefab, tags it with a new netId owned by you, and broadcasts `spawn`. Returns the entity (or `nil` if the prefab failed). Offline it only creates the entity locally. |
| `net_despawn(e)` | Removes a networked entity and tells the others. Only the owner can despawn: calling it on a remote entity while online logs a warning and does nothing. An entity without network identity is just killed. |
| `is_local(e)` | `true` if you own the entity or it is not networked. Always `true` offline. |
| `get_net_id(e)` | The entity's netId string, or `nil`. |
| `find_by_net_id(id)` | The entity with that netId, or `nil`. |
| `get_owner(e)` | The owner's player id, or `nil` if the entity is not networked. |
| `set_owner(e, player_id)` | Rewrites the owner **locally only**; nothing is broadcast. |

`net_despawn` is a plain kill: `on_death` does **not** run, on either side.
That way remote copies do not repeat gameplay hooks (loot drops, score...) the
owner already handled. Use `destroy_entity` first if you want the hook locally.

`state_tbl` is `{ pos = {x, y}, vel = {x, y}, acc = {x, y}, rot = radians, hp = n }`
plus any extra data (it travels to the other players in `spawn.state`). Missing
`pos`/`vel`/`acc`/`rot` are filled with zeros before sending, because the server
requires them. They override the prefab: `pos` -> `transform.position`,
`rot` -> `transform.rotation`, `vel` -> `rigid_body.velocity`,
`acc` -> `rigid_body.acceleration` (the `transform` / `rigid_body` tables are
created when the prefab does not have them), and `hp` sets the `health` of an
entity that has a `health` component.

#### Prefabs

`script_path` is relative to `assets/scripts/prefabs/` (so
`"player/remote_player.lua"` is `assets/scripts/prefabs/player/remote_player.lua`)
and must not contain `..`. The same relative path is what other players receive
in `spawn.script`. A prefab is a Lua file that returns either a scene-format
entity definition or a `function(state)` returning one (`state` is the table
above):

```lua
-- assets/scripts/prefabs/bullet.lua
return {
  components = {
    transform = { position = { x = 0, y = 0 }, scale = { x = 0.5, y = 0.5 } },
    sprite = { assetId = "bullet", width = 64, height = 32, src_rect = { x = 0, y = 192 } },
    script = { path = "./assets/scripts/bullet.lua" },
  },
}
```

The entity is built with the same factory as scene entities (see
[scene-format.md](scene-format.md)), so every component works. Textures must
already be loaded by the current scene; a sprite whose texture is missing is
simply not drawn.

When another player's `spawn` arrives, the engine builds the same prefab
automatically and tags it with the sender's netId and owner: Lua does not have
to handle `spawn` (a `net_on("spawn", ...)` handler still fires afterwards).
Incoming `despawn` removes the entity the same way.

Building a prefab with a `script` component redefines the `update` / `on_*`
globals while it loads (same as `require` of a script mid-update); `this` is
saved and restored around it.

---

## Reading a component you don't have

`getComponent` performs **no validation**. Most bindings call it directly, so
asking for something an entity does not have reads whatever the previous owner
of that slot left behind — entity ids are recycled.

| Guarded, safe to call on anything | Unguarded, requires the component |
| --- | --- |
| `get_health`, `get_max_health`, `is_alive`, `set_health`, `heal`, `set_max_health`, `get_damage`, `set_damage`, `is_path_active`, `set_path_active`, `set_equipment_level`, `get_equipment_level`, `has_equipment`, `upgrade_equipment`, `remove_equipment`, `get_equipment_count`, `get_equipment_at`, `has_inventory`, `add_item`, `remove_item`, `update_item_count`, `get_item_count`, `has_item`, `get_inventory_total`, `get_inventory_capacity`, `set_inventory_capacity`, `get_inventory_count`, `get_inventory_at`, `clear_inventory`, `has_loot`, `get_loot_count`, `get_loot_at`, `set_loot`, `destroy_entity`, `draw_rect`, `draw_rect_world` | `get_position`, `get_rotation`, `set_rotation*`, every `*_velocity` / `*_acceleration` / `*_max_speed`, `get_speed`, `set_sprite`, `set_text`, `set_text_color` |

In practice: before calling anything in the right-hand column on an entity you
did not build yourself, make sure it has the component.
