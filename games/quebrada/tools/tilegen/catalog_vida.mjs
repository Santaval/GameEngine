// Vida sheet (vida.png + vida.tsx): name plaques for the houses of the main street, and (later) street life: animals, bus stop, laundry, motorbike, poles, signs.
// Eighth tileset of zona1.tmx (appended after rio, so no earlier firstgid moves). Sheet: 16 columns x 16 rows of 16x16 tiles, id = row * 16 + col. Every tile name starts with `vida_`.
//   ids 0-63    name plaques  vida_rotulo_<key>_<cx>_0   (1 row tall, 3-4 tiles wide; ysort, solid: a board on two posts, or mounted on a fence)
//   ids 64-255  reserved for street life (see docs/vida.md)
// Property scheme as town.tsx: name, layer (ground|overlay|ysort|above), surface (non-solid ground only), solid, sort_offset (and `anim` for animated tiles, see tsx.mjs).
import { Frame, rgb, withAlpha } from "./draw.mjs";
import { C } from "./palette.mjs";
import { tileRng } from "./rng.mjs";
import { drawText, textWidth } from "./font.mjs";

export const SIZE = 16;
export const V_COLS = 16;
export const V_ROWS = 16;
export const V_PLAQUE_IDS = 64; // ids 0..63 are plaque cells
export const V_PROP_BASE = 64; // street-life tiles start here
const B = C.bldg;
const SH = withAlpha([0, 0, 0, 255], 60);
const INK = rgb("#4a2f1a"); // text colour of the plaques (dark brown on a cream board)

/** key -> { lines, style }: "post" = a board on two wooden posts (one line); "fence" = a board hung on a fence (up to two lines). Max 4 tiles wide. */
export const PLAQUES = [
  { key: "berta", lines: ["CASA DE BERTA"], style: "post" },
  { key: "maria_juvenal", lines: ["MARIA Y JUVENAL"], style: "post" },
  { key: "isabel", lines: ["DOÑA ISABEL"], style: "post" },
  { key: "carmen", lines: ["CASA DE CARMEN"], style: "post" },
  { key: "machillos", lines: ["LOS MACHILLOS"], style: "post" },
  { key: "ingracia", lines: ["DOÑA INGRACIA"], style: "post" },
  { key: "guarderia", lines: ["GUARDERIA"], style: "post" },
  { key: "caliles", lines: ["LOS CALILES"], style: "post" },
  { key: "enrique", lines: ["TIO ENRIQUE"], style: "post" },
  { key: "paula", lines: ["ABUELA PAULA", "Y ABUELO PEPE"], style: "fence" },
];
const tilesWide = (p) => Math.ceil((Math.max(...p.lines.map(textWidth)) + 4) / SIZE);

function drawPlaque(p, w) {
  return (f) => {
    const W = w * SIZE;
    if (p.style === "post") {
      f.ellipse(7, 15, 5, 1.4, SH); f.ellipse(W - 7, 15, 5, 1.4, SH);
      for (const x of [5, W - 8]) { f.rect(x, 9, 3, 7, B.wood); f.vline(x, 9, 7, B.woodLight); f.vline(x + 2, 9, 7, B.woodDark); }
      f.rect(1, 1, W - 2, 10, B.whiteTrim); f.rect(1, 1, W - 2, 1, B.woodDark); f.rect(1, 10, W - 2, 1, B.woodDark); f.vline(1, 1, 10, B.woodDark); f.vline(W - 2, 1, 10, B.woodDark);
      f.hline(2, 9, W - 4, B.whiteTrimShade);
      drawText(f, p.lines[0], 1 + Math.floor((W - 2 - textWidth(p.lines[0])) / 2), 3, INK);
    } else { // board hung on a wire fence: a short piece of fence wire at both ends, two lines of text
      for (const x of [0, W - 3]) { f.rect(x, 3, 3, 12, B.wood); f.vline(x, 3, 12, B.woodLight); f.vline(x + 2, 3, 12, B.woodDark); }
      f.rect(2, 1, W - 4, 14, B.whiteTrim); f.rect(2, 1, W - 4, 1, B.woodDark); f.rect(2, 14, W - 4, 1, B.woodDark); f.vline(2, 1, 14, B.woodDark); f.vline(W - 3, 1, 14, B.woodDark);
      f.hline(3, 13, W - 6, B.whiteTrimShade);
      p.lines.forEach((line, i) => drawText(f, line, 2 + Math.floor((W - 4 - textWidth(line)) / 2), 3 + i * 6, INK));
    }
  };
}

const O = [];
let nextId = 0;
for (const p of PLAQUES) {
  const w = tilesWide(p);
  if (w > 4) throw new Error(`plaque ${p.key} is ${w} tiles wide, the maximum is 4`);
  const name = `vida_rotulo_${p.key}`;
  const cells = Array.from({ length: w }, (_, cx) => ({ cx, cy: 0, id: nextId++, name: `${name}_${cx}_0`, layer: "ysort", solid: true }));
  O.push({ name, w, h: 1, cells, draw: drawPlaque(p, w) });
}
if (nextId > V_PLAQUE_IDS) throw new Error(`too many plaque cells: ${nextId} > ${V_PLAQUE_IDS}`);

export const V_TILES = [];
for (const o of O) for (const c of o.cells) V_TILES.push({ ...c, object: o.name });
V_TILES.sort((a, b) => a.id - b.id);
{
  const ids = new Set(), names = new Set();
  for (const t of V_TILES) {
    if (t.id < 0 || t.id >= V_COLS * V_ROWS) throw new Error(`id out of vida sheet: ${t.name} ${t.id}`);
    if (ids.has(t.id)) throw new Error(`duplicate vida id ${t.id} (${t.name})`);
    if (names.has(t.name)) throw new Error(`duplicate vida name ${t.name}`);
    if (!t.name.startsWith("vida_")) throw new Error(`vida tile without vida_ prefix: ${t.name}`);
    ids.add(t.id); names.add(t.name);
  }
}
export const vIdByName = new Map(V_TILES.map((t) => [t.name, t.id]));
export const V_OBJECTS = O;
export const V_OBJECT_BY_NAME = new Map(O.map((o) => [o.name, o]));
export const VIDA_TILE_COUNT = V_TILES.length;

export function renderVidaSheet() {
  const sheet = new Frame(V_COLS * SIZE, V_ROWS * SIZE);
  const put = (tid, fr) => sheet.blit(fr, (tid % V_COLS) * SIZE, Math.floor(tid / V_COLS) * SIZE);
  for (const o of O) {
    const canvas = new Frame(o.w * SIZE, o.h * SIZE);
    o.draw(canvas, tileRng(o.name));
    for (const c of o.cells) put(c.id, canvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  return sheet;
}
