// Ebais sheet (ebais.png + ebais.tsx): the health clinic of zone 1 (first-pass procedural art). Fifth tileset of zona1.tmx.
// Sheet: 16 columns x 16 rows of 16x16 tiles, id = row * 16 + col. Every tile name starts with `ebais_`.
// Layout:
//   rows 0-6   cols 0-11   ebais_edificio ROOF block 12x7: main blue corrugated zinc roof (rows 0-2) and the lower porch roof + wooden-slat eave (rows 5-6)
//   rows 7-13  cols 0-11   ebais_edificio WALL block 12x7 (same cell grid): stone-clad band + light-blue wall (rows 3-4), the covered ramp porch (rows 5-6)
//   rows 0-1   cols 12-15  concreto floors (3), parking stall line, blue plastic bench, potted plant, garbage bin
//   row 2      cols 12-13  ebais_rotulo sign board 2x1 on two posts
//   rows 14-15             lit window / door-glass cells  ebais_edificio_lit_<cx>_<cy>
// One building cell can carry TWO tiles: the wall tile `ebais_edificio_<cx>_<cy>` (layer ysort; solid unless it is one of the open porch cells) in the `buildings`
// layer and the roof tile `ebais_edificio_techo_<cx>_<cy>` (layer above, never solid) in `roof_ebais_edificio`. That lets the lower porch roof cover the ramp
// while the wall below it stays visible when the roofs fade out.
// Building entry shape as catalog_school.mjs ({ name, roof_of, sheet, w, h, footRows, open, windows, door, draw, drawLit, cells, lit }).
// Property scheme as town.tsx: name, layer (ground|overlay|ysort|above), surface (non-solid ground only), solid (ysort only), sort_offset.
import { Frame, rgb, shade, withAlpha } from "./draw.mjs";
import { C } from "./palette.mjs";
import { noise, tileRng } from "./rng.mjs";
import { concreteAt } from "./materials.mjs";
import * as D from "./building_draw.mjs";

export const SIZE = 16;
export const E_COLS = 16;
export const E_ROWS = 16;
const id = (row, col) => row * E_COLS + col;
const B = C.bldg;
const SH = withAlpha([0, 0, 0, 255], 60);

const YEL = { base: rgb("#e2b92d"), light: rgb("#f4d764"), dark: rgb("#a98418") };
const BENCH = { base: rgb("#3f6fb0"), light: rgb("#6a97d2"), dark: rgb("#2b4f86"), deep: rgb("#1f3a66") };
const SLAT = { base: rgb("#8d8173"), light: rgb("#a99d8d"), dark: rgb("#5d544a") };
const STONES = ["#767a82", "#8a8e95", "#6a6e76", "#9fa3a9", "#c2c5c8", "#7f838b"].map(rgb);
const MORTAR = rgb("#4f5359");
const ROOF = { base: B.blueBase, light: B.blueLight, dark: B.blueDark, line: B.blueLine, trim: B.whiteTrimShade, trimDark: B.zincDark };
const WALL = { base: B.blueWall, shade: B.blueWallShade, hi: rgb("#d3e3f0"), dark: shade(B.blueWallShade, 0.88), salt: "eb" };

// ---------------------------------------------------------------- ebais_edificio (12x7 cells = 192x112 px), facing SOUTH
const W = 12, H = 7;
const PORCH_X0 = 32, PORCH_X1 = 160; // porch = cells 2..9
const WALL_Y0 = 48, WALL_Y1 = 80; // stone band + wall rows 3-4
const DOOR = { x: 84, y: 58, w: 24, h: 22 }; // double glass door, centre x = 96
const WIN_Y = 61, WIN_W = 10, WIN_H = 12;
const WINDOWS = [4, 18, 164, 178].map((x) => ({ x, y: WIN_Y, w: WIN_W, h: WIN_H })); // 4 windows with grilles, two in each wing
const OPEN = []; // the porch cells (rows 5-6, cols 2-9) are walkable
for (let cy = 5; cy < H; cy++) for (let cx = 2; cx < 10; cx++) OPEN.push([cx, cy]);

/** Stone cladding: staggered rows of irregular stones with dark mortar. */
function stoneBand(f, x, y, w, h) {
  f.rect(x, y, w, h, MORTAR);
  let yy = y;
  for (let row = 0; yy < y + h; row++) {
    const rh = row % 2 === 0 ? 5 : 5;
    let xx = x - (row % 2 ? 4 : 0);
    while (xx < x + w) {
      const sw = 5 + Math.floor(noise("ebs", xx, row) * 5);
      const col = STONES[Math.floor(noise("ebc", xx, row) * STONES.length) % STONES.length];
      f.rect(xx + 1, yy, sw - 1, rh - 1, col);
      f.hline(xx + 1, yy, sw - 1, shade(col, 1.18));
      f.hline(xx + 1, yy + rh - 2, sw - 1, shade(col, 0.82));
      xx += sw;
    }
    yy += rh;
  }
}

function grilleWindow(f, w) {
  const { x, y, w: ww, h } = w;
  f.rect(x - 1, y - 1, ww + 2, h + 2, B.whiteTrim);
  f.rect(x, y, ww, h, B.glass);
  f.rect(x, y, ww, 3, B.glassHi);
  f.hline(x, y + h - 2, ww, B.glassDark); f.hline(x, y + h - 1, ww, B.glassDark);
  for (let i = 2; i < ww; i += 3) f.vline(x + i, y, h, B.whiteTrim); // white security grille
  f.hline(x, y + Math.round(h / 2), ww, B.whiteTrim);
  f.rect(x - 2, y + h + 1, ww + 4, 2, B.whiteTrimShade); f.hline(x - 2, y + h + 1, ww + 4, B.whiteTrim); // sill
}

function glassDoor(f, d) {
  const { x, y, w, h } = d;
  f.rect(x - 2, y - 2, w + 4, h + 2, B.whiteTrim);
  f.hline(x - 2, y - 2, w + 4, B.whiteTrimShade);
  f.vline(x - 2, y - 2, h + 2, B.whiteTrimShade);
  const half = w / 2;
  for (const lx of [x, x + half]) {
    f.rect(lx, y, half, h, B.glassDark);
    f.rect(lx + 1, y + 1, half - 2, h - 2, B.glass);
    f.rect(lx + 1, y + 1, half - 2, 4, B.glassHi);
    f.hline(lx + 1, y + h - 5, half - 2, B.glassDark);
    f.hline(lx, y + 9, half, B.whiteTrim); // push bar
  }
  f.vline(x + half - 1, y, h, B.whiteTrim); f.vline(x + half, y, h, B.whiteTrimShade);
  f.px(x + half - 3, y + 11, B.metal); f.px(x + half + 2, y + 11, B.metal);
}

function column(f, x, y0, y1) {
  f.rect(x, y0, 6, y1 - y0 + 1, B.whiteTrim);
  f.vline(x, y0, y1 - y0 + 1, shade(B.whiteTrim, 1.0));
  f.vline(x + 5, y0, y1 - y0 + 1, B.whiteTrimShade);
  f.vline(x + 4, y0, y1 - y0 + 1, shade(B.whiteTrimShade, 1.05));
  f.rect(x - 1, y1 - 1, 8, 2, B.whiteTrimShade);
}

/** Yellow railing along the straight line p0 -> p1: a post every ~9 px and a rail joining the post tops. */
function railing(f, p0, p1, h = 6) {
  const [x0, y0] = p0, [x1, y1] = p1;
  const n = Math.max(2, Math.round(Math.hypot(x1 - x0, y1 - y0) / 9));
  let prev = null;
  for (let i = 0; i <= n; i++) {
    const x = Math.round(x0 + ((x1 - x0) * i) / n), y = Math.round(y0 + ((y1 - y0) * i) / n);
    f.rect(x, y - h, 2, h + 1, YEL.base); f.vline(x, y - h, h + 1, YEL.light);
    if (prev) f.line(prev[0] + 1, prev[1] - h, x + 1, y - h, YEL.base);
    prev = [x, y];
  }
}

function drawWall(f) {
  stoneBand(f, 0, WALL_Y0, W * SIZE, 10);
  D.plasterWall(f, 0, 58, W * SIZE, 22, { ...WALL, skirt: 3 });
  for (let y = WALL_Y0; y < WALL_Y0 + 4; y++) f.hline(0, y, W * SIZE, withAlpha([0, 0, 0, 255], 70 - (y - WALL_Y0) * 16)); // eave shadow
  for (const w of WINDOWS) grilleWindow(f, w);
  glassDoor(f, DOOR);
  // ---- covered porch floor (concrete) with the ramp ----
  for (let y = 80; y < H * SIZE; y++) for (let x = PORCH_X0; x < PORCH_X1; x++) f.px(x, y, concreteAt(x, y, 70));
  f.hline(PORCH_X0, 80, PORCH_X1 - PORCH_X0, C.concrete.joint);
  f.rect(PORCH_X0, 81, PORCH_X1 - PORCH_X0, 3, withAlpha([0, 0, 0, 255], 40));
  f.hline(PORCH_X0, H * SIZE - 1, PORCH_X1 - PORCH_X0, C.concrete.dark);
  // ramp: a lighter slab that widens toward the street, yellow edges and yellow step stripes
  const ramp = [[80, 80], [112, 80], [126, 111], [66, 111]];
  const edgeX = (y, side) => (side === 0 ? 80 - ((y - 80) * 14) / 31 : 112 + ((y - 80) * 14) / 31);
  D.fillPoly(f, ramp, (x, y) => shade(concreteAt(x, y, 71), 1.07));
  for (let y = 80; y < 112; y++) {
    for (const side of [0, 1]) {
      const ex = Math.round(edgeX(y, side));
      f.rect(side === 0 ? ex - 1 : ex - 1, y, 3, 1, YEL.base);
      f.px(side === 0 ? ex - 1 : ex + 1, y, YEL.dark);
    }
  }
  for (const y of [90, 98, 106]) f.hline(Math.round(edgeX(y, 0)), y, Math.round(edgeX(y, 1) - edgeX(y, 0)), YEL.base);
  railing(f, [Math.round(edgeX(84, 0)) - 3, 84], [Math.round(edgeX(108, 0)) - 3, 108]);
  railing(f, [Math.round(edgeX(84, 1)) + 3, 84], [Math.round(edgeX(108, 1)) + 3, 108]);
  // white square columns holding the porch roof
  for (const x of [PORCH_X0 + 1, 62, 128, PORCH_X1 - 7]) column(f, x, 84, 110); // trims stay inside the porch cells (x 32..159)
}
const drawWallLit = (f) => {
  for (const w of WINDOWS) D.plainWindow(f, w.x, w.y, w.w, w.h, { lit: true, bar: true });
  D.plainWindow(f, DOOR.x + 1, DOOR.y + 1, DOOR.w - 2, DOOR.h - 6, { lit: true });
};

function drawRoof(f) {
  D.hipRoof(f, 0, 0, W * SIZE, 47, ROOF, { top: 14, side: 22, frontTrim: 4, salt: "ebr" });
  // lower porch roof (blue corrugated zinc) and its wooden-slat eave
  D.gableRoof(f, PORCH_X0, 80, PORCH_X1 - PORCH_X0, 15, ROOF, { ridge: 5, frontTrim: 3, salt: "ebp" });
  for (let y = 95; y < 104; y++) for (let x = PORCH_X0; x < PORCH_X1; x++) {
    const slat = (x - PORCH_X0) % 4 === 0;
    f.px(x, y, slat ? SLAT.dark : (y === 95 ? SLAT.light : noise("ebw", x, y) < 0.1 ? shade(SLAT.base, 0.9) : SLAT.base));
  }
  f.hline(PORCH_X0, 103, PORCH_X1 - PORCH_X0, SLAT.dark);
  for (let y = 104; y < 108; y++) f.hline(PORCH_X0, y, PORCH_X1 - PORCH_X0, withAlpha([0, 0, 0, 255], 55 - (y - 104) * 14));
}

const EBAIS_BUILDINGS = [{
  name: "ebais_edificio", roof_of: "ebais_edificio", sheet: "ebais", w: W, h: H, footRows: [1, 5], open: OPEN,
  windows: WINDOWS, doors: [96], door: { cx: 6, cy: 5, w: 32 }, draw: drawWall, drawRoof, drawLit: drawWallLit,
}];

// ---------------------------------------------------------------- singles (floors, parking line, bench, plant, bin)
function singles() {
  const T = [];
  const add = (row, col, name, layer, props, draw) => T.push({ id: id(row, col), name, layer, ...props, draw });
  const K = { surface: "concreto" };
  const floor = (v) => (f) => f.fill((x, y) => shade(concreteAt(x, y, v), 1.04));
  add(0, 12, "ebais_piso_a", "ground", K, (f) => { floor(80)(f); f.hline(0, 15, 16, C.concrete.joint); f.vline(15, 0, 16, C.concrete.joint); f.hline(0, 0, 16, C.concrete.light); });
  add(0, 13, "ebais_piso_b", "ground", K, (f) => { floor(81)(f); f.hline(0, 7, 16, C.concrete.joint); f.hline(0, 15, 16, C.concrete.joint); f.vline(8, 0, 7, C.concrete.joint); f.vline(4, 8, 7, C.concrete.joint); });
  add(0, 14, "ebais_piso_grieta", "ground", K, (f) => {
    floor(82)(f); f.hline(0, 15, 16, C.concrete.joint); f.vline(15, 0, 16, C.concrete.joint);
    f.line(10, 0, 8, 5, C.concrete.joint); f.line(8, 5, 11, 10, C.concrete.joint); f.line(8, 5, 3, 7, C.concrete.stain);
  });
  add(0, 15, "ebais_parqueo_linea", "ground", K, (f) => { floor(83)(f); f.hline(0, 15, 16, C.concrete.joint); f.vline(7, 0, 16, rgb("#ecebe3")); f.vline(8, 0, 16, rgb("#d6d5cc")); });
  const solid = { solid: true };
  // blue plastic bench, front view
  add(1, 12, "ebais_banca", "ysort", solid, (f) => {
    f.ellipse(8, 14, 7, 2, SH);
    f.rect(2, 3, 12, 6, BENCH.base); f.hline(2, 3, 12, BENCH.light); f.hline(2, 8, 12, BENCH.dark); // moulded backrest
    for (const x of [4, 7, 10]) f.vline(x, 4, 4, BENCH.deep); // backrest slots
    f.rect(1, 9, 14, 3, BENCH.light); f.hline(1, 11, 14, BENCH.dark); // seat
    f.rect(2, 12, 2, 3, C.post.arm); f.rect(12, 12, 2, 3, C.post.arm); // metal legs
  });
  add(1, 13, "ebais_maceta", "ysort", solid, (f) => { D.pottedPlant(f, 3, 15, { flowers: true }); });
  // blue plastic drum bin on a post
  add(1, 14, "ebais_basurero", "ysort", solid, (f) => {
    f.ellipse(8, 14, 5, 1.8, SH);
    f.rect(7, 11, 2, 4, C.post.arm);
    f.rect(4, 2, 8, 10, BENCH.base); f.vline(4, 2, 10, BENCH.light); f.vline(5, 2, 10, BENCH.light); f.vline(11, 2, 10, BENCH.dark);
    f.rect(3, 1, 10, 2, BENCH.dark); f.hline(3, 1, 10, BENCH.light); f.hline(4, 6, 8, BENCH.dark);
  });
  return T;
}

const GLYPHS = {
  E: ["111", "100", "110", "100", "111"], B: ["110", "101", "110", "101", "110"], A: ["010", "101", "111", "101", "101"],
  I: ["111", "010", "010", "010", "111"], S: ["111", "100", "111", "001", "111"],
};
function objects() {
  const cell = (name, cx, cy, row, col, layer, props = {}) => ({ cx, cy, id: id(row, col), name: `${name}_${cx}_${cy}`, layer, ...props });
  // sign board 2x1 on two posts: solid like a post
  return [{
    name: "ebais_rotulo", w: 2, h: 1,
    cells: [cell("ebais_rotulo", 0, 0, 2, 12, "ysort", { solid: true }), cell("ebais_rotulo", 1, 0, 2, 13, "ysort", { solid: true })],
    draw(f) {
      f.ellipse(7, 15, 5, 1.4, SH); f.ellipse(25, 15, 5, 1.4, SH);
      for (const x of [5, 25]) { f.rect(x, 9, 3, 7, B.wood); f.vline(x, 9, 7, B.woodLight); f.vline(x + 2, 9, 7, B.woodDark); }
      const blue = rgb("#2a5a9a");
      f.rect(1, 1, 30, 10, B.whiteTrim); f.rect(1, 1, 30, 1, blue); f.rect(1, 10, 30, 1, blue); f.vline(1, 1, 10, blue); f.vline(30, 1, 10, blue);
      f.hline(2, 9, 28, B.whiteTrimShade);
      "EBAIS".split("").forEach((ch, i) => GLYPHS[ch].forEach((row, j) => [...row].forEach((v, k) => { if (v === "1") f.px(7 + i * 4 + k, 3 + j, blue); })));
    },
  }];
}

// ---------------------------------------------------------------- assemble
const nonEmpty = (fr) => fr.data.some((v, i) => i % 4 === 3 && v > 0);
const ROOF_ROW0 = 0, WALL_ROW0 = 7, LIT_BASE_ID = id(14, 0);
const canvases = new Map();
let nextLit = LIT_BASE_ID;
for (const b of EBAIS_BUILDINGS) {
  const wall = new Frame(b.w * SIZE, b.h * SIZE); b.draw(wall);
  const roof = new Frame(b.w * SIZE, b.h * SIZE); b.drawRoof(roof);
  const lit = new Frame(b.w * SIZE, b.h * SIZE); b.drawLit(lit);
  const day = new Frame(b.w * SIZE, b.h * SIZE); day.blit(wall, 0, 0); day.blit(roof, 0, 0); // whole picture for previews
  canvases.set(b.name, { day, wall, roof, lit });
  b.cells = []; b.lit = [];
  const open = new Set(b.open.map(([cx, cy]) => `${cx},${cy}`));
  for (let cy = 0; cy < b.h; cy++) for (let cx = 0; cx < b.w; cx++) {
    if (nonEmpty(wall.slice(cx * SIZE, cy * SIZE, SIZE, SIZE))) {
      const c = { cx, cy, id: id(WALL_ROW0 + cy, cx), name: `${b.name}_${cx}_${cy}`, layer: "ysort", building: b.name, part: "wall" };
      if (open.has(`${cx},${cy}`)) c.sort_offset = -16; else c.solid = true;
      b.cells.push(c);
    }
    if (nonEmpty(roof.slice(cx * SIZE, cy * SIZE, SIZE, SIZE))) b.cells.push({ cx, cy, id: id(ROOF_ROW0 + cy, cx), name: `${b.name}_techo_${cx}_${cy}`, layer: "above", building: b.name, part: "roof" });
    if (nonEmpty(lit.slice(cx * SIZE, cy * SIZE, SIZE, SIZE))) b.lit.push({ cx, cy, id: nextLit++, name: `${b.name}_lit_${cx}_${cy}`, layer: "ysort", sort_offset: 1, building: b.name });
  }
}
if (nextLit > id(16, 0)) throw new Error(`too many ebais lit cells: ${nextLit - LIT_BASE_ID}`);

const S = singles();
const O = objects();
export { EBAIS_BUILDINGS };
export const EBAIS_BUILDING_BY_NAME = new Map(EBAIS_BUILDINGS.map((b) => [b.name, b]));
export const E_TILES = [...S];
for (const o of O) for (const c of o.cells) E_TILES.push({ ...c, object: o.name });
for (const b of EBAIS_BUILDINGS) { for (const c of b.cells) E_TILES.push(c); for (const c of b.lit) E_TILES.push(c); }
E_TILES.sort((a, b) => a.id - b.id);
{
  const ids = new Set(), names = new Set();
  for (const t of E_TILES) {
    if (t.id < 0 || t.id >= E_COLS * E_ROWS) throw new Error(`id out of ebais sheet: ${t.name} ${t.id}`);
    if (ids.has(t.id)) throw new Error(`duplicate ebais id ${t.id} (${t.name})`);
    if (names.has(t.name)) throw new Error(`duplicate ebais name ${t.name}`);
    if (!t.name.startsWith("ebais_")) throw new Error(`ebais tile without ebais_ prefix: ${t.name}`);
    ids.add(t.id); names.add(t.name);
  }
}
export const eIdByName = new Map(E_TILES.map((t) => [t.name, t.id]));

export function renderEbaisSheet() {
  const sheet = new Frame(E_COLS * SIZE, E_ROWS * SIZE);
  const put = (tid, fr) => sheet.blit(fr, (tid % E_COLS) * SIZE, Math.floor(tid / E_COLS) * SIZE);
  for (const t of S) { const f = new Frame(SIZE, SIZE); t.draw(f, tileRng(t.name)); put(t.id, f); }
  for (const o of O) {
    const canvas = new Frame(o.w * SIZE, o.h * SIZE);
    o.draw(canvas, tileRng(o.name));
    for (const c of o.cells) put(c.id, canvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  for (const b of EBAIS_BUILDINGS) {
    const { wall, roof, lit } = canvases.get(b.name);
    for (const c of b.cells) put(c.id, (c.part === "roof" ? roof : wall).slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
    for (const c of b.lit) put(c.id, lit.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  return sheet;
}

export const ebaisBuildingCanvas = (name) => canvases.get(name);
