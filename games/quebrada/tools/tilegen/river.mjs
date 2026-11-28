// The quebrada (river) course of zone 1: pure geometry, no tiles (docs/rio.md).
//
// The river runs the FULL WIDTH of the map (west-east), north of everything. Its centre line is a function row = c(col) in the ORIGINAL (pre-TOP_PAD) row frame, so it is
// negative where the river lies north of the old map. Anchors pin the centre line at the user's three measured distances (north of an object, in tiles):
//   church   door column, building top row     RIVER_CHURCH_M  = 175 m  (the user said 150-200 m)
//   cafetal  centre column, north fence row    RIVER_CAFETAL_M = 20 m
//   mama     house centre column, top row      RIVER_MAMA_M    = 50 m
// Between the anchors the baseline is a smoothstep; seeded low-frequency noise (+-5 tiles, wavelengths 27-62 tiles) makes it wander. The noise is zero (flat) within
// ANCHOR_FLAT columns of every anchor and within BRIDGE_FLAT columns of the bridge, so the measured distances are exact and the crossing is straight and horizontal.
// The water mask is the union of discs along the centre line (radius from a varying width), cleaned of slivers (1-tile peninsulas / 1-tile channels / holes).
import { noise } from "./rng.mjs";

const smooth = (t) => t * t * (3 - 2 * t);
const taper = (d, flat, ramp) => (d <= flat ? 0 : d >= flat + ramp ? 1 : smooth((d - flat) / ramp)); // 0 within `flat`, 1 beyond flat + ramp
const lat = (salt, t) => { // 1-D value noise in [-1, 1] (cosine interpolation over an integer lattice)
  const i = Math.floor(t), f = t - i, s = (1 - Math.cos(f * Math.PI)) / 2;
  return (noise(salt, i, 0) * (1 - s) + noise(salt, i + 1, 0) * s) * 2 - 1;
};

export const ANCHOR_FLAT = 8, ANCHOR_RAMP = 18; // noise-free columns each side of an anchor / the ramp back up to full noise
export const BRIDGE_FLAT = 9, BRIDGE_RAMP = 12;
export const FLAT_WIDTH = 4.4; // river width (tiles) on the flat stretches (anchors, bridge)
export const GRASS_NORTH = 6; // grass rows required north of the northernmost bank

/** o: { mapW, anchors: [{ id, col, top, tiles }], bridgeCentre (col boundary x, tiles), seed }. `top` = the object's top row in the ORIGINAL frame; the centre line is `tiles` rows north of it. */
export function makeRiver({ mapW, anchors, bridgeCentre, seed = "rio" }) {
  const A = anchors.map((a) => ({ ...a, row: a.top - a.tiles })).sort((p, q) => p.col - q.col);
  const baseline = (x) => {
    if (x <= A[0].col) return A[0].row;
    for (let i = 1; i < A.length; i++) if (x <= A[i].col) { // the smoothstep runs between the flat stretches around the anchors
      const x0 = A[i - 1].col + ANCHOR_FLAT, x1 = A[i].col - ANCHOR_FLAT;
      return A[i - 1].row + (A[i].row - A[i - 1].row) * smooth(Math.max(0, Math.min(1, (x - x0) / (x1 - x0))));
    }
    return A[A.length - 1].row;
  };
  const weight = (x) => Math.min(taper(Math.abs(x - bridgeCentre), BRIDGE_FLAT, BRIDGE_RAMP), ...A.map((a) => taper(Math.abs(x - a.col), ANCHOR_FLAT, ANCHOR_RAMP)));
  const centre = (x) => baseline(x) + weight(x) * (2.6 * lat(seed + "1", x / 62) + 1.6 * lat(seed + "2", x / 41 + 7.3) + 0.8 * lat(seed + "3", x / 27 + 3.1));
  const width = (x) => {
    const w0 = 4.7 + 1.5 * lat(seed + "w", x / 33) + 0.4 * lat(seed + "v", x / 14);
    return Math.max(3.2, Math.min(6, FLAT_WIDTH + (w0 - FLAT_WIDTH) * weight(x)));
  };
  const radius = (x) => width(x) / 2 + 0.35;

  // fine samples of the centre line (every 0.25 col) for the disc union
  const STEP = 0.25, N = Math.round((mapW + 8) / STEP) + 1;
  const sx = new Float64Array(N), sc = new Float64Array(N), sr = new Float64Array(N);
  for (let k = 0; k < N; k++) { sx[k] = -4 + k * STEP; sc[k] = centre(sx[k]); sr[k] = radius(sx[k]); }
  let lo = Infinity, hi = -Infinity;
  for (let k = 0; k < N; k++) { lo = Math.min(lo, sc[k] - sr[k]); hi = Math.max(hi, sc[k] + sr[k]); }
  const rMin = Math.floor(lo) - 3, rMax = Math.ceil(hi) + 3, H = rMax - rMin + 1;
  const W = new Uint8Array(mapW * H); // [row - rMin][col]
  for (let x = 0; x < mapW; x++) {
    const k0 = Math.round((x - 4 + 4) / STEP), k1 = Math.round((x + 4 + 4) / STEP);
    for (let r = rMin; r <= rMax; r++) {
      let inside = false;
      for (let k = Math.max(0, k0); k <= Math.min(N - 1, k1) && !inside; k++) {
        const dx = sx[k] - x, dy = sc[k] - r;
        if (dx * dx + dy * dy <= sr[k] * sr[k]) inside = true;
      }
      if (inside) W[(r - rMin) * mapW + x] = 1;
    }
  }
  const get = (x, r) => (r < rMin || r > rMax ? 0 : W[(r - rMin) * mapW + Math.max(0, Math.min(mapW - 1, x))]);
  // clean slivers: a land cell with water on two opposite sides or on >= 3 sides becomes water; a water cell with <= 1 water neighbour or with land on two opposite sides becomes land
  let passes = 0;
  for (; passes < 40; passes++) {
    let changed = 0;
    const next = W.slice();
    for (let r = rMin; r <= rMax; r++) for (let x = 0; x < mapW; x++) {
      const n = get(x, r - 1), s = get(x, r + 1), e = x + 1 < mapW ? get(x + 1, r) : get(x, r), w = x > 0 ? get(x - 1, r) : get(x, r), here = get(x, r), cnt = n + s + e + w;
      let v = here;
      if (!here && ((n && s) || (e && w) || cnt >= 3)) v = 1;
      else if (here && (cnt <= 1 || (!n && !s) || (!e && !w))) v = 0;
      if (v !== here) { next[(r - rMin) * mapW + x] = v; changed++; }
    }
    W.set(next);
    if (!changed) break;
  }
  // the northernmost water row -> TOP_PAD: bank row = minWater - 1, and GRASS_NORTH grass rows must lie above it
  let minWater = Infinity, maxWater = -Infinity;
  for (let r = rMin; r <= rMax; r++) for (let x = 0; x < mapW; x++) if (get(x, r)) { minWater = Math.min(minWater, r); maxWater = Math.max(maxWater, r); }
  const topPad = GRASS_NORTH + 1 - minWater;

  /** The water run (rows) containing the centre line in column x -> { a, b, centre (row index), thickness }. */
  const run = (x) => {
    let r = Math.round(centre(x));
    if (!get(x, r)) throw new Error(`river: no water on the centre line at col ${x}`);
    let a = r, b = r;
    while (get(x, a - 1)) a--;
    while (get(x, b + 1)) b++;
    return { a, b, centre: (a + b) / 2, thickness: b - a + 1 };
  };
  let minT = Infinity, maxT = -Infinity, slopeMax = 0;
  for (let x = 0; x < mapW; x++) { const t = run(x).thickness; minT = Math.min(minT, t); maxT = Math.max(maxT, t); slopeMax = Math.max(slopeMax, Math.abs(centre(x + 1) - centre(x))); }
  return {
    anchors: A, bridgeCentre, centre, width, topPad, rMin, rMax, minWater, maxWater, run, passes,
    isWater: (x, r) => get(x, r) === 1, // ORIGINAL row frame
    stats: { minThickness: minT, maxThickness: maxT, slopeMax },
  };
}
