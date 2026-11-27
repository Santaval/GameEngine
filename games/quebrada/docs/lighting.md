# Lighting (issue #48)

Night darkness with light circles, built on the engine's
[lighting](../../../engine/docs/lua-api.md#lighting) API. Everything Quebrada-specific is
`scripts/lighting.lua`, called from `town_controller.lua`.

- **Ambient from the time of day.** `lighting.tick()` reads `ambience.get_time()`:
  `"day"` is full white (the pass is skipped, no cost); `"night"` is `20, 26, 51`.
  A change fades over 2 s. On scene load `lighting.init(map)` applies the current
  time instantly (the screen arrives black, so the snap is not visible).
- **Player lantern.** `lighting.tick()` attaches a warm, slightly flickering
  light (`radius 70`) to `player_entity` once per scene.
- **Map lights.** `lighting.init(map)` calls `lights_from_map(map)`. In Tiled, add an
  object of class `light` with custom properties `radius` (required), `r`, `g`, `b`,
  `intensity`, `flicker`.
- Press `N` in the town or a house to toggle day/night and see it.
- HUD, dialogue and subtitles are drawn after the overlay and are never darkened.
