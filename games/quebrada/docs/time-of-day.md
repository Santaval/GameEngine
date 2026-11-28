# Time of day (issue #66)

Story-driven, **not** a running clock. Phases: `day` → `dusk` → `night` → `dawn` → `day`.
Missions, the bed and the debug key `N` change it. Code: `scripts/time_of_day.lua` (glue)
and `scripts/time_of_day_logic.lua` (pure, tested by `tests/time_of_day_logic.lua`).

## API (`require("time_of_day")`)

| Function | Description |
| --- | --- |
| `get()` / `base()` | Current phase / coarse time (`"day"` for day+dusk, `"night"` for night+dawn). |
| `set(phase, opts)` | Moves to `phase`. `opts.title` shows a title card ("Esa noche..."), `opts.instant` skips the transition, `opts.advance_day = false` does not add a day when reaching `day` from night. |
| `toggle()` | Day-ish → night, night-ish → day (key `N`). |
| `sleep()` | Only at night: goes to `day` with the "Amanece..." card. Returns `true` if it slept. |
| `visible(props_or_only)` | Whether an object with that `only` is visible now. |
| `is_busy()` | `true` while the title card is on screen (doors, interaction and clues are paused; the player can still walk). |

`set` applies the new phase at once (flags, `only` objects, ambience crossfade, lights) and fades the
ambient colour over 4 s, covered by the title card. Calling it with the current phase does nothing.
Colours: day `255,255,255`, dusk `150,120,130`, night `6,8,18`, dawn `70,70,100`.
Entering `day` from night/dawn calls `consequences.advance_day()` (day counter).
The state is a global (`time_state`) so it survives scene changes; `init(map)` reapplies it
instantly on every scene load.

## Tiled: `only`

Any object may have `only = "night"`, `"day"`, `"dusk,night"`... (comma list). It is
visible if the list contains the current phase **or** the coarse time (`night` also matches
`dawn`, `day` also matches `dusk`). No `only` = always visible. Honoured by: `interactable`
(NPCs, objects), `door`, `gate`, `light`, and the debug drawing of `collision` rects.
(Colliders themselves are not toggled.)

## Lights

Objects of class `light` (`radius`, `r`, `g`, `b`, `intensity`, `flicker`, `only`) are created by
`time_of_day.init(map)` and fade in/out (1.5 s) when the phase changes. Street posts and
windows in `town.tmx` use `only = "dusk,night"`.

## Flags (world_state)

`time` (phase), `time.day`, `time.dusk`, `time.night`, `time.dawn`. `time.day`/`time.night` are
the coarse time. Usable in Tiled `locked`/`enabled` strings (e.g. `locked = "time.day"`).

## Missions

`mission_defs.lua`: `chequelo` sets night on `on_accept` (and on `on_start_night`) and day on
`on_complete`/`on_fail`. Only the `zona1` triggers call `start_night`/`complete` (issue #78, [zona1.md](zona1.md)); elsewhere,
after accepting it stays night until you sleep in the bed (or press `N`).
Clues in `legends/*.lua` can use `time = "dawn"` or `"dusk"` as well as `"day"`/`"night"`.

## Sleeping

An interactable with `sleep = true` (`cama` in `house_mama.tmx`) calls `time_of_day.sleep()`.

## Manual checklist

- `N`: fades through dusk to night, lamps turn on, `don_lencho` disappears and `sereno`
  appears, the east gate opens; `N` again: dawn, then day, "Día N".
- In the house, the bed at night: "Amanece..." card and a new day. By day: "Todavía no tengo sueño".
