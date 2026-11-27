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
