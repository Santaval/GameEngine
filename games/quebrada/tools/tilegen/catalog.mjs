// Single source of truth for town.png + town.tsx.
// Every entry: { id, name, layer, surface?, solid?, sort_offset?, draw(frame, rng) }.
//   layer   authoring hint: ground | overlay | ysort | above (the map decides the real layer)
//   surface footstep material; only ground tiles that can be walked carry one
//   solid   blocks the player (water, fences, trunks...)
// Sheet: 16 columns x 9 rows of 16x16 tiles, id = row * 16 + col. Ids not listed are reserved (transparent).
import { Frame } from "./draw.mjs";
import { tileRng } from "./rng.mjs";
import { groundTiles } from "./catalog_ground.mjs";
import { fenceTiles } from "./catalog_fences.mjs";
import { plantTiles } from "./catalog_plants.mjs";

export const SIZE = 16;
export const COLS = 16;
export const ROWS = 9;

const singles = [...groundTiles(), ...fenceTiles(), ...plantTiles.singles()];
// Multi-cell objects: drawn on one canvas, sliced into cells. cells[i] = { cx, cy, id, name, layer, ... }
const objects = plantTiles.objects();

export const TILES = [];
for (const t of singles) TILES.push(t);
for (const o of objects) for (const c of o.cells) TILES.push({ ...c, object: o.name });
TILES.sort((a, b) => a.id - b.id);

// Sanity: ids unique and inside the sheet
{
  const seen = new Set();
  for (const t of TILES) {
    if (t.id < 0 || t.id >= COLS * ROWS) throw new Error(`id out of sheet: ${t.name} ${t.id}`);
    if (seen.has(t.id)) throw new Error(`duplicate id ${t.id} (${t.name})`);
    seen.add(t.id);
  }
}

/** Render the sheet into a Frame of COLS*SIZE x ROWS*SIZE. */
export function renderSheet() {
  const sheet = new Frame(COLS * SIZE, ROWS * SIZE);
  const put = (id, frame) => sheet.blit(frame, (id % COLS) * SIZE, Math.floor(id / COLS) * SIZE);
  for (const t of singles) {
    const f = new Frame(SIZE, SIZE);
    t.draw(f, tileRng(t.name));
    put(t.id, f);
  }
  for (const o of objects) {
    const canvas = new Frame(o.w * SIZE, o.h * SIZE);
    o.draw(canvas, tileRng(o.name));
    for (const c of o.cells) put(c.id, canvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  return sheet;
}
