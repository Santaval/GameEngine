// Ground tiles: rows 0-4 (grass, lastre, asphalt, concrete, river).
import { C } from "./palette.mjs";
import { noise, wobble, hash, GLOBAL_SEED, strHash } from "./rng.mjs";
import { mix, shade, withAlpha } from "./draw.mjs";
import { grassAt, dryGrassAt, lastreAt, soilAt, asphaltAt, concreteAt, waterAt, grassMask, paintBlend, sideGrass } from "./materials.mjs";

const id = (row, col) => row * 16 + col;

function tuft(f, x, y, light, dark) {
  f.px(x, y, light);
  f.px(x, y - 1, light);
  f.px(x - 1, y - 2, light);
  f.px(x, y + 1, dark);
}

export function groundTiles() {
  const T = [];
  const add = (row, col, name, props, draw) => T.push({ id: id(row, col), name, layer: "ground", ...props, draw });
  const Z = { surface: "zacate" };
  const L = { surface: "lastre" };
  const K = { surface: "concreto" };

  // ---------- row 0: grass, soil, wood ----------
  for (let v = 0; v < 4; v++) {
    add(0, v, `grass_${"abcd"[v]}`, Z, (f, r) => {
      f.fill((x, y) => grassAt(x, y, v));
      for (let i = 0; i < 2 + v; i++) tuft(f, r.int(1, 14), r.int(3, 13), C.zacate.light, C.zacate.dark);
    });
  }
  add(0, 4, "grass_dry", Z, (f, r) => {
    f.fill((x, y) => dryGrassAt(x, y));
    for (let i = 0; i < 3; i++) tuft(f, r.int(1, 14), r.int(3, 13), C.zacate.dry, C.zacate.dryDark);
  });
  add(0, 5, "grass_flowers", Z, (f, r) => {
    f.fill((x, y) => grassAt(x, y, 5));
    const cols = [C.flower.white, C.flower.yellow, C.flower.white, C.flower.purple];
    for (let i = 0; i < 5; i++) {
      const x = r.int(1, 14), y = r.int(2, 13), c = cols[i % cols.length];
      f.px(x, y, c);
      if (i % 2 === 0) { f.px(x + 1, y, c); f.px(x, y + 1, C.zacate.dark); }
    }
  });
  add(0, 6, "grass_tall", Z, (f, r) => {
    f.fill((x, y) => (noise("tall", x, y) < 0.3 ? C.zacate.tall : grassAt(x, y, 6)));
    for (let i = 0; i < 9; i++) {
      const x = r.int(0, 15), y = r.int(4, 14);
      f.px(x, y, C.zacate.tall); f.px(x, y - 1, C.zacate.mid); f.px(x, y - 2, C.zacate.light); f.px(x + 1, y - 3, C.zacate.light);
    }
  });
  add(0, 7, "soil", L, (f) => f.fill((x, y) => soilAt(x, y)));
  // terrace: retaining lip across the lower third (cafetal)
  add(0, 8, "soil_terrace", L, (f) => {
    f.fill((x, y) => soilAt(x, y, 1));
    f.hline(0, 9, 16, C.soil.lip);
    for (let x = 0; x < 16; x++) {
      f.px(x, 10, noise("lip", x, 0) < 0.5 ? C.soil.light : C.soil.base);
      f.px(x, 11, C.soil.dark);
      f.px(x, 12, noise("lipd", x, 0) < 0.6 ? C.soil.clod : C.soil.dark);
    }
  });
  add(0, 9, "soil_furrow", L, (f) => {
    f.fill((x, y) => soilAt(x, y, 2));
    for (const y of [3, 8, 13]) {
      f.hline(0, y, 16, C.soil.clod);
      f.hline(0, y + 1, 16, C.soil.dark);
      for (let x = 0; x < 16; x += 3) f.px(x, y - 1, C.soil.light);
    }
  });
  const planks = (f, horizontal) => {
    for (let k = 0; k < 4; k++) {
      const base = k % 2 ? C.wood.base : mix(C.wood.base, C.wood.light, 0.35);
      for (let a = 0; a < 3; a++) for (let b = 0; b < 16; b++) {
        const n = noise("plank", horizontal ? b : k * 3 + a, horizontal ? k * 3 + a : b, k);
        const c = n < 0.12 ? C.wood.grain : n > 0.9 ? C.wood.light : base;
        horizontal ? f.px(b, k * 4 + a, c) : f.px(k * 4 + a, b, c);
      }
      horizontal ? f.hline(0, k * 4 + 3, 16, C.wood.gap) : f.vline(k * 4 + 3, 0, 16, C.wood.gap);
      // nails
      if (horizontal) { f.px(2 + (k % 2) * 6, k * 4 + 1, C.wood.dark); f.px(13 - (k % 2) * 4, k * 4 + 1, C.wood.dark); }
      else { f.px(k * 4 + 1, 2 + (k % 2) * 6, C.wood.dark); f.px(k * 4 + 1, 13 - (k % 2) * 4, C.wood.dark); }
    }
  };
  add(0, 10, "plank_h", { surface: "madera" }, (f) => planks(f, true));
  add(0, 11, "plank_v", { surface: "madera" }, (f) => planks(f, false));
  add(0, 12, "mud", L, (f, r) => {
    f.fill((x, y) => lastreAt(x, y, 4));
    f.ellipse(8, 8, 6, 3.6, C.lastre.rut);
    f.ellipse(8, 8, 5, 2.8, C.lastre.wet);
    for (let i = 0; i < 4; i++) f.px(r.int(4, 11), r.int(7, 9), withAlpha(C.river.light, 150));
  });
  add(0, 13, "grass_dirt", Z, (f, r) => {
    f.fill((x, y) => grassAt(x, y, 8));
    f.ellipse(8, 8, 5.5, 3.5, C.soil.base);
    for (let i = 0; i < 12; i++) f.px(r.int(3, 12), r.int(5, 11), noise("dp", i, 0) < 0.5 ? C.soil.dark : C.soil.light);
  });

  // ---------- row 1: lastre road ----------
  add(1, 0, "lastre_a", L, (f) => f.fill((x, y) => lastreAt(x, y, 0)));
  add(1, 1, "lastre_b", L, (f, r) => {
    f.fill((x, y) => lastreAt(x, y, 1));
    for (let i = 0; i < 3; i++) { const x = r.int(1, 13), y = r.int(1, 13); f.px(x, y, C.lastre.stone); f.px(x + 1, y, C.lastre.stoneDark); }
  });
  add(1, 2, "lastre_ruts_h", L, (f) => {
    f.fill((x, y) => lastreAt(x, y, 2));
    for (const y of [4, 11]) {
      for (let x = 0; x < 16; x++) {
        f.px(x, y, C.lastre.rut);
        f.px(x, y + 1, noise("rut", x, y) < 0.7 ? C.lastre.dark : C.lastre.rut);
        f.px(x, y - 1, noise("rutl", x, y) < 0.3 ? C.lastre.light : lastreAt(x, y - 1, 2));
      }
    }
  });
  add(1, 15, "lastre_ruts_v", L, (f) => {
    f.fill((x, y) => lastreAt(x, y, 3));
    for (const x of [4, 11]) {
      for (let y = 0; y < 16; y++) {
        f.px(x, y, C.lastre.rut);
        f.px(x + 1, y, noise("rut", y, x) < 0.7 ? C.lastre.dark : C.lastre.rut);
        f.px(x - 1, y, noise("rutl", y, x) < 0.3 ? C.lastre.light : lastreAt(x - 1, y, 3));
      }
    }
  });
  const rimG = C.zacate.dark;
  const rimL = mix(C.lastre.base, C.lastre.dark, 0.8);
  const edgeCol = { N: 3, E: 4, S: 5, W: 6 };
  for (const s of ["N", "E", "S", "W"]) {
    add(1, edgeCol[s], `lastre_edge_${s.toLowerCase()}`, L, (f) =>
      paintBlend(f, grassMask("edge", [s]), (x, y) => grassAt(x, y, 0), (x, y) => lastreAt(x, y, 0), rimG, rimL));
  }
  const corners = [["NW", 7], ["NE", 8], ["SW", 9], ["SE", 10]];
  for (const [c, col] of corners) {
    add(1, col, `lastre_outer_${c.toLowerCase()}`, L, (f) =>
      paintBlend(f, grassMask("outer", c.split("")), (x, y) => grassAt(x, y, 0), (x, y) => lastreAt(x, y, 0), rimG, rimL));
  }
  const inners = [["NW", 11], ["NE", 12], ["SW", 13], ["SE", 14]];
  for (const [c, col] of inners) {
    add(1, col, `lastre_inner_${c.toLowerCase()}`, L, (f) =>
      paintBlend(f, grassMask("inner", c.split("")), (x, y) => grassAt(x, y, 0), (x, y) => lastreAt(x, y, 0), rimG, rimL));
  }

  // ---------- row 2: asphalt ----------
  add(2, 0, "asphalt_a", K, (f) => f.fill((x, y) => asphaltAt(x, y, 0)));
  add(2, 1, "asphalt_b", K, (f) => f.fill((x, y) => asphaltAt(x, y, 1)));
  add(2, 2, "asphalt_crack", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 2));
    let x = 3;
    for (let y = 0; y < 16; y++) {
      f.px(x, y, C.asphalt.crack);
      const n = noise("crack", y, 0);
      if (n < 0.3) { x -= 1; f.px(x, y, C.asphalt.crack); } else if (n > 0.7) { x += 1; f.px(x, y, C.asphalt.crack); }
      x = Math.max(1, Math.min(14, x));
    }
    f.px(4, 7, C.asphalt.crack); f.px(5, 8, C.asphalt.crack); f.px(6, 8, C.asphalt.crack);
  });
  add(2, 3, "asphalt_patch", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 3));
    f.rect(3, 4, 10, 8, C.asphalt.patch);
    f.hline(3, 4, 10, C.asphalt.crack); f.hline(3, 11, 10, C.asphalt.crack);
    f.vline(3, 4, 8, C.asphalt.crack); f.vline(12, 4, 8, C.asphalt.crack);
  });
  add(2, 4, "asphalt_line_h", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 4));
    f.hline(0, 6, 16, C.asphalt.yellow); f.hline(0, 9, 16, C.asphalt.yellow);
    for (let x = 0; x < 16; x++) if (noise("wl", x, 1) < 0.15) { f.px(x, 6, shade(C.asphalt.yellow, 0.8)); }
  });
  add(2, 5, "asphalt_line_v", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 5));
    f.vline(6, 0, 16, C.asphalt.yellow); f.vline(9, 0, 16, C.asphalt.yellow);
    for (let y = 0; y < 16; y++) if (noise("wl", y, 2) < 0.15) { f.px(6, y, shade(C.asphalt.yellow, 0.8)); }
  });
  add(2, 6, "asphalt_dash_h", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 6));
    f.hline(1, 7, 6, C.asphalt.yellow); f.hline(1, 8, 6, C.asphalt.yellow);
  });
  add(2, 7, "asphalt_dash_v", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 7));
    f.vline(7, 1, 6, C.asphalt.yellow); f.vline(8, 1, 6, C.asphalt.yellow);
  });
  add(2, 8, "crosswalk_h", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 8));
    for (const y of [1, 5, 9, 13]) { f.rect(0, y, 16, 2, C.asphalt.white); f.hline(0, y + 1, 16, shade(C.asphalt.white, 0.88)); }
  });
  add(2, 9, "crosswalk_v", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 9));
    for (const x of [1, 5, 9, 13]) { f.rect(x, 0, 2, 16, C.asphalt.white); f.vline(x + 1, 0, 16, shade(C.asphalt.white, 0.88)); }
  });
  add(2, 10, "manhole", K, (f) => {
    f.fill((x, y) => asphaltAt(x, y, 10));
    f.ellipse(8, 8, 5.5, 5.5, C.asphalt.crack);
    f.ellipse(8, 8, 4.5, 4.5, C.concrete.chanDark);
    for (const y of [6, 8, 10]) f.hline(4, y, 8, C.asphalt.dark);
    f.vline(8, 4, 8, C.asphalt.dark);
  });

  // ---------- row 3: concrete, pavers, gutters, seams ----------
  add(3, 0, "sidewalk_a", K, (f) => {
    f.fill((x, y) => concreteAt(x, y, 0));
    f.hline(0, 15, 16, C.concrete.joint); f.vline(15, 0, 16, C.concrete.joint);
    f.hline(0, 0, 16, C.concrete.light); f.vline(0, 0, 15, C.concrete.light);
  });
  add(3, 1, "sidewalk_b", K, (f) => {
    f.fill((x, y) => concreteAt(x, y, 1));
    f.hline(0, 7, 16, C.concrete.joint); f.hline(0, 15, 16, C.concrete.joint);
    f.vline(7, 0, 7, C.concrete.joint); f.vline(11, 8, 7, C.concrete.joint);
    f.hline(0, 0, 16, C.concrete.light);
    f.px(3, 3, C.concrete.joint); f.px(4, 4, C.concrete.joint);
  });
  const paver = (f, pal, v) => {
    f.fill((x, y) => (noise("pv", x, y, v) < 0.12 ? pal.shade : pal.base));
    for (let row = 0; row < 4; row++) {
      f.hline(0, row * 4 + 3, 16, C.paver.joint);
      const off = row % 2 ? 4 : 0;
      for (let k = 0; k < 4; k++) f.vline((off + k * 8) % 16, row * 4, 3, C.paver.joint);
      for (let x = 0; x < 16; x++) if (noise("pvl", x, row, v) < 0.25) f.px(x, row * 4, pal.light);
    }
  };
  add(3, 2, "paver_a", K, (f) => paver(f, { base: C.paver.grey, light: C.paver.greyLight, shade: shade(C.paver.grey, 0.93) }, 0));
  add(3, 3, "paver_b", K, (f) => paver(f, { base: C.paver.red, light: C.paver.redLight, shade: shade(C.paver.red, 0.92) }, 1));
  const gutterMask = (kind, x, y) => {
    const v = x >= 4 && x <= 11, h = y >= 4 && y <= 11;
    switch (kind) {
      case "h": return h;
      case "v": return v;
      case "ne": return (v && y <= 11) || (h && x >= 4);
      case "nw": return (v && y <= 11) || (h && x <= 11);
      case "se": return (v && y >= 4) || (h && x >= 4);
      case "sw": return (v && y >= 4) || (h && x <= 11);
    }
    return false;
  };
  const gutter = (f, kind) => {
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const inside = gutterMask(kind, x, y);
      if (!inside) { f.px(x, y, concreteAt(x, y, 4)); continue; }
      const edge = !gutterMask(kind, x - 1, y) || !gutterMask(kind, x + 1, y) || !gutterMask(kind, x, y - 1) || !gutterMask(kind, x, y + 1);
      let c = noise("gt", x, y) < 0.2 ? C.concrete.chanDark : C.concrete.chan;
      if (!edge && noise("gw", x, y) < 0.18) c = C.concrete.water;
      if (edge) c = C.concrete.chanDark;
      f.px(x, y, c);
    }
    // lit lip just outside the channel
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      if (gutterMask(kind, x, y)) continue;
      if (gutterMask(kind, x, y + 1) || gutterMask(kind, x + 1, y)) f.px(x, y, C.concrete.dark);
      else if (gutterMask(kind, x, y - 1) || gutterMask(kind, x - 1, y)) f.px(x, y, C.concrete.light);
    }
  };
  add(3, 4, "gutter_h", K, (f) => gutter(f, "h"));
  add(3, 5, "gutter_v", K, (f) => gutter(f, "v"));
  add(3, 6, "gutter_corner_ne", K, (f) => gutter(f, "ne"));
  add(3, 7, "gutter_corner_nw", K, (f) => gutter(f, "nw"));
  add(3, 8, "gutter_corner_se", K, (f) => gutter(f, "se"));
  add(3, 9, "gutter_corner_sw", K, (f) => gutter(f, "sw"));
  add(3, 10, "drain", K, (f) => {
    f.fill((x, y) => concreteAt(x, y, 5));
    f.rect(2, 3, 12, 10, C.concrete.joint);
    f.rect(3, 4, 10, 8, C.concrete.chanDark);
    for (let x = 4; x < 12; x += 2) f.vline(x, 4, 8, C.concrete.chan);
    f.hline(0, 15, 16, C.concrete.joint);
  });
  const seam = (f, dir, asphaltFirst) => {
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const t = dir === "h" ? y : x;
      const cut = 8 + Math.round(wobble("seam" + dir, dir === "h" ? x : y, 1.4));
      const asphalt = asphaltFirst ? t < cut : t >= cut;
      f.px(x, y, asphalt ? asphaltAt(x, y, 0) : lastreAt(x, y, 0));
      const nb = dir === "h" ? Math.abs(y - cut) < 1 : Math.abs(x - cut) < 1;
      if (nb && asphalt) f.px(x, y, C.lastre.stoneDark);
    }
  };
  add(3, 11, "seam_asphalt_n", K, (f) => seam(f, "h", true));
  add(3, 12, "seam_asphalt_s", K, (f) => seam(f, "h", false));
  add(3, 13, "seam_asphalt_w", K, (f) => seam(f, "v", true));
  add(3, 14, "seam_asphalt_e", K, (f) => seam(f, "v", false));

  // ---------- row 4: river ----------
  const waterStreaks = (f, r, n) => {
    for (let i = 0; i < n; i++) {
      const x = r.int(0, 15), y = r.int(0, 15), len = r.int(3, 6);
      for (let k = 0; k < len; k++) f.px((x + k) % 16, y, k === 0 || k === len - 1 ? C.river.mid : C.river.light);
    }
  };
  const solid = { solid: true };
  add(4, 0, "water_a", solid, (f, r) => { f.fill((x, y) => waterAt(x, y, 0)); waterStreaks(f, r, 3); });
  add(4, 1, "water_b", solid, (f, r) => { f.fill((x, y) => waterAt(x, y, 1)); waterStreaks(f, r, 4); });
  add(4, 2, "water_ripple", solid, (f, r) => {
    f.fill((x, y) => waterAt(x, y, 2));
    waterStreaks(f, r, 2);
    f.hline(3, 5, 4, C.river.foam); f.hline(9, 11, 3, C.river.foam); f.hline(4, 12, 2, C.river.light);
  });
  // bank: land tile whose rim toward the water is wet mud
  const bankDepth = (side, x, y) => {
    const u = side === "N" || side === "S" ? x : y;
    const d = side === "N" ? y : side === "S" ? 15 - y : side === "W" ? x : 15 - x;
    return d + 0.5 < 3.2 + wobble("bank" + side, u, 1.2);
  };
  const bank = (f, sides) => {
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const wet = sides.some((s) => bankDepth(s, x, y));
      const veryWet = sides.some((s) => {
        const d = s === "N" ? y : s === "S" ? 15 - y : s === "W" ? x : 15 - x;
        return d < 1;
      });
      let c = lastreAt(x, y, 7);
      if (wet) c = noise("mud", x, y) < 0.25 ? C.river.mudDark : C.river.mud;
      if (veryWet) c = noise("foam", x, y) < 0.35 ? C.river.foam : mix(C.river.mudDark, C.river.base, 0.5);
      f.px(x, y, c);
    }
  };
  for (const [col, s] of [[3, "N"], [4, "E"], [5, "S"], [6, "W"]]) add(4, col, `bank_${s.toLowerCase()}`, L, (f) => bank(f, [s]));
  for (const [col, s] of [[7, "NE"], [8, "NW"], [9, "SE"], [10, "SW"]]) add(4, col, `bank_corner_${s.toLowerCase()}`, L, (f) => bank(f, s.split("")));
  add(4, 11, "river_stones", L, (f, r) => {
    f.fill((x, y) => lastreAt(x, y, 8));
    const spots = [[4, 5, 3], [11, 4, 2.5], [8, 11, 3.5], [3, 12, 2]];
    for (const [cx, cy, rad] of spots) {
      f.ellipse(cx + 0.5, cy + 1, rad + 0.5, rad - 0.5, withAlpha(C.river.mudDark, 120));
      f.ellipse(cx, cy, rad, rad - 0.5, C.river.stoneDark);
      f.ellipse(cx - 0.5, cy - 0.5, rad - 1, rad - 1.5, C.river.stone);
      f.px(cx - 1, cy - 1, C.rock.light);
    }
  });
  add(4, 12, "riverside_grass", Z, (f, r) => {
    f.fill((x, y) => (noise("wetg", x, y) < 0.3 ? C.zacate.tall : grassAt(x, y, 9)));
    for (let i = 0; i < 5; i++) tuft(f, r.int(1, 14), r.int(4, 13), C.zacate.light, C.zacate.tall);
  });

  return T;
}
