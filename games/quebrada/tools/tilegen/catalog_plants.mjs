// Rows 6-8: tree canopies (above), trunks / bases / bushes / props (ysort) and ground overlays.
// A tree = canopy cells (3x2, layer "above") sitting directly over a one cell trunk (ysort, solid)
// under the canopy's middle column. The hero walks behind the trunk and under the canopy.
import { C } from "./palette.mjs";
import { noise } from "./rng.mjs";
import { mix, shade, withAlpha } from "./draw.mjs";

const id = (row, col) => row * 16 + col;
const SH = withAlpha([0, 0, 0, 255], 70);

/** Leaf-mass canopy from circular lobes: lit from the upper left, ragged edge, darker underside. */
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
    let c = v < 0.2 ? pal.deep : v < 0.38 ? pal.dark : v < 0.66 ? pal.base : v < 0.82 ? pal.light : pal.hi;
    f.px(x, y, c);
  }
}

/** Curved leaf from (x0,y0) toward (x1,y1); bend pushes the middle sideways. */
function leaf(f, x0, y0, x1, y1, bend, width, cols, vein = true) {
  const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
  const nx = -dy / len, ny = dx / len;
  const steps = Math.ceil(len * 2);
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const off = Math.sin(t * Math.PI) * bend;
    const cx = x0 + dx * t + nx * off, cy = y0 + dy * t + ny * off;
    const w = width * Math.sin(Math.PI * Math.min(1, t * 0.85 + 0.12));
    for (let k = -Math.ceil(w); k <= Math.ceil(w); k++) {
      const px = cx + nx * k * 0.5, py = cy + ny * k * 0.5;
      if (Math.abs(k * 0.5) > w) continue;
      const c = k * 0.5 < -w * 0.2 ? cols.light : k * 0.5 > w * 0.35 ? cols.dark : cols.base;
      f.px(px, py, c);
    }
    if (vein && cols.vein && i % 1 === 0) f.px(cx, cy, cols.vein);
  }
}

export const plantTiles = {
  singles() {
    const T = [];
    const add = (row, col, name, layer, props, draw) => T.push({ id: id(row, col), name, layer, ...props, draw });

    // ---- wire across the poles (above) ----
    add(6, 13, "power_wire", "above", {}, (f) => {
      for (let x = 0; x < 16; x++) f.px(x, 2, C.post.cable);
      for (let x = 0; x < 16; x++) f.px(x, 3, withAlpha(C.post.cable, 70));
    });

    // ---- row 8: trunks (ysort, solid) ----
    const groundShadow = (f, rx = 7.5, cy = 13) => f.ellipse(8, cy, rx, 2.6, SH);
    const trunk = (f, x0, x1, pal, salt, flare = 2) => {
      groundShadow(f);
      for (let y = 0; y < 16; y++) {
        const fl = y >= 12 ? (y - 11) * (flare / 4) : 0;
        const a = Math.round(x0 - fl), b = Math.round(x1 + fl);
        for (let x = a; x <= b; x++) {
          const n = noise(salt, x, y);
          const edge = x === a ? 0.8 : x === b ? 0.7 : 1;
          let c = x - a < (b - a) * 0.3 ? pal.barkLight ?? pal.bark : pal.bark;
          if (n < 0.28 || (x + (y >> 2)) % 5 === 0) c = pal.barkDark;
          f.px(x, y, edge < 1 ? shade(c, edge) : c);
        }
      }
      f.hline(x0 - 1, 15, x1 - x0 + 3, pal.barkDark);
    };
    add(8, 0, "guanacaste_trunk", "ysort", { solid: true, sort_offset: -2 }, (f) => {
      trunk(f, 4, 11, C.guanacaste, "gt", 3);
      f.hline(3, 0, 10, withAlpha(C.guanacaste.deep, 160));
    });
    add(8, 1, "platano_stem", "ysort", { solid: true, sort_offset: -2 }, (f, r) => {
      groundShadow(f, 7);
      // pseudostem
      for (let y = 0; y < 15; y++) for (let x = 5; x <= 10; x++) {
        let c = x < 7 ? C.plantain.stem : x > 9 ? C.plantain.stemDark : mix(C.plantain.stem, C.plantain.stemDark, 0.4);
        if ((y + 1) % 5 === 0) c = C.plantain.stemDark;
        f.px(x, y, c);
      }
      f.hline(4, 15, 8, C.plantain.stemDark);
      // hanging bunch of fruit
      f.rect(10, 4, 2, 2, C.plantain.flower);
      for (const [x, y] of [[11, 6], [12, 7], [11, 8], [12, 9], [10, 8], [11, 10]]) { f.rect(x, y, 2, 2, C.plantain.fruit); f.px(x + 1, y + 1, C.plantain.fruitDark); }
      // pup at the base
      leaf(f, 3, 15, 1, 9, 1, 1.6, C.plantain, false);
      f.px(2, 12, C.plantain.vein);
    });
    add(8, 2, "palm_trunk", "ysort", { solid: true, sort_offset: -2 }, (f) => {
      groundShadow(f, 6);
      for (let y = 0; y < 16; y++) for (let x = 6; x <= 9; x++) {
        let c = x === 6 ? C.palm.trunkLight : x === 9 ? C.palm.trunkDark : C.palm.trunk;
        if (y % 3 === 0) c = C.palm.trunkDark;
        f.px(x, y, c);
      }
      f.hline(5, 15, 6, C.palm.trunkDark); f.px(5, 14, C.palm.trunkDark); f.px(10, 14, C.palm.trunkDark);
    });
    add(8, 3, "monte_trunk", "ysort", { solid: true, sort_offset: -2 }, (f) => {
      trunk(f, 5, 10, C.monte, "mt", 2.5);
    });
    add(8, 4, "poste_base", "ysort", { solid: true, sort_offset: -2 }, (f) => {
      f.ellipse(9, 14, 6, 2, SH);
      f.rect(5, 12, 6, 3, C.post.dark); f.hline(5, 12, 6, C.post.base); // footing
      for (let y = 0; y < 13; y++) { f.px(6, y, C.post.light); f.px(7, y, C.post.base); f.px(8, y, C.post.dark); }
      f.hline(5, 15, 6, C.post.arm);
    });
    const cafeto = (f, berry, salt) => {
      f.ellipse(8, 13, 7, 2.4, SH);
      const lobes = [[5, 9, 5], [11, 9, 5], [8, 6, 5.5], [8, 10.5, 5.5]];
      canopy(f, lobes, { deep: C.coffee.leafDark, dark: C.coffee.leafDark, base: C.coffee.leaf, light: C.coffee.leafLight, hi: C.coffee.leafLight }, salt, { ragged: 0.12 });
      for (let i = 0; i < 9; i++) {
        const x = 3 + Math.floor(noise(salt + "bx", i, 0) * 10), y = 4 + Math.floor(noise(salt + "by", i, 0) * 8);
        if (f.get(x, y)[3]) { f.px(x, y, berry); }
      }
      f.hline(5, 14, 6, C.coffee.stem);
    };
    add(8, 5, "cafeto_a", "ysort", { solid: true }, (f) => cafeto(f, C.coffee.red, "cfa"));
    add(8, 6, "cafeto_b", "ysort", { solid: true }, (f) => cafeto(f, C.coffee.green, "cfb"));
    add(8, 7, "rock", "ysort", { solid: true }, (f) => {
      f.ellipse(8, 13, 7, 2.2, SH);
      const lobes = [[8, 9, 6.2], [5, 10, 4]];
      for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
        let best = null;
        for (const [cx, cy, rad] of lobes) {
          const d = Math.hypot((x + 0.5 - cx) / 1.15, y + 0.5 - cy) / rad;
          if (d <= 1 && (!best || d < best.d)) best = { d, dx: (x + 0.5 - cx) / rad, dy: (y + 0.5 - cy) / rad };
        }
        if (!best) continue;
        const v = 0.5 - (best.dx * 0.4 + best.dy * 0.7) * 0.4 + (noise("rk", x, y) - 0.5) * 0.3;
        f.px(x, y, v < 0.32 ? C.rock.dark : v < 0.66 ? C.rock.base : C.rock.light);
      }
    });
    add(8, 8, "bench", "ysort", { solid: true }, (f) => {
      f.hline(1, 13, 14, SH); f.hline(2, 14, 12, SH);
      f.rect(2, 8, 2, 5, C.wood.dark); f.rect(12, 8, 2, 5, C.wood.dark);
      f.rect(0, 5, 16, 3, C.wood.light); f.hline(0, 7, 16, C.wood.base);
      f.rect(0, 3, 16, 2, C.wood.base); f.hline(0, 3, 16, C.wood.light);
      f.rect(1, 8, 14, 1, C.wood.dark);
    });
    add(8, 9, "stump", "ysort", { solid: true }, (f) => {
      f.ellipse(8, 13, 7, 2.4, SH);
      f.rect(3, 7, 10, 6, C.guanacaste.bark);
      f.vline(3, 7, 6, C.guanacaste.barkDark); f.vline(12, 7, 6, C.guanacaste.barkDark); f.hline(3, 12, 10, C.guanacaste.barkDark);
      f.ellipse(8, 7, 5, 3, C.guanacaste.barkLight);
      f.ellipse(8, 7, 3.4, 1.9, C.wood.light); f.ellipse(8, 7, 1.6, 0.8, C.wood.base);
    });
    add(8, 10, "weeds", "ysort", {}, (f, r) => {
      for (let i = 0; i < 10; i++) {
        const x = r.int(1, 14), y = r.int(7, 14), h = r.int(3, 6);
        for (let k = 0; k < h; k++) f.px(x + (k > 2 ? 1 : 0), y - k, k < 2 ? C.zacate.tall : k < 4 ? C.zacate.mid : C.zacate.light);
      }
    });
    add(8, 11, "bougainvillea", "ysort", { solid: true }, (f, r) => {
      f.ellipse(8, 13, 7.5, 2.4, SH);
      canopy(f, [[5, 9, 5], [11, 9, 5], [8, 6, 5.5]], { deep: C.hedge.dark, dark: C.hedge.dark, base: C.hedge.base, light: C.hedge.light, hi: C.hedge.light }, "bg", { ragged: 0.15 });
      for (let i = 0; i < 16; i++) {
        const x = 2 + Math.floor(noise("bgx", i, 0) * 12), y = 2 + Math.floor(noise("bgy", i, 0) * 10);
        if (f.get(x, y)[3]) { f.px(x, y, i % 3 === 0 ? C.flower.pinkLight : C.flower.pink); if (i % 2) f.px(x + 1, y, C.flower.pink); }
      }
    });

    // ---- overlays (no surface) ----
    add(8, 12, "shadow_blob", "overlay", {}, (f) => f.ellipse(8, 9, 7.5, 5.5, withAlpha([0, 0, 0, 255], 60)));
    add(8, 13, "shadow_pole", "overlay", {}, (f) => { f.ellipse(9, 9, 5, 2, withAlpha([0, 0, 0, 255], 70)); f.ellipse(10, 9, 3.5, 1.4, withAlpha([0, 0, 0, 255], 40)); });
    add(8, 14, "fallen_leaves", "overlay", {}, (f, r) => {
      const cols = [C.guanacaste.light, C.zacate.dry, C.plantain.light, C.zacate.dryDark];
      for (let i = 0; i < 7; i++) { const x = r.int(1, 14), y = r.int(1, 14), c = cols[i % cols.length]; f.px(x, y, c); f.px(x + 1, y, c); f.px(x, y + 1, shade(c, 0.8)); }
    });
    add(8, 15, "puddle", "overlay", {}, (f) => {
      f.ellipse(8, 9, 6, 3.2, withAlpha(C.river.dark, 170));
      f.ellipse(8, 9, 5, 2.4, withAlpha(C.river.base, 190));
      f.hline(5, 8, 3, withAlpha(C.river.foam, 200));
    });
    return T;
  },

  objects() {
    const O = [];
    // 3x2 canopies: cells (cx,cy) -> ids rows 6-7
    const grid = (name, col0, props = {}) => {
      const cells = [];
      for (let cy = 0; cy < 2; cy++) for (let cx = 0; cx < 3; cx++) {
        cells.push({ cx, cy, id: id(6 + cy, col0 + cx), name: `${name}_${cx}_${cy}`, layer: "above", ...props });
      }
      return cells;
    };
    O.push({
      name: "guanacaste_canopy", w: 3, h: 2, cells: grid("guanacaste_canopy", 0),
      draw(f) {
        const lobes = [[24, 14, 14], [10, 17, 9], [38, 17, 9], [15, 8, 9.5], [33, 8, 9.5], [24, 6, 8], [6, 12, 6], [42, 12, 6], [24, 23, 7.5], [16, 22, 6], [32, 22, 6]];
        canopy(f, lobes, C.guanacaste, "gc");
      },
    });
    O.push({
      name: "platano_canopy", w: 3, h: 2, cells: grid("platano_canopy", 3),
      draw(f) {
        const base = { x: 24, y: 29 };
        const L = C.plantain;
        const leaves = [
          [-150, 20, 3, 4.5], [-115, 24, -2, 4.8], [-80, 22, 2, 4.6], [-45, 24, -3, 4.8], [-18, 20, 3, 4.4],
          [-165, 13, -2, 3.8], [-30, 12, 2, 3.8], [-98, 12, 0, 4.0], [-62, 14, 1, 4.0], [-132, 15, 2, 4.0],
        ];
        for (const [ang, len, bend, w] of leaves) {
          const a = (ang * Math.PI) / 180;
          leaf(f, base.x, base.y, base.x + Math.cos(a) * len * 1.35, base.y + Math.sin(a) * len * 0.95, bend, w, { base: L.leaf, light: L.light, dark: L.dark, vein: L.vein });
        }
        // darker centre so the stem reads as the source
        f.ellipse(24, 29, 3, 2, L.dark);
      },
    });
    O.push({
      name: "palm_canopy", w: 3, h: 2, cells: grid("palm_canopy", 6),
      draw(f) {
        const P = C.palm;
        const cx = 24, cy = 24;
        const fronds = [[-170, 20, 4], [-140, 22, 2], [-110, 21, 0], [-70, 21, 0], [-40, 22, -2], [-10, 20, -4], [160, 14, -4], [20, 14, 4], [-90, 17, 0]];
        for (const [ang, len, bend] of fronds) {
          const a = (ang * Math.PI) / 180;
          leaf(f, cx, cy, cx + Math.cos(a) * len * 1.2, cy + Math.sin(a) * len * 0.95, bend, 2.6, { base: P.frond, light: P.light, dark: P.dark, vein: P.dark });
          // feathery leaflets
          for (let t = 0.3; t < 0.95; t += 0.14) {
            const bx = cx + Math.cos(a) * len * 1.2 * t, by = cy + Math.sin(a) * len * 0.95 * t;
            f.px(bx, by + 2, P.dark); f.px(bx, by - 2, P.light);
          }
        }
        f.ellipse(cx, cy, 2.6, 2.2, P.dark);
        for (const [x, y] of [[22, 25], [26, 25], [24, 27]]) f.px(x, y, C.wood.base);
      },
    });
    O.push({
      name: "monte_canopy", w: 3, h: 2, cells: grid("monte_canopy", 9),
      draw(f) {
        const lobes = [[24, 15, 13], [12, 16, 9], [36, 16, 9], [18, 8, 8], [30, 8, 8], [24, 22, 7], [9, 22, 5], [39, 22, 5], [24, 5, 6]];
        canopy(f, lobes, C.monte, "mc", { ragged: 0.3 });
      },
    });
    O.push({
      name: "poste_head", w: 1, h: 2,
      cells: [
        { cx: 0, cy: 0, id: id(6, 12), name: "poste_head_top", layer: "above" },
        { cx: 0, cy: 1, id: id(7, 12), name: "poste_head_shaft", layer: "above" },
      ],
      draw(f) {
        const P = C.post;
        // cables leave toward both neighbours at y = 2 (matches power_wire)
        for (let x = 0; x < 16; x++) f.px(x, 2, P.cable);
        // pole
        for (let y = 3; y < 32; y++) { f.px(6, y, P.light); f.px(7, y, P.base); f.px(8, y, P.dark); }
        // crossarm and insulators
        f.rect(1, 3, 14, 2, P.arm); f.hline(1, 3, 14, shade(P.arm, 1.3));
        for (const x of [2, 7, 13]) { f.px(x, 1, P.lampDim); f.px(x, 2, P.lamp); }
        // street lamp
        f.rect(9, 9, 5, 1, P.arm); f.rect(12, 10, 4, 2, P.lampDim); f.rect(12, 10, 4, 1, P.lamp);
        f.px(13, 12, withAlpha(P.lamp, 150));
      },
    });
    return O;
  },
};
