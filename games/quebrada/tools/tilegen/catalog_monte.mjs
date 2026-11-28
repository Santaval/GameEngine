// Monte sheet (monte.png + monte.tsx): the monte de hule y nispero and the wind turbines (aerogeneradores) of zone 1 (first-pass procedural art).
// Sixth tileset of zona1.tmx. Sheet: 16 columns x 16 rows of 16x16 tiles, id = row * 16 + col; ids are handed out in order by an allocator (see the
// order of `alloc()` calls below), the rest of the sheet is reserved (transparent). Every tile name starts with `monte_`.
// Contents:
//   ground    monte_grass_a/b/c (dark monte grass, surface zacate), monte_litter_a/b (leaf litter, zacate), monte_mud_a/b (mud, lastre),
//             monte_road_edge_n/s (asphalt road with a grass shoulder, concreto), monte_road_line_n/s (the two halves of the double yellow line, concreto),
//             monte_pad_a/b (the concrete pad of a turbine, concreto)
//   props     monte_fern_a/b (ysort, walk-through), monte_bush, monte_log, monte_rock_moss (ysort, solid)
//   trees     hule: monte_hule_trunk (ysort, solid) + monte_hule_shaft (above) + monte_hule_canopy_<cx>_<cy> (3x3, above)
//             nispero: monte_nispero_trunk (ysort, solid) + monte_nispero_canopy_<cx>_<cy> (3x2, above)
//   tower     monte_tower_0_<cy> (1x10 cells): cy 0 = nacelle, 1-8 = shaft (above), 9 = base with a door (ysort, solid)
//   rotor     9x9 cells = 144x144 px, 3 blades, 4 angles (0, 30, 60, 90 degrees; 3-blade symmetry = a 120 degree cycle). Per cell (cx,cy):
//             monte_rotor_<cx>_<cy>  (angle 0 picture; carries the <animation> in the tsx) and monte_rotor_<cx>_<cy>_f<k> (k = 1..3, the other angles);
//             monte_rotor_blank is the transparent frame of a cell that is empty at that angle. All `above`.
// Property scheme as town.tsx: name, layer (ground|overlay|ysort|above), surface (non-solid ground only), solid (ysort only), sort_offset.
import { Frame, rgb, shade, withAlpha, mix } from "./draw.mjs";
import { C } from "./palette.mjs";
import { noise, tileRng as tileRngFor } from "./rng.mjs";
import { grassAt, lastreAt, asphaltAt, concreteAt, soilAt } from "./materials.mjs";
import { TILES as TOWN_TILES } from "./catalog.mjs";

export const SIZE = 16;
export const M_COLS = 16;
export const M_ROWS = 16;
export const TOWER_H = 10; // cells: nacelle (cy 0), shaft (1-8), base (9)
export const ROTOR_N = 9; // rotor = 9x9 cells (the hub is the centre cell (4,4), right above the tower's nacelle cell)
export const ROTOR_FRAMES = 4; // 0, 30, 60, 90 degrees
export const ROTOR_STEP = 30; // degrees between frames (3 blades: 120 degrees cycle = 4 frames)
export const ROTOR_MS = 400; // duration of each frame (ms): a full 120 degree cycle every 1.6 s
const SH = withAlpha([0, 0, 0, 255], 70);

const PAL = {
  hule: { deep: rgb("#0f3322"), dark: rgb("#164a2d"), base: rgb("#1e5f38"), light: rgb("#2f7f4b"), hi: rgb("#58a96b"), spec: rgb("#9fd9a6") },
  nispero: { deep: rgb("#1f3a1d"), dark: rgb("#2c5226"), base: rgb("#3b6a2e"), light: rgb("#58883e"), hi: rgb("#7fa851") },
  huleBark: { bark: rgb("#7b6a5e"), barkDark: rgb("#4f4339"), barkLight: rgb("#988777") },
  nisperoBark: { bark: rgb("#6e4f3a"), barkDark: rgb("#44301f"), barkLight: rgb("#8a6a50") },
  fruit: rgb("#9a6a3a"), fruitDark: rgb("#6e4526"),
  white: { hi: rgb("#fbfcfa"), base: rgb("#eef1ef"), shade: rgb("#cdd5d6"), dark: rgb("#a7b2b5"), edge: rgb("#7f8d92") },
};

// ---------------------------------------------------------------- drawing helpers
/** Leaf-mass canopy from circular lobes (as catalog_plants.mjs) with an optional glossy specular pass. */
function canopy(f, lobes, pal, salt, opts = {}) {
  const ragged = opts.ragged ?? 0.22;
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) {
    let best = null;
    for (const [cx, cy, rad] of lobes) {
      const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / rad;
      if (d <= 1 && (!best || d < best.d)) best = { d, dx: (x + 0.5 - cx) / rad, dy: (y + 0.5 - cy) / rad };
    }
    if (!best) continue;
    const n = 0.55 * noise(salt + "c", x >> 1, y >> 1) + 0.45 * noise(salt, x, y);
    if (best.d > 0.86 && noise(salt + "r", x, y) < ragged) continue;
    let v = 0.52 - (best.dx * 0.5 + best.dy * 0.75) * 0.34 + (n - 0.5) * 0.5 - best.d * 0.06;
    if (best.d > 0.72 && best.dy > 0.1) v -= 0.22;
    const c = v < 0.2 ? pal.deep : v < 0.38 ? pal.dark : v < 0.66 ? pal.base : v < 0.82 ? pal.light : pal.hi;
    f.px(x, y, c);
    if (opts.gloss && v > 0.7 && noise(salt + "g", x, y) < 0.3) f.px(x, y, pal.spec); // glossy leaf highlights
  }
}

function trunk(f, x0, x1, pal, salt, flare = 2, h = 16) {
  f.ellipse(8, 13, 7.5, 2.6, SH);
  for (let y = 0; y < h; y++) {
    const fl = y >= 12 ? (y - 11) * (flare / 4) : 0;
    const a = Math.round(x0 - fl), b = Math.round(x1 + fl);
    for (let x = a; x <= b; x++) {
      const n = noise(salt, x, y);
      const edge = x === a ? 0.8 : x === b ? 0.7 : 1;
      let c = x - a < (b - a) * 0.3 ? pal.barkLight : pal.bark;
      if (n < 0.28 || (x + (y >> 2)) % 5 === 0) c = pal.barkDark;
      f.px(x, y, edge < 1 ? shade(c, edge) : c);
    }
  }
  f.hline(x0 - 1, h - 1, x1 - x0 + 3, pal.barkDark);
}

/** Straight trunk piece without the ground shadow (the hule's upper trunk, drawn above the hero). */
function shaft(f, x0, x1, pal, salt) {
  for (let y = 0; y < 16; y++) for (let x = x0; x <= x1; x++) {
    const n = noise(salt, x, y);
    let c = x - x0 < (x1 - x0) * 0.3 ? pal.barkLight : pal.bark;
    if (n < 0.22 || (x + (y >> 3)) % 5 === 0) c = pal.barkDark;
    f.px(x, y, x === x0 ? shade(c, 0.85) : x === x1 ? shade(c, 0.72) : c);
  }
}

// ---------------------------------------------------------------- the tower (1x10 cells = 16x160)
function drawTower(f) {
  const W = PAL.white;
  const halfAt = (y) => 2.6 + (Math.min(Math.max(y - 12, 0), 138) / 138) * 2.2; // 2.6 px at the top -> 4.8 px at the foot (y 150)
  // base ground shadow, in the base cell only (y 144-159)
  f.ellipse(9, 153, 8, 2.6, SH);
  // shaft + base flare
  for (let y = 10; y < 160; y++) {
    let hw = halfAt(y);
    if (y >= 148) hw += (y - 147) * 0.35; // flange at the foot
    const c0 = Math.round(8 - hw), c1 = Math.round(8 + hw - 0.01);
    for (let x = c0; x <= c1; x++) {
      const t = (x - c0) / Math.max(1, c1 - c0);
      let c = t < 0.28 ? W.hi : t < 0.7 ? W.base : t < 0.9 ? W.shade : W.dark;
      if (x === c0 || x === c1) c = shade(c, 0.85);
      f.px(x, y, c);
    }
    if ((y - 10) % 34 === 0 && y > 12 && y < 148) f.hline(c0, y, c1 - c0 + 1, W.dark); // section joints
  }
  f.hline(4, 159, 9, W.edge);
  // the door at the foot
  f.rect(6, 143, 4, 9, rgb("#4b5961")); f.vline(6, 143, 9, W.edge); f.vline(9, 143, 9, W.edge); f.hline(6, 143, 4, W.edge); f.px(8, 148, W.hi);
  // nacelle (cell 0): a body a little wider than the hub, with the warning lamp on top; the rotor's hub (drawn over it) covers its middle
  f.rect(3, 5, 10, 8, W.base); f.hline(3, 5, 10, W.hi); f.rect(3, 11, 10, 2, W.shade); f.vline(3, 5, 8, W.shade); f.vline(12, 5, 8, W.dark);
  f.rect(6, 12, 4, 2, W.dark);
  f.rect(7, 0, 2, 2, rgb("#e0382e")); f.px(7, 0, rgb("#ff7a6a"));
}

// ---------------------------------------------------------------- the rotor (9x9 cells = 144x144), angle in degrees (blade 0 points up at angle 0)
const R = ROTOR_N * SIZE; // 144
function drawRotor(alpha) {
  const f = new Frame(R, R);
  const W = PAL.white;
  const half = (r) => (r < 14 ? 2.0 + (r - 4) * 0.14 : 3.4 - ((r - 14) / (67 - 14)) * 2.6);
  const dirs = [0, 1, 2].map((k) => { const a = ((-90 + alpha + 120 * k) * Math.PI) / 180; return [Math.cos(a), Math.sin(a)]; });
  for (let y = 0; y < R; y++) for (let x = 0; x < R; x++) {
    const px = x + 0.5 - R / 2, py = y + 0.5 - R / 2;
    for (const [dx, dy] of dirs) {
      const along = px * dx + py * dy, perp = -px * dy + py * dx;
      if (along < 3 || along > 67) continue;
      const hw = half(along);
      if (Math.abs(perp) > hw) continue;
      const edge = hw > 1.7 && Math.abs(perp) > hw - 0.85;
      f.px(x, y, edge ? W.edge : perp < -hw * 0.25 ? W.hi : perp > hw * 0.45 ? W.shade : W.base);
      break;
    }
  }
  // hub spinner: a small dome
  const hr = 6.6;
  for (let y = 0; y < R; y++) for (let x = 0; x < R; x++) {
    const px = x + 0.5 - R / 2, py = y + 0.5 - R / 2, d = Math.hypot(px, py);
    if (d > hr) continue;
    const l = (-px * 0.5 - py * 0.7) / hr;
    f.px(x, y, d > hr - 1 ? W.edge : l > 0.35 ? W.hi : l > -0.1 ? W.base : l > -0.45 ? W.shade : W.dark);
  }
  return f;
}

// ---------------------------------------------------------------- ground singles and props
function groundSingles() {
  const T = [];
  const add = (name, layer, props, draw) => T.push({ name, layer, ...props, draw });
  const Z = { surface: "zacate" }, L = { surface: "lastre" }, K = { surface: "concreto" };
  const dark = (c, f = 0.8) => shade(c, f);
  const monteGrass = (x, y, v) => {
    const r = noise("mgr", x, y, v);
    const base = grassAt(x, y, 20 + v);
    return r < 0.12 ? dark(C.zacate.dark, 0.85) : r < 0.5 ? dark(base, 0.82) : dark(base, 0.9);
  };
  for (let v = 0; v < 3; v++) {
    add(`monte_grass_${"abc"[v]}`, "ground", Z, (f, r) => {
      f.fill((x, y) => monteGrass(x, y, v));
      for (let i = 0; i < 3 + v; i++) { const x = r.int(2, 13), y = r.int(4, 13); f.px(x, y, C.zacate.tall); f.px(x, y - 1, dark(C.zacate.light, 0.8)); f.px(x - 1, y - 2, dark(C.zacate.light, 0.8)); }
    });
  }
  const litterCols = [rgb("#7a5a34"), rgb("#946c3c"), rgb("#5f4528"), rgb("#a98550")];
  for (let v = 0; v < 2; v++) {
    add(`monte_litter_${"ab"[v]}`, "ground", Z, (f, r) => {
      f.fill((x, y) => (noise("mlt", x, y, v) < 0.82 ? dark(grassAt(x, y, 30 + v), 0.66) : mix(dark(C.soil.base, 0.9), dark(C.zacate.dark, 0.8), 0.3)));
      for (let i = 0; i < 12 + v * 4; i++) { const x = r.int(1, 14), y = r.int(1, 14), c = litterCols[i % litterCols.length]; f.px(x, y, c); f.px(x + 1, y, c); f.px(x, y + 1, dark(c, 0.8)); }
    });
  }
  for (let v = 0; v < 2; v++) {
    add(`monte_mud_${"ab"[v]}`, "ground", L, (f, r) => {
      f.fill((x, y) => { const s = soilAt(x, y, 10 + v); return noise("mmd", x, y, v) < 0.3 ? mix(dark(grassAt(x, y, 40 + v), 0.7), C.lastre.wet, 0.5) : mix(s, C.lastre.wet, 0.5); });
      for (let i = 0; i < 3; i++) f.px(r.int(2, 13), r.int(2, 13), withAlpha(C.river.light, 130));
      f.ellipse(8 + v * 2 - 1, 8, 4.5, 2.4, withAlpha(C.river.mudDark, 120));
    });
  }
  // asphalt road with a grass shoulder: the shoulder fades the outer 3 rows (n = top, s = bottom) into grass; tufts overhang the asphalt
  const roadEdge = (side) => (f) => {
    f.fill((x, y) => asphaltAt(x, y, noise("mre", x, y, 1) < 0.5 ? 0 : 1));
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const d = side === "n" ? y : 15 - y;
      const cut = 2.4 + noise("mrc", x, side === "n" ? 1 : 2) * 2.2; // ragged shoulder 2.4-4.6 px
      if (d + 0.5 < cut) f.px(x, y, d + 0.5 < cut - 1.1 ? grassAt(x, y, 0) : C.zacate.dark);
      else if (d + 0.5 < cut + 0.9) f.px(x, y, C.lastre.stoneDark); // gravel rim
    }
  };
  add("monte_road_edge_n", "ground", K, roadEdge("n"));
  add("monte_road_edge_s", "ground", K, roadEdge("s"));
  // double yellow centre line of the 4-wide road, split over its two middle rows (row 1: line at y=14, row 2: line at y=1; 2 px gap, as asphalt_line_h)
  const yellow = C.asphalt.yellow;
  add("monte_road_line_n", "ground", K, (f) => { f.fill((x, y) => asphaltAt(x, y, 4)); f.hline(0, 14, 16, yellow); for (let x = 0; x < 16; x++) if (noise("wl", x, 3) < 0.15) f.px(x, 14, shade(yellow, 0.8)); });
  add("monte_road_line_s", "ground", K, (f) => { f.fill((x, y) => asphaltAt(x, y, 5)); f.hline(0, 1, 16, yellow); for (let x = 0; x < 16; x++) if (noise("wl", x, 4) < 0.15) f.px(x, 1, shade(yellow, 0.8)); });
  // concrete pad of a turbine
  const pad = (v, joints) => (f) => { f.fill((x, y) => shade(concreteAt(x, y, 90 + v), 1.03)); joints(f); };
  add("monte_pad_a", "ground", K, pad(0, (f) => { f.hline(0, 15, 16, C.concrete.joint); f.vline(15, 0, 16, C.concrete.joint); f.hline(0, 0, 16, C.concrete.light); }));
  add("monte_pad_b", "ground", K, pad(1, (f) => { f.hline(0, 7, 16, C.concrete.joint); f.hline(0, 15, 16, C.concrete.joint); f.vline(8, 0, 7, C.concrete.joint); f.vline(4, 8, 8, C.concrete.joint); }));
  // undergrowth props
  const solid = { solid: true };
  const fern = (salt) => (f, r) => {
    f.ellipse(8, 13, 6, 2, SH);
    for (const ang of [-160, -130, -100, -80, -50, -20]) {
      const a = (ang * Math.PI) / 180, len = 6 + noise(salt, ang, 0) * 3;
      for (let t = 0; t <= len; t += 0.5) {
        const x = 8 + Math.cos(a) * t, y = 13 + Math.sin(a) * t * 0.9 + (t * t) * 0.03;
        f.px(x, y, t < len * 0.5 ? C.palm.dark : C.palm.light);
        if (t > 2 && t < len - 1) { f.px(x, y - 1, C.palm.frond); f.px(x, y + 1, C.palm.dark); }
      }
    }
  };
  add("monte_fern_a", "ysort", { sort_offset: -2 }, fern("fnA"));
  add("monte_fern_b", "ysort", { sort_offset: -2 }, fern("fnB"));
  add("monte_bush", "ysort", solid, (f) => {
    f.ellipse(8, 13, 7.5, 2.4, SH);
    canopy(f, [[5, 9, 5], [11, 9, 5], [8, 6, 5.5], [8, 10.5, 5]], { deep: PAL.nispero.deep, dark: PAL.nispero.dark, base: PAL.nispero.base, light: PAL.nispero.light, hi: PAL.nispero.hi }, "mbu", { ragged: 0.2 });
    for (let i = 0; i < 5; i++) { const x = 3 + Math.floor(noise("mbx", i, 0) * 10), y = 4 + Math.floor(noise("mby", i, 0) * 8); if (f.get(x, y)[3]) f.px(x, y, i % 2 ? C.flower.pink : C.flower.white); }
  });
  add("monte_log", "ysort", solid, (f) => {
    f.ellipse(8, 13, 7.5, 2.2, SH);
    f.rect(1, 7, 14, 6, PAL.nisperoBark.bark); f.hline(1, 7, 14, PAL.nisperoBark.barkLight); f.hline(1, 12, 14, PAL.nisperoBark.barkDark);
    for (const x of [4, 8, 11]) f.vline(x, 8, 4, PAL.nisperoBark.barkDark);
    f.ellipse(2, 10, 1.6, 3, C.wood.light); f.ellipse(2, 10, 0.8, 1.4, C.wood.base); // cut end
    f.rect(9, 5, 3, 2, C.zacate.dark); f.px(10, 4, C.zacate.light); // moss
  });
  add("monte_rock_moss", "ysort", solid, (f) => {
    f.ellipse(8, 13, 7, 2.2, SH);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const d = Math.hypot((x + 0.5 - 8) / 1.2, y + 0.5 - 9) / 6;
      if (d > 1) continue;
      const v = 0.5 - ((x - 8) * 0.04 + (y - 9) * 0.06) + (noise("mrk", x, y) - 0.5) * 0.3;
      f.px(x, y, y < 6 && noise("mrm", x, y) < 0.5 ? C.zacate.dark : v < 0.32 ? C.rock.dark : v < 0.66 ? C.rock.base : C.rock.light);
    }
  });
  return T;
}

// ---------------------------------------------------------------- assemble: ids by an allocator
let nextId = 0;
const alloc = () => nextId++;
const singles = groundSingles().map((t) => ({ ...t, id: alloc() }));
const objectsList = [];
const addObject = (name, w, h, cellsFn, draw) => {
  const cells = [];
  for (let cy = 0; cy < h; cy++) for (let cx = 0; cx < w; cx++) cells.push({ cx, cy, id: alloc(), ...cellsFn(cx, cy) });
  objectsList.push({ name, w, h, cells, draw });
};
// trees: each cell is its own tile (trunks live in their own cell kinds below)
singles.push({ name: "monte_hule_trunk", layer: "ysort", solid: true, sort_offset: -2, id: alloc(), draw: (f) => trunk(f, 6, 9, PAL.huleBark, "hut", 2) });
singles.push({ name: "monte_hule_shaft", layer: "above", id: alloc(), draw: (f) => shaft(f, 6, 9, PAL.huleBark, "hus") });
singles.push({ name: "monte_nispero_trunk", layer: "ysort", solid: true, sort_offset: -2, id: alloc(), draw: (f) => trunk(f, 4, 11, PAL.nisperoBark, "nit", 3) });
addObject("monte_hule_canopy", 3, 3, (cx, cy) => ({ name: `monte_hule_canopy_${cx}_${cy}`, layer: "above" }), (f) => {
  // tall narrow crown with glossy dark leaves; the lowest row stays clear of the middle column so the shaft shows
  canopy(f, [[24, 20, 15], [13, 26, 10], [35, 26, 10], [24, 9, 9], [15, 14, 8], [33, 14, 8], [24, 33, 7.5], [8, 30, 5], [40, 30, 5]], PAL.hule, "hc", { ragged: 0.26, gloss: true });
});
addObject("monte_nispero_canopy", 3, 2, (cx, cy) => ({ name: `monte_nispero_canopy_${cx}_${cy}`, layer: "above" }), (f) => {
  canopy(f, [[24, 15, 14], [12, 17, 10], [36, 17, 10], [24, 8, 9], [15, 9, 7], [33, 9, 7], [24, 23, 7.5]], PAL.nispero, "nc", { ragged: 0.2 });
  for (let i = 0; i < 26; i++) { // brown fruit among the leaves
    const x = 6 + Math.floor(noise("nfx", i, 0) * 36), y = 4 + Math.floor(noise("nfy", i, 0) * 22);
    if (f.get(x, y)[3]) { f.px(x, y, PAL.fruit); f.px(x + 1, y, PAL.fruitDark); }
  }
});
addObject("monte_tower", 1, TOWER_H, (cx, cy) => (cy === TOWER_H - 1 ? { name: `monte_tower_${cx}_${cy}`, layer: "ysort", solid: true, sort_offset: -2 } : { name: `monte_tower_${cx}_${cy}`, layer: "above" }), drawTower);

// rotor: render the 4 angle pictures, slice into cells, allocate anchors (angle 0) + the other angles' non-empty cells
const nonEmpty = (fr) => fr.data.some((v, i) => i % 4 === 3 && v > 0);
const rotorFrames = Array.from({ length: ROTOR_FRAMES }, (_, k) => drawRotor(k * ROTOR_STEP));
const BLANK = { name: "monte_rotor_blank", layer: "above", id: alloc(), draw: () => {} };
singles.push(BLANK);
export const ROTOR_CELLS = [];
const rotorTiles = []; // { id, name, layer, anim?, frame (Frame) }
for (let cy = 0; cy < ROTOR_N; cy++) for (let cx = 0; cx < ROTOR_N; cx++) {
  const slices = rotorFrames.map((fr) => fr.slice(cx * SIZE, cy * SIZE, SIZE, SIZE));
  if (!slices.some(nonEmpty)) continue;
  const anchor = { id: alloc(), name: `monte_rotor_${cx}_${cy}`, layer: "above", frame: slices[0], cx, cy };
  const ids = [anchor.id];
  for (let k = 1; k < ROTOR_FRAMES; k++) {
    if (nonEmpty(slices[k])) { const t = { id: alloc(), name: `monte_rotor_${cx}_${cy}_f${k}`, layer: "above", frame: slices[k] }; rotorTiles.push(t); ids.push(t.id); } else ids.push(BLANK.id);
  }
  anchor.anim = ids.map((tid) => ({ id: tid, duration: ROTOR_MS }));
  rotorTiles.push(anchor);
  ROTOR_CELLS.push({ cx, cy, name: anchor.name });
}
if (nextId > M_COLS * M_ROWS) throw new Error(`too many monte tiles: ${nextId} > ${M_COLS * M_ROWS}`);

export const M_TILES = [...singles];
for (const o of objectsList) for (const c of o.cells) M_TILES.push({ ...c, object: o.name });
for (const t of rotorTiles) M_TILES.push(t);
M_TILES.sort((a, b) => a.id - b.id);
{
  const townNames = new Set(TOWN_TILES.map((t) => t.name));
  const ids = new Set(), names = new Set();
  for (const t of M_TILES) {
    if (t.id < 0 || t.id >= M_COLS * M_ROWS) throw new Error(`id out of monte sheet: ${t.name} ${t.id}`);
    if (ids.has(t.id)) throw new Error(`duplicate monte id ${t.id} (${t.name})`);
    if (names.has(t.name)) throw new Error(`duplicate monte name ${t.name}`);
    if (townNames.has(t.name)) throw new Error(`monte tile name clashes with a town tile: ${t.name}`);
    if (!t.name.startsWith("monte_")) throw new Error(`monte tile without monte_ prefix: ${t.name}`);
    ids.add(t.id); names.add(t.name);
  }
}
export const mIdByName = new Map(M_TILES.map((t) => [t.name, t.id]));
export const MONTE_TILE_COUNT = M_TILES.length;
export const MONTE_ROTOR_TILE_COUNT = rotorTiles.length + 1; // + monte_rotor_blank

export function renderMonteSheet() {
  const sheet = new Frame(M_COLS * SIZE, M_ROWS * SIZE);
  const put = (tid, fr) => sheet.blit(fr, (tid % M_COLS) * SIZE, Math.floor(tid / M_COLS) * SIZE);
  for (const t of singles) { const f = new Frame(SIZE, SIZE); t.draw(f, tileRngFor(t.name)); put(t.id, f); }
  for (const o of objectsList) {
    const canvas = new Frame(o.w * SIZE, o.h * SIZE);
    o.draw(canvas);
    for (const c of o.cells) put(c.id, canvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  for (const t of rotorTiles) put(t.id, t.frame);
  return sheet;
}

/** A whole turbine picture (rotor at the given frame over the tower) for previews: 144 x (16 * 14 - ...) px, origin = rotor top-left. Returns { frame, w, h }. */
export function turbineCanvas(frameIdx = 0) {
  const tower = new Frame(16, TOWER_H * SIZE); drawTower(tower);
  const out = new Frame(ROTOR_N * SIZE, (4 + TOWER_H) * SIZE);
  out.blit(tower, 4 * SIZE, 4 * SIZE);
  out.blit(rotorFrames[frameIdx], 0, 0);
  return { frame: out, w: out.w, h: out.h, hub: [ROTOR_N * 8, 4 * SIZE + 8] };
}
export { rotorFrames };
