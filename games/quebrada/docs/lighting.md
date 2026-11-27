# Lighting (issue #48)

Night darkness with light circles, built on the engine's
[lighting](../../../engine/docs/lua-api.md#lighting) API. Everything Quebrada-specific is
`scripts/lighting.lua`, called from `town_controller.lua`.

- **Ambient from the time of day.** `time_of_day.lua` (see `time-of-day.md`) owns the
  ambient colour: `day` is full white (the pass is skipped, no cost), `night` is
  `20, 26, 51`, with dusk and dawn in between. On scene load it reapplies the phase instantly.
- **Player lantern.** `lighting.tick()` attaches a warm, slightly flickering
  light (`radius 70`) to `player_entity` once per scene.
- **Map lights.** `time_of_day.init(map)` creates them. In Tiled, add an object of class
  `light` with custom properties `radius` (required), `r`, `g`, `b`, `intensity`, `flicker`
  and optionally `only` (e.g. `"dusk,night"`): they fade in and out with the phase.
- Press `N` in the town or a house to toggle day/night and see it. `lighting.lua` now only
  attaches the lantern.
- HUD, dialogue and subtitles are drawn after the overlay and are never darkened.
