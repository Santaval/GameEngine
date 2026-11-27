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

## Flag layout

| Flag | Meaning |
| --- | --- |
| `mission.<id>.state` | `none`, `offered`, `accepted`, `rejected`, `night_active`, `done` or `failed`. |
| `mission.<id>.<state>` | Derived boolean, `true` only for the current state (absent otherwise). Readable from Tiled `locked` / `enabled`, e.g. `mission.chequelo.rejected`. |
| `mission.<id>.outcome` | Result string passed to `complete(id, outcome)`; cleared when leaving `done`. |
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
- Mission row: Left / Right / `E` cycle the state (via `jump`, no hooks).
- Flag row: Right / `E` toggles a boolean or adds 1, Left toggles a boolean or subtracts 1. Strings are read-only.

Nothing calls `start_night`, `complete` or `fail` yet, so use the overlay to reach
those states.

## Demo walkthrough

1. Town demo, enter Mama's house and talk to her. The first lines play and the mission becomes `offered`.
2. Choose "Mejor no": state `rejected`, `chequelo.ending = stayed_home`; talking again plays the rejected line, not the intro.
3. Open F3, set `chequelo` to `none`, talk and choose "Sí": state `accepted`, `mama.avisada` and `chequelo.accepted` are true.
4. Cycle the states in the overlay; `night_active`, `done` and `failed` give Mama's fallback line.
