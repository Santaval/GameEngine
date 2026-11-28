// School sheet (school.png + school.tsx): the Escuela of zone 1 (first-pass procedural art). Fourth tileset of zona1.tmx.
// Sheet: 16 columns x 14 rows of 16x16 tiles, id = row * 16 + col. Every tile name starts with `escuela_`.
// Layout:
//   rows 0-5  cols 0-9    escuela_aulas_a   10x6  classroom block A (cream walls)
//   rows 6-11 cols 0-9    escuela_aulas_b   10x6  classroom block B (ochre walls)
//   row 0     cols 10-15  patio floors (3), low wall + chain-link (h, v), whitewashed pillar
//   rows 2-4  col 10      escuela_asta      flagpole 1x3
//   rows 2-3  cols 11-12  escuela_rotulo    sign board 2x2
//   rows 12-13            lit window cells of the two aulas  <building>_lit_<cx>_<cy>
//   rows 14-19 cols 0-9   escuela_colegio   10x6  the Colegio's classroom block (light green walls, blue zinc roof, white beam)
//   rows 20-21            lit window cells of the colegio
//   rows 2-3  cols 13-14  escuela_rotulo_colegio 2x2 (sign "COLEGIO")
// Building entries have the shape of catalog_buildings.mjs ({ name, roof_of, col0,row0,w,h, roofRows, footRows, open, windows, door, draw, drawLit,
// cells, lit }) plus `sheet: "school"` and `doors` (door centres, px from the building's left edge).
// Property scheme as town.tsx: name, layer (ground|overlay|ysort|above), surface (non-solid ground only), solid (ysort only), sort_offset.
import { Frame, rgb, shade, withAlpha } from "./draw.mjs";
import { C } from "./palette.mjs";
import { tileRng } from "./rng.mjs";
import { concreteAt } from "./materials.mjs";
import * as D from "./building_draw.mjs";

export const SIZE = 16;
export const S_COLS = 16;
export const S_ROWS = 22;
const id = (row, col) => row * S_COLS + col;
const B = C.bldg;
const SH = withAlpha([0, 0, 0, 255], 60);

// ---------------------------------------------------------------- escuela_aulas (long classroom block, 10x6 cells = 160x96 px)
const AULA_W = 10, AULA_H = 6;
const BAYS = 6;
const bayX = (k) => Math.round((k * AULA_W * SIZE) / BAYS); // bay edges
const BAY_KINDS = ["W", "D", "W", "W", "D", "W"]; // 4 windows, 2 green doors
const WIN_Y = 68, WIN_W = 16, WIN_H = 9;
const bayCentre = (k) => Math.round((bayX(k) + bayX(k + 1)) / 2);
const AULA_WINDOWS = BAY_KINDS.flatMap((kd, k) => (kd === "W" ? [{ x: bayCentre(k) - WIN_W / 2, y: WIN_Y, w: WIN_W, h: WIN_H }] : []));
const AULA_DOORS = BAY_KINDS.flatMap((kd, k) => (kd === "D" ? [bayCentre(k)] : []));
const PINK = { base: B.pinkColumn, light: B.pinkLight, dark: B.pinkColumnDark };

/** Wooden-framed window with an iron grille (day pixels; the lit version paints the same glass rectangle). */
function grilleWindow(f, w) {
  const { x, y, w: ww, h } = w;
  f.rect(x - 2, y - 2, ww + 4, h + 4, B.wood);
  f.hline(x - 2, y - 2, ww + 4, B.woodLight);
  f.hline(x - 2, y + h + 1, ww + 4, B.woodDark);
  f.rect(x, y, ww, h, B.glass);
  f.rect(x, y, ww, 3, B.glassHi);
  f.hline(x, y + h - 2, ww, B.glassDark); f.hline(x, y + h - 1, ww, B.glassDark);
  for (let i = 1; i < ww; i += 3) f.vline(x + i, y, h, B.zincDark); // grille bars
  f.hline(x, y + Math.round(h / 2), ww, B.zincDark);
  f.rect(x - 3, y + h + 2, ww + 6, 2, B.whiteTrimShade); f.hline(x - 3, y + h + 2, ww + 6, B.whiteTrim); // sill
}

function bench(f, cx) {
  const x = cx - 11;
  f.rect(x, 81, 22, 2, B.woodDark); f.hline(x, 81, 22, B.wood); // back rail
  f.vline(x + 2, 83, 3, B.woodDark); f.vline(x + 19, 83, 3, B.woodDark);
  f.rect(x, 85, 22, 3, B.woodLight); f.hline(x, 85, 22, shade(B.woodLight, 1.2)); f.hline(x, 87, 22, B.wood);
  f.rect(x + 1, 88, 2, 4, B.woodDeep); f.rect(x + 19, 88, 2, 4, B.woodDeep);
  f.hline(x + 1, 92, 20, SH);
}

function drawAulas({ wall, roof, salt, beam = PINK, door = { base: B.doorGreen, light: shade(B.doorGreen, 1.25), dark: B.doorGreenDark } }) {
  return (f) => {
    D.hipRoof(f, 2, 2, AULA_W * SIZE - 4, 62, roof, { top: 20, side: 24, frontTrim: 4, salt });
    D.plasterWall(f, 0, 64, AULA_W * SIZE, 32, { ...wall, skirt: 2 });
    // corridor floor (concrete) in front of the wall, a darker footing line where the wall meets it
    for (let y = 84; y < 96; y++) for (let x = 0; x < AULA_W * SIZE; x++) f.px(x, y, concreteAt(x, y, 40));
    f.hline(0, 83, AULA_W * SIZE, wall.dark); f.hline(0, 84, AULA_W * SIZE, C.concrete.joint);
    // roof beam (pink) with the eave shadow under it
    f.rect(0, 64, AULA_W * SIZE, 3, beam.base); f.hline(0, 64, AULA_W * SIZE, beam.light); f.hline(0, 66, AULA_W * SIZE, beam.dark);
    for (let y = 67; y < 71; y++) f.hline(0, y, AULA_W * SIZE, withAlpha([0, 0, 0, 255], 60 - (y - 67) * 14));
    BAY_KINDS.forEach((kd, k) => {
      const c = bayCentre(k);
      if (kd === "W") { grilleWindow(f, AULA_WINDOWS.find((w) => w.x === c - WIN_W / 2)); bench(f, c); }
      else D.door(f, c - 6, 67, 12, 17, door);
    });
    // thin pink columns between the bays
    for (let k = 0; k <= BAYS; k++) D.column(f, Math.min(AULA_W * SIZE - 5, Math.max(0, bayX(k) - 2)), 66, 92, 5, beam);
    f.hline(0, 95, AULA_W * SIZE, SH);
  };
}
const drawAulasLit = (f) => { for (const w of AULA_WINDOWS) D.plainWindow(f, w.x, w.y, w.w, w.h, { lit: true, bar: true }); };

const roofRed = { base: B.redBase, light: B.redLight, dark: B.redDark, line: B.redLine, trim: B.whiteTrimShade, trimDark: B.zincDark };
const roofBlue = { base: B.blueBase, light: B.blueLight, dark: B.blueDark, line: B.blueLine, trim: B.whiteTrimShade, trimDark: B.zincDark };
const WHITE_BEAM = { base: B.whiteTrim, light: B.whiteLight, dark: B.whiteTrimShade };
const aulaBuilding = (name, row0, wall, salt, o = {}) => ({
  name, roof_of: name, sheet: "school", col0: 0, row0, litBase: o.litBase ?? id(12, 0), litEnd: o.litEnd ?? id(14, 0), w: AULA_W, h: AULA_H, roofRows: 4, footRows: [1, 5],
  open: Array.from({ length: AULA_W }, (_, cx) => [cx, 5]), // the corridor row is walkable
  windows: AULA_WINDOWS, doors: AULA_DOORS, door: { cx: 0, cy: 5, w: 32 },
  draw: drawAulas({ wall, roof: o.roof ?? roofRed, salt, beam: o.beam, door: o.door }), drawLit: drawAulasLit,
});
const SCHOOL_BUILDINGS = [
  aulaBuilding("escuela_aulas_a", 0, { base: B.cream, shade: B.creamShade, hi: B.creamHi, dark: B.creamDark, salt: "ea" }, "esca"),
  aulaBuilding("escuela_aulas_b", 6, { base: rgb("#e2c58a"), shade: rgb("#c8a96c"), hi: rgb("#f0dcae"), dark: rgb("#a98d56"), salt: "eb" }, "escb"),
  // the Colegio (Liceo): light-green walls, blue zinc roof, white beam and columns, brown doors; rows 14-19 of the sheet, its lit cells in rows 20-21
  aulaBuilding("escuela_colegio", 14, { base: rgb("#bcd6a9"), shade: rgb("#a2c08f"), hi: rgb("#d5e8c5"), dark: rgb("#7f9e72"), salt: "ec" }, "escc",
    { roof: roofBlue, beam: WHITE_BEAM, door: { base: B.doorBrown, light: B.doorLight, dark: B.doorDark }, litBase: id(20, 0), litEnd: id(22, 0) }),
];

// ---------------------------------------------------------------- singles (patio floors, fence pieces, pillar)
function singles() {
  const T = [];
  const add = (row, col, name, layer, props, draw) => T.push({ id: id(row, col), name, layer, ...props, draw });
  const K = { surface: "concreto" };
  const floor = (v) => (f) => f.fill((x, y) => shade(concreteAt(x, y, v), 1.03));
  add(0, 0 + 10, "escuela_patio_a", "ground", K, (f) => { floor(60)(f); f.hline(0, 15, 16, C.concrete.joint); f.vline(15, 0, 16, C.concrete.joint); f.hline(0, 0, 16, C.concrete.light); });
  add(0, 11, "escuela_patio_b", "ground", K, (f) => { floor(61)(f); f.hline(0, 7, 16, C.concrete.joint); f.hline(0, 15, 16, C.concrete.joint); f.vline(8, 0, 7, C.concrete.joint); f.vline(4, 8, 7, C.concrete.joint); });
  add(0, 12, "escuela_patio_grieta", "ground", K, (f) => {
    floor(62)(f); f.hline(0, 15, 16, C.concrete.joint); f.vline(15, 0, 16, C.concrete.joint);
    f.line(3, 0, 6, 6, C.concrete.joint); f.line(6, 6, 5, 11, C.concrete.joint); f.line(6, 6, 12, 8, C.concrete.stain);
  });
  const fence = { solid: true };
  const mesh = (f, x0, y0, x1, y1) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) if ((x + y) % 4 === 0 || (x - y + 64) % 4 === 0) f.px(x, y, withAlpha(C.wire.metal, 210)); };
  // low whitewashed wall topped by chain-link: horizontal run, vertical run and a whitewashed pillar (corners, gate posts)
  add(0, 13, "escuela_cerca_h", "ysort", fence, (f) => {
    f.hline(1, 15, 15, SH);
    mesh(f, 0, 4, 15, 9);
    f.hline(0, 3, 16, C.wire.metal); f.hline(0, 4, 16, C.wire.dark);
    f.rect(0, 10, 16, 5, B.whitewash); f.hline(0, 10, 16, B.whiteLight); f.hline(0, 14, 16, B.whiteShade);
    f.rect(0, 3, 2, 12, B.whiteShade); f.vline(0, 3, 12, B.whiteLight);
  });
  add(0, 14, "escuela_cerca_v", "ysort", fence, (f) => {
    f.rect(5, 15, 6, 1, SH);
    f.rect(6, 0, 4, 16, B.whitewash); f.vline(6, 0, 16, B.whiteLight); f.vline(9, 0, 16, B.whiteShade);
    for (let y = 1; y < 16; y += 2) f.px(7, y, C.wire.dark);
    f.vline(8, 0, 16, withAlpha(C.wire.metal, 220));
    f.rect(5, 0, 6, 2, C.wire.metal); f.hline(5, 1, 6, C.wire.dark);
  });
  add(0, 15, "escuela_pilar", "ysort", fence, (f) => {
    f.ellipse(8, 14, 6, 2, SH);
    f.rect(4, 3, 8, 12, B.whitewash); f.vline(4, 3, 12, B.whiteLight); f.vline(11, 3, 12, B.whiteShade);
    f.rect(4, 7, 8, 2, B.pinkColumn); f.hline(4, 8, 8, B.pinkColumnDark);
    f.rect(3, 1, 10, 3, B.whiteTrimShade); f.hline(3, 1, 10, B.whiteTrim);
    f.hline(4, 14, 8, B.whiteShade);
  });
  return T;
}

// ---------------------------------------------------------------- multi-cell objects
const GLYPHS = {
  E: ["111", "100", "110", "100", "111"], O: ["111", "101", "101", "101", "111"], G: ["111", "100", "101", "101", "111"], I: ["111", "010", "010", "010", "111"], S: ["111", "100", "111", "001", "111"], C: ["111", "100", "100", "100", "111"],
  U: ["101", "101", "101", "101", "111"], L: ["100", "100", "100", "100", "111"], A: ["010", "101", "111", "101", "101"],
};
function objects() {
  const O = [];
  const cell = (name, cx, cy, row, col, layer, props = {}) => ({ cx, cy, id: id(row, col), name: `${name}_${cx}_${cy}`, layer, ...props });
  // flagpole 1x3: flag and pole top in the two upper cells (above), the base is the solid ysort cell
  O.push({
    name: "escuela_asta", w: 1, h: 3,
    cells: [cell("escuela_asta", 0, 0, 2, 10, "above"), cell("escuela_asta", 0, 1, 3, 10, "above"), cell("escuela_asta", 0, 2, 4, 10, "ysort", { solid: true, sort_offset: -2 })],
    draw(f) {
      f.ellipse(6, 44, 6, 2.2, SH);
      f.rect(4, 4, 2, 41, C.post.light); f.vline(5, 4, 41, C.post.dark); f.rect(3, 1, 4, 3, rgb("#e0b83a")); f.hline(3, 1, 4, rgb("#f1d56a"));
      f.rect(1, 41, 9, 6, C.concrete.base); f.hline(1, 41, 9, C.concrete.light); f.hline(1, 46, 9, C.concrete.dark);
      const bands = [[2, rgb("#2a4a9a")], [2, rgb("#f1f1ea")], [3, rgb("#c8372d")], [2, rgb("#f1f1ea")], [2, rgb("#2a4a9a")]];
      let y = 5;
      for (const [h, col] of bands) { for (let j = 0; j < h; j++) f.hline(6, y + j + (j % 2 ? 0 : 0), 10, col); y += h; }
      f.px(15, 5, rgb("#f1f1ea")); f.hline(6, 16, 9, withAlpha([0, 0, 0, 255], 40));
    },
  });
  // sign board 2x2 on two posts: board above, posts (solid) below
  const sign = (name, text, col, blue) => O.push({
    name, w: 2, h: 2,
    cells: [cell(name, 0, 0, 2, col, "above"), cell(name, 1, 0, 2, col + 1, "above"),
      cell(name, 0, 1, 3, col, "ysort", { solid: true, sort_offset: -2 }), cell(name, 1, 1, 3, col + 1, "ysort", { solid: true, sort_offset: -2 })],
    draw(f) {
      f.ellipse(6, 29, 5, 2, SH); f.ellipse(26, 29, 5, 2, SH);
      for (const x of [5, 25]) { f.rect(x, 14, 3, 17, B.wood); f.vline(x, 14, 17, B.woodLight); f.vline(x + 2, 14, 17, B.woodDark); }
      f.rect(1, 2, 30, 13, B.whiteTrim); f.rect(1, 2, 30, 1, blue); f.rect(1, 14, 30, 1, blue); f.vline(1, 2, 13, blue); f.vline(30, 2, 13, blue);
      f.hline(2, 13, 28, B.whiteTrimShade);
      text.split("").forEach((ch, i) => GLYPHS[ch].forEach((row, j) => [...row].forEach((v, k) => { if (v === "1") f.px(2 + i * 4 + k, 5 + j, blue); })));
    },
  });
  sign("escuela_rotulo", "ESCUELA", 11, rgb("#2a4a9a"));
  sign("escuela_rotulo_colegio", "COLEGIO", 13, rgb("#2f6e3a"));
  return O;
}

// ---------------------------------------------------------------- assemble
const nonEmpty = (fr) => fr.data.some((v, i) => i % 4 === 3 && v > 0);
const canvases = new Map();
const litNext = new Map(); // litBase -> next free lit id (the two aulas share rows 12-13)
for (const b of SCHOOL_BUILDINGS) {
  const day = new Frame(b.w * SIZE, b.h * SIZE);
  b.draw(day);
  const lit = new Frame(b.w * SIZE, b.h * SIZE);
  b.drawLit(lit);
  canvases.set(b.name, { day, lit });
  b.cells = []; b.lit = [];
  let nextLit = litNext.get(b.litBase) ?? b.litBase;
  const open = new Set(b.open.map(([cx, cy]) => `${cx},${cy}`));
  for (let cy = 0; cy < b.h; cy++) for (let cx = 0; cx < b.w; cx++) {
    if (nonEmpty(day.slice(cx * SIZE, cy * SIZE, SIZE, SIZE))) {
      const isRoof = cy < b.roofRows;
      const c = { cx, cy, id: id(b.row0 + cy, b.col0 + cx), name: `${b.name}_${cx}_${cy}`, layer: isRoof ? "above" : "ysort", building: b.name };
      if (!isRoof) { if (open.has(`${cx},${cy}`)) c.sort_offset = -16; else c.solid = true; }
      b.cells.push(c);
    }
    if (nonEmpty(lit.slice(cx * SIZE, cy * SIZE, SIZE, SIZE))) b.lit.push({ cx, cy, id: nextLit++, name: `${b.name}_lit_${cx}_${cy}`, layer: "ysort", sort_offset: 1, building: b.name });
  }
  litNext.set(b.litBase, nextLit);
  if (nextLit > b.litEnd) throw new Error(`too many lit cells in ${b.name}: ${nextLit - b.litBase}`);
}


const S = singles();
const O = objects();
export { SCHOOL_BUILDINGS };
export const SCHOOL_BUILDING_BY_NAME = new Map(SCHOOL_BUILDINGS.map((b) => [b.name, b]));
export const SCHOOL_OBJECTS = O;
export const SCHOOL_OBJECT_BY_NAME = new Map(O.map((o) => [o.name, o]));
export const S_TILES = [...S];
for (const o of O) for (const c of o.cells) S_TILES.push({ ...c, object: o.name });
for (const b of SCHOOL_BUILDINGS) { for (const c of b.cells) S_TILES.push(c); for (const c of b.lit) S_TILES.push(c); }
S_TILES.sort((a, b) => a.id - b.id);
{
  const ids = new Set(), names = new Set();
  for (const t of S_TILES) {
    if (t.id < 0 || t.id >= S_COLS * S_ROWS) throw new Error(`id out of school sheet: ${t.name} ${t.id}`);
    if (ids.has(t.id)) throw new Error(`duplicate school id ${t.id} (${t.name})`);
    if (names.has(t.name)) throw new Error(`duplicate school name ${t.name}`);
    if (!t.name.startsWith("escuela_")) throw new Error(`school tile without escuela_ prefix: ${t.name}`);
    ids.add(t.id); names.add(t.name);
  }
}
export const sIdByName = new Map(S_TILES.map((t) => [t.name, t.id]));

export function renderSchoolSheet() {
  const sheet = new Frame(S_COLS * SIZE, S_ROWS * SIZE);
  const put = (tid, fr) => sheet.blit(fr, (tid % S_COLS) * SIZE, Math.floor(tid / S_COLS) * SIZE);
  for (const t of S) { const f = new Frame(SIZE, SIZE); t.draw(f, tileRng(t.name)); put(t.id, f); }
  for (const o of O) {
    const canvas = new Frame(o.w * SIZE, o.h * SIZE);
    o.draw(canvas, tileRng(o.name));
    for (const c of o.cells) put(c.id, canvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  for (const b of SCHOOL_BUILDINGS) {
    const { day, lit } = canvases.get(b.name);
    for (const c of b.cells) put(c.id, day.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
    for (const c of b.lit) put(c.id, lit.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  return sheet;
}

export const schoolBuildingCanvas = (name) => canvases.get(name);
