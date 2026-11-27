# Ambience and footsteps by surface (issue #65)

Day/night ambience layers for the town and houses, and footsteps that change with
the surface under the player. Everything is Lua in `games/quebrada/scripts/`; the
engine is not changed.

## Modules

| File | Role |
| --- | --- |
| `ambience_logic.lua` | Pure logic: sets per zone and time, crossfade, one-shot scheduler. No engine calls; the random generator is injected. |
| `ambience.lua` | Engine glue. Keeps its state in the global `ambience_state`, which survives scene loads. |
| `surface_logic.lua` | Pure logic: surface lookup from the map, step sound choice and volume. |
| `footsteps.lua` | Engine glue for the walker callback `on_state(entity, moving, running)`. |

The map controller (`town_controller.lua`) drives all of it: it calls
`footsteps.set_source(surface_logic.build(map))` on load, `ambience.set_zone(...)`
every frame, `ambience.tick(dt)` every frame, and `ambience.set_time(...)` on key N.

## Time of day

- `ambience_state.time` is `"day"` or `"night"`. `ambience.set_time(t)` is the only
  way to change it; `ambience.get_time()` reads it.
- Key `N` toggles it in the town and house scenes (`toggle_time` in the scene's
  `keys`).
- Ambience only reads the time. `time_of_day.lua` (see `time-of-day.md`) is the only
  caller of `set_time`: it passes the coarse time (`day`/`night`) of the current phase.
  Lighting and objects follow the same phase.

## Ambience sets

`ambience_logic.SETS[key][time] = { loop, volume, oneshots }`.

- `loop` is the sound id of the looping layer. `volume` is its base volume.
- `oneshots` is `{ min, max, sounds }` or absent. `min` and `max` are the seconds
  between one-shots; each sound is `{ id, volume }`.
- The key comes from the zone property `ambience` in the TMX. Example:
  `<property name="ambience" value="pueblo"/>`.
- A zone with no `ambience`, or an unknown key, keeps the previous set. Nested zones
  work like the zone toast: the smallest zone wins (see
  [doors-and-zones.md](doors-and-zones.md)).
- Sets in use: `pueblo`, `monte`, `quebrada` (town), `casa` (house). `cafetal` and
  `eolicas` are defined but no map uses them yet.

## Crossfade

- Changing the set (or the time) fades the old loop out and the new one in over
  `ambience_logic.FADE_TIME` (3 s).
- The curve is equal-power (`sin(level * pi / 2) * volume`), so the level stays even
  while the layers overlap.
- Each layer moves on its own. Changing the target in the middle of a fade does not
  jump: the new layer starts from its current level.
- Loops are played with `play_sound(id, { loop = true, bus = "ambience" })` and start
  at volume 0.

## One-shots

- Every `min..max` seconds (random) one sound is picked, never the same one twice in
  a row.
- It plays at a random point 120 to 300 px away from the player
  (`ambience_logic.SPAWN_MIN` / `SPAWN_MAX`), using `play_sound_at` with
  `min_dist = 96`, `max_dist = 500` and bus `ambience`.
- No player entity (for example between scenes) means no one-shots.

## Surfaces

The surface under the foot box center is found in this order. The first hit wins:

1. Tile layers with a `surface` tile property (the top-most layer that has a tile
   there). The town map has none yet; this is for tilesets such as #55.
2. Objects of class `surface` (rect, property `surface`) in an object layer named
   `surfaces`. With overlapping rects the smallest one wins (`door_logic.find_zone`).
3. The map property `surface` (default for the whole map). `house_mama.tmx` uses
   `madera`.
4. `lastre` (gravel), the fallback.

Values: `lastre`, `zacate`, `madera`, `concreto`. An unknown value falls back to
`lastre` when choosing the sound.

The walk demo (`scenes/walk_demo.lua`) has no map, so every step is `lastre`.

## Footstep sounds

- `surface_logic.STEPS[surface][walk|run]` is the list of sound ids. Walking uses
  volume 0.5, running 0.8.
- Variation: one step is picked from the list (never the same id twice in a row)
  and its volume gets a random jitter of +-15%.
- There is no pitch jitter. The engine has no per-sound pitch, so the variation
  comes from the volume and from the list of files.
- Steps play on the `sfx` bus.
- The step files are ~5 s strips of several steps, so they play as a **loop while
  the player moves** and fade out (80 ms) when the player stops. The walker calls
  `on_state(entity, moving, running)` every frame; `running` is true while Shift is
  held. Changing surface or switching walk/run restarts the loop with the new sound.
  Players wire it with `footsteps = { on_state = require("footsteps").on_state }`.

### Adding a step variation

1. Add the sound file under `sounds/sfx/` and its id to the list in
   `surface_logic.STEPS`.
2. Declare the id (`assetId`) in the `sounds` table of every scene that can play it.
   An undeclared sound makes `play_sound` return `0`; the step is then silent.

## Scene sounds

Every scene must declare each sound it plays in its `sounds` table:

- `town_demo.lua`: the 8 step sounds, the 6 town loops (`amb_pueblo_*`,
  `amb_monte_*`, `amb_quebrada_*`) and the one-shot sounds of those sets.
- `house_demo.lua`: the 8 step sounds, `amb_casa_day` / `amb_casa_night` and the
  narrated story `story_chequelo` (issue #68).
- `walk_demo.lua`: the 8 step sounds.

Ambience loops are declared with `stream = true` (decoded when first played).

## Narrated stories (issue #68)

A story recording is a `stream = true` sound declared in the scene, for example
`{ assetId = "story_chequelo", filePath = "sounds/stories/chequelo.mp3", stream = true }`.
It is played with `play_sound(id, { bus = "voice" })`, so the ambience and the
music duck to 0.35 while it plays. `sound_duration(id)` is read right after the
play starts, so the progress uses the real length.

`pause_sound(handle)` and `resume_sound(handle)` pause and resume the recording
without losing its position (see [lua-api.md](../../../engine/docs/lua-api.md#audio)).
A paused voice keeps the ducking active. The player stops a paused recording with
`stop_sound(handle)` without a fade. Details: [stories.md](stories.md).

## Limitations

- No pitch jitter (see above).
- A scene load stops all sounds. The ambience layers are restarted by the next
  `tick`, so the new scene fades in over 3 s.
- Changing scenes does not reset the time of day; the state is global and lasts for
  the whole session.
- The walk demo has no map, so all of its steps are `lastre`.
