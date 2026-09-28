# Scene Format

A scene is a Lua file that defines one global table called `scene`. The engine
loads it at startup, registers the assets and input mappings it declares, and
builds the entities it lists.

The scene file currently loaded is hardcoded in
[`Game::setup()`](../src/Game/Game.cpp):

```cpp
this->sceneLoader->load("./assets/scripts/scenes/scene_01.lua", ...);
```

---

## Shape

```lua
scene = {
  sprites  = { ... },   -- required
  fonts    = { ... },   -- optional
  keys     = { ... },   -- required
  mouse    = { ... },   -- optional
  entities = { ... },   -- required
}
```

> **Every list is 0-indexed.** The loader walks `t[0]`, `t[1]`, `t[2]`… and
> stops at the first missing index. That is why scene files start with
> `[0] =` and then continue with bare entries:
>
> ```lua
> sprites = {
>   [0] =
>   { assetId = "bullet", filePath = "./assets/sprites/bullets/bullets.png" },
>   { assetId = "asteroid", filePath = "./assets/sprites/asteroid/asteroid.png" },
> }
> ```
>
> Forget the `[0] =` and the list silently loads nothing.

---

## `sprites`

Textures, loaded once and referenced everywhere by `assetId`.

```lua
{ assetId = "spaceship-idle", filePath = "./assets/sprites/spaceship/player/idle.png" }
```

Paths are relative to the working directory the engine is launched from.

## `fonts`

```lua
{ fontId = "default",   filePath = "./assets/fonts/DejaVuSansMono.ttf", fontSize = 16 }
{ fontId = "debug-big", filePath = "./assets/fonts/DejaVuSansMono.ttf", fontSize = 28 }
```

**Size is baked in at load time** — one `fontId` per size, even for the same
font file.

## `keys`

Maps a name to an SDL keycode. Scripts then ask for the name, never the code.

```lua
{ name = "accelerate",       key = 119 },  -- w
{ name = "brake",            key = 115 },  -- s
{ name = "toggle_path",      key = 116 },  -- t
{ name = "toggle_colliders", key = 99  },  -- c
```

For printable ASCII keys the code is simply the character's byte value, so
`string.byte("w")` gives you `119`.

## `mouse`

```lua
{ name = "shoot", button = 1 }   -- 1 = left, 2 = middle, 3 = right
```

Keyboard and mouse actions share one namespace — `is_action_activated("shoot")`
works the same either way.

## `entities`

Each entry is a table with a `components` table inside it:

```lua
entities = {
  [0] =
  {
    components = {
      transform = { ... },
      sprite    = { ... },
      -- ...
    },
  },
}
```

Entities can be built procedurally — a scene file is ordinary Lua, so a loop
that appends generated entities to the list works fine:

```lua
for _, asteroid in ipairs(buildAsteroidField()) do
  entities[#entities + 1] = asteroid
end
```

---

## Component tables

Every component is optional. Anything you leave out is simply not added.

### `transform`

```lua
transform = {
  position = { x = 400, y = 100 },   -- default { 0, 0 }
  scale    = { x = 0.2, y = 0.2 },   -- default { 1, 1 }
  rotation = 0,                      -- default 0, in radians
}
```

`position` is the sprite's **top-left corner**, not its centre.

### `rigid_body`

```lua
rigid_body = {
  velocity     = { x = 0, y = 0 },   -- default { 0, 0 }
  acceleration = { x = 0, y = 0 },   -- default { 0, 0 }
  max_speed    = 100,                -- default 0 = unlimited
}
```

Acceleration is in the entity's **local space** (rotated by its rotation before
being integrated); velocity is in world space.

### `sprite`

```lua
sprite = {
  assetId  = "spaceship-idle",   -- required
  width    = 430,                -- required, source frame size
  height   = 650,                -- required
  src_rect = { x = 0, y = 0 },   -- optional, defaults to { 0, 0 }
}
```

`src_rect` picks a frame out of a spritesheet. On-screen size is
`width * scale.x` by `height * scale.y`.

> The existing scene file has a `rotation = 0` key inside its `sprite` tables.
> The loader does not read it — rotation lives on the `transform`. It is a
> leftover, and copying it into a new entity does nothing.

### `animation`

```lua
animation = {
  numFrames      = 4,      -- default 1
  frameSpeedRate = 5,      -- default 1, frames per second
  isLoop         = true,   -- default true
}
```

Note the camelCase keys — this table has not been renamed to snake_case like the
newer ones.

**An animation overwrites `src_rect.x` every frame**, so it cannot be combined
with a hand-picked spritesheet frame.

### `circle_collider`

```lua
circle_collider = {
  radius = 170,
  width  = 430,
  heigth = 650,   -- NOTE THE SPELLING
}
```

> **`heigth` is the real key**, misspelled in the loader. Writing `height` here
> makes the value silently `nil` and the collider geometry wrong. This is the
> single most common mistake when writing a new scene entity.

`width`/`height` should be the **full sprite frame**, not the artwork's bounding
box: the collider centre is `position + (width / 2) * scale`, which is the same
point SDL rotates the sprite around. Any other value drifts as the entity turns.

`radius` is in **unscaled** sprite units and is multiplied by `scale.x` only.

Scene entities cannot declare an `owner` — that is a runtime-only argument of
`add_circle_collider`.

### `health`

```lua
health = {
  max             = 100,   -- default 1
  current         = 100,   -- optional, defaults to max
  invulnerability = 0.5,   -- default 0, seconds of grace after a hit
}
```

### `damage`

```lua
damage = {
  amount         = 20,      -- default 0
  destroy_on_hit = true,    -- default false
}
```

See [health-and-damage.md](health-and-damage.md) for how these two interact.

### `equipment`

```lua
equipment = {
  engine = 1,
  gun    = 3,
  shield = 4,
}
```

Keys are free-form — anything the loader finds with a string key and an
integer value is accepted, no need to register tool names anywhere in C++.
The loader normalizes the order alphabetically by name before storing it,
since Lua table iteration order is not guaranteed. See
[equipment.md](equipment.md).

### `inventory`

```lua
inventory = {
  capacity = 50,        -- optional, default 0 (unlimited)
  items = {
    mineral = 0,
  },
}
```

Both `capacity` and `items` are optional. `items` follows the same rule as
`equipment`: free-form string keys with integer values, sorted alphabetically
by the loader before storing. Quantities of `0` or less are skipped. Unlike
the Lua-facing `add_item` / `update_item_count`, scene items are **not**
clamped against `capacity` — the loader trusts the scene author. See
[inventory.md](inventory.md).

### `text`

```lua
text = {
  content        = "PLAYER",                       -- default ""
  fontId         = "default",                      -- default "default"
  is_world_space = true,                           -- default true
  color          = { r = 255, g = 200, b = 0, a = 255 },
  offset         = { x = 0, y = -60 },
}
```

A persistent label drawn at the entity's transform plus the offset.

### `path`

```lua
path = { active = true }   -- default true
```

Draws the predicted trajectory. Needs a transform and a rigid body.

### `script`

```lua
script = { path = "./assets/scripts/player.lua" }
```

The file is executed immediately, and its globals `update`, `on_damage`,
`on_death` and `on_collision` are captured as that entity's callbacks.

> The loader clears those four globals before executing each file, so a script
> that defines only `update` will not inherit the `on_death` of whichever file
> happened to load before it. This also means every entity loaded from the
> same script file shares whatever `on_collision` that file defines as a
> global — a hook meant for one runtime-created entity only (like a pickup
> spawned from `on_death`) should be attached with `set_on_collision` instead,
> not declared as the file's global `on_collision`. See
> [inventory.md](inventory.md#gotchas-and-limits).
>
> Everything *else* a script defines stays global and shared across files. Use
> prefixes (`player_cooldown`, not `cooldown`) to avoid collisions.

---

## A complete minimal entity

```lua
{
  components = {
    transform = {
      position = { x = 400, y = 100 },
      scale    = { x = 0.2, y = 0.2 },
    },
    sprite = {
      assetId = "spaceship-idle",
      width   = 430,
      height  = 650,
    },
    circle_collider = {
      radius = 170,
      width  = 430,
      heigth = 650,
    },
    rigid_body = { max_speed = 100 },
    health     = { max = 100, invulnerability = 0.5 },
    script     = { path = "./assets/scripts/player.lua" },
  },
}
```
