// Rio sheet (rio.png + rio.tsx): the quebrada of zone 1 and the concrete road bridge of the asphalt street (first-pass procedural art, docs/rio.md).
// Seventh tileset of zona1.tmx. Sheet: 16 columns x 4 rows of 16x16 tiles, id = row * 16 + col; ids are handed out in order by an allocator (see the
// order of `add()` calls below), the rest of the sheet is reserved (transparent). Every tile name starts with `rio_`.
// The river itself reuses the town sheet (water_a/b/ripple, bank_<n|e|s|w>, bank_corner_<ne|nw|se|sw>, river_stones, riverside_grass); this sheet only adds what it lacks:
//   water   rio_water_rapids_a/b (white-water streaks, solid), rio_water_dark (deep pool, solid)                    ground, solid, no surface
//   banks   rio_bank_inner_<ne|nw|se|sw> (a bank cell whose only wet side is the diagonal corner), rio_gravel_a/b   ground, surface lastre
//   bridge  rio_deck_curb_w/e (the deck cells under the guard rails, surface concreto)                              ground
//           rio_rail_w/e (rusty yellow-painted guard rail along the deck, solid), rio_post (square concrete post at the rail ends, solid),
//           rio_abutment_w/e (concrete pier at the water edge beside the deck, solid)                               ysort
//   stream  rio_boulder_a/b/c (rocks in the water, solid)                                                           ysort
// Property scheme as town.tsx: name, layer (ground|overlay|ysort|above), surface (non-solid ground only), solid, sort_offset.
import { Frame, rgb, shade, withAlpha, mix } from "./draw.mjs";
import { C } from "./palette.mjs";
import { noise, wobble, tileRng as tileRngFor } from "./rng.mjs";
import { lastreAt, concreteAt, waterAt } from "./materials.mjs";
import { TILES as TOWN_TILES } from "./catalog.mjs";

export const SIZE = 16;
export const R_COLS = 16;
export const R_ROWS = 4;
const SH = withAlpha([0, 0, 0, 255], 70);
const PAINT = { hi: rgb("#f2c94c"), base: rgb("#dba21a"), shade: rgb("#b27a12"), rust: rgb("#a4521e"), rustDark: rgb("#6c3516"), rustLight: rgb("#c4752f") };

let nextId = 0;
const alloc = () => nextId++;
export const R_TILES = [];
const add = (name, layer, props, draw) => R_TILES.push({ id: alloc(), name, layer, ...props, draw });

// ---------------------------------------------------------------- water
const streaks = (f, r, n, len0, len1, col, colEnd) => {
  for (let i = 0; i < n; i++) {
    const x = r.int(0, 15), y = r.int(0, 15), len = r.int(len0, len1);
    for (let k = 0; k < len; k++) f.px((x + k) % 16, y, k === 0 || k === len - 1 ? colEnd : col);
  }
};
add("rio_water_rapids_a", "ground", { solid: true }, (f, r) => {
  f.fill((x, y) => waterAt(x, y, 3));
  streaks(f, r, 6, 3, 7, C.river.light, C.river.mid);
  streaks(f, r, 4, 2, 4, C.river.foam, C.river.light);
  for (let i = 0; i < 6; i++) f.px(r.int(0, 15), r.int(0, 15), C.river.foam);
});
add("rio_water_rapids_b", "ground", { solid: true }, (f, r) => {
  f.fill((x, y) => waterAt(x, y, 4));
  streaks(f, r, 5, 3, 6, C.river.light, C.river.mid);
  f.hline(2, 4, 6, C.river.foam); f.hline(8, 5, 5, C.river.light); f.hline(1, 10, 5, C.river.foam); f.hline(7, 11, 7, C.river.light); f.hline(10, 14, 4, C.river.foam);
  for (let i = 0; i < 5; i++) f.px(r.int(0, 15), r.int(0, 15), C.river.foam);
});
add("rio_water_dark", "ground", { solid: true }, (f, r) => {
  f.fill((x, y) => { const c = waterAt(x, y, 5); return mix(c, C.river.dark, 0.55); });
  streaks(f, r, 2, 3, 5, mix(C.river.mid, C.river.dark, 0.5), C.river.dark);
  f.hline(4, 7, 3, C.river.mid);
});

// ---------------------------------------------------------------- banks
const wetMask = (corner, x, y) => { // wet cap around one corner of the tile (the diagonal neighbour is water)
  const cx = corner.includes("E") ? 15 : 0, cy = corner.includes("S") ? 15 : 0;
  const d = Math.hypot(x - cx, y - cy);
  return d + 0.5 < 5.4 + wobble("rbk" + corner, x + y, 1.1);
};
for (const corner of ["NE", "NW", "SE", "SW"]) {
  add(`rio_bank_inner_${corner.toLowerCase()}`, "ground", { surface: "lastre" }, (f) => {
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      let c = lastreAt(x, y, 7);
      if (wetMask(corner, x, y)) {
        const cx = corner.includes("E") ? 15 : 0, cy = corner.includes("S") ? 15 : 0;
        c = noise("mud", x, y) < 0.25 ? C.river.mudDark : C.river.mud;
        if (Math.hypot(x - cx, y - cy) < 1.8) c = noise("foam", x, y) < 0.35 ? C.river.foam : mix(C.river.mudDark, C.river.base, 0.5);
      }
      f.px(x, y, c);
    }
  });
}
for (const [n, v] of [["a", 20], ["b", 21]]) {
  add(`rio_gravel_${n}`, "ground", { surface: "lastre" }, (f, r) => {
    f.fill((x, y) => { const q = noise("grv", x, y, v); return q < 0.3 ? C.river.stoneDark : q > 0.82 ? C.rock.light : q > 0.55 ? C.river.stone : lastreAt(x, y, v); });
    for (let i = 0; i < 5; i++) { const x = r.int(1, 13), y = r.int(1, 13); f.px(x, y, C.rock.light); f.px(x + 1, y, C.river.stone); f.px(x, y + 1, C.river.stoneDark); }
  });
}

// ---------------------------------------------------------------- bridge
for (const side of ["w", "e"]) {
  add(`rio_deck_curb_${side}`, "ground", { surface: "concreto" }, (f) => {
    f.fill((x, y) => concreteAt(x, y, side === "w" ? 11 : 12));
    const edge = side === "w" ? 0 : 15; // the outer edge of the deck
    f.vline(edge, 0, 16, C.concrete.joint);
    f.vline(side === "w" ? 1 : 14, 0, 16, C.concrete.dark);
    f.vline(side === "w" ? 14 : 1, 0, 16, C.concrete.light);
    for (const y of [3, 11]) f.hline(0, y, 16, C.concrete.joint); // expansion seams
    f.hline(0, 15, 16, C.concrete.joint);
  });
}
/** Guard rail running north-south along the deck edge: a yellow beam (rust-streaked) with square posts; seen from above it is a thin vertical bar with its nubs. */
function rail(f, x0, salt) {
  f.rect(x0 + 3, 12, 5, 3, SH); // shadow on the deck
  for (let y = 0; y < 16; y++) for (let k = 0; k < 4; k++) {
    const x = x0 + k, n = noise(salt, x, y);
    let c = k === 0 ? PAINT.hi : k === 3 ? PAINT.shade : PAINT.base;
    if (n < 0.16) c = PAINT.rust; else if (n < 0.24) c = PAINT.rustLight; else if (n > 0.93) c = PAINT.rustDark; // flaking paint, rust bleeding through
    f.px(x, y, c);
  }
  for (const y of [1, 8]) { // the post nubs (the posts holding the beam)
    f.rect(x0 - 1, y, 6, 4, PAINT.base); f.hline(x0 - 1, y, 6, PAINT.hi); f.hline(x0 - 1, y + 3, 6, PAINT.shade);
    f.px(x0, y + 1, PAINT.rust); f.px(x0 + 3, y + 2, PAINT.rustDark);
  }
  f.vline(x0 + 4, 0, 16, withAlpha(PAINT.rustDark, 120)); // the beam's own shadow edge
}
add("rio_rail_w", "ysort", { solid: true }, (f) => rail(f, 3, "rrw"));
add("rio_rail_e", "ysort", { solid: true }, (f) => rail(f, 9, "rre"));
add("rio_post", "ysort", { solid: true, sort_offset: -2 }, (f) => {
  f.ellipse(8, 13, 6.5, 2.2, SH);
  f.rect(4, 3, 8, 11, C.concrete.base); // the square post: front face
  f.rect(3, 2, 10, 3, C.concrete.light); f.hline(3, 4, 10, C.concrete.joint); // cap
  f.vline(4, 5, 9, C.concrete.light); f.vline(11, 5, 9, C.concrete.dark); f.vline(10, 5, 9, C.concrete.dark);
  f.hline(4, 13, 8, C.concrete.joint);
  for (let y = 5; y < 13; y++) for (let x = 5; x < 10; x++) if (noise("pst", x, y) < 0.12) f.px(x, y, C.concrete.stain);
  f.px(6, 7, PAINT.rust); f.px(6, 8, PAINT.rustDark); f.px(9, 10, PAINT.rust); // rust runs from the bolts
  f.hline(5, 9, 6, PAINT.base); f.hline(5, 10, 6, PAINT.shade); // yellow painted band
});
for (const side of ["w", "e"]) {
  add(`rio_abutment_${side}`, "ysort", { solid: true }, (f) => {
    // concrete pier standing in the water: a foam ring at its base, a lit top face and the shaded side away from the light
    f.ellipse(8, 8, 8, 8, withAlpha(C.river.foam, 130));
    f.rect(1, 1, 14, 14, C.concrete.base);
    f.rect(0, 0, 16, 16, C.concrete.base); // fills the cell: the corners are cut below
    for (const [x, y] of [[0, 0], [15, 0], [0, 15], [15, 15]]) f.set(x, y, [0, 0, 0, 0]);
    f.hline(1, 0, 14, C.concrete.light); f.hline(1, 1, 14, C.concrete.light);
    const dark = side === "w" ? 15 : 0, lite = side === "w" ? 0 : 15;
    f.vline(dark, 1, 14, C.concrete.joint); f.vline(dark === 15 ? 14 : 1, 1, 14, C.concrete.dark);
    f.vline(lite, 1, 14, C.concrete.light);
    f.hline(1, 15, 14, C.concrete.chanDark); f.hline(1, 14, 14, C.concrete.joint);
    for (let y = 2; y < 14; y++) for (let x = 2; x < 14; x++) if (noise("abt" + side, x, y) < 0.1) f.px(x, y, C.concrete.stain);
    f.hline(2, 8, 12, C.concrete.joint); // pour seam
    for (let x = 3; x < 14; x += 3) f.px(x, 13, C.river.mudDark); // waterline stain
  });
}

// ---------------------------------------------------------------- boulders (transparent background: drawn over water)
function boulder(f, cx, cy, rx, ry, salt) {
  f.ellipse(cx, cy + ry * 0.55 + 1, rx + 2, ry * 0.7 + 1, withAlpha(C.river.foam, 150)); // foam where the current splits
  f.ellipse(cx + 1, cy + ry * 0.45 + 1, rx + 0.5, ry * 0.55, SH);
  for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++) for (let x = Math.floor(cx - rx); x <= Math.ceil(cx + rx); x++) {
    const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
    if (dx * dx + dy * dy > 1) continue;
    const n = noise(salt, x, y), v = 0.5 - dx * 0.3 - dy * 0.45 + (n - 0.5) * 0.4;
    f.px(x, y, v < 0.22 ? C.rock.dark : v < 0.55 ? C.rock.base : C.rock.light);
    if (dy > 0.45 && n < 0.5) f.px(x, y, C.river.stoneDark); // wet dark foot
    if (dy < -0.2 && n > 0.88) f.px(x, y, C.zacate.mid); // moss on the top
  }
  f.px(Math.round(cx - rx * 0.35), Math.round(cy - ry * 0.45), C.rock.light);
}
add("rio_boulder_a", "ysort", { solid: true }, (f) => boulder(f, 8, 8, 6, 4.6, "ba"));
add("rio_boulder_b", "ysort", { solid: true }, (f) => boulder(f, 8, 8, 7, 5.6, "bb"));
add("rio_boulder_c", "ysort", { solid: true }, (f) => { boulder(f, 5, 9, 4.2, 3.4, "bc"); boulder(f, 11, 7, 4, 3.2, "bd"); });

if (nextId > R_COLS * R_ROWS) throw new Error(`too many rio tiles: ${nextId} > ${R_COLS * R_ROWS}`);
{
  const townNames = new Set(TOWN_TILES.map((t) => t.name));
  const ids = new Set(), names = new Set();
  for (const t of R_TILES) {
    if (ids.has(t.id)) throw new Error(`duplicate rio id ${t.id} (${t.name})`);
    if (names.has(t.name)) throw new Error(`duplicate rio name ${t.name}`);
    if (townNames.has(t.name)) throw new Error(`rio tile name clashes with a town tile: ${t.name}`);
    if (!t.name.startsWith("rio_")) throw new Error(`rio tile without rio_ prefix: ${t.name}`);
    ids.add(t.id); names.add(t.name);
  }
}
export const rIdByName = new Map(R_TILES.map((t) => [t.name, t.id]));
export const RIO_TILE_COUNT = R_TILES.length;
export const RIO_SOLID_NAMES = new Set(R_TILES.filter((t) => t.solid).map((t) => t.name));

export function renderRioSheet() {
  const sheet = new Frame(R_COLS * SIZE, R_ROWS * SIZE);
  for (const t of R_TILES) {
    const f = new Frame(SIZE, SIZE);
    t.draw(f, tileRngFor(t.name));
    sheet.blit(f, (t.id % R_COLS) * SIZE, Math.floor(t.id / R_COLS) * SIZE);
  }
  return sheet;
}
