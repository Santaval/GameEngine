# Missions and world flags (issue #51)

Missions are a small state machine stored entirely in `world_state` flags, so the
state survives scene changes and is covered by `world_state.snapshot()`. Code:
`scripts/missions_logic.lua` (pure logic), `scripts/missions.lua` (glue),
`scripts/mission_defs.lua` (data and hooks).

## States

```
none --offer--> offered --accept--> accepted --start_night--> night_active --complete--> done
                   |                    |                          |
                   +--reject--> rejected +----------fail-----------+--> failed
```

`rejected` is terminal. `offer` is idempotent: it does nothing unless the state
is `none`. Invalid transitions log a message and return `false, err`.

Chequelo (issue #82): `accept` only sets `chequelo.accepted` (the hook does not change the
time of day). The night starts when the player reaches the church door: `walk_start` in
`zona1` calls `start_night`. Accepting and rejecting both autosave (see
[save.md](save.md)); the glue for the day lives in `scripts/chequelo_day.lua`.

## Flag layout

| Flag | Meaning |
| --- | --- |
| `mission.<id>.state` | `none`, `offered`, `accepted`, `rejected`, `night_active`, `done` or `failed`. |
| `mission.<id>.<state>` | Derived boolean, `true` only for the current state (absent otherwise). Readable from Tiled `locked` / `enabled`, e.g. `mission.chequelo.rejected`. |
| `mission.<id>.outcome` | Result string passed to `complete(id, outcome)`; cleared when leaving `done`. |
| `mission.<id>.day` | Day (the `day` flag) when the state last changed. Every state write stamps it, including `jump`. See [consequences.md](consequences.md). |
| `mission.<id>.next_day` | Derived by `consequences.tick()`: `true` when the mission has a result (`accepted`, `rejected`, `night_active`, `done` or `failed`) and the current day is later than `mission.<id>.day`. Absent otherwise. Readable from Tiled. |
| `day` | Current day, a number that starts at 1. Not a mission flag: the night-to-day toggle (`N`) advances it. |
| `chequelo.accepted`, `chequelo.ending` | Content flags written by the hooks in `mission_defs.lua` (`stayed_home`, `failed`, or the outcome). |

## Hooks

A definition in `mission_defs.lua` may have `on_offer`, `on_accept`, `on_reject`,
`on_start_night`, `on_complete(id, outcome)` and `on_fail`. They run after the
state is written; an erroring hook is logged and ignored. Definitions are data and
are reloaded with every scene.

## API (`require("missions")`)

- `offer(id)`, `accept(id)`, `reject(id)`, `start_night(id)`, `complete(id, outcome?)`, `fail(id)`
- `jump(id, state, outcome?)`: debug only. Forces a state, skips the transition table and does NOT run hooks.
- `state(id)`: current state (`"none"` if never offered).
- `ids()`: sorted ids from the definitions and from stored `mission.<id>.state` flags.
- `define(id, def)`: adds or replaces a definition at runtime.

## Conditions

Helpers return a `function() -> bool` that is evaluated at the moment of use:
`flag(name)`, `not_flag(name)`, `mission_is(id, ...)`, `mission_accepted(id)`
(accepted, night_active, done or failed), `mission_rejected(id)`, `mission_failed(id)`,
`mission_done(id, outcome?)`, and the combinators `all(...)`, `any(...)`, `not_(f)`.
Day conditions (issue #70): `next_day(id)` (has a result and it is a later day),
`days_since(id, n?)` (at least `n` days, 1 by default, since the last state change),
`same_day(id)` (the last state change was today). `flag(name, value?)` without a value
is "flag set"; with a value it is "flag equals that value", for example
`flag("chequelo.ending", "stayed_home")`.
`check(when)` evaluates a `when` value: `nil` is true, a boolean, a function, or a
string `"a,!b"` over world flags (same syntax as door locks).

## Save hooks

`world_state.snapshot()` returns a pure table of the persistable flags (only
booleans, numbers and strings; the transient `dialogue.open`, `libreta.open` and
`story.open` flags and the transition context are excluded). `world_state.restore(t)` replaces
them and notifies listeners. `world_state.add(name, n?)` increments a counter and
`set(name, nil)` clears a flag. No file is written yet.

## F3 debug overlay

Press `F3` in a scene that declares the `debug_overlay` key (SDL 1073741884); the
town controller option `debug_overlay` (default true) enables it. It cannot open
during a transition, a dialogue, a fade or before the player is placed; it can
always be closed. While open it locks the player input, doors, interactions, `F`
and `0`, and hides the toast, line and prompt texts.

- Up / Down: move the selection.
- Mission row: Left / Right / `E` cycle the state (via `jump`, no hooks). `jump` also stamps `mission.<id>.day` with the current day.
- Flag row: Right / `E` toggles a boolean or adds 1, Left toggles a boolean or subtracts 1. Strings are read-only.

In `zona1` (issue #78) the triggers call `start_night` and `complete` for `chequelo` (see
[zona1.md](zona1.md)): `walk_start` at the church door (needs `accepted`) and `house_arrival` at
mama's door (needs `night_active`, completes with the first detour taken or `done`). `fail` is still
unused, and in any other map use the overlay to reach those states.

## Leads

`leads.tick` (see [leads.md](leads.md)) reads the state of a legend's `mission_offer`
mission. When it leaves `none` and `offered` (accepted or rejected), the legend's lead
resolves, even if the story never reaches its closing lines.

## Demo walkthrough

1. By day, enter Mama's house: she greets you once (`mama.saludada`). Talk to her (`Hablar`) for the offer, which makes the mission `offered`. `Escuchar la historia` plays the recording.
2. Choose "Mejor no": state `rejected`, `chequelo.ending = stayed_home`; talking again plays the rejected line, not the intro.
3. Open F3, set `chequelo` to `none`, talk and choose "Sí": state `accepted`, `mama.avisada` and `chequelo.accepted` are true, the screen fades to the church and the night starts when you reach its door.
4. Cycle the states in the overlay; `night_active`, `done` and `failed` give Mama's fallback line.

## Inicio de la partida (refinado)

La partida nueva arranca en la casa de mamá (`scripts/new_game.lua`, entidad de `scenes/main.lua`; no actúa con partida cargada ni con el atajo `z`). Flujo (`scripts/chequelo_day.lua`):

1. Mamá: "Mijo, ya alístate que tienes que ir a misa." (`on_start` de la casa).
2. Una flecha "v" parpadea sobre la puerta de salida.
3. Al usar la puerta (`cfg.on_door` del controlador) mamá avisa de la luz y pregunta si quieres oír la historia. Si dices sí, suena la grabación (con su saludo y cierre).
4. Sin preguntar por la misión: bendición, la misión se ofrece y acepta sola (`mama.avisada`, `intro.bendecido`), se guarda y fundido a la puerta de la iglesia, donde `walk_start` empieza la noche.

Ya no hay rechazo en este flujo; `on_reject` y los textos de "quedarse en casa" quedan por si se reutilizan.
