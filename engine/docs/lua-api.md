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
- [Box colliders & static walls](#box-colliders--static-walls)
- [Health & damage](#health--damage)
- [Equipment](#equipment)
- [Inventory](#inventory)
- [Loot](#loot)
- [Text & HUD](#text--hud)
- [Camera](#camera)
- [Audio](#audio)
  - [Spatial audio](#spatial-audio)
  - [Buses and ducking](#buses-and-ducking)
- [Lighting](#lighting)
- [Input](#input)
- [Trajectory path](#trajectory-path)
- [Scripts & hooks](#scripts--hooks)
- [Game flow & scenes](#game-flow--scenes)
- [Tiled maps](#tiled-maps)
- [Tile map rendering](#tile-map-rendering)
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

`require("name")` searches `<game root>/scripts/`, each direct subfolder of it
(except `prefabs`) and `engine/common/scripts/` (see `Game.cpp`). Modules are loaded once and cached, so `local` variables at
the top of a module persist across frames — `games/aval/scripts/player/` uses this
for cooldowns and key-edge state instead of globals.

---

## Entities

| Function | Returns | Notes |
| --- | --- | --- |
| `create_entity()` | entity | Created empty. It joins the systems on the next frame, once its components are in place. |
| `add_transform(e, x, y, scale_x, scale_y, rotation)` | — | All arguments required. `rotation` in **radians**. |
| `get_position(e)` | `x, y` | Two return values. |
| `set_position(e, x, y)` | — | Moves the entity at once. `x, y` is the sprite's top-left corner, like `get_position`. Does not touch velocity and sends nothing over the network. |

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
| `set_sprite_frame(e, src_x, src_y)` | — | Moves the source rect inside the sheet (px). For hand-animated sprites without an `animation` component. |
| `add_animation(e, num_frames, frame_speed_rate, is_loop)` | — | `frame_speed_rate` is frames per second. |
| `add_animation_atlas(e, atlas_id, tag [, loop])` | — | Animates with an Aseprite/pixelfx atlas (the sprite's `atlas` in the scene, by its `assetId`). `loop` defaults to `true`. Unknown atlas or tag: warning, nothing changes. |
| `play_animation(e, tag [, loop])` | — | Switches to `tag` and restarts from its first frame, applying it right away. Calling it with the tag already looping is a no-op, so it is safe to call every frame from a script. Unknown tag, no animation or no atlas: warning, no-op. |
| `set_sprite_layer(e, name)` | bool | Draw pass relative to a [tile map](#tile-map-rendering): `"ground"` (right after the ground tiles), `"world"` (default, y-sorted with tall tiles) or `"above"` (after the `above` layers). Returns `false` for an unknown name or an entity without a sprite. |
| `set_sprite_sort_offset(e, px)` | — | Where the sprite's "feet" are for y-sorting: `px` from the top of the current frame, multiplied by `scale.y`. `-1` (default) means the bottom edge of the frame. |
| `set_sprite_flip(e, flip_h)` | — | Mirrors the sprite horizontally (no vertical flip). |
| `animation_finished(e)` | bool | `true` once a `loop = false` atlas animation has played to its end. `false` while it plays, when it loops or when `e` has no animation. |
| `get_animation_frame(e)` | int | Index (0-based) of the frame shown within the current tag, e.g. `0..3` for a 4-frame tag. `-1` when `e` has no animation, no atlas or no valid tag. Handy to sync effects (footsteps) with the animation. |

The rendered size is `width * scale.x` by `height * scale.y`, so scale lives on
the transform, not the sprite.

> **`add_animation` takes over `src_rect.x`.** `AnimationSystem` rewrites it
> every frame as `current_frame * width`. If you picked a specific frame of a
> spritesheet via `add_sprite`'s `src_x`, do **not** also add an animation — the
> two fight and the animation wins.

An atlas animation also overwrites the sprite's `width`/`height` and the whole
`src_rect` with the frame's rectangle from the JSON; export without trim. See
[scene-format.md](scene-format.md#animation) for the scene form.

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

## Box colliders & static walls

Axis-aligned boxes for walls, fences, houses and trigger zones. The full model
(flags, sweep, TMX conventions) is in [collision.md](collision.md).

| Function | Returns | Notes |
| --- | --- | --- |
| `add_box_collider(e, w, h, opts?)` | — | `opts = { x, y, solid, trigger, mover, owner }`. `x`, `y` is the offset from the sprite's top-left corner; `w`, `h`, `x`, `y` are scaled by the transform scale. Rotation is ignored. Enrols the entity in the box systems at once. |
| `set_box_collider(e, opts)` | `bool` | Updates any of `width, height, x, y, solid, trigger, mover, enabled, owner`. `false` if `e` has no box. `enabled = false` removes the box from every check. |
| `get_wall_contacts(e)` | `left, right, top, bottom` | Sides blocked by a wall or solid box during the entity's last move. |
| `add_static_box(x, y, w, h)` | `id` | A wall that is not an entity (world px, top-left corner). |
| `remove_static_box(id)` | `bool` | |
| `clear_static_colliders()` | — | Static walls are also cleared on every scene load. |
| `static_collider_count()` | `int` | |
| `overlaps_static(x, y, w, h)` | `bool` | Does this box overlap any static wall? |
| `load_tmx_colliders(path, opts?)` | `count` or `nil, err` | Creates walls from a Tiled map. `opts = { tile_layers = {"name"}, object_layer = "collision", x, y, scale }`. Warnings (skipped polygons, ellipses...) are logged as `[TmxColliders] ...`. |

`get_collider_center(e)` falls back to the centre of the box when the entity has
a box collider and no circle (a circle still wins when both exist).

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
| `set_shield(e, seconds)` | — | Spawn shield: while it lasts, `applyDamage` (bullets, rams, `DamageSystem`) does nothing to the entity. `0` cancels it. `set_health` still bypasses it, so scripted damage (storms) must check `get_shield` itself. No-op without a `HealthComponent`. |
| `get_shield(e)` | seconds | Seconds of shield left; `0` if there is none, it expired, or the entity has no `HealthComponent`. |
| `add_damage(e, amount, destroy_on_hit?, player?)` | — | `destroy_on_hit` defaults to `false`. `player` (default `false`) marks a player weapon that does not hurt other players when PvP is off. |
| `set_impact_damage(e, min_speed, full_speed)` | — | Scales contact damage by closing speed (px/s): none at or below `min_speed`, full `amount` at or above `full_speed`. `0, 0` = flat damage. |
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
| `draw_text_wrapped(x, y, max_w, text, font_id?, r?, g?, b?, a?)` | — | **Screen** coordinates. `max_w` is in logical units. Wraps at spaces, honors `\n`, and breaks words wider than `max_w` mid-word. Lasts one frame. |
| `measure_text(text, font_id?, max_w?)` | `w, h` | Size of the text in logical units (native pixels divided by the scale, rounded up). With `max_w` it measures the wrapped text. Returns `0, 0` for empty text or an unknown font. |
| `get_line_height(font_id?)` | height | Line height of the font in logical units (`0` for an unknown font). |
| `add_text(e, text, font_id?, r?, g?, b?, a?, offset_x?, offset_y?)` | — | A persistent label attached to the entity's transform. |
| `set_text(e, text)` | — | |
| `set_text_color(e, r, g, b, a?)` | — | |
| `draw_rect(x, y, w, h, r?, g?, b?, a?, filled?)` | — | **Screen** coordinates. `filled` defaults to `true`. Lasts one frame. |
| `draw_rect_world(x, y, w, h, r?, g?, b?, a?, filled?)` | — | **World** coordinates, scrolls with the camera. Lasts one frame. |
| `draw_image(asset_id, x, y, w, h, a?, layer?, opts?)` | — | **Screen** coordinates, stretched to `w` x `h`. `a` (0-255) defaults to `255`. `layer` is `"back"` (under the entities), `"front"` (default: over the entities, under the HUD rects and text) or `"hud"` (over the HUD rects, under the text). `opts = { src = {x, y, w, h}, angle = deg }` draws only that texture rect and rotates clockwise around the centre of the `w` x `h` destination. Lasts one frame. |

`font_id` defaults to `"default"`; colour channels default to `255`.

Text is rasterized at native resolution while positions scale, so with a logical size the glyphs stay sharp. `measure_text`, `get_line_height` and `max_w` all work in logical units.

The `draw_*` calls push into a buffer that is flushed and cleared every frame,
so a HUD line has to be re-issued from `update()` each time:

```lua
draw_text(20, 20, string.format("Speed: %.1f", get_speed(this)), "default", 120, 220, 255)
```

`add_text` is the opposite — set it once and it follows the entity forever.

> **Font size is baked in at load time.** One `fontId` per size: register
> `debug-big` separately if you want 28px alongside the 16px `default`.
> In pixel-perfect mode text is drawn at native resolution, not scaled, so
> size fonts for the real screen.

---

## Camera

| Function | Returns | Notes |
| --- | --- | --- |
| `center_camera_on(x, y)` | — | Puts the world point `(x, y)` in the middle of the screen. In pixel-perfect mode the camera is rounded to the nearest logical pixel. |
| `set_camera_position(x, y)` | — | Sets the camera's top-left corner. In pixel-perfect mode the position is rounded to the nearest logical pixel. |
| `get_camera_position()` | `x, y` | |
| `get_screen_size()` | `w, h` | The logical size in pixel-perfect mode (`logical_size`), otherwise the window size. |

Nothing follows the player automatically — a script has to drive it:

```lua
local x, y = get_position(this)
center_camera_on(x, y)
```

---

## Audio

Sounds and music are declared in the scene's [`sounds`](scene-format.md#sounds)
and [`music`](scene-format.md#music) tables and played by id. Volumes are floats
from `0` (silent) to `1` (full). Up to 48 sounds can play at once; beyond that
`play_sound` returns `0`.

| Function | Returns | Notes |
| --- | --- | --- |
| `play_sound(id, opts?)` | handle | `opts = { volume = 1, loop = false, bus = "sfx" }`. Returns an integer handle, or `0` if the sound does not exist or no channel is free. `bus` is one of `"voice"`, `"sfx"`, `"ambience"`, `"music"` (see [Buses and ducking](#buses-and-ducking)). |
| `stop_sound(handle, fade_ms?)` | — | Stops the sound, optionally fading out over `fade_ms`. Unknown or finished handles are ignored. |
| `pause_sound(handle)` | — | Pauses a playing sound. `sound_position` stays frozen and `is_playing` stays `true`. A voice on the `voice` bus keeps the ducking active. Unknown or finished handles are ignored. Do not fade-stop a paused sound (the fade never ends): stop it with `stop_sound(handle)`. |
| `resume_sound(handle)` | — | Resumes a paused sound from where it stopped. |
| `set_sound_volume(handle, v)` | — | Changes the volume of a playing sound. |
| `is_playing(handle)` | boolean | `false` once the sound ended or was stopped. |
| `sound_position(handle)` | seconds or `nil` | Playback position, accurate to about 50 ms. Wraps back to `0` on looping sounds. `nil` if the handle is no longer playing. |
| `sound_duration(id)` | seconds or `nil` | Length of the sound. `nil` if the id is unknown. |
| `play_music(id, fade_ms?, opts?)` | — | `opts = { loop = true, volume = 1 }`. Only one music track plays at a time: starting another replaces it. |
| `stop_music(fade_ms?)` | — | Stops the music, optionally fading out. |
| `set_bus_volume(bus, v)` | — | Volume of a bus, `0` to `1`. Saved to `settings.json`. An unknown bus name is logged and ignored. |
| `get_bus_volume(bus)` | number or `nil` | Current volume of a bus. `nil` if the bus name is unknown. |
| `set_ducking(opts)` | — | Changes the ducking of the current scene. See [Buses and ducking](#buses-and-ducking). |

`sound_position` is meant for syncing subtitles to a voice recording:

```lua
local lines = {
  { at = 0.0, text = "Do you copy?" },
  { at = 2.5, text = "We lost the signal." },
}
local voice = play_sound("intro_voice")

function update()
  local t = sound_position(voice)
  if not t then return end
  local current
  for _, line in ipairs(lines) do
    if t >= line.at then current = line.text end
  end
  if current then draw_text(40, 400, current, "default", 255, 255, 255) end
end
```

Loading a scene stops every sound and the music. The loaded audio assets are
kept and reused by id, like textures. Sounds declared with `stream = true` are
decoded on their first `play_sound` and freed when no voice is using them
(see the scene format); the decode may cause a short hitch on that first play.

### Spatial audio

A spatial sound (an *emitter*) sits at a world position. Its volume follows the
distance to the *listener* and its pan follows the horizontal offset, so a
sound to the left of the listener comes out of the left speaker. An emitter is
a normal voice: `play_sound_at` returns the same kind of handle as `play_sound`,
and `stop_sound`, `set_sound_volume` and `is_playing` work on it unchanged
(`set_sound_volume` changes the base volume; the final volume is base times the
distance gain).

| Function | Returns | Notes |
| --- | --- | --- |
| `play_sound_at(id, x, y, opts?)` | handle | `opts = { volume = 1, loop = false, min_dist = 64, max_dist = 400, rolloff = "linear", pan_width = 0, follow = entity, bus = "sfx" }`. Positions are world coordinates (the same ones as `get_position`). With `follow`, `x, y` is only the starting point: the emitter then tracks the center of that entity and stops when it dies. |
| `set_listener(entity)` | — | Chooses which entity hears the audio. `nil` goes back to the automatic listener. |
| `set_emitter_position(handle, x, y)` | — | Moves the emitter and stops it following an entity. |
| `set_emitter_distance_override(handle, d)` | — | Uses `d` instead of the real distance for the volume (the "distance lie"). `nil` removes it. The pan keeps the real direction. |
| `emitters_from_map(map, opts?)` | list of handles | Starts one emitter per object of class `opts.class` (default `"emitter"`) in a map from `load_tmx`. See below. |

The listener is, in order: the entity given to `set_listener` (if it is alive
and has a transform), the Lua global `player_entity` (if it is an entity), or
the center of the camera. Loading a scene resets the listener.

**Distance curves.** Inside `min_dist` the sound plays at full volume and
beyond `max_dist` it is silent.

- `"linear"`: the gain falls in a straight line from `1` at `min_dist` to `0`
  at `max_dist`.
- `"inverse"`: the gain is `min_dist / distance`, with a fade over the last
  quarter before `max_dist` so it reaches `0`.

**Pan.** The pan goes from `-1` (left) to `1` (right) and saturates at a
horizontal offset of `pan_width` pixels (`0` means half of `max_dist`). It
fades out when the listener is on top of the emitter. Left and right use an
equal-power law.

Volume and pan are smoothed (about 80 ms), so crossing an emitter does not
click. A sound beyond `max_dist` keeps playing at volume `0`, so a looping
sound keeps its phase while you are away.

```lua
-- a radio that follows an entity
local radio = play_sound_at("radio", 0, 0, {
  loop = true, min_dist = 48, max_dist = 320, follow = this,
})

-- a voice that always sounds close, wherever it is
local voice = play_sound_at("llorona", 900, 400, { loop = true, max_dist = 600 })
set_emitter_distance_override(voice, 80)   -- later: set_emitter_distance_override(voice, nil)
```

**Emitters placed in Tiled.** `emitters_from_map(map)` reads the objects of
class `emitter`. The position is the center of the object rectangle (the point
itself for a point object), in the same coordinates as the rest of the map.

| Property | Notes |
| --- | --- |
| `sound` | Sound id (required; objects without it are skipped with a warning). |
| `radius` / `max_distance` | Distance at which the sound is silent (default 400). `max_distance` wins when both exist. |
| `min_distance` | Full-volume radius (default 64). |
| `volume`, `loop`, `rolloff` | Same as in `play_sound_at`. `loop` defaults to `true`. |
| `bus` | `"voice"`, `"sfx"`, `"ambience"` or `"music"`. Default `"sfx"`; an unknown name is logged and the emitter uses `"sfx"`. |

An emitter can also be attached to an entity from the scene with the
[`sound_emitter`](scene-format.md#sound_emitter) component.

### Buses and ducking

Every sound plays on a *bus*. The bus has its own volume, set by the game with
`set_bus_volume` (for example from an options screen):

| Bus | Used for | Ducked by default |
| --- | --- | --- |
| `voice` | Dialogue and narration | Never |
| `sfx` | Effects (default for `play_sound`) | No |
| `ambience` | Looping background sounds | Yes |
| `music` | `play_music` | Yes |

The final volume of a voice is `volume * bus_volume * duck` (times the distance
gain for emitters). `duck` is `1` normally and the ducking amount while ducking
is active. The music track uses the same formula with its `volume` argument.

**Ducking.** While any voice on the `voice` bus is playing, the buses in the
duck list drop to `amount` (default `0.35`). They come back to `1` once no voice
is left. The change is a linear fade over `fade_ms` (default `300`). A voice that
is stopping keeps the ducking until its channel is silent. A music track started
during a duck starts at the ducked volume.

```lua
-- a narration on the voice bus ducks the music and the ambience while it plays
play_sound("mama_story", { bus = "voice" })
-- looping ambience on its own bus, positioned in the world
play_sound_at("crickets", x, y, { bus = "ambience", loop = true })

-- scene: scene.audio.duck is optional; these are the defaults
set_ducking({ enabled = true, amount = 0.35, fade_ms = 300, buses = { "ambience", "music" } })
set_ducking({ enabled = false })   -- turns it off for this scene
```

| Field | Notes |
| --- | --- |
| `enabled` | `false` turns ducking off. Default `true`. |
| `amount` | Volume of the ducked buses, `0` to `1`. Clamped to that range. |
| `fade_ms` | Length of the fade in milliseconds. `0` changes the volume at once. |
| `buses` | List of bus names to duck. Replaces the default list. `"voice"` is ignored (it is never ducked). |

Each scene starts with the defaults above. A scene can set its own ducking with
[`audio.duck`](scene-format.md#audio) in its scene file; without it the defaults
apply. `set_ducking` only changes the current scene and is not saved.

**Saved settings.** `set_bus_volume` writes the four bus volumes to
`settings.json` in the game's preferences folder, under `audio.buses`
(`{ "audio": { "buses": { "music": 0.5 } } }`). The folder comes from
`SDL_GetPrefPath("gameEngine", <game>)`; if SDL cannot give one, the file goes
in the game's folder (`games/<name>/settings.json`). The write happens about
500 ms after the last change and when the game closes. The file is merged with
what is already there, so other keys are kept. The saved values are loaded at
start-up, before the first scene. A file that cannot be read is ignored.

```lua
-- options menu: the music slider, and a key that mutes music
set_bus_volume("music", 0.5)
local music_now = get_bus_volume("music")   -- 0.5
```

---

## Lighting

A darkness overlay with soft light circles. A screen-sized light map is filled with
the ambient colour, every visible light is added to it as a radial gradient
(generated in code, no asset), and the map is multiplied over the world. It runs
after the world and before the HUD, so `draw_rect`, `hud` images, text, dialogue
and subtitles are never darkened. Lights are culled against the camera.

With the ambient at full white (`255, 255, 255`) and no transition running the
whole pass is skipped, so daytime scenes cost nothing.

Colours are `0..255`. `intensity` is `0..1` (higher values are clamped when drawn).
`flicker` is `0..1`: how far the light dips when it flickers (`0` = steady). It modulates
the intensity and, a little, the radius (down to 75% at full dip), following a smooth noise
curve with no random jumps.

| Function | Description |
| --- | --- |
| `add_light(x, y, radius, r, g, b, [intensity])` | Creates a free light at world coordinates and returns its id (`> 0`). `intensity` defaults to `1`. Returns `0` (and logs) if `radius <= 0`. |
| `move_light(id, x, y)` | Moves a free light. |
| `set_light(id, opts)` | Changes any of `x`, `y`, `radius`, `intensity`, `flicker`, `r`, `g`, `b` (or `color = { r=, g=, b= }`). Setting `intensity` cancels a running fade. |
| `fade_light(id, to, seconds)` | Fades the intensity to `to` over `seconds` (`<= 0` is instant). The light is not removed at `0`. |
| `remove_light(id)` | Deletes a free light. |
| `set_ambient(r, g, b, [seconds])` | Sets the ambient colour, linearly over `seconds` (default `0`, instant). Night is roughly `20, 26, 51`. |
| `attach_light(entity, [opts])` | Adds (or updates) a `LightComponent` on an entity, centred on its sprite. Same fields as the scene [`light`](scene-format.md#light) component. |
| `detach_light(entity)` | Removes the entity's light. |
| `lights_from_map(map, [opts])` | Creates a light for each Tiled object of class `opts.class` (default `"light"`). Properties: `radius` (required), `r`, `g`, `b`, `intensity`, `flicker`. The light sits at the centre of the object's rectangle. Returns the list of ids. |

Ids are never reused. An unknown id is ignored silently (so `move_light` can be
called every frame). `load_scene` removes every free light and resets the ambient to
white; a scene can set its own with [`lighting`](scene-format.md#lighting).

```lua
set_ambient(20, 26, 51, 2.0)                       -- dusk over two seconds
local lamp = add_light(320, 200, 90, 255, 200, 120, 0.9)
set_light(lamp, { flicker = 0.2 })
fade_light(lamp, 0, 1.5)
```

## Input

| Function | Returns | Notes |
| --- | --- | --- |
| `is_action_activated(name)` | `bool` | Works for both keyboard and mouse actions. |
| `get_mouse_position()` | `x, y` | Screen coordinates. In pixel-perfect mode, logical coordinates: over the letterbox bars they can be negative or larger than the logical size. |
| `get_mouse_world_position()` | `x, y` | Screen position plus the camera offset. |

Action names come from the scene's `keys` and `mouse` tables — see
[scene-format.md](scene-format.md). Escape quits the engine and is never delivered to scripts; do not bind it in a scene's `keys`.

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
| `set_on_trigger_enter(e, fn)` | — | `fn(other)`. A collider starts overlapping a trigger zone. Fires on **both** sides: `this` is the entity owning the hook, `other` the one it touched. |
| `set_on_trigger_stay(e, fn)` | — | `fn(other)`. Every frame the overlap continues. |
| `set_on_trigger_exit(e, fn)` | — | `fn(other)`. The overlap ends (also when either side goes dormant or is disabled). An entity that is *killed* gets no exit: use `on_death`. |
| `set_on_collision(e, fn)` | — | `fn(other)`. Fires every frame the two colliders keep overlapping, not once per contact — see [inventory.md](inventory.md#gotchas-and-limits) for the pickup pattern this implies. |

A script file loaded through a scene defines its hooks as globals:

```lua
function update() end
function on_damage(amount, source) end
function on_death() end
function on_collision(other) end
function on_trigger_enter(other) end
function on_trigger_stay(other) end
function on_trigger_exit(other) end
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
| `get_window_size()` | Returns `w, h` of the window in pixels (for centering HUD/menus). In pixel-perfect mode it returns the logical size (`logical_size`), see the README. |
| `random_seed()` | A random integer in `0..2^31-1` from `std::random_device`. Use it to pick a seed (`math.random` is C `rand()` and there is no `os`). |
| `set_active_area(minX, minY, maxX, maxY)` | Enables the active area (world px). Entities with the `cull` component outside it sleep: no scripts, animation, gravity, movement, collision or rendering. |
| `clear_active_area()` | Disables the active area (also done on every scene load). |

Loading a scene is a full reset: every entity is destroyed, entity ids start at
0 again, the camera goes back to `(0, 0)`, the `player_entity` / `game_over`
globals are cleared, and every module loaded with `require` is unloaded so its
module-level locals (cooldowns, open menus...) start fresh. Textures, fonts and
audio assets already loaded are kept and reused by id, but every playing sound
and the music are stopped.

**Lua globals survive `load_scene`** (only `player_entity` and `game_over` are
cleared), while modules are unloaded and re-run on the next `require`. Keep state
that must outlive a scene in a global table created with `x = x or {...}`; Quebrada's
`world_state` does this for flags and door transitions
([doors-and-zones.md](../../games/quebrada/docs/doors-and-zones.md)).

Flow used by the game: `scenes/menu.lua` (start screen) → `scenes/aval_cup.lua`
(ENTER for single player, M for Multiplayer). The menu stores the chosen
scene in the global `current_game_scene` (globals survive scene loads).
`player.lua`'s `on_death` sets `game_over = true` and `game_director.lua` shows
the game-over overlay (ENTER reloads `current_game_scene`, M returns to the
menu). `scenes/scene_01.lua` is the older single-scene prototype. Shared helpers
for these screens live in `ui_helpers.lua`. The Aval Cup map is described in
[aval-cup.md](../../games/aval/docs/aval-cup.md).

---

## Saving

Lua has no `io`, so the engine saves and loads tables as JSON (same conversion as the
network layer, `src/Network/LuaJson.hpp`).

| Function | Description |
| --- | --- |
| `save_data(slot, table)` | Writes `table` to the slot. Returns `true`, or `false` if it could not be written (the previous save stays intact). `slot` is 1-64 characters of `A-Z a-z 0-9 _ -`. |
| `load_data(slot)` | Returns the saved table, or `nil` if the slot does not exist or both files are unreadable. |
| `has_save(slot)` | `true` if `load_data(slot)` would return a table. |

- **Location**: the platform's user data folder, `SDL_GetPrefPath("santaval", "Quebrada")`
  (`~/Library/Application Support/Quebrada/` on macOS), never next to the binary. If SDL gives
  no path, `<game root>/saves/` is used.
- **Files**: `save_<slot>.json`, plus `save_<slot>.json.bak` (the previous save) and a short-lived
  `.tmp`.
- **Crash safety**: the new save is written completely to `.tmp` and then renamed over the old one,
  and the previous readable save is copied to `.bak` first. Killing the process mid-save leaves the
  old save usable; if the main file is ever corrupt, `load_data` falls back to `.bak`.
- **Table shape**: the top level must be a table. Tables that are exactly `1..n` become arrays;
  anything else becomes an object with string keys (so a table mixing both loses the numeric keys
  on the way back: use pure arrays or string keys). `nil`, functions and userdata are dropped.
  `1.0` comes back as the integer `1`; NaN/inf become `nil`; nesting is limited to 32 levels.
  Strings are UTF-8 and round-trip exactly.
- **Versioning is up to the game**: put a `version` field in the table and migrate it in Lua
  (Quebrada: [save.md](../../games/quebrada/docs/save.md)).

---

## Tiled maps

| Function | Description |
| --- | --- |
| `load_tmx(path)` | Parses a Tiled `.tmx` file (orthogonal, finite maps) and returns a table, or `nil, message` on failure (also logged as `[TmxLoader] ...`). |

Tile data may be CSV, XML, or base64 (uncompressed, zlib or gzip). zstd, infinite
maps, image-collection tilesets and object templates are not supported. External
`.tsx` tilesets resolve relative to the `.tmx`; tileset images relative to the tileset.
The `path` is resolved like other asset paths: relative to the game root
(`games/<name>/maps/town.tmx`), `@common/` for engine assets, `./` for the working directory (see [Asset paths](scene-format.md#asset-paths)).

```lua
local map, err = load_tmx("maps/town.tmx")
if not map then print(err) return end

map.width, map.height, map.tilewidth, map.tileheight, map.orientation
map.properties.name          -- int / float / bool / string keep their Lua type
map.tilesets[1].firstgid
map.tilesets[1].tiles[3]     -- per-tile type, properties, animation = {{tileid=, duration=}, ...}
map.layers[1].data[i]        -- gids, row by row, 1-based; 0 = empty; flip bits stripped
map.layers[1].flips[i]       -- only flipped cells: { h=, v=, d= }
for _, o in ipairs(map.objects) do ... end
```

Each entry of `map.objects` (flat list across all object layers, also reachable as
`layer.objects`): `id, name, type, layer, shape, x, y, width, height, rotation,
rect = {x, y, w, h}, properties`, plus `gid, flip_h, flip_v` for tile objects and
`points` for polygons/polylines (relative to `x, y`). `shape` is `rect`, `ellipse`,
`point`, `polygon`, `polyline`, `text` or `tile`. `type` is the Tiled 1.9+ `class`,
falling back to the older `type` attribute. Tile objects have `y` at their bottom
edge in Tiled; `rect` is already corrected to the top-left.

Every call to `load_tmx`, `load_tmx_colliders` and `load_tile_map` parses the file
again, so call them once (on scene start), not every frame.

---

## Tile map rendering

Draws the tile layers of a Tiled map under, between and over the entities. Tile
layers are culled to the camera, entities are y-sorted with tall tiles (a player
walks behind a tree trunk and in front of it), `above` layers (roofs, treetops)
go on top, animated tiles play on their own and layers can be faded from Lua.
Orthogonal, finite maps only. Tiles are not entities.

| Function | Returns | Notes |
| --- | --- | --- |
| `load_tile_map(path [, opts])` | `true` or `nil, message` | `opts = { x =, y = }` places the map in the world (default 0, 0). Path rules as in `load_tmx`. A second call replaces the first map. Loading a map turns y-sorting on. The map is dropped when a scene is (re)loaded. |
| `unload_tile_map()` | — | Removes the map. |
| `get_tile_map_size()` | `w_px, h_px` | `0, 0` when no map is loaded. |
| `get_tile_layers()` | array | One entry per drawable layer: `{ name, pass, visible, alpha, opacity, roof_of, properties }`. `pass` is `"ground"`, `"ysort"` or `"above"`. |
| `set_layer_alpha(name, a)` | count | `a` is 0-255 (clamped). Matches a layer by its name **or by the name of any group that contains it**, so naming a group fades every layer inside. Returns how many layers changed. |
| `get_layer_alpha(name)` | `a` or `nil` | Alpha of the first matching layer. |
| `set_layer_visible(name, v)` | count | Same matching as `set_layer_alpha`. |
| `set_roof_alpha(roof_of, a)` | count | Sets the alpha of every layer whose `roof_of` property equals `roof_of`. |
| `set_y_sort(on)` | — | Forces y-sorting of `world` sprites on or off. It is on whenever a map is loaded; use it to y-sort sprites without a map. |

The drawn alpha of a layer is `opacity * alpha / 255`, where `opacity` is the one
set in Tiled (multiplied through parent groups) and `alpha` is the one Lua drives.

### Layer properties

Set these as custom properties on a layer or on a group (children without the
property inherit it from their group; offsets add up and opacities multiply):

| Property | Meaning |
| --- | --- |
| `above` (bool) | The layer is drawn after the entities (treetops, roofs). Wins over `ysort`. |
| `ysort` (bool) | The layer's tiles (or tile objects, for an object layer) are sorted by Y together with the `world` sprites. |
| `roof_of` (string) | Tag used by `set_roof_alpha` to fade the roof of a building. |

A tile layer with neither property is plain ground, drawn in file order under the
entities. An object layer is only drawn when it is `ysort` or `above` (only its
tile objects); any other object layer is just data for `load_tmx`. Image layers
are skipped with a warning.

On tilesets, a tile may carry an int property `sort_offset`: it is added to the
Y used to sort that tile (a negative value lets the player pass in front of the
trunk's foot earlier). Tiles taller than the grid are aligned to the bottom of
their cell.

### Draw order

1. `draw_image` with layer `back`.
2. Ground tile layers, then sprites with layer `ground`.
3. `ysort` tile layers and `world` sprites, sorted by Y (ties: tile first, then
   creation order). Without a map and without `set_y_sort(true)`, `world`
   sprites keep their creation order, as before.
4. `above` tile layers, then sprites with layer `above`.
5. Trajectory, collider debug, `draw_image` with layer `front`, `draw_rect_world`
   rects, then the [lighting](#lighting) overlay. Everything after it is never lit:
   HUD (`draw_rect`, `hud` images, text).

A tile sorts by the bottom edge of its cell plus `sort_offset`; a sprite sorts by
the bottom edge of its current frame (or `set_sprite_sort_offset`).

### Fading a roof

```lua
-- house.tmx: group "casa_mama" with above = true and roof_of = "casa_mama"
local roof_target = 255
local roof_alpha = 255

function on_trigger_enter(other) roof_target = 0 end
function on_trigger_exit(other) roof_target = 255 end

function update()
  local step = 600 * get_delta_time()
  if roof_alpha < roof_target then roof_alpha = math.min(roof_target, roof_alpha + step)
  elseif roof_alpha > roof_target then roof_alpha = math.max(roof_target, roof_alpha - step) end
  set_roof_alpha("casa_mama", math.floor(roof_alpha))
end
```

---

## Network

Multiplayer bindings (protocol: [multiplayer-protocol.md](multiplayer-protocol.md)).
They are always safe to call: without `--server` (or while disconnected) each
one returns the offline default below, so single-player scripts run unchanged.

### Connection

The engine never connects by itself: the menu's Multiplayer option does it.

| Function | Description |
| --- | --- |
| `net_connect()` | Starts connecting to the configured server (`--server` / `GAME_SERVER`). Returns `false` if no URL is configured. The session is ready when `net_status()` is `"online"`. |
| `net_disconnect()` | Closes the connection and clears the session (peers, ids, pending messages). Others get `peer_left`. A later `net_connect()` works again. |
| `net_status()` | `"offline"` (no connection started), `"connecting"` (started, no `welcome` yet, or the link dropped and it is retrying) or `"online"`. |
| `net_server_url()` | The configured server URL, or `""` if none. |

### Session

| Function | Online | Offline |
| --- | --- | --- |
| `net_is_online()` | `true` once the server sent `welcome` | `false` |
| `net_my_id()` | Your player id | `""` |
| `net_is_host()` | `true` if you are the host | `true` |
| `net_peers()` | Array of the other players' ids | `{}` |
| `net_room_settings()` | Table `{ pvp = bool, seed = int? }` with the room settings (default `pvp = false`; `seed` is the map seed, `nil` until it is set) | `{ pvp = false }` |
| `net_set_pvp(enabled)` | Host only: sets PvP and broadcasts it. Returns `true` if applied, `false` if you are not the online host | `false` |
| `net_set_match_seed(seed)` | Sets the map seed (`1..4294967295`) and broadcasts it with the room settings. Allowed offline and for the host; returns `false` for a non-host or an invalid seed | applies locally, returns `true` |
| `net_host_id()` | The current host's player id | `""` |

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
| `net_register(e [, script, state_tbl])` | Gives an **existing** entity a netId owned by you (and adds it to the network sync). With a non-empty `script` and an online session it also broadcasts `spawn` for that prefab; `state_tbl` is merged over the entity's own `pos` / `vel` / `rot` / `acc` / `hp`. Returns the netId. Offline it only registers locally. Used by `player.lua` for the ship (no `script` for bullets, which are announced with `fire`). Entities registered without a `script` never send `state`: every client simulates them from the announcing event. |
| `net_despawn(e)` | Removes a networked entity and tells the others. Only the owner can despawn: calling it on a remote entity while online logs a warning and does nothing. An entity without network identity is just killed. |
| `spawn_local(script_path, state_tbl)` | Builds the entity from a prefab like `net_spawn` but with no netId and no `spawn` message: every client builds its own copy (used for the map's chunk rocks). Returns the entity or `nil`. |
| `is_local(e)` | `true` if you own the entity or it is not networked. Always `true` offline. |
| `get_net_id(e)` | The entity's netId string, or `nil`. |
| `find_by_net_id(id)` | The entity with that netId, or `nil`. |
| `get_owner(e)` | The owner's player id, or `nil` if the entity is not networked. |
| `set_owner(e, player_id)` | Rewrites the owner **locally only**; nothing is broadcast. |
| `net_reset_correction(e)` | Drops the pending drift correction of a remote copy. Call it right after `set_position` on a copy teleported by its owner, so an older `state` does not pull it back. No-op if the entity is not networked. |

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

While a prefab is built, the engine exposes the spawn state as the global
`spawn_state` (restored afterwards), so the prefab's runtime script can read it
when its chunk loads (`remote_player.lua` reads `name` and `max_hp`). Chunk-level
`local` variables are per entity, since the script file runs once per entity.
`this` is **not** the new entity at that point: resolve it inside `update()`.

The engine also handles an incoming `fire` itself: it builds
`prefabs/bullet.lua` and registers it under `bulletNetId`.

`script_path` is relative to `<game root>/scripts/prefabs/` (so
`"player/remote_player.lua"` is `games/aval/scripts/prefabs/player/remote_player.lua`)
and must not contain `..`. The same relative path is what other players receive
in `spawn.script`. A prefab is a Lua file that returns either a scene-format
entity definition or a `function(state)` returning one (`state` is the table
above):

```lua
-- games/aval/scripts/prefabs/bullet.lua
return {
  components = {
    transform = { position = { x = 0, y = 0 }, scale = { x = 0.5, y = 0.5 } },
    sprite = { assetId = "bullet", width = 64, height = 32, src_rect = { x = 0, y = 192 } },
    script = { path = "scripts/bullet.lua" },
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

#### World entities (`world = true`)

A spawn state with `world = true` marks a **host-owned world entity** (asteroids,
ring rocks, pickups, enemies). The host answers a late joiner's snapshot with
all of them, built again from `spawn_state`, so a prefab for a world entity must
rebuild itself **entirely from its state** (`prefabs/asteroid.lua` reads `kind`
and `scale`; `prefabs/pickup.lua` reads `item` and `quantity`; ring rocks carry
`ring = {x, y, radius, speed}` and `slot`). When the host leaves, the engine
reassigns the world entities to the new host, and `is_local(e)` becomes `true`
there. Only world entities are adopted: a player's ship and bullets are removed
when that player leaves. Spawners must run only `if net_is_host()` (always
`true` offline), and the hooks of world entities act only `if is_local(this)`.

Shared Lua globals used by the gameplay scripts (reset by each scene on load,
filled on every client): `drifting_asteroids` (netIds of spawned asteroids, used
to cap them), `ring_slots` (slot -> netId of the Saturn ring rock) and
`player_ships` (netIds of the other players' ships, used by enemies to pick the
nearest target). Always resolve them with `find_by_net_id` and ignore ids that
return `nil`.

#### Loot flow (`loot_net.lua`)

Pickups are world entities, so loot is granted exactly once:

1. When an asteroid dies, only its owner runs the `on_death` hook of `asteroid.lua` and creates
   one pickup per loot item with `net_spawn("pickup.lua", {item, quantity, world = true})`.
2. A client whose ship touches a pickup it does not own sends the custom message
   `pickup_request {lootNetId}` to the pickup's owner (at most once per second
   per pickup). If the pickup is its own, it calls `loot_net.grant` directly.
3. The owner runs `grant(pickup, by)`: it broadcasts `loot_taken {lootNetId, by, items}`
   and despawns the pickup. The first request wins; later ones find nothing and are
   ignored. When `by` is the owner itself, items that do not fit stay in the
   pickup (same as offline).
4. Only the client named in `by` adds `items` to its ship's inventory, and only if
   the message comes from the pickup's owner. Items beyond that player's hold
   capacity are lost in multiplayer.

`loot_net.lua` registers its `net_on` handlers when it is `require`d (from
`pickup.lua`), so it re-registers itself on every scene load.

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
| `get_health`, `get_max_health`, `is_alive`, `set_health`, `heal`, `set_max_health`, `get_shield`, `get_damage`, `set_damage`, `is_path_active`, `set_path_active`, `set_equipment_level`, `get_equipment_level`, `has_equipment`, `upgrade_equipment`, `remove_equipment`, `get_equipment_count`, `get_equipment_at`, `has_inventory`, `add_item`, `remove_item`, `update_item_count`, `get_item_count`, `has_item`, `get_inventory_total`, `get_inventory_capacity`, `set_inventory_capacity`, `get_inventory_count`, `get_inventory_at`, `clear_inventory`, `has_loot`, `get_loot_count`, `get_loot_at`, `set_loot`, `destroy_entity`, `draw_rect`, `draw_rect_world` | `get_position`, `set_position`, `get_rotation`, `set_rotation*`, every `*_velocity` / `*_acceleration` / `*_max_speed`, `get_speed`, `set_sprite`, `set_sprite_frame`, `set_text`, `set_text_color` |

In practice: before calling anything in the right-hand column on an entity you
did not build yourself, make sure it has the component.
