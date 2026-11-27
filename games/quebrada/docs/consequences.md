# Consequences of the player's choices (issue #70)

Mission outcomes change the town as data: NPCs comment on an outcome the **next
day**, a door opens or closes through a flag, and an NPC appears in the street.
Nothing here needs new code for a new consequence: it is a data entry, a `locked`
or `enabled` string in Tiled, or both.

## Files

| File | Role |
| --- | --- |
| `scripts/consequences_data.lua` | Data: the comment entries. |
| `scripts/consequences_logic.lua` | Pure logic: picks the comments that apply and validates the entries. |
| `scripts/consequences.lua` | Engine glue: the `day` counter, the derived `next_day` flags, `build_script` and `validate`. |
| `scripts/missions_logic.lua`, `scripts/missions.lua` | Day stamp on every mission state change, and the day conditions. See [missions.md](missions.md). |
| `scripts/dialogue.lua` | `attach()` builds each NPC script with `consequences.build_script`. See [dialogue.md](dialogue.md). |
| `scripts/interaction.lua`, `scripts/interaction_logic.lua` | `figure` property and `draw_figures()`. See [interaction.md](interaction.md). |
| `scripts/town_controller.lua` | Calls `init`, `validate` and `tick`, advances the day with `N`, and shows the day in F3. |
| `maps/town.tmx` | The doors and gates with mission conditions, and the `interactables` layer with the neighbour. |

## The day counter

- The day is the world flag `day`: a number that starts at 1. It is saved with
  `world_state.snapshot()` like any other flag.
- `N` at night turns to day: `consequences.advance_day()` adds 1 and the toast shows
  "Día N". Turning from day to night does not change the day.
- `consequences.init()` runs when the town scene loads and creates `day` if it is missing.
- F3 shows the day in the header ("día N") and as the row `[F] day = N`. Right or `E`
  on that row adds 1.
- A future "sleep" action can call `consequences.advance_day()` too.

## Outcome stamp

Every write of `mission.<id>.state` also writes `mission.<id>.day` with the current
day. This covers the normal transitions (`offer`, `accept`, `reject`, `start_night`,
`complete`, `fail`) and the debug `jump` in F3.

## Derived conditions

`consequences.tick()` runs every frame in the town controller and publishes
`mission.<id>.next_day` = `true` for a mission that has a result (`accepted`,
`rejected`, `night_active`, `done` or `failed`) when the current day is later than the
day of its last change. Otherwise the flag is removed. Tiled uses it as a plain flag.

The Lua conditions (see [missions.md](missions.md#conditions)):

| Condition | True when |
| --- | --- |
| `m.next_day(id)` | The mission has a result and the day is later than its stamp. |
| `m.days_since(id, n?)` | At least `n` days (1 by default) have passed since the last change. |
| `m.same_day(id)` | The last change was today. |
| `m.flag(name, value?)` | The flag is set (no value) or equals `value`. |

Tiled `locked` and `enabled` strings only have AND (`a,!b`). Use the derived
`mission.<id>.next_day` for "the day after".

Conditions read mission state flags, not the flags set by hooks (`chequelo.ending`),
because F3 jumps skip the hooks. See [missions.md](missions.md).

## Comments (`consequences_data.lua`)

```lua
{ id = "vecina_rechazada", who = "vecina",
  when = m.all(m.mission_rejected("chequelo"), manana),
  lines = { { speaker = "Vecina", text = "..." } } },
```

| Field | Meaning |
| --- | --- |
| `id` | Unique name. Also the key of `comment.<id>.seen` when `once` is set. |
| `who` | The value of the `npc` property of the interactable in the TMX. |
| `when` | Condition: a function, a string over flags, or a boolean. Missing means always. |
| `once` | Optional boolean, `false` by default. The comment is shown once. |
| `lines` | Dialogue lines, the same format as `dialogues.lua` (`speaker`, `text`, ...). |

Merge rules:

- Matching entries are **prepended** to the NPC's base script, in the order of the
  data file. The base lines come after them.
- An NPC with no base script gets only the comments. Without any matching entry the
  `line` property of the interactable is used, as before.
- A `once` entry is marked seen (`comment.<id>.seen`) when the script is built, so it
  does not repeat.
- `consequences.validate()` runs at scene init and prints `[consequences] ERROR` for
  an entry without `id`, a repeated `id`, no `who`, a bad `when`, or `lines` empty or
  without `text`. It prints `aviso` for a line without `speaker` and for an entry
  without `when`.

## Doors

A door or gate with `locked` (see [doors-and-zones.md](doors-and-zones.md#lock-syntax))
reads mission flags like any other flag:

- `door_mama`: `locked = mission.chequelo.failed,!mission.chequelo.next_day`. The door
  is closed the day after a failed mission and opens again the next day.
- `door_shed`, `gate_quebrada_n`, `gate_quebrada_e`: `locked = !unlock.zone.quebrada,!mission.chequelo.done`.
  They open through the legend (the flag) or when the mission is done.

Caveat: each door or gate has a single `locked_line`. It is shown whichever condition
locked it. Use one door per message, or keep the line true for every reason.

## Appearing NPC

An NPC is an `interactable` object in the `interactables` layer, with:

- `npc`: the id that the comments use in `who`.
- `enabled`: a condition, for example `mission.chequelo.next_day`. While it is false,
  the NPC is not in the street: no prompt, no interaction and no figure.
- `figure`: `"r,g,b"`, a placeholder figure drawn with `interaction.draw_figures()`.

The neighbour in `town.tmx` is the example (`id="42"`, at `232,212`, free floor).

## How to add a consequence with no code

1. **A comment.** Add an entry to `consequences_data.lua` with `who` (an existing `npc`),
   a `when` built with `m.*` (for example `m.all(m.mission_done("chequelo"), manana)`),
   and `lines`. Use `once = true` for a comment that should appear only once.
2. **A door that changes.** Set `locked` on the door in Tiled with the flags
   `mission.<id>.<state>` or `mission.<id>.next_day`, and `locked_line` for its message.
3. **An NPC that appears.** Add an `interactable` in the `interactables` layer with `npc`,
   `line`, `enabled` (for example `mission.<id>.next_day`) and `figure`. If it has comments,
   add entries with the same `who`.
4. Change the code only for a new kind of condition (`consequences_logic.lua` or
   `missions.lua`).

## Demo walkthrough

1. Talk to Mamá and choose "Mejor no": `chequelo` is `rejected`. The neighbour does not appear that day.
2. Press `N` twice (night, then day): the toast shows "Día 2". The neighbour appears
   (purple figure at the bottom of the square). Talk to her: `vecina_rechazada`.
3. Talk to Mamá: `mama_rechazada_manana` plays once, then her usual lines.
4. Open F3 and set `chequelo` to `accepted`: the neighbour disappears (the stamp is today).
   Raise `day` with Right: she returns with `vecina_aceptada`.
5. Set `failed` in F3: `door_mama` is locked with its message. Raise `day`: it opens.
6. Set `done`: `door_shed` and the quebrada gates open.

## Caveats

- F3 cannot set outcome strings, so `vecina_cafetal` (`detour_cafetal`) is not reachable
  from the overlay. In `zona1` it is reachable by playing: walk into the cafetal gap during the
  night and then to mama's door (`complete("chequelo", "detour_cafetal")`, see [zona1.md](zona1.md)).
- The NPC `who` is not checked against the TMX at run time. A misspelt `who` is silent.
- Mamá's story (`story="chequelo"`) takes `E` until it has been heard. Her day comment
  follows the story, not before it.
- An old save has no `mission.<id>.day` stamp: `next_day` stays false until the mission
  changes state again. A missing `day` flag is restored by `consequences.init()`.
- Re-deciding a mission restarts "the next day" from the latest change.
