# Engine Documentation

A 2D game engine built on SDL2, with an ECS core in C++ and gameplay written
entirely in Lua.

| Document | What's in it |
| --- | --- |
| [lua-api.md](lua-api.md) | Every function the engine exposes to Lua. |
| [scene-format.md](scene-format.md) | The `scene` table: assets, input mappings, entities and every component. |
| [health-and-damage.md](health-and-damage.md) | Hit points, contact damage, invulnerability and death hooks. |
| [equipment.md](equipment.md) | Named upgrade levels tracked per entity. |
| [inventory.md](inventory.md) | Named item quantities, an optional capacity, and the mineral pickup gameplay. |
| [gravity.md](gravity.md) | Mass-based attraction between planets, ship, asteroids and bullets. |
| [asteroid-spawner.md](asteroid-spawner.md) | Generators outside the map that keep spawning asteroids at random intervals. |
| [multiplayer-protocol.md](multiplayer-protocol.md) | Wire protocol and ownership rules for the relay server and multiplayer clients. |

---

## Building and running

```sh
make        # builds ./engine
make run    # ./engine
make deps   # fetches IXWebSocket + nlohmann/json (make build does it automatically)
make test   # unit test for NetworkRegistry (ECS only, no SDL)
make clean
make clean-deps   # forces IXWebSocket to be rebuilt
```

Needs `libsdl2-dev`, `libsdl2-image-dev`, `libsdl2-ttf-dev`, `zlib1g-dev`, `libssl-dev` and a
Lua dev package (`liblua5.3-dev` or 5.4). GLM, sol2 and the Lua headers are
vendored in `libs/`. IXWebSocket and nlohmann/json are not committed:
`scripts/fetch-deps.sh` downloads pinned versions into `libs/` (needs `curl`),
and IXWebSocket is compiled once, with TLS via OpenSSL, into
`libs/IXWebSocket/libixwebsocket-tls.a`.

Multiplayer is opt-in: `./engine --server ws://host:7777` (or the `GAME_SERVER`
environment variable). Use `wss://` for servers behind HTTPS, e.g.
`./engine --server wss://<app>.up.railway.app`. Without it the engine runs offline and prints nothing
from the network layer. See [multiplayer-protocol.md](multiplayer-protocol.md).

Paths in scene files are relative to the working directory, so run the binary
from the repository root.

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
5. **AnimationSystem** — advances spritesheet frames.
6. **GravitySystem** — adds the pull of every attractor to the velocity of
   every affected body (see [gravity.md](gravity.md)).
7. **MovementSystem** — integrates acceleration into velocity into position.
8. **CollisionSystem** — circle-vs-circle over every collider pair, emitting a
   collision event for each overlap. **DamageSystem** reacts to those events
   immediately.

Then `Game::render()` draws, back to front:

1. **RenderSystem** — sprites.
2. **PathRenderSystem** — predicted trajectories.
3. **ColliderRenderSystem** — the hitbox overlay, skipped entirely when off.
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
| `AnimationComponent` | Spritesheet playback. | `animation` |
| `CircleColliderComponent` | Collision circle plus an owner exclusion. | `circle_collider` |
| `HealthComponent` | Hit points and invulnerability window. | `health` |
| `DamageComponent` | Contact damage dealt. | `damage` |
| `GravityComponent` | Mass, plus whether it attracts and/or is attracted. | `gravity` |
| `EquipmentComponent` | Named upgrade levels (engine, gun, shield, ...). | `equipment` |
| `InventoryComponent` | Named item quantities plus an optional total capacity. | `inventory` |
| `TextComponent` | A label pinned to the entity. | `text` |
| `PathComponent` | Trajectory prediction toggle. | `path` |
| `NetworkComponent` | Network identity (`netId`) and owner (`ownerId`); set via `NetworkRegistry`. | none yet |
| `ScriptComponent` | `update`, `on_damage`, `on_death`, `on_collision`. | `script` |

---

## Two engine quirks worth knowing up front

**System membership is decided once.** An entity is matched against every
system's signature exactly once, when it is first flushed into the registry.
Adding a component to an entity that is already alive will not enrol it in a
new system. In practice: give an entity its `transform`, `sprite`,
`rigid_body` and `circle_collider` in the same frame you create it.

Components that only get read on demand — `health`, `damage`, `path` — are
exempt, because the systems that use them either are event-driven or filter
inside their loop instead of through the signature.

**Death is deferred.** `kill()` queues the entity; it is actually removed at
the start of the next frame. Until then it still shows up in collision checks.

---

## What is not here yet

- No entity lifetime — a projectile that never hits anything lives forever.
- Collision detection is O(n²) over every collider, every frame. This is the
  first thing that will limit scene size.
- Only one scene, hardcoded in `Game::setup()`; there is no scene switching.
