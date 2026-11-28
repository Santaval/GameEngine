# Lighting (issue #48)

Night darkness with light circles, built on the engine's
[lighting](../../../engine/docs/lua-api.md#lighting) API. Everything Quebrada-specific is
`scripts/lighting.lua`, called from `town_controller.lua`.

- **Ambient from the time of day.** `time_of_day.lua` (see `time-of-day.md`) owns the
  ambient colour: `day` is full white (the pass is skipped, no cost), `night` is
  `6, 8, 18`, with dusk and dawn in between. On scene load it reapplies the phase instantly.
- **Player halo.** `lighting.tick()` attaches a tiny warm halo (`radius 20`, steady,
  offset to the feet) to `player_entity` once per scene, so the character is never lost at night.
- **Map lights.** `time_of_day.init(map)` creates them. In Tiled, add an object of class
  `light` with custom properties `radius` (required), `r`, `g`, `b`, `intensity`, `flicker`
  and optionally `only` (e.g. `"dusk,night"`): they fade in and out with the phase.
- **Street posts.** In `town.tmx` a row of posts at `y=245` lights the street at dusk and
  night: `x=100`, `335`, `510` and `600` (plus the older `250` and `420`). The post at `335`
  flickers (`flicker 0.5`) and the broken post at `510` dims and flickers hard (`intensity 0.5`,
  `flicker 0.8`). A fire (`fogata`) at `580,440` glows orange (`flicker 0.4`).
- Flicker shakes the radius too, a little (down to 75% at the deepest dip), on a smooth curve.
- Press `N` in the town or a house to toggle day/night and see it. `lighting.lua` now only
  attaches the halo.
- **Foco (issue #67).** The foco is a tool (#53, [tools.md](tools.md)): take it from the `linterna` in
  the house, then select it and press `X` to turn it on: a beam of 3 circles in front of the
  player, following the facing. It runs on a battery of 90 seconds that drains only while it is
  on; below 20% the light weakens, and at 0 it turns off and `X` says `Sin bateria`. Recharge it
  at the `cargador` in the house (`Cargar el foco`) or by sleeping in the bed. A small HUD bar
  (bottom left) shows the charge and hides when it is full and off. Logic: `scripts/foco_logic.lua`;
  controller: `scripts/foco.lua`.

## Companion light (issue #81)

The Luz de Chequelo night has a light that walks ahead of the player along the route (`vfx_luz` sprite + free light). See `docs/zona1.md` ("La luz"); code in `scripts/companion_light.lua`.

## Lit windows (issue #71)

Buildings that use `tilesets/buildings.png` get their window glow in two parts: `light` objects with
`only = "dusk,night"` (the usual pool of light, above) and a `windows_lit` tile layer whose alpha
`scripts/roofs.lua` ramps to 255 at dusk / night and to 0 by day. See [buildings.md](buildings.md).

## Manual checklist

- At night a row of posts lights the street; one flickers and one is broken.
- Take the `linterna`; `X` turns the foco on, the bar drains, it dies at 0 and `X` says `Sin bateria`.
- Recharge at the `cargador` in the house, or by sleeping.
- HUD, dialogue and subtitles are drawn after the overlay and are never darkened.
