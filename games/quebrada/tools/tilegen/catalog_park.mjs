// Park sheet (park.png + park.tsx): skate park, playground, court, lines, walkway. First-pass procedural art.
// Sheet: 16 columns x 12 rows of 16x16 tiles, id = row * 16 + col. Every tile name starts with `park_`.
// Layout:
//   row 0   skate floors      row 1  skate banks (edges, pit corners, pyramid corners)
//   row 2   sand, court floors, walkway     row 3  court line pieces (named by the arms they have)
//   row 4   rails, box, bench, seesaw       rows 5-9  playground / hoops / goals objects
//   rows 10-11 centre circle cells (ground, sequential ids)
// Property scheme as town.tsx: name, layer (ground|overlay|ysort|above), surface (ground only), solid (ysort only), sort_offset.
import { Frame, rgb, shade, mix, withAlpha } from "./draw.mjs";
import { C } from "./palette.mjs";
import { noise } from "./rng.mjs";
import { tileRng } from "./rng.mjs";
import { concreteAt } from "./materials.mjs";

export const SIZE = 16;
export const P_COLS = 16;
export const P_ROWS = 12;
const id = (row, col) => row * P_COLS + col;
const SH = withAlpha([0, 0, 0, 255], 70);

const PK = {
  sand: { base: rgb("#d3bd8a"), dark: rgb("#bda672"), light: rgb("#e5d3a4"), peb: rgb("#9a8f7e"), pebDark: rgb("#756c5f") },
  court: { green: rgb("#4f8b62"), greenDark: rgb("#467f58"), greenLight: rgb("#5e9a6f"), blue: rgb("#4a76a3"), blueDark: rgb("#416b96"), blueLight: rgb("#5d8ab5"), line: rgb("#ecebe3") },
  paint: { yellow: rgb("#d9b630"), white: rgb("#e6e4da") },
  metal: { red: rgb("#b8423a"), redDark: rgb("#7f2c27"), blue: rgb("#3f6db0"), blueDark: rgb("#2c4d82"), yellow: rgb("#e0b83a"), steel: rgb("#a9aeb4"), steelDark: rgb("#6c7178"), steelLight: rgb("#d2d6da") },
  net: rgb("#f1f1ea"),
  rim: rgb("#d9622a"),
};

const sandAt = (x, y, v = 0) => {
  const r = noise("sand", x, y, v);
  if (r < 0.12) return PK.sand.dark;
  if (r > 0.9) return PK.sand.light;
  return PK.sand.base;
};
export const courtAt = (x, y, kind = "green", v = 0) => {
  const r = noise("court" + kind, x, y, v);
  const p = PK.court;
  const [b, d, l] = kind === "green" ? [p.green, p.greenDark, p.greenLight] : [p.blue, p.blueDark, p.blueLight];
  return r < 0.08 ? d : r > 0.94 ? l : b;
};

// ---------------------------------------------------------------- singles
function singles() {
  const T = [];
  const add = (row, col, name, layer, props, draw) => T.push({ id: id(row, col), name, layer, ...props, draw });
  const K = { surface: "concreto" };

  // ---- row 0: skate floors ----
  const skate = (x, y, v) => { const c = concreteAt(x, y, v + 20); return c; };
  add(0, 0, "park_skate_plain", "ground", K, (f) => f.fill((x, y) => skate(x, y, 0)));
  add(0, 1, "park_skate_cracked", "ground", K, (f) => {
    f.fill((x, y) => skate(x, y, 1));
    f.line(2, 0, 5, 5, C.concrete.joint); f.line(5, 5, 4, 9, C.concrete.joint); f.line(4, 9, 8, 15, C.concrete.joint);
    f.line(5, 5, 11, 7, C.concrete.stain); f.px(12, 3, C.concrete.joint); f.px(13, 4, C.concrete.joint);
  });
  add(0, 2, "park_skate_line_h", "ground", K, (f) => { f.fill((x, y) => skate(x, y, 2)); f.rect(0, 7, 16, 2, PK.paint.yellow); f.hline(0, 10, 16, withAlpha(PK.paint.yellow, 90)); });
  add(0, 3, "park_skate_line_v", "ground", K, (f) => { f.fill((x, y) => skate(x, y, 3)); f.rect(7, 0, 2, 16, PK.paint.white); });
  add(0, 4, "park_skate_dots", "ground", K, (f) => {
    f.fill((x, y) => skate(x, y, 4));
    for (const [x, y] of [[3, 3], [11, 3], [3, 11], [11, 11]]) f.rect(x, y, 2, 2, PK.paint.yellow);
  });
  add(0, 5, "park_skate_bowl", "ground", K, (f) => f.fill((x, y) => shade(skate(x, y, 5), 0.86)));
  add(0, 6, "park_skate_deck", "ground", K, (f) => {
    f.fill((x, y) => shade(skate(x, y, 6), 1.06));
    f.hline(0, 0, 16, C.concrete.light);
  });

  // ---- row 1: banks. height field h in [0,1]; lit from the NW ----
  const bank = (f, hfn, highSides) => {
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const h = hfn(x, y);
      const dhx = hfn(Math.min(15, x + 1), y) - hfn(Math.max(0, x - 1), y);
      const dhy = hfn(x, Math.min(15, y + 1)) - hfn(x, Math.max(0, y - 1));
      let k = 0.80 + 0.45 * h + 2.4 * (dhx + dhy);
      let c = shade(skate(x, y, 7), Math.max(0.6, Math.min(1.12, k)));
      if (Math.floor(h * 8) % 2 === 0 && h > 0.05 && h < 0.97) c = shade(c, 0.96); // subtle contour bands
      f.px(x, y, c);
    }
    // coping on the high sides
    for (const s of highSides) {
      if (s === "N") { f.hline(0, 0, 16, C.concrete.light); f.hline(0, 1, 16, C.concrete.joint); }
      if (s === "S") { f.hline(0, 15, 16, C.concrete.light); f.hline(0, 14, 16, C.concrete.joint); }
      if (s === "W") { f.vline(0, 0, 16, C.concrete.light); f.vline(1, 0, 16, C.concrete.joint); }
      if (s === "E") { f.vline(15, 0, 16, C.concrete.light); f.vline(14, 0, 16, C.concrete.joint); }
    }
  };
  const hN = (x, y) => 1 - y / 15, hS = (x, y) => y / 15, hW = (x, y) => 1 - x / 15, hE = (x, y) => x / 15;
  const edges = { n: [hN, ["N"]], e: [hE, ["E"]], s: [hS, ["S"]], w: [hW, ["W"]] };
  let col = 0;
  for (const [k, [fn, hs]] of Object.entries(edges)) add(1, col++, `park_bank_${k}`, "ground", K, (f) => bank(f, fn, hs));
  // pit corners (concave): high on two sides
  const inC = { ne: [(x, y) => Math.max(hN(x, y), hE(x, y)), ["N", "E"]], se: [(x, y) => Math.max(hS(x, y), hE(x, y)), ["S", "E"]], sw: [(x, y) => Math.max(hS(x, y), hW(x, y)), ["S", "W"]], nw: [(x, y) => Math.max(hN(x, y), hW(x, y)), ["N", "W"]] };
  for (const [k, [fn, hs]] of Object.entries(inC)) add(1, col++, `park_bank_in_${k}`, "ground", K, (f) => bank(f, fn, hs));
  // pyramid corners (convex): slope drops toward the named corner
  const outC = { ne: (x, y) => Math.min(hS(x, y), hW(x, y)), se: (x, y) => Math.min(hN(x, y), hW(x, y)), sw: (x, y) => Math.min(hN(x, y), hE(x, y)), nw: (x, y) => Math.min(hS(x, y), hE(x, y)) };
  for (const [k, fn] of Object.entries(outC)) add(1, col++, `park_bank_out_${k}`, "ground", K, (f) => bank(f, fn, []));

  // ---- row 2: sand, court, walkway ----
  add(2, 0, "park_sand_a", "ground", { surface: "lastre" }, (f) => f.fill((x, y) => sandAt(x, y, 0)));
  add(2, 1, "park_sand_b", "ground", { surface: "lastre" }, (f) => f.fill((x, y) => sandAt(x, y, 1)));
  add(2, 2, "park_sand_pebbles", "ground", { surface: "lastre" }, (f, r) => {
    f.fill((x, y) => sandAt(x, y, 2));
    for (let i = 0; i < 5; i++) { const x = r.int(1, 13), y = r.int(1, 13); f.px(x, y, PK.sand.peb); f.px(x + 1, y, PK.sand.peb); f.px(x, y + 1, PK.sand.pebDark); }
  });
  add(2, 4, "park_court_green_a", "ground", K, (f) => f.fill((x, y) => courtAt(x, y, "green", 0)));
  add(2, 5, "park_court_green_b", "ground", K, (f) => f.fill((x, y) => courtAt(x, y, "green", 1)));
  add(2, 6, "park_court_blue_a", "ground", K, (f) => f.fill((x, y) => courtAt(x, y, "blue", 0)));
  add(2, 7, "park_court_blue_b", "ground", K, (f) => f.fill((x, y) => courtAt(x, y, "blue", 1)));
  add(2, 8, "park_walk_a", "ground", K, (f) => {
    f.fill((x, y) => concreteAt(x, y, 30));
    f.hline(0, 15, 16, C.concrete.joint); f.vline(15, 0, 16, C.concrete.joint); f.hline(0, 0, 16, C.concrete.light);
  });
  add(2, 9, "park_walk_b", "ground", K, (f) => {
    f.fill((x, y) => concreteAt(x, y, 31));
    f.hline(0, 7, 16, C.concrete.joint); f.hline(0, 15, 16, C.concrete.joint); f.vline(8, 0, 7, C.concrete.joint); f.vline(4, 8, 7, C.concrete.joint);
  });

  // ---- row 3: court line pieces. Lines are 2 px wide, centred on pixels 7-8 ----
  const ARMS = ["ew", "ns", "ne", "nw", "se", "sw", "new", "sew", "nse", "nsw", "nsew"];
  ARMS.forEach((arms, i) => {
    add(3, i, `park_line_${arms}`, "ground", K, (f) => {
      f.fill((x, y) => courtAt(x, y, "green", 0));
      drawArms(f, arms, 0, 0);
    });
  });

  // ---- row 4: rails, box, bench, seesaw ----
  const railFoot = (f, x) => { f.rect(x - 1, 11, 3, 4, PK.metal.steelDark); f.hline(x - 1, 11, 3, PK.metal.steel); };
  add(4, 0, "park_rail_l", "ysort", { solid: true, sort_offset: -2 }, (f) => {
    f.hline(2, 14, 12, SH); railFoot(f, 3);
    f.rect(3, 8, 13, 2, PK.metal.steelLight); f.hline(3, 9, 13, PK.metal.steel);
  });
  add(4, 1, "park_rail_m", "ysort", { solid: true, sort_offset: -2 }, (f) => {
    f.hline(0, 14, 16, SH);
    f.rect(0, 8, 16, 2, PK.metal.steelLight); f.hline(0, 9, 16, PK.metal.steel);
  });
  add(4, 2, "park_rail_r", "ysort", { solid: true, sort_offset: -2 }, (f) => {
    f.hline(0, 14, 12, SH); railFoot(f, 12);
    f.rect(0, 8, 13, 2, PK.metal.steelLight); f.hline(0, 9, 13, PK.metal.steel);
  });
  add(4, 3, "park_box", "ysort", { solid: true }, (f) => {
    f.hline(1, 14, 14, SH); f.hline(2, 15, 12, SH);
    f.rect(1, 6, 14, 8, shade(C.concrete.base, 0.9));
    f.rect(1, 4, 14, 3, C.concrete.light); f.hline(1, 4, 14, mix(C.concrete.light, [255, 255, 255, 255], 0.4));
    f.hline(1, 13, 14, C.concrete.dark); f.vline(1, 6, 8, C.concrete.joint); f.vline(14, 6, 8, C.concrete.joint);
    f.hline(1, 7, 14, C.concrete.joint);
    f.rect(1, 5, 14, 1, PK.paint.yellow);
  });
  add(4, 4, "park_bench", "ysort", { solid: true }, (f) => {
    f.hline(1, 14, 14, SH);
    f.rect(1, 9, 2, 5, C.concrete.dark); f.rect(13, 9, 2, 5, C.concrete.dark);
    f.rect(0, 2, 16, 3, PK.metal.blueDark); f.hline(0, 2, 16, PK.metal.blue);
    f.rect(0, 5, 16, 1, C.wood.dark);
    f.rect(0, 6, 16, 3, C.wood.light); f.hline(0, 8, 16, C.wood.base); f.hline(0, 9, 16, C.wood.dark);
  });
  add(4, 5, "park_seesaw_l", "ysort", { solid: true }, (f) => {
    f.hline(1, 14, 15, SH);
    f.line(0, 11, 15, 8, C.wood.dark); f.line(0, 10, 15, 7, PK.metal.yellow); f.line(0, 9, 15, 6, PK.metal.yellow);
    f.rect(0, 11, 2, 4, PK.metal.steel);
    f.rect(11, 9, 3, 6, PK.metal.steelDark); f.rect(12, 9, 1, 5, PK.metal.steel);
  });
  add(4, 6, "park_seesaw_r", "ysort", { solid: true }, (f) => {
    f.hline(0, 14, 15, SH);
    f.line(0, 8, 15, 5, C.wood.dark); f.line(0, 7, 15, 4, PK.metal.yellow); f.line(0, 6, 15, 3, PK.metal.yellow);
    f.rect(2, 9, 3, 6, PK.metal.steelDark); f.rect(3, 9, 1, 5, PK.metal.steel);
    f.rect(14, 4, 2, 2, PK.metal.steel);
  });
  return T;
}

/** Draw line arms ("n","e","s","w" letters) on a frame at cell offset (ox, oy) px. */
function drawArms(f, arms, ox, oy) {
  const L = PK.court.line;
  const has = (c) => arms.includes(c);
  if (has("n")) f.rect(ox + 7, oy, 2, 9, L);
  if (has("s")) f.rect(ox + 7, oy + 7, 2, 9, L);
  if (has("w")) f.rect(ox, oy + 7, 9, 2, L);
  if (has("e")) f.rect(ox + 7, oy + 7, 9, 2, L);
}

// ---------------------------------------------------------------- multi-cell objects
// cells: { cx, cy, id, name, layer, solid?, sort_offset? }. Upper cells `above`, base `ysort`.
function objects() {
  const O = [];
  const cell = (name, cx, cy, row, col, layer, props = {}) => ({ cx, cy, id: id(row, col), name: `${name}_${cx}_${cy}`, layer, ...props });
  const post = (f, x, y0, y1, c = PK.metal.red, d = PK.metal.redDark) => { for (let y = y0; y <= y1; y++) { f.px(x, y, c); f.px(x + 1, y, c); f.px(x + 2, y, d); } };

  // swing set 3x2: crossbar over two swings, posts at both ends (cells 0 and 2 solid)
  O.push({
    name: "park_swing", w: 3, h: 2,
    cells: [
      cell("park_swing", 0, 0, 5, 0, "above"), cell("park_swing", 1, 0, 5, 1, "above"), cell("park_swing", 2, 0, 5, 2, "above"),
      cell("park_swing", 0, 1, 6, 0, "ysort", { solid: true, sort_offset: -2 }),
      cell("park_swing", 1, 1, 6, 1, "ysort", { sort_offset: -2 }),
      cell("park_swing", 2, 1, 6, 2, "ysort", { solid: true, sort_offset: -2 }),
    ],
    draw(f) {
      f.ellipse(8, 29, 7, 2.4, SH); f.ellipse(40, 29, 7, 2.4, SH); f.ellipse(24, 29, 18, 2, withAlpha([0, 0, 0, 255], 40));
      post(f, 3, 4, 30); post(f, 42, 4, 30);
      f.rect(2, 3, 44, 3, PK.metal.blue); f.hline(2, 3, 44, shade(PK.metal.blue, 1.3)); f.hline(2, 5, 44, PK.metal.blueDark);
      for (const sx of [17, 31]) {
        f.vline(sx - 3, 6, 17, PK.metal.steelDark); f.vline(sx + 3, 6, 17, PK.metal.steelDark);
        f.rect(sx - 4, 23, 9, 2, C.tire ?? C.wood.dark); f.hline(sx - 4, 23, 9, C.wood.base);
      }
    },
  });
  // slide 2x2: ladder platform on the left, chute to the lower right
  O.push({
    name: "park_slide", w: 2, h: 2,
    cells: [
      cell("park_slide", 0, 0, 5, 3, "above"), cell("park_slide", 1, 0, 5, 4, "above"),
      cell("park_slide", 0, 1, 6, 3, "ysort", { solid: true, sort_offset: -2 }), cell("park_slide", 1, 1, 6, 4, "ysort", { solid: true, sort_offset: -2 }),
    ],
    draw(f) {
      f.ellipse(8, 29, 7, 2.4, SH); f.ellipse(23, 29, 8, 2.2, SH);
      post(f, 2, 7, 30, PK.metal.steelDark, PK.metal.steelDark); post(f, 11, 7, 30, PK.metal.steelDark, PK.metal.steelDark);
      f.rect(1, 5, 13, 3, PK.metal.yellow); f.hline(1, 5, 13, shade(PK.metal.yellow, 1.2));
      for (let y = 17; y < 29; y += 3) f.hline(3, y, 8, PK.metal.steelLight); // ladder rungs
      // chute: slopes from the platform edge (14,10) down to (30,28)
      for (let t = 0; t <= 20; t++) {
        const x = 14 + t * 0.8, y = 9 + t * 0.95;
        f.rect(Math.round(x), Math.round(y), 3, 3, PK.metal.red); f.px(Math.round(x), Math.round(y), shade(PK.metal.red, 1.25));
        f.px(Math.round(x) + 2, Math.round(y) + 2, PK.metal.redDark);
      }
    },
  });
  // climbing frame 2x2: dome of bars
  O.push({
    name: "park_climb", w: 2, h: 2,
    cells: [
      cell("park_climb", 0, 0, 5, 5, "above"), cell("park_climb", 1, 0, 5, 6, "above"),
      cell("park_climb", 0, 1, 6, 5, "ysort", { solid: true, sort_offset: -2 }), cell("park_climb", 1, 1, 6, 6, "ysort", { solid: true, sort_offset: -2 }),
    ],
    draw(f) {
      f.ellipse(16, 28, 14, 3, SH);
      const R = PK.metal.red, B = PK.metal.blue;
      f.rect(3, 6, 26, 2, R);
      f.rect(3, 6, 2, 24, R); f.rect(27, 6, 2, 24, R); f.rect(14, 6, 2, 24, B);
      for (const y of [13, 20, 27]) f.rect(3, y, 26, 2, y === 20 ? B : R);
      f.hline(3, 6, 26, shade(R, 1.25));
    },
  });
  // basketball hoops 1x2: pole behind the backboard, rim toward the court
  const hoop = (name, col, flip) => ({
    name, w: 1, h: 2,
    cells: [cell(name, 0, 0, 5, col, "above"), cell(name, 0, 1, 6, col, "ysort", { solid: true, sort_offset: -2 })],
    draw(f) {
      const g = new Frame(16, 32);
      g.ellipse(4, 29, 4, 2, SH);
      g.rect(2, 8, 3, 23, PK.metal.steel); g.vline(2, 8, 23, PK.metal.steelLight); g.vline(4, 8, 23, PK.metal.steelDark);
      g.rect(1, 29, 5, 2, PK.metal.steelDark);
      g.rect(5, 1, 2, 11, PK.metal.steelLight); g.rect(5, 1, 1, 11, C.concrete.light); // backboard edge-on
      g.rect(6, 3, 1, 6, PK.court.line); g.rect(7, 1, 1, 11, PK.metal.steelDark);
      g.rect(8, 10, 6, 1, PK.rim); g.px(14, 10, shade(PK.rim, 0.8)); g.px(8, 11, shade(PK.rim, 0.8));
      for (let k = 0; k < 4; k++) { g.px(9 + k, 11 + (k % 2), PK.net); g.px(9 + k, 13, withAlpha(PK.net, 200)); }
      g.px(10, 12, PK.net); g.px(12, 12, PK.net); g.px(10, 14, withAlpha(PK.net, 160)); g.px(12, 14, withAlpha(PK.net, 160));
      if (!flip) { f.blit(g, 0, 0); return; }
      for (let y = 0; y < 32; y++) for (let x = 0; x < 16; x++) f.set(15 - x, y, g.get(x, y));
    },
  });
  O.push(hoop("park_hoop_l", 7, false));
  O.push(hoop("park_hoop_r", 8, true));
  // football goals 1x5: posts in the first / last cell, net in between. goal_l opens toward the east
  const goal = (name, col, flip) => ({
    name, w: 1, h: 5,
    cells: [0, 1, 2, 3, 4].map((cy) => cell(name, 0, cy, 5 + cy, col, "ysort", { solid: true, sort_offset: cy === 4 ? -2 : 0 })),
    draw(f) {
      const g = new Frame(16, 80);
      g.ellipse(8, 73, 7, 2.4, SH); g.ellipse(8, 7, 7, 2.4, withAlpha([0, 0, 0, 255], 40));
      // back net frame (left) and side nets
      for (let y = 8; y < 72; y++) for (let x = 3; x < 13; x++) {
        if ((x + y) % 3 === 0 || (x - y + 64) % 3 === 0) g.px(x, y, withAlpha(PK.net, 150));
      }
      g.rect(2, 4, 2, 72, PK.net); // back bar
      g.rect(2, 4, 12, 3, PK.net); g.rect(2, 73, 12, 3, PK.net); // posts seen from the side
      g.hline(2, 4, 12, shade(PK.net, 0.8)); g.hline(2, 75, 12, shade(PK.net, 0.8));
      if (!flip) { f.blit(g, 0, 0); return; }
      for (let y = 0; y < 80; y++) for (let x = 0; x < 16; x++) f.set(15 - x, y, g.get(x, y));
    },
  });
  O.push(goal("park_goal_l", 9, false));
  O.push(goal("park_goal_r", 10, true));
  return O;
}

// ---------------------------------------------------------------- centre circle cells (ground)
// 7x8 cells: centre line column (cx 3) over the 6 middle rows plus a ring of radius 38 px around (56, 64).
export const CIRCLE_W = 7, CIRCLE_H = 8;
const circleCanvas = (() => {
  const f = new Frame(CIRCLE_W * SIZE, CIRCLE_H * SIZE);
  const cx = 56, cy = 64, r = 38;
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) {
    const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
    if (Math.abs(d - r) < 1) f.px(x, y, PK.court.line);
  }
  f.rect(55, SIZE, 2, (CIRCLE_H - 2) * SIZE, PK.court.line); // vertical centre line through cy 1..6
  return f;
})();
const circleCells = [];
{
  let n = 0;
  for (let cy = 0; cy < CIRCLE_H; cy++) for (let cx = 0; cx < CIRCLE_W; cx++) {
    const s = circleCanvas.slice(cx * SIZE, cy * SIZE, SIZE, SIZE);
    if (s.data.some((v, i) => i % 4 === 3 && v)) {
      circleCells.push({ cx, cy, id: id(10, 0) + n++, name: `park_court_circle_${cx}_${cy}`, layer: "ground", surface: "concreto" });
    }
  }
}
export const CIRCLE_CELLS = circleCells;

// ---------------------------------------------------------------- assemble
const S = singles();
const O = objects();
export const PARK_OBJECTS = O;
export const PARK_OBJECT_BY_NAME = new Map(O.map((o) => [o.name, o]));
export const PARK_TILES = [...S];
for (const o of O) for (const c of o.cells) PARK_TILES.push({ ...c, object: o.name });
for (const c of circleCells) PARK_TILES.push(c);
PARK_TILES.sort((a, b) => a.id - b.id);
{
  const ids = new Set(), names = new Set();
  for (const t of PARK_TILES) {
    if (t.id < 0 || t.id >= P_COLS * P_ROWS) throw new Error(`id out of park sheet: ${t.name} ${t.id}`);
    if (ids.has(t.id)) throw new Error(`duplicate park id ${t.id} (${t.name})`);
    if (names.has(t.name)) throw new Error(`duplicate park name ${t.name}`);
    if (!t.name.startsWith("park_")) throw new Error(`park tile without park_ prefix: ${t.name}`);
    ids.add(t.id); names.add(t.name);
  }
}
export const pIdByName = new Map(PARK_TILES.map((t) => [t.name, t.id]));

export function renderParkSheet() {
  const sheet = new Frame(P_COLS * SIZE, P_ROWS * SIZE);
  const put = (tid, fr) => sheet.blit(fr, (tid % P_COLS) * SIZE, Math.floor(tid / P_COLS) * SIZE);
  for (const t of S) { const f = new Frame(SIZE, SIZE); t.draw(f, tileRng(t.name)); put(t.id, f); }
  for (const o of O) {
    const canvas = new Frame(o.w * SIZE, o.h * SIZE);
    o.draw(canvas, tileRng(o.name));
    for (const c of o.cells) put(c.id, canvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  for (const c of circleCells) {
    const f = new Frame(SIZE, SIZE);
    f.fill((x, y) => courtAt(x, y, "green", 0));
    f.blit(circleCanvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE), 0, 0);
    put(c.id, f);
  }
  return sheet;
}
