# Credits: town tileset

## Art (`town.png`, `town.tsx`, `maps/tiles_demo.tmx`)

Original art, produced procedurally by `games/quebrada/tools/tilegen/` (palette, shapes and noise
written for this project).

**License: TO BE CHOSEN by the project owner — suggested CC0.**
(Placeholder: this file does not decide the licence of the original art. Replace this paragraph once decided.)

## Code reused from pixelfx (MIT)

`games/quebrada/tools/tilegen/vendor/pixelfx/math.mjs` is a verbatim excerpt (`hash`, `rand`, `Rng`, `rng`:
a 32 bit integer hash and the mulberry32 generator) of `src/core/math.js` from
https://github.com/patch-gg/pixelfx, commit `5294518ce7c72e48b6100a744596e0acf57f2826`.

MIT License. Copyright (c) 2026 Patch, Copyright (c) 2026 Hugo Duprez. The full licence text is in
`games/quebrada/tools/tilegen/vendor/pixelfx/LICENSE`.

Nothing else from pixelfx is used (no effects, fonts or other assets).

## References

Shapes and colours were chosen with the photos and sketch of the real town in
`games/quebrada/docs/reference/` (croquis, camino de las carretas, cafetal, rio, monte, clinica, escuela).
Those are references only; no pixel of them is in the tileset.

## Buildings sheet (issue #71)

`tilesets/buildings.png` / `buildings.tsx` (church, mama's house, three filler houses, the interior of mama's
house, window glow cells and two coloured hedges) are original procedural art drawn by
`games/quebrada/tools/tilegen/catalog_buildings.mjs` and `building_draw.mjs`. No third party pixels. The licence
is the same TO-BE-CHOSEN placeholder as above.

The church follows the photo `games/quebrada/docs/reference/iglesia/iglesia-frente.jpg` (shapes and colours only).
Mama's house is based on a written description, not on a committed photo.

## Park sheet (zone 1)

`tilesets/park.png` / `park.tsx` (skate park floors and banks, rails, playground equipment, sand, basketball + football
court, line pieces, hoops, goals, walkway) are original procedural art drawn by
`games/quebrada/tools/tilegen/catalog_park.mjs`. No third party pixels. The licence is the same TO-BE-CHOSEN placeholder
as above (this file does not decide the licence of the original art).

## School sheet (zone 1)

`tilesets/school.png` / `school.tsx` (two long classroom blocks with red zinc roofs, pink corridor columns, grilled windows and benches, the flagpole,
the sign board, the patio floors and the low whitewashed wall with chain-link) are original procedural art drawn by
`games/quebrada/tools/tilegen/catalog_school.mjs`. No third party pixels. The shapes follow the reference photo
`games/quebrada/docs/reference/escuela/escuela-frente.jpg` (shapes and colours only). The licence is the same TO-BE-CHOSEN placeholder
as above (this file does not decide the licence of the original art).

## Ebais sheet (zone 1)

`tilesets/ebais.png` / `ebais.tsx` (the clinic building with its blue zinc roofs, stone-clad band, grilled windows, glass door and covered ramp porch with yellow railings, the concrete floors and parking line,
blue plastic benches, potted plants, garbage bin and the small sign board) are original procedural art drawn by `games/quebrada/tools/tilegen/catalog_ebais.mjs`. No third party pixels. The shapes follow the
reference photo `games/quebrada/docs/reference/clinica/ebais-rampa.jpg` (shapes and colours only). The licence is the same TO-BE-CHOSEN placeholder as above (this file does not decide the licence of the original art).

## Monte sheet (zone 1)

`tilesets/monte.png` / `monte.tsx` (the hule and nispero trees, the dark monte grass, leaf litter and mud ground tiles, ferns, bush, log, mossy rock, the asphalt road edge and centre-line pieces, the
concrete turbine pad, and the wind turbine: tower, nacelle and the animated three-blade rotor) are original procedural art drawn by `games/quebrada/tools/tilegen/catalog_monte.mjs`. No third party pixels.
The shapes follow the reference photos `games/quebrada/docs/reference/aerogeneradores/*.jpg` and `games/quebrada/docs/reference/monte/*.jpg` (shapes and colours only). The licence is the same
TO-BE-CHOSEN placeholder as above (this file does not decide the licence of the original art).

`tilesets/rio.png` / `rio.tsx` (rapids and deep-pool water, inner-corner banks, gravel, the concrete road bridge: deck curbs, rusty yellow-painted guard rails, concrete post and piers, and the boulders of the stream) are original procedural art drawn by `games/quebrada/tools/tilegen/catalog_rio.mjs`; the river course is computed by `river.mjs`. No third party pixels. The shapes follow the reference photo `games/quebrada/docs/reference/rio/quebrada-piedras.jpg` and the user's description of the river crossing (shapes and colours only). The licence is the same TO-BE-CHOSEN placeholder as above (this file does not decide the licence of the original art).
