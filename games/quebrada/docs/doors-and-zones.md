# Doors, interiors and zones (issue #62)

Quebrada maps describe doors, spawn points and zones as Tiled **object layers**.
`scripts/town_controller.lua` polls them every frame with the player's foot box
(the engine has no static trigger rects), fades to black, and either teleports
inside the map or loads another scene.

Modules:

| File | Role |
| --- | --- |
| `scripts/door_logic.lua` | Pure logic (conditions, rects, spawns, facing, fade state machine). Tested without the engine: `games/quebrada/tests/door_logic.lua`. |
| `scripts/world_state.lua` | Flag store plus transition context. Also `add(name, n)`, `snapshot()` and `restore(t)` (save hooks, see Persistence model). |
| `scripts/missions_logic.lua`, `scripts/missions.lua`, `scripts/mission_defs.lua` | Mission state machine on top of the flags: pure logic, engine glue and data. See [missions.md](missions.md). |
| `scripts/leads_logic.lua`, `scripts/leads.lua` | Word-of-mouth lead graph, markers and gates (issue #69): pure logic and engine glue. See [leads.md](leads.md). |
| `scripts/fade.lua` | Black fade drawn with `draw_rect`. |
| `scripts/town_controller.lua` | Per-scene controller: loads the TMX, places the player, handles prompts, zones and transitions. |
| `scripts/town_player.lua`, `scripts/house_player.lua` | Player scripts: the walker from #61 plus the `player_entity` / `player_walker` globals. |

## Tiled conventions

Object layers are enough (`town.tmx` has no tile layers), but tile layers are now allowed too: with
`tile_map = true` the controller draws them and `solid` tiles collide (see [tileset.md](tileset.md)). A tile
`surface` wins over `surface` rects (see [audio.md](audio.md#surfaces)). Spawn points mark the
**center of the player's foot box** (the controller converts it to the sprite
top-left).

| Object | Shape | Class | Layer | Properties |
| --- | --- | --- | --- | --- |
| Door | rect | `door` | `doors` | `target_map` (string; empty/absent = same map, `"@return"` = the map we came from), `target_spawn` (spawn name, or `"@return"`), `locked` (see below), `locked_line` (default "Está cerrado."), `prompt` (default "E: entrar"), `exit_spawn` (spawn name in the **outer** map where the player re-emerges after leaving the interior entered through this door) |
| Spawn | point (`<point/>`) | `spawn` | `spawns` | `name`; optional string `facing` (`up`/`down`/`left`/`right`) |
| Zone | rect | `zone` | `zones` | `zone` (id), `title` (toast text), optional `ambience` (ambience set key: pueblo, monte, quebrada, casa, ...; fed to `scripts/ambience.lua` by the map controller, see [audio.md](audio.md)), optional `save` (bool, informational) |
| Gate | rect | `gate` | `gates` | `locked` (same syntax as doors), `locked_line`, optional `lead`. Not a collider: while locked, the controller returns the player to the last free position. Keep it at least 12 px thick. See [leads.md](leads.md) |
| Lead marker | any | `door`, `gate` or `marker` | any | `lead` (`house.<id>` or `zone.<id>`): shows a small bobbing dot while `lead.mark.<key>` is set and `lead.seen.<key>` is not. See [leads.md](leads.md) |
| Surface | rect | `surface` | `surfaces` | `surface` (lastre, zacate, madera or concreto); decides the footstep sound, see [audio.md](audio.md). The map property `surface` is the default for cells without a surface |
| Emitter | rect or point | `emitter` | `emitters` | `sound` (required), `radius` / `max_distance`, `min_distance`, `volume`, `loop` (default true), `rolloff`, plus `only` (time of day), `when` (flag condition) and `interval` (seconds between one-shots, instead of a loop) when played by `scripts/emitters.lua` (the town controller); `emitters_from_map(map)` ignores those three, see [Spatial audio](../../../engine/docs/lua-api.md#spatial-audio) |
| Trigger | rect | `trigger` | `triggers` | `trigger` (id; not `id`), `mission`, `requires` (door-lock syntax, empty = true), `sets` (flags set on enter), `line`. Fires once per stay while the mission is `accepted` or `night_active`; run by `scripts/triggers.lua`, see [zona1.md](zona1.md) |
| Edge | rect | `edge` | `edges` | `edge` (id), `connects_to` (empty for now). Marker for future map connections; nothing reads it yet. Each has a spawn `edge_<id>` |
| Route | point | `route` | `route` | `route_00`..`route_NN`: the intended walk (documentation and tests), not read by the game |
| Interactable | rect or point | `interactable` | `interactables` | `npc` (NPC id) or `interact` (`npc` or `object`; `door` is not supported here), `label`, `target`, `radius` (default 24), `line`, `set_flag`, `enabled` (condition syntax `a`, `!a`, `a,!b`); see [interaction.md](interaction.md) |
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
- An overlapped door suppresses interactables: while the foot box is inside a
  door rect, no interactable prompt or press is handled (see
  [interaction.md](interaction.md#doors-take-precedence)).

## Lock syntax

`locked` is a condition that, when **true**, means the door is locked.

- `flag` : locked while the flag is set.
- `!flag` : locked while the flag is **not** set, for example
  `!unlock.house.chayo` (locked until the flag is set).
- `a,!b` : comma list = AND.
- Empty or absent: never locked.
- Mission flags work the same way (issue #70): the derived flags `mission.<id>.<state>`
  and `mission.<id>.next_day` can be used. Examples from `maps/town.tmx`:
  `door_mama` has `locked = mission.chequelo.failed,!mission.chequelo.next_day` (locked
  the day after a failed mission it opens again on the next day), and `door_shed` and
  the quebrada gates have `locked = !unlock.zone.quebrada,!mission.chequelo.done`
  (open through the legend or through the mission). See [consequences.md](consequences.md).
- Each door or gate has a single `locked_line`; it is shown whatever condition locked it.

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

`world_state.snapshot()` returns a pure copy of the persistable flags (booleans,
numbers and strings; the transient `dialogue.open` and `libreta.open` flags and the
transition context are excluded). `world_state.restore(t)` replaces them, going
through `set` so listeners are notified. These are the hooks a save system uses;
no file is written yet.

## Demo

In the main scene press `6` to open the demo (`scenes/town_demo.lua`).

| Key | Action |
| --- | --- |
| WASD / arrows, Shift | Walk, run |
| `E` / `Enter` | Interact with the door under your feet |
| `F` | Toggle the flag `unlock.house.chayo` (debug) |
| `N` | Toggle day / night (ambience, see [audio.md](audio.md)); night to day advances the day counter (see [consequences.md](consequences.md)) |
| `F3` | Debug overlay of flags and missions (see [missions.md](missions.md)) |
| `0` | Back to the main scene |

- Mama's door (`maps/house_mama.tmx`): enter, leave through the bottom door and
  land outside facing away from it.
- Ña Chayo's door is locked until Mama's story lead resolves (accept or reject the mission) or you press `F`.
- The quebrada gates and the shed door stay locked until Chayo's lead resolves, which happens the first time you enter her house.
- The shed door teleports inside the same map (`shed_out`).
- Zones: "Barrio Alto" (north) and "La Plaza" (south) show a toast when crossed.

## `only` (issue #66)

`door` and `gate` objects accept `only = "day" | "night" | "dusk,night"...`: outside those
phases the object does not exist (no prompt, no blocking). See `time-of-day.md`.

## Roofs and house maps (issue #71)

A building's roof is faded by `class = "roof"` rects (layer `roofs`), not by doors or zones: see [buildings.md](buildings.md).
`maps/house_mama.tmx` is now generated by `tools/tilegen`, and any exterior map with a door to it must be listed in
`scripts/house_scene.lua` so that `@return` finds its scene.

## Casa de Abuela Paula y Abuelo Pepe

`door_paula` (zona 1, below the porch steps of the wooden house across from mama's) is a plain door: `target_map = maps/house_paula.tmx`, `target_spawn = inside_door`, `exit_spawn = exit_paula`, no `locked`. The interior's `door_out` returns with `@return`.
Its scene (`scenes/house_paula.lua`) lists zona1 and itself in `scenes` (`scripts/house_paula_scene.lua`); zona1's controller (`zona1_scene.lua`) lists the Paula scene.
