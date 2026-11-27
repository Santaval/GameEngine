// Position-based material samplers and edge masks. Each sampler depends only on
// (x, y, variant), so an edge tile and a fill tile of the same material agree pixel for pixel.
import { C } from "./palette.mjs";
import { noise, wobble } from "./rng.mjs";
import { mix } from "./draw.mjs";

export function grassAt(x, y, v = 0) {
  const r = noise("grass", x, y, v);
  const clump = noise("grassc", x >> 1, y >> 1, v);
  if (r < 0.1) return C.zacate.dark;
  if (clump < 0.2 || r < 0.26) return C.zacate.mid;
  if (r > 0.965) return C.zacate.hi;
  if (r > 0.9) return C.zacate.light;
  return C.zacate.base;
}

export function dryGrassAt(x, y, v = 0) {
  const r = noise("drygrass", x, y, v);
  if (r < 0.3) return C.zacate.dryDark;
  if (r < 0.55) return C.zacate.dry;
  return grassAt(x, y, v + 7);
}

export function lastreAt(x, y, v = 0) {
  const r = noise("lastre", x, y, v);
  if (r < 0.07) return C.lastre.dark;
  if (r < 0.14) return C.lastre.light;
  if (noise("lastrestone", x >> 1, y >> 1, v) > 0.93) return r > 0.5 ? C.lastre.stone : C.lastre.stoneDark;
  return C.lastre.base;
}

export function soilAt(x, y, v = 0) {
  const r = noise("soil", x, y, v);
  if (r < 0.1) return C.soil.clod;
  if (r < 0.22) return C.soil.dark;
  if (r > 0.9) return C.soil.light;
  return C.soil.base;
}

export function asphaltAt(x, y, v = 0) {
  const r = noise("asphalt", x, y, v);
  if (r < 0.09) return C.asphalt.dark;
  if (r > 0.92) return C.asphalt.light;
  return C.asphalt.base;
}

export function concreteAt(x, y, v = 0) {
  const r = noise("concrete", x, y, v);
  if (r < 0.06) return C.concrete.stain;
  if (r > 0.94) return C.concrete.light;
  return C.concrete.base;
}

export function waterAt(x, y, v = 0) {
  const r = noise("water", x, y, v);
  if (r < 0.14) return C.river.mid;
  if (r > 0.97) return C.river.light;
  return C.river.base;
}

// ---- masks (true = grass side) for lastre edges ----
const band = (salt, u) => 4.6 + wobble(salt, u, 1.7);

export function sideGrass(side, x, y) {
  switch (side) {
    case "N": return y + 0.5 < band("lN", x);
    case "S": return 15 - y + 0.5 < band("lS", x);
    case "W": return x + 0.5 < band("lW", y);
    case "E": return 15 - x + 0.5 < band("lE", y);
  }
  return false;
}

/** Convex rounding of the lastre corner: grass in the corner outside a quarter circle. */
function rounded(cornerSides, x, y) {
  const u = cornerSides.includes("W") ? x : 15 - x;
  const v = cornerSides.includes("N") ? y : 15 - y;
  const R = 4, c = 4.6 + R;
  if (u + 0.5 >= c || v + 0.5 >= c) return false;
  return Math.hypot(u + 0.5 - c, v + 0.5 - c) > R;
}

/** kind: "edge" (one side), "outer" (two sides: lastre corner pokes out), "inner" (grass notch). */
export function grassMask(kind, sides) {
  return (x, y) => {
    if (kind === "edge") return sideGrass(sides[0], x, y);
    if (kind === "outer") return sideGrass(sides[0], x, y) || sideGrass(sides[1], x, y) || rounded(sides, x, y);
    return sideGrass(sides[0], x, y) && sideGrass(sides[1], x, y);
  };
}

/**
 * Paint a two-material tile from a mask. insideFn(x,y) -> true where material A shows.
 * Border pixels are darkened so the transition reads clearly.
 */
export function paintBlend(f, insideFn, samplerA, samplerB, rimA, rimB) {
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const a = insideFn(x, y);
    const nb = insideFn(x + 1, y) !== a || insideFn(x - 1, y) !== a || insideFn(x, y + 1) !== a || insideFn(x, y - 1) !== a;
    let c = a ? samplerA(x, y) : samplerB(x, y);
    if (nb) c = a ? (rimA ?? c) : (rimB ?? c);
    f.px(x, y, c);
  }
}

export { mix };
