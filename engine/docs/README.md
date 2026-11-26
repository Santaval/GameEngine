# Engine Documentation

A 2D game engine built on SDL2, with an ECS core in C++ and gameplay written
entirely in Lua.

| Document | What's in it |
| --- | --- |
| [lua-api.md](lua-api.md) | Every function the engine exposes to Lua. |
| [scene-format.md](scene-format.md) | The `scene` table: assets, input mappings, entities and every component. |
| [collision.md](collision.md) | Box colliders, static walls, solid Tiled tiles, trigger zones and wall sliding. |
| [health-and-damage.md](health-and-damage.md) | Hit points, contact damage, invulnerability and death hooks. |
| [equipment.md](equipment.md) | Named upgrade levels tracked per entity. |
| [inventory.md](inventory.md) | Named item quantities, an optional capacity, and the mineral pickup gameplay. |
| [gravity.md](gravity.md) | Mass-based attraction between planets, ship, asteroids and bullets. |
| [asteroid-spawner.md](../../games/aval/docs/asteroid-spawner.md) | Aval: generators outside the map that keep spawning asteroids at random intervals. |
| [multiplayer-protocol.md](multiplayer-protocol.md) | Wire protocol and ownership rules for the relay server and multiplayer clients. |
| [aval-cup.md](../../games/aval/docs/aval-cup.md) | Aval: Aval Cup map: world grid, sectors, chunks, deterministic seed and culling. |

---

## Building and running

```sh
# from the repository root (it forwards to engine/Makefile):
make        # builds engine/engine
make run    # engine/engine (default game: aval); make run-quebrada for Quebrada
make deps   # fetches IXWebSocket + nlohmann/json (make build does it automatically)
make test   # unit test for NetworkRegistry (ECS only, no SDL)
make clean
make clean-deps   # forces IXWebSocket to be rebuilt
make lua-info     # prints which Lua pkg-config/headers were detected
```

Needs `libsdl2-dev`, `libsdl2-image-dev`, `libsdl2-ttf-dev`, `zlib1g-dev`, `libssl-dev` and a
Lua dev package (`liblua5.3-dev` or 5.4). GLM, sol2 and the Lua headers are
vendored in `engine/libs/` (not tracked by git; if you had `./libs` before the split, `mv libs engine/libs`). The Makefile reads `LUA_VERSION_NUM` from whichever
`lua.h` the compiler actually resolves and passes it to sol2 as
`-DSOL_LUA_VERSION`; if sol2 errors on `lua_newuserdatauv` or `LUA_GCGEN`, it
was built for 5.4 against 5.3 headers -- run `make lua-info` to see what was
picked up. IXWebSocket and nlohmann/json are not committed:
`scripts/fetch-deps.sh` downloads pinned versions into `engine/libs/` (needs `curl`),
and IXWebSocket is compiled once, with TLS via OpenSSL, into
`engine/libs/IXWebSocket/libixwebsocket-tls.a`.

Multiplayer is opt-in: `./engine/engine --server ws://host:7777` (or the `GAME_SERVER`
environment variable). Use `wss://` for servers behind HTTPS, e.g.
`./engine/engine --server wss://<app>.up.railway.app`. Without it the engine runs offline and prints nothing
from the network layer. See [multiplayer-protocol.md](multiplayer-protocol.md).

### Choosing the game

The repository is split into the engine (`engine/`) and one folder per game
(`games/<name>/`). Pick a game at boot with `--game <name>` (or `--game=<name>`,
or the `GAME` environment variable; the flag wins). Without it the default
game, `aval` (Space Battle Royale), starts. `make run` and `make run-quebrada`
are shortcuts from the repository root.

| Game | Root | Entry scene |
|------|------|-------------|
| default (no flag) = `aval` | `games/aval/` | `games/aval/scenes/main.lua` |
| `--game <name>` | `games/<name>/` | `games/<name>/scenes/main.lua` |

A game has its own folders: `scripts/`, `scenes/`, `sprites/`, `sounds/`,
`maps/`, plus an optional `game.lua`. `require` searches, in order,
`<root>/scripts/?.lua`, each direct subfolder of `<root>/scripts/` except
`prefabs` (`scripts/*/?.lua`), then the shared `engine/common/scripts/`
(helpers used by every game, e.g. `ui_helpers.lua`).
Prefabs spawned over the network are read from `<root>/scripts/prefabs/`.

`games/<name>/game.lua` is optional and sets the window:

```lua
return { title = "Quebrada", width = 1280, height = 720 }
```

With `width` and `height` the window is windowed at that size; without them it
is fullscreen at desktop size (Aval sets only a `title`). An unknown or invalid
game name (`--game nope`, `--game ../x`), or a game without
`scenes/main.lua`, exits with an error.

The binary is `engine/engine` and must be run from the repository root
(`make run` does this; or `./engine/engine --game quebrada`): the game roots
are relative to the working directory. Asset paths written in scenes and
scripts follow the rules in [scene-format.md](scene-format.md#asset-paths).

Components, systems and bindings are **header-only**, so adding one needs no
Makefile change — only the `.cpp` directories are globbed.

---

## How the engine is put together

### Entities, components, systems

An entity is just an integer id. Components are plain structs held in pools
indexed by that id. A system declares which components it cares about and
receives the matching entities.

Nothing about gameplay lives in C++: the engine provides mechanisms
(movement, collision, damage, rendering) and a scene file wires them into a
game.

### The frame

`Game::update()` runs, in this order:

0. `NetClient::poll()` — only when online: drains the inbound network queue and
   runs the network handlers on the main thread.
1. Event subscriptions are reset and re-registered.
2. `Registry::update()` — entities created last frame join their systems, and
   entities killed last frame are removed.
3. **ScriptSystem** — every entity's `update()` runs.
4. **NetSyncSystem** — owners send their `state` (12.5 Hz, within a message
   budget); non-owners get pulled toward the owner's last known state (see
   [multiplayer-protocol.md](multiplayer-protocol.md)).
5. **AnimationSystem** — advances spritesheet frames (equal-frame strips or Aseprite JSON atlases with tags).
6. **GravitySystem** — adds the pull of every attractor to the velocity of
   every affected body (see [gravity.md](gravity.md)).
7. **MovementSystem** — integrates acceleration into velocity into position.
8. **BoxColliderSystem** — moves every `mover` box collider with an exact
   sweep against static walls and solid boxes (see [collision.md](collision.md)).
9. **CollisionSystem** — circles and boxes share one 256 px uniform-grid
   broadphase. Overlaps emit a collision event (circle-vs-circle, circle-vs-box,
   box-vs-box), and overlaps with a trigger zone emit enter / stay / exit
   events instead. **DamageSystem** reacts to collision events immediately.

Then `Game::render()` draws, back to front:

1. **RenderSystem** — sprites.
2. **PathRenderSystem** — predicted trajectories.
3. **ColliderRenderSystem** and **BoxColliderRenderSystem** — the hitbox
   overlay (circles, boxes and static walls), skipped entirely when off.
4. **TextRenderSystem** — world labels and the HUD.

The loop is capped at 30 FPS.

### Why scripts run before physics

A script sets acceleration and rotation; the movement system consumes them the
same frame. That is also why `set_acceleration` is in local space — the script
says "thrust forward", and the engine resolves what forward means.

---

## Components at a glance

| Component | Purpose | Scene key |
| --- | --- | --- |
| `TransformComponent` | Position (top-left), scale, rotation. | `transform` |
| `RigidBodyComponent` | Velocity, acceleration, speed limit. | `rigid_body` |
| `SpriteComponent` | Texture id, frame size, source rect. | `sprite` |
| `AnimationComponent` | Spritesheet playback (strip or Aseprite atlas + tags). | `animation` |
| `CircleColliderComponent` | Collision circle plus an owner exclusion. | `circle_collider` |
| `BoxColliderComponent` | Axis-aligned collision box: solid, trigger zone and/or wall-sliding mover. | `box_collider` |
| `HealthComponent` | Hit points and invulnerability window. | `health` |
| `DamageComponent` | Contact damage dealt. | `damage` |
| `GravityComponent` | Mass, plus whether it attracts and/or is attracted. | `gravity` |
| `EquipmentComponent` | Named upgrade levels (engine, gun, shield, ...). | `equipment` |
| `InventoryComponent` | Named item quantities plus an optional total capacity. | `inventory` |
| `TextComponent` | A label pinned to the entity. | `text` |
| `PathComponent` | Trajectory prediction toggle. | `path` |
| `NetworkComponent` | Network identity (`netId`) and owner (`ownerId`); set via `NetworkRegistry`. | none yet |
| `ScriptComponent` | `update`, `on_damage`, `on_death`, `on_collision`, `on_trigger_enter/stay/exit`. | `script` |

---

## Two engine quirks worth knowing up front

**System membership is decided once.** An entity is matched against every
system's signature exactly once, when it is first flushed into the registry.
Adding a component to an entity that is already alive will not enrol it in a
new system. In practice: give an entity its `transform`, `sprite`,
`rigid_body` and `circle_collider` in the same frame you create it.

`add_box_collider` is the exception: it re-enrols the entity in the systems
itself, so a box can be added to a live entity.

Components that only get read on demand — `health`, `damage`, `path` — are
exempt, because the systems that use them either are event-driven or filter
inside their loop instead of through the signature.

**Death is deferred.** `kill()` queues the entity; it is actually removed at
the start of the next frame. Until then it still shows up in collision checks.

---

## Loading Tiled maps

`load_tmx(path)` reads a Tiled `.tmx` file (orthogonal, finite maps only) and
returns a plain Lua table, or `nil, message` on failure (the error is also
logged as `[TmxLoader] ...`). Tile data may be CSV, XML, or base64 with no
compression, zlib or gzip; zstd and infinite maps are rejected. External `.tsx`
tilesets are resolved relative to the `.tmx`, and image paths relative to the
tileset. The path is relative to the game root (`games/<name>/maps/town.tmx`);
see [Asset paths](scene-format.md#asset-paths).

```lua
local map, err = load_tmx("maps/town.tmx")
if not map then error(err) end

map.width, map.height, map.tilewidth, map.tileheight
map.properties.title                 -- int/float/bool/string keep their Lua type
map.tilesets[1].firstgid
map.tilesets[1].tiles[3].type        -- per-tile class/type, properties, animation
map.layers[1].data[i]                -- gids (1-based, row by row), flip flags stripped
map.layers[1].flips[i]               -- only flipped cells: { h=, v=, d= }
map.objects                          -- every object, flattened across object layers
-- object: id, name, type (class), layer, shape, x, y, width, height, rotation,
--         rect = {x, y, w, h} (top-left; tile objects are corrected from
--         Tiled's bottom-left), gid/flip_h/flip_v (tile objects), points, properties
```

Object `shape` is one of `rect`, `ellipse`, `point`, `polygon`, `polyline`,
`text` or `tile`. Polygon and polyline `points` are relative to the object's
`x`, `y`. `type` is the Tiled 1.9+ `class`, falling back to the older `type`
attribute. Object templates are not supported.

`load_tmx_colliders(path, opts?)` turns the solid tiles and the `collision`
object layer of a map into static walls; see [collision.md](collision.md).

---

## What is not here yet

- No entity lifetime — a projectile that never hits anything lives forever.
- Only one scene, hardcoded in `Game::setup()`; there is no scene switching.
