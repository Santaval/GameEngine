# Doors, interiors and zones (issue #62)

Quebrada maps describe doors, spawn points and zones as Tiled **object layers**.
`scripts/town_controller.lua` polls them every frame with the player's foot box
(the engine has no static trigger rects), fades to black, and either teleports
inside the map or loads another scene.

Modules:

| File | Role |
| --- | --- |
| `scripts/door_logic.lua` | Pure logic (conditions, rects, spawns, facing, fade state machine). Tested without the engine: `games/quebrada/tests/door_logic.lua`. |
| `scripts/world_state.lua` | Minimal flag store plus transition context, compatible with the flags planned in #51. |
| `scripts/fade.lua` | Black fade drawn with `draw_rect`. |
| `scripts/town_controller.lua` | Per-scene controller: loads the TMX, places the player, handles prompts, zones and transitions. |
| `scripts/town_player.lua`, `scripts/house_player.lua` | Player scripts: the walker from #61 plus the `player_entity` / `player_walker` globals. |

## Tiled conventions

Use object layers only; tile layers are not needed. Spawn points mark the
**center of the player's foot box** (the controller converts it to the sprite
top-left).

| Object | Shape | Class | Layer | Properties |
| --- | --- | --- | --- | --- |
| Door | rect | `door` | `doors` | `target_map` (string; empty/absent = same map, `"@return"` = the map we came from), `target_spawn` (spawn name, or `"@return"`), `locked` (see below), `locked_line` (default "Está cerrado."), `prompt` (default "E: entrar"), `exit_spawn` (spawn name in the **outer** map where the player re-emerges after leaving the interior entered through this door) |
| Spawn | point (`<point/>`) | `spawn` | `spawns` | `name`; optional string `facing` (`up`/`down`/`left`/`right`) |
| Zone | rect | `zone` | `zones` | `zone` (id), `title` (toast text), optional `ambience` (stored only; ambience is not played from the zone, use an emitter object instead), optional `save` (bool, informational) |
| Emitter | rect or point | `emitter` | `emitters` | `sound` (required), `radius` / `max_distance`, `min_distance`, `volume`, `loop` (default true), `rolloff`; started by `emitters_from_map(map)`, see [Spatial audio](../../../engine/docs/lua-api.md#spatial-audio) |
| Wall | rect | any | `collision` | read by `load_tmx_colliders` |

Rules:

- If a spawn has no `facing`, the player faces away from the door: the dominant
  axis from the door center to the spawn, vertical on a tie. This only works
  inside one map; spawns reached from another map (interior arrivals) need an
  explicit `facing`.
- Nested zones: the smallest area wins. The zone edge is half-open (the right and
  bottom edges are outside).
- Place exit spawns a few px outside the door rect. After arriving, the controller
  ignores interaction until the foot box has left every door rect once.

## Lock syntax

`locked` is a condition that, when **true**, means the door is locked.

- `flag` : locked while the flag is set.
- `!flag` : locked while the flag is **not** set, for example
  `!house.chayo.open` (locked until the flag is set).
- `a,!b` : comma list = AND.
- Empty or absent: never locked.

Flags are read at the moment they are needed (every frame for the prompt, at
interaction time for the door), never cached, so a door opens as soon as the flag
changes. A locked door shows `locked_line` for 2 seconds and starts no fade.

## Transition flow

1. Interact (`E` or `Enter`, edge-triggered) while the foot box overlaps a door.
2. Player input is blocked; the screen fades out (0.3 s, 0.05 s hold at black).
3. Same map (`target_map` empty or equal to this map): teleport to `target_spawn`,
   reset the camera, fade in.
4. Another map: the controller stores the context in `world_state.ctx()`
   (`arrival`, `return_map`, `return_spawn` from `exit_spawn`, `return_facing`)
   and calls `load_scene` with the scene registered for that map in the
   controller config (`scenes = { ["maps/x.tmx"] = "scenes/x.lua" }`). The next
   scene starts black, places the player at the arrival spawn and fades in.
5. `@return` on an interior door reads `return_map` / `return_spawn` from the
   context, so the player comes back to the exit spawn of the door they entered,
   facing away from it.

`load_scene` is deferred, so the black frame is held until the new scene starts.
The zone toast appears when the current zone id changes, including on arrival at a
new map, but not when re-entering the same zone.

## Persistence model

`load_scene` unloads modules loaded with `require` but **Lua globals survive**.
`world_state` is therefore a global table (`world_state = world_state or {...}`);
the module is re-run in every scene and reuses the table. The flags and the
transition context live only in memory: there is no save file yet. Listeners
registered with `world_state.on_change` are closures of the scene that created
them; call `world_state.clear_listeners()` at the start of each scene (the
controller does).

## Demo

In the main scene press `6` to open the demo (`scenes/town_demo.lua`).

| Key | Action |
| --- | --- |
| WASD / arrows, Shift | Walk, run |
| `E` / `Enter` | Interact with the door under your feet |
| `F` | Toggle the flag `house.chayo.open` (debug) |
| `0` | Back to the main scene |

- Mama's door (`maps/house_mama.tmx`): enter, leave through the bottom door and
  land outside facing away from it.
- Ña Chayo's door is locked until you press `F`.
- The shed door teleports inside the same map (`shed_out`).
- Zones: "Barrio Alto" (north) and "La Plaza" (south) show a toast when crossed.
