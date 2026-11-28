// Vida sheet (vida.png + vida.tsx): name plaques for the houses of the main street, and (later) street life: animals, bus stop, laundry, motorbike, poles, signs.
// Eighth tileset of zona1.tmx (appended after rio, so no earlier firstgid moves). Sheet: 16 columns x 16 rows of 16x16 tiles, id = row * 16 + col. Every tile name starts with `vida_`.
//   ids 0-63    name plaques  vida_rotulo_<key>_<cx>_0   (1 row tall, 3-4 tiles wide; ysort, solid: a board on two posts, or mounted on a fence)
//   ids 64-...  street furniture (bus stop, laundry lines, moto, utility pole, signs) and street life: hens / rooster (animated, 2 variants with offset frame lists), dogs, cows and a horse (see docs/vida.md)
// Property scheme as town.tsx: name, layer (ground|overlay|ysort|above), surface (non-solid ground only), solid, sort_offset (and `anim` for animated tiles, see tsx.mjs).
import { Frame, rgb, shade, withAlpha } from "./draw.mjs";
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

// ---------------------------------------------------------------- animals (ids from V_PROP_BASE)
let propId = V_PROP_BASE;
const singles = [];
const addSingle = (name, layer, props, draw) => { const t = { id: propId++, name, layer, ...props, draw }; singles.push(t); return t; };
const SHADOW = withAlpha([0, 0, 0, 255], 60);
const col = { red: rgb("#c1272f"), orange: rgb("#e8a02e"), black: rgb("#26231f"), cream: rgb("#ece6d8"), creamShade: rgb("#c9c1ad"), brown: rgb("#8a4b2a"), brownLight: rgb("#b06a3a"), brownDark: rgb("#5e3119") };

/** Hen seen from the side, facing right; `peck` lowers the head to the ground. */
function hen(f, body, light, dark, peck) {
  f.ellipse(8, 14, 6, 1.8, SHADOW);
  f.ellipse(8, 10, 4.8, 3.6, body); f.ellipse(7, 9, 3, 2, light); f.hline(4, 12, 8, dark); // body, wing highlight, belly shade
  f.line(3, 8, 1, 6, dark); f.line(3, 9, 1, 8, dark); f.px(2, 7, body); // tail feathers
  const hx = peck ? 13 : 12, hy = peck ? 10 : 6;
  if (peck) f.line(11, 8, 12, 9, body); else f.line(11, 8, 12, 7, body);
  f.ellipse(hx, hy, 2.2, 2.2, body); f.px(hx, hy - 3, col.red); f.px(hx + 1, hy - 3, col.red); f.px(hx + 1, hy - 1, col.black); // comb and eye
  f.px(hx + 2, hy, col.orange); f.px(hx + 3, hy + (peck ? 1 : 0), col.orange); f.px(hx + 1, hy + 2, col.red); // beak and wattle
  f.vline(7, 13, 2, col.orange); f.vline(10, 13, 2, col.orange); f.px(6, 15, col.orange); f.px(11, 15, col.orange); // legs
}
addSingle("vida_gallina_a", "ysort", {}, (f) => hen(f, col.brown, col.brownLight, col.brownDark, false));
const gallinaA1 = addSingle("vida_gallina_a_f1", "ysort", {}, (f) => hen(f, col.brown, col.brownLight, col.brownDark, true));
addSingle("vida_gallina_b", "ysort", {}, (f) => hen(f, col.cream, rgb("#f6f2e8"), col.creamShade, false));
const gallinaB1 = addSingle("vida_gallina_b_f1", "ysort", {}, (f) => hen(f, col.cream, rgb("#f6f2e8"), col.creamShade, true));
/** Rooster: bigger comb, arched tail of green/black feathers. */
function rooster(f, crow) {
  f.ellipse(8, 14, 6, 1.8, SHADOW);
  f.ellipse(8, 10, 4.8, 3.8, rgb("#a8472a")); f.ellipse(7, 9.5, 3, 2.2, rgb("#c4693a")); f.hline(4, 12, 8, col.brownDark);
  for (const [x, y, c] of [[3, 7, col.black], [2, 5, rgb("#2f7a33")], [1, 4, rgb("#2f7a33")], [3, 5, col.black], [2, 8, rgb("#2f7a33")], [1, 7, col.black]]) f.px(x, y, c);
  f.line(11, 8, 12, crow ? 3 : 5, rgb("#a8472a"));
  const hy = crow ? 3 : 5;
  f.ellipse(12, hy, 2, 2, rgb("#c4693a")); f.rect(11, hy - 4, 3, 2, col.red); f.px(11, hy - 5, col.red); f.px(13, hy - 5, col.red); f.px(13, hy - 1, col.black);
  f.px(14, hy, col.orange); f.px(15, hy + (crow ? -1 : 0), col.orange); f.px(13, hy + 2, col.red);
  f.vline(7, 13, 2, col.orange); f.vline(10, 13, 2, col.orange); f.px(6, 15, col.orange); f.px(11, 15, col.orange);
}
addSingle("vida_gallo", "ysort", {}, (f) => rooster(f, false));
const galloF1 = addSingle("vida_gallo_f1", "ysort", {}, (f) => rooster(f, true));
// animations (tile ids of this sheet): two hens with offset frame lists so they do not move in lockstep; the rooster crows now and then
const byNameSingle = (n) => singles.find((t) => t.name === n);
byNameSingle("vida_gallina_a").anim = [0, 1, 0, 0].map((k) => ({ id: k ? gallinaA1.id : byNameSingle("vida_gallina_a").id, duration: 450 }));
byNameSingle("vida_gallina_b").anim = [0, 0, 1, 0].map((k) => ({ id: k ? gallinaB1.id : byNameSingle("vida_gallina_b").id, duration: 450 }));
byNameSingle("vida_gallo").anim = [0, 0, 0, 1].map((k) => ({ id: k ? galloF1.id : byNameSingle("vida_gallo").id, duration: 700 }));
// dogs (solid)
const dogCol = { fur: rgb("#b98b4e"), light: rgb("#d8b27a"), dark: rgb("#7a5630"), ear: rgb("#5e3f20") };
addSingle("vida_perro_echado", "ysort", { solid: true }, (f) => {
  f.ellipse(8, 14, 7, 2, SHADOW);
  f.ellipse(7, 11, 6, 3.2, dogCol.fur); f.ellipse(6, 10, 4, 1.8, dogCol.light); f.hline(2, 13, 11, dogCol.dark);
  f.line(2, 12, 0, 10, dogCol.fur); f.px(0, 9, dogCol.dark); // tail
  f.ellipse(12, 10, 3, 2.6, dogCol.fur); f.px(11, 7, dogCol.ear); f.px(12, 7, dogCol.ear); f.rect(14, 10, 2, 2, dogCol.dark); f.px(12, 9, col.black); // head, ear, snout, eye
  f.rect(10, 12, 4, 2, dogCol.light); // paws
});
addSingle("vida_perro_sentado", "ysort", { solid: true }, (f) => {
  f.ellipse(8, 14, 5, 1.8, SHADOW);
  f.ellipse(7, 10, 3.6, 4.6, dogCol.fur); f.ellipse(6, 10, 2, 3, dogCol.light); f.rect(8, 12, 3, 3, dogCol.fur); f.rect(5, 13, 3, 2, dogCol.dark); // body, chest, paws
  f.line(3, 13, 1, 12, dogCol.fur); f.px(1, 11, dogCol.dark);
  f.ellipse(9, 5, 3.2, 3, dogCol.fur); f.rect(8, 2, 2, 3, dogCol.ear); f.rect(11, 5, 3, 2, dogCol.dark); f.px(10, 4, col.black); f.px(13, 5, col.black); // head, ear, snout
});

// cows and a horse: 2x1 solid ysort objects (cells vida_<name>_<cx>_0), ids after the singles
const cowDraw = (spots, face) => (f) => {
  f.ellipse(16, 14, 13, 2.2, SHADOW);
  f.ellipse(14, 9, 11, 5, spots ? col.cream : col.black); f.hline(5, 13, 18, spots ? col.creamShade : rgb("#161412")); f.hline(6, 5, 16, spots ? rgb("#f6f2e8") : rgb("#3a3733"));
  if (spots) for (const [cx, cy, rx, ry] of [[9, 8, 3.5, 3], [17, 7, 3, 2.5], [21, 11, 3, 2], [12, 12, 2.5, 1.6]]) f.ellipse(cx, cy, rx, ry, col.black);
  f.line(3, 7, 1, 13, spots ? col.black : rgb("#161412")); f.px(1, 14, col.black); // tail
  for (const x of [6, 10, 19, 23]) { f.rect(x, 12, 2, 4, spots ? col.creamShade : rgb("#161412")); f.rect(x, 15, 2, 1, col.black); } // legs and hooves
  f.ellipse(27, 8, 4, 3.2, spots ? col.cream : col.black); f.rect(28, 9, 4, 3, face); f.px(30, 10, col.black); f.px(29, 6, col.black); // head, muzzle, nostril, eye
  f.rect(24, 4, 2, 2, col.cream); f.rect(29, 3, 2, 3, col.cream); f.px(27, 5, col.black); // horns and ear
  f.rect(23, 11, 4, 3, spots ? col.creamShade : rgb("#161412")); // dewlap
};
const horseDraw = (f) => {
  const body = rgb("#7a4a27"), light = rgb("#95602f"), dark = rgb("#4a2c14"), mane = rgb("#231a12");
  f.ellipse(16, 14, 13, 2.2, SHADOW);
  f.ellipse(14, 8, 10, 4, body); f.hline(5, 11, 18, dark); f.hline(6, 5, 16, light);
  f.line(3, 6, 1, 12, mane); f.line(4, 7, 2, 13, mane); // tail
  for (const x of [6, 10, 19, 23]) { f.rect(x, 10, 2, 6, body); f.rect(x, 15, 2, 1, mane); f.hline(x, 12, 2, dark); }
  f.line(22, 6, 27, 2, body); f.line(23, 7, 28, 3, body); f.line(22, 5, 27, 1, mane); f.line(21, 5, 25, 1, mane); // neck and mane
  f.ellipse(28, 4, 3.2, 2.6, body); f.rect(29, 5, 3, 2, light); f.px(31, 6, col.black); f.px(28, 3, col.black); f.rect(27, 0, 2, 2, mane); // head, muzzle, eye, ear
  f.rect(15, 5, 6, 2, rgb("#a8472a")); f.hline(15, 5, 6, rgb("#c4584a")); // saddle blanket
};
const animalObjects = [
  { name: "vida_vaca_pinta", draw: cowDraw(true, rgb("#e8b8b0")) },
  { name: "vida_vaca_negra", draw: cowDraw(false, rgb("#4a4540")) },
  { name: "vida_caballo", draw: horseDraw },
];
for (const a of animalObjects) {
  const cells = [0, 1].map((cx) => ({ cx, cy: 0, id: propId++, name: `${a.name}_${cx}_0`, layer: "ysort", solid: true }));
  O.push({ name: a.name, w: 2, h: 1, cells, draw: a.draw });
}

// ---------------------------------------------------------------- street furniture (multi-cell objects; the upper rows are `above` so you walk behind roofs and wires)
const ZN = { base: B.zincBase, light: B.zincLight, dark: B.zincDark };
const ROPE = rgb("#c9b48a");
const objectCells = (name, w, h, layerOf) => Array.from({ length: w * h }, (_, i) => { const cx = i % w, cy = Math.floor(i / w), layer = layerOf(cx, cy); return { cx, cy, id: propId++, name: `${name}_${cx}_${cy}`, layer, ...(layer === "ysort" ? { solid: true } : {}) }; });
const post = (f, x, y0, y1) => { f.rect(x, y0, 3, y1 - y0 + 1, B.wood); f.vline(x, y0, y1 - y0 + 1, B.woodLight); f.vline(x + 2, y0, y1 - y0 + 1, B.woodDark); };
const furniture = [
  { name: "vida_parada", w: 3, h: 2, layerOf: (cx, cy) => (cy === 0 ? "above" : "ysort"), draw(f) { // bus stop: zinc roof with the PARADA board, a wooden bench under it
    f.rect(0, 6, 48, 5, ZN.base); f.hline(0, 6, 48, ZN.light); f.hline(0, 10, 48, ZN.dark); for (let x = 2; x < 48; x += 3) f.vline(x, 7, 3, ZN.dark);
    f.rect(0, 11, 48, 2, B.woodDark); f.hline(0, 11, 48, B.wood);
    f.rect(8, 1, 32, 8, B.whiteTrim); f.rect(8, 1, 32, 1, rgb("#2a4a9a")); f.rect(8, 8, 32, 1, rgb("#2a4a9a")); f.vline(8, 1, 8, rgb("#2a4a9a")); f.vline(39, 1, 8, rgb("#2a4a9a"));
    drawText(f, "PARADA", 8 + Math.floor((32 - textWidth("PARADA")) / 2), 2, rgb("#2a4a9a"));
    f.ellipse(24, 30, 22, 2, SHADOW); post(f, 3, 16, 30); post(f, 42, 16, 30);
    f.rect(8, 24, 32, 3, B.woodLight); f.hline(8, 24, 32, shade(B.woodLight, 1.2)); f.hline(8, 26, 32, B.woodDark); f.rect(8, 19, 32, 2, B.wood); f.rect(9, 27, 2, 4, B.woodDeep); f.rect(37, 27, 2, 4, B.woodDeep);
  } },
  ...["a", "b"].map((k) => ({ name: `vida_ropa_${k}`, w: 2, h: 2, layerOf: (cx, cy) => (cy === 0 ? "above" : "ysort"), draw(f) { // laundry line between two posts, clothes hanging
    post(f, 2, 2, 30); post(f, 27, 2, 30); f.ellipse(16, 30, 14, 2, SHADOW);
    f.hline(5, 5, 22, ROPE); f.px(5, 6, ROPE); f.px(26, 6, ROPE);
    const items = k === "a" ? [[7, 9, 6, 10, rgb("#c4584a")], [15, 9, 5, 7, rgb("#f1efe4")], [21, 9, 5, 11, rgb("#4f6fa8")]] : [[7, 9, 5, 12, rgb("#e8c442")], [14, 9, 6, 8, rgb("#4f9a9e")], [21, 9, 5, 6, rgb("#f1efe4")]];
    for (const [x, y, w, h, c] of items) { f.rect(x, y - 3, w, h + 3, c); f.hline(x, y - 3, w, shade(c, 1.2)); f.hline(x, y + h - 1, w, shade(c, 0.8)); f.px(x + 1, y - 4, B.woodDeep); f.px(x + w - 2, y - 4, B.woodDeep); }
  } })),
  { name: "vida_moto", w: 2, h: 1, layerOf: () => "ysort", draw(f) { // parked red motorbike, side view
    f.ellipse(16, 14, 14, 2, SHADOW);
    for (const x of [7, 25]) { f.ellipse(x, 11, 4, 4, B.tire); f.ellipse(x, 11, 2.2, 2.2, rgb("#8c8c88")); f.px(x, 11, B.tire); }
    f.rect(8, 10, 17, 2, B.zincDark); f.rect(11, 6, 10, 5, rgb("#b83a32")); f.hline(11, 6, 10, rgb("#d6584c")); f.rect(7, 5, 5, 3, rgb("#26231f")); f.rect(20, 4, 3, 2, rgb("#d6584c")); // frame, tank, seat, headlight
    f.line(24, 4, 27, 8, B.metal); f.hline(22, 3, 4, B.metal); f.px(25, 2, B.metal); f.rect(4, 8, 3, 2, rgb("#b83a32")); f.rect(14, 11, 6, 2, B.zincDark); // fork, handlebar, tail, engine
  } },
  { name: "vida_poste", w: 1, h: 3, layerOf: (cx, cy) => (cy === 2 ? "ysort" : "above"), draw(f) { // utility pole without a lamp: crossarm with insulators, the cable at y=2 (like the lamp poles)
    const P = C.post;
    for (let x = 0; x < 16; x++) f.px(x, 2, P.cable);
    f.ellipse(8, 46, 6, 1.8, SHADOW);
    for (let y = 3; y < 46; y++) { f.px(6, y, P.light); f.px(7, y, P.base); f.px(8, y, P.dark); }
    f.rect(1, 3, 14, 2, P.arm); f.hline(1, 3, 14, shade(P.arm, 1.3)); for (const x of [2, 7, 13]) { f.px(x, 1, P.lampDim); f.px(x, 2, P.lamp); }
    f.rect(5, 40, 6, 6, C.concrete.base); f.hline(5, 40, 6, C.concrete.light); f.vline(10, 40, 6, C.concrete.dark);
  } },
  { name: "vida_senal_alto", w: 1, h: 2, layerOf: (cx, cy) => (cy === 0 ? "above" : "ysort"), draw(f) { // ALTO board on a post
    f.rect(0, 2, 16, 12, rgb("#c1272f")); f.hline(0, 2, 16, rgb("#e0584f")); f.hline(0, 13, 16, rgb("#8c1a20"));
    for (const [x, y] of [[0, 2], [15, 2], [0, 13], [15, 13]]) f.set(x, y, [0, 0, 0, 0]);
    drawText(f, "ALTO", 1, 6, B.whiteTrim); f.ellipse(8, 30, 5, 1.6, SHADOW); post(f, 6, 14, 30);
  } },
  { name: "vida_senal_escolar", w: 1, h: 2, layerOf: (cx, cy) => (cy === 0 ? "above" : "ysort"), draw(f) { // school-zone diamond: two children
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) { const d = Math.abs(x - 7.5) + Math.abs(y - 7.5); if (d <= 8) f.px(x, y, d > 6.6 ? rgb("#26231f") : rgb("#f0cf3a")); }
    f.rect(5, 6, 2, 5, rgb("#26231f")); f.rect(9, 7, 2, 4, rgb("#26231f")); f.rect(5, 4, 2, 2, rgb("#26231f")); f.rect(9, 5, 2, 2, rgb("#26231f"));
    f.ellipse(8, 30, 5, 1.6, SHADOW); post(f, 6, 16, 30);
  } },
];
for (const fu of furniture) {
  const cells = objectCells(fu.name, fu.w, fu.h, fu.layerOf);
  O.push({ name: fu.name, w: fu.w, h: fu.h, cells, draw: fu.draw });
}

export const V_TILES = [];
for (const o of O) for (const c of o.cells) V_TILES.push({ ...c, object: o.name });
for (const t of singles) V_TILES.push(t);
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
  for (const t of singles) { const f = new Frame(SIZE, SIZE); t.draw(f, tileRng(t.name)); put(t.id, f); }
  for (const o of O) {
    const canvas = new Frame(o.w * SIZE, o.h * SIZE);
    o.draw(canvas, tileRng(o.name));
    for (const c of o.cells) put(c.id, canvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  return sheet;
}
