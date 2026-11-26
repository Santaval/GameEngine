# Collision: boxes, static walls and triggers

Besides circles (see [lua-api.md](lua-api.md#colliders)), the engine has
axis-aligned **boxes** and **static walls**. The physics core is header-only in
`engine/src/Physics/` (no SDL, ECS or Lua), so it is unit-tested by
`engine/tests/PhysicsTest.cpp`.

## The pieces

| Piece | What it is |
| --- | --- |
| `circle_collider` | Unchanged. Circle-vs-circle events only, exactly as before. |
| `box_collider` | An entity's axis-aligned box. Can be solid, a trigger, a mover, or none of these (a plain hitbox). |
| Static walls | Rectangles stored in `Game::staticWorld`, not entities. Block movers, never emit events. Cleared on every scene load. |
| Triggers | A box with `trigger = true`: enter / stay / exit hooks. |

Box geometry: `x = position.x + offset_x * scale.x`, `width * scale.x` (same for
y). Rotation is ignored. A negative scale is normalised.

## Flag combinations

| `solid` | `trigger` | `mover` | Behaviour |
| --- | --- | --- | --- |
| no | no | no | Plain hitbox: emits `CollisionEvent` (so `on_collision` and `DamageComponent` work) against circles and other non-trigger boxes. |
| yes | no | no | Wall entity: blocks movers, and also emits `CollisionEvent` on real overlap. |
| any | no | yes | Mover: moved by `BoxColliderSystem` with a sweep against static walls and solid non-mover boxes. Velocity into a wall is zeroed. |
| any | yes | no | Trigger zone. `solid` is ignored (the loader warns). |
| any | yes | yes | Moving trigger: integrated normally by `MovementSystem`, blocked by nothing. |
| - | - | - | `enabled = false` (runtime only): the box does not exist for anyone. |

Trigger-vs-trigger pairs are ignored. A trigger against a circle or a
non-trigger box produces trigger events, not `CollisionEvent`. `owner` skips the
pair with that entity, as for circles.

## Movement: exact sweep

Each frame, after `MovementSystem` updated velocities, `BoxColliderSystem` moves
every mover by `velocity * dt`:

1. **Depenetrate**: if the box starts inside a solid (teleport, a network
   correction), push it out along the least-penetration axis (up to 4 passes).
2. **Sweep X** against every solid in the whole swept region, clamping to the
   nearest wall; then **sweep Y** from the new X.

The sweep covers the entire path, so nothing can be tunnelled at any speed or
frame time, and a diagonal move slides along a wall. Boxes that are flush, or
overlap by less than `SKIN` (0.01 px), do not count as overlapping, so resting
against a wall is stable and a seam between two aligned wall rects does not
snag. Contacts are only reported on a move that was actually blocked
(`get_wall_contacts`): a mover with zero velocity touching a wall reports none.

Dynamic-vs-dynamic blocking is out of scope: two movers pass through each other
(they still raise `CollisionEvent`s). In multiplayer, a remote mover pulled by
`NetSyncSystem` can briefly end up inside a wall; depenetration fixes it on the
next frame.

## Triggers

Each frame the set of overlapping (trigger, other) pairs is compared with the
previous frame's. Events are emitted after all pairs are tested, in a fixed
order: all **exits**, then all **enters**, then all **stays**; inside each group
sorted by entity id. Each hook runs on both entities with `this` = the entity
owning the hook and `other` = the one it touched.

- An entity that goes **dormant** (outside the active area), is disabled, or
  loses its box produces an **exit**.
- An entity that is **killed** produces **no exit** and its pairs are dropped
  silently. Use `on_death` to clean up.
- A scene load forgets every pair.
- Triggers only detect entities, never static walls (there are no trigger vs
  static-rect events). A static wall is only felt by movers.

## Tiled maps

`load_tmx_colliders(path, opts?)` fills the static world from a `.tmx`:

- **Solid tiles**: a tileset tile with the bool property `solid = true`, or any
  non-empty tile on a tile layer with the bool layer property `solid = true`.
  A layer with `solid = false` is skipped. `opts.tile_layers` restricts which
  layers are read (by name); the solidity rule is the same.
- **Merging**: horizontal runs per row are merged, then identical runs on
  consecutive rows, so a 3x2 block is one rect.
- **Object layer** named `collision` (`opts.object_layer` to change, `""` to
  disable): rectangles and tile objects become walls. Ellipses use their bounding
  box (with a warning). Polygons, polylines and rotated objects are skipped with
  a warning. An object with `solid = false` is skipped. Points and text are
  ignored.
- Layer and group offsets are applied. `opts.x`, `opts.y` is where the map's
  origin sits in the world and `opts.scale` multiplies everything.
- Only orthogonal, finite maps (the same as `load_tmx`).

Returns the number of rects added, or `nil, message`.

```lua
local n, err = load_tmx_colliders("maps/town.tmx", { scale = 2 })
if not n then error(err) end

local player = create_entity()
-- ... transform, rigid_body, sprite ...
add_box_collider(player, 16, 16, { solid = true, mover = true, y = 16 })

local door = create_entity()
-- ... transform ...
add_box_collider(door, 32, 8, { trigger = true })
set_on_trigger_enter(door, function(other) print("entered", other) end)
```
