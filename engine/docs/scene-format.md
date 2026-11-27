# Scene Format

A scene is a Lua file that defines one global table called `scene`. The engine
loads it at startup, registers the assets and input mappings it declares, and
builds the entities it lists.

The first scene is always `<game root>/scenes/main.lua` (for the default game,
`games/aval/scenes/main.lua`), set in [`Game::setup()`](../src/Game/Game.cpp):

```cpp
this->loadScene(this->entryScenePath());
```

From there scripts switch scenes with `load_scene(path)` (see
[Game flow & scenes](lua-api.md#game-flow--scenes)). Reloading a scene resets
all entities and `require`d modules, so restarting a level is just
`load_scene` on the same file.

---

## Asset paths

Paths in a scene or script (sprite and font `filePath`, `script.path`,
`load_scene(path)`, `load_tmx(path)`) are resolved like this:

| Written as | Resolves to |
|------------|-------------|
| `@common/x` | `engine/common/x` (shared engine assets: `fonts/`, `scripts/`) |
| `/abs/x` | unchanged (absolute) |
| `./x`, `../x` | unchanged: relative to the working directory (the repo root) |
| anything else, e.g. `sprites/ship.png` | `<game root>/sprites/ship.png`, e.g. `games/aval/sprites/ship.png` |

So a game never writes its own folder name: `"sprites/ship.png"` means the
current game's sprite. `require` is unaffected (it searches the game's
`scripts/`, see [README](README.md#choosing-the-game)), and neither are the
prefab paths used by `net_spawn`/`spawn_local`, which stay relative to
`<game root>/scripts/prefabs/` so they match on the wire.

---

## Shape

```lua
scene = {
  sprites  = { ... },   -- required
  fonts    = { ... },   -- optional
  audio    = { ... },   -- optional
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
>   { assetId = "bullet", filePath = "sprites/bullets/bullets.png" },
>   { assetId = "asteroid", filePath = "sprites/asteroid/asteroid.png" },
> }
> ```
>
> Forget the `[0] =` and the list silently loads nothing.

---

## `sprites`

Textures, loaded once and referenced everywhere by `assetId`.

```lua
{ assetId = "spaceship-idle", filePath = "sprites/spaceship/player/idle.png" }
```

Paths follow the [asset path rules](#asset-paths): relative to the game root.

A sprite can also carry an Aseprite/pixelfx JSON next to its PNG. It is
registered under the same `assetId` and used by the
[atlas form of `animation`](#animation):

```lua
{ assetId = "hero", filePath = "sprites/hero.png", atlas = "sprites/hero.json" }
```

A missing or invalid JSON is reported on stderr and the atlas is not registered.

## `fonts`

```lua
{ fontId = "default",   filePath = "@common/fonts/DejaVuSansMono.ttf", fontSize = 16 }
{ fontId = "debug-big", filePath = "@common/fonts/DejaVuSansMono.ttf", fontSize = 28 }
```

**Size is baked in at load time** — one `fontId` per size, even for the same
font file.

## `sounds`

Optional. Sound effects and voice recordings, played with `play_sound` (see
[Audio](lua-api.md#audio)).

```lua
{ assetId = "shot",  filePath = "sounds/shot.ogg" }
{ assetId = "intro", filePath = "sounds/intro-voice.mp3", stream = true }
```

OGG and MP3 are supported (depending on the installed SDL2_mixer). `stream` is
optional and defaults to `false`: the file is fully decoded when the scene
loads. With `stream = true` the file is only registered at load and decoded on
the first `play_sound`, then freed when nothing is playing it, which keeps long
recordings out of memory until needed. It is a lazy decode, not true streaming:
a 3-minute stereo recording needs roughly 34 MB while it plays, and the first
play can hitch while it decodes. A file that fails to load is reported on
stdout and not registered.

## `music`

Optional. Background music tracks, played with `play_music`. Only one track
plays at a time.

```lua
{ assetId = "last_signal", filePath = "sounds/last-signal.mp3" }
```

Both tables are 0-indexed like `fonts`, and their assets are kept by id across
scene loads.

## `audio`

Optional. Sets the ducking of this scene (see
[Buses and ducking](lua-api.md#buses-and-ducking)). Without it the defaults
apply: while a voice plays, `ambience` and `music` drop to `0.35` over 300 ms.
Each scene starts from the defaults, so a value here only lasts for this scene.

```lua
audio = {
  duck = {
    enabled = true,                     -- default true
    amount  = 0.35,                     -- default 0.35, clamped to 0..1
    fade_ms = 300,                      -- default 300
    buses   = { "ambience", "music" },  -- default; "voice" is ignored
  },
},
```

Every field under `duck` is optional. The bus volumes themselves are not part of
the scene: they belong to the player and are saved in `settings.json`.

## `lighting`

Optional. Sets the ambient colour this scene starts with (see
[Lighting](lua-api.md#lighting)). Without it the scene starts at full white, i.e.
no darkness. Lights and ambient are reset on every scene load.

```lua
lighting = {
  ambient = { r = 20, g = 26, b = 51 },  -- 0..255 each, default 255
},
```

## `keys`

Maps a name to an SDL keycode. Scripts then ask for the name, never the code.

```lua
{ name = "accelerate",       key = 119 },  -- w
{ name = "brake",            key = 115 },  -- s
{ name = "toggle_path",      key = 116 },  -- t
{ name = "toggle_colliders", key = 99  },  -- c
{ name = "toggle_upgrades",  key = 101 },  -- e
{ name = "upgrade_1",        key = 49  },  -- 1
{ name = "upgrade_2",        key = 50  },  -- 2
{ name = "upgrade_3",        key = 51  },  -- 3
```

For printable ASCII keys the code is simply the character's byte value, so
`string.byte("w")` gives you `119`.

Non-ASCII keys use the raw SDL keysym (Right `1073741903`, Left `1073741904`,
Down `1073741905`, Up `1073741906`, Left Shift `1073742049`, Right Shift
`1073742053`).

> **One key per action name.** Duplicate names are silently ignored (the first
> one wins), so an action cannot be bound to two keys. To accept both WASD and
> the arrow keys, declare two names (`walk_up` and `walk_up_alt`) and have the
> script check both, as `walker.lua` does in the Quebrada walk demo.

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

Optional keys that matter with a [tile map](lua-api.md#tile-map-rendering):

```lua
sprite = {
  ...
  layer       = "world",  -- "ground" | "world" (default) | "above"; unknown: warning, stays "world"
  sort_offset = -1,       -- y-sort feet, px from the frame top (* scale.y); -1 = bottom of the frame
  flip_h      = false,    -- mirror horizontally
}
```

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

#### Atlas form (Aseprite JSON)

For sheets exported from Aseprite or pixelfx: frames may differ in size and
duration, and animations are selected by **tag**.

```lua
animation = {
  atlas = "hero",    -- assetId of a sprite that declares `atlas = ...`
  tag   = "idle",    -- default: the first tag of the atlas
  loop  = true,      -- default true
}
```

While an atlas animation plays, every frame the system writes the **whole**
`src_rect` (x, y, w, h) and the sprite's `width`/`height` from the JSON, so the
entity's `sprite` width/height only matter before the first update. Frame
durations come from the JSON (`duration`, ms; `<= 0` falls back to 100). Without
`frameTags`, the atlas has one implicit tag named `""` covering all frames. Tag
directions: `forward`, `reverse`, `pingpong` (endpoints are not repeated:
0,1,2,1,0,...) and `pingpong_reverse`. With `loop = false` the animation stops
on the last frame (a pingpong ends back on the first one) and
`animation_finished(e)` becomes true. An unknown `atlas` falls back to a default
animation; an unknown `tag` falls back to the first tag, both with a warning.

Legacy keys (`numFrames`, `frameSpeedRate`, `isLoop`) keep working when `atlas`
is absent.

**Aseprite export recipe.** File > Export Sprite Sheet: in *Output* tick *JSON
Data* (hash or array are both read) and *Tags*, in *Sprite* leave *Trim* **off**
(trimmed frames would be drawn at their cropped size and shift the sprite).
Walk cycles: one tag per direction (`walk_down`, `walk_left`, ...) and the script
calls `play_animation(e, "walk_" .. dir)`.

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

### `box_collider`

```lua
box_collider = {
  width    = 32,
  height   = 48,    -- spelled correctly here; "heigth" is NOT accepted
  offset_x = 0,     -- from the sprite's top-left corner, scaled
  offset_y = 0,
  solid    = false, -- blocks `mover` boxes
  trigger  = false, -- enter / stay / exit events; wins over solid (the loader warns)
  mover    = false, -- moved by the sweep against walls instead of plain integration
}
```

All keys are optional (default `0` / `false`). An entity can have both a
`circle_collider` and a `box_collider`. See [collision.md](collision.md) for
what each flag combination does. `owner` and `enabled` are runtime-only
(`add_box_collider`, `set_box_collider`).

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
  min_impact_speed  = 40,   -- optional, px/s: slower impacts deal no damage
  full_impact_speed = 200,  -- optional, px/s: impacts at/above deal `amount`; 0 = flat damage
}
```

See [health-and-damage.md](health-and-damage.md) for how these two interact.

### `gravity`

```lua
gravity = {
  mass     = 3000,    -- default 1
  attracts = true,    -- default false: pulls other bodies
  affected = false,   -- default true: is pulled (also needs a rigid_body)
  range    = 700,     -- default 0 = unlimited, in px
}
```

See [gravity.md](gravity.md).

### `cull`

```lua
cull = true   -- default false: no component
```

Adds a `CullComponent` (a tag with no data). While an active area is set
(`set_active_area`), the entity is skipped by the script, animation, gravity,
movement, collision, render and collider-overlay systems whenever its
`transform.position` is outside that area. See [aval-cup.md](../../games/aval/docs/aval-cup.md).

### `sound_emitter`

```lua
sound_emitter = {
  sound        = "fountain",   -- required: a sound id from `sounds`
  min_distance = 64,           -- default 64: full volume inside this radius
  max_distance = 400,          -- default 400; `radius` is an alias
  rolloff      = "linear",     -- "linear" (default) or "inverse"
  volume       = 1,            -- default 1
  loop         = true,         -- default true
  offset       = { x = 0, y = 0 },  -- default { 0, 0 }, from the entity center
  bus          = "sfx",        -- "voice", "sfx" (default), "ambience" or "music"
}
```

Adds a `SoundEmitterComponent`. An unknown `bus` is logged and the emitter uses `sfx`. The sound starts the first frame the entity is
active and follows the entity, with volume by distance and pan by horizontal
offset relative to the listener. It stops when the entity dies. The entity
needs a `transform`; its center is the position plus half the sprite size
(scaled) when it has a sprite. See [Spatial audio](lua-api.md#spatial-audio).

### `light`

A circular light centred on the entity (the middle of its sprite, plus `offset`).
Needs a `transform`. See [Lighting](lua-api.md#lighting).

```lua
light = {
  radius    = 64,                          -- default 64; must be > 0
  color     = { r = 255, g = 210, b = 150 }, -- default white
  intensity = 1,                           -- default 1
  flicker   = 0,                           -- default 0
  offset    = { x = 0, y = 0 },            -- default 0, 0
},
```

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

### `loot`

```lua
loot = {
  iron  = 2,
  stone = 1,
}
```

What the entity drops, read by its script (see `on_death` in
`scripts/asteroid.lua`). Same rules as `inventory.items`: free-form
string keys with integer values, quantities of `0` or less skipped, sorted
alphabetically by the loader. It is a separate component from `inventory` on
purpose: `has_inventory(other)` is what decides who can pick things up.

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
script = { path = "scripts/player.lua" }
```

The file is executed immediately, and its globals `update`, `on_damage`,
`on_death`, `on_collision`, `on_trigger_enter`, `on_trigger_stay` and
`on_trigger_exit` are captured as that entity's callbacks.

> The loader clears those globals before executing each file, so a script
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
    script     = { path = "scripts/player.lua" },
  },
}
```
