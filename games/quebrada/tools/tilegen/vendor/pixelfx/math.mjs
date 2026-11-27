// Vendored from patch-gg/pixelfx (MIT, see LICENSE in this folder).
// Source: src/core/math.js, lines 53-99 (hash, rand, Rng, rng), unmodified.
// Commit: 5294518ce7c72e48b6100a744596e0acf57f2826
/** 32-bit integer hash of any number of integers. */
export function hash(...ns) {
  let h = 0x9e3779b9;
  for (const n of ns) {
    h = Math.imul(h ^ (n | 0), 0x85ebca6b);
    h ^= h >>> 13;
    h = Math.imul(h, 0xc2b2ae35);
    h ^= h >>> 16;
  }
  return h >>> 0;
}
/** Deterministic random number in [0, 1) from integers (seed, particle index, which value...). */
export const rand = (...ns) => hash(...ns) / 4294967296;

/** Seeded random generator (mulberry32). */
export class Rng {
  constructor(seed = 1) {
    this.s = seed >>> 0 || 1;
  }
  next() {
    let t = (this.s = (this.s + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  range(a, b) {
    return a + (b - a) * this.next();
  }
  int(a, b) {
    return Math.floor(this.range(a, b + 1));
  }
  chance(p) {
    return this.next() < p;
  }
  sign() {
    return this.next() < 0.5 ? -1 : 1;
  }
  pick(list) {
    return list[Math.floor(this.next() * list.length)];
  }
  /** Roughly normal, mean 0, sd 1. */
  gauss() {
    return (this.next() + this.next() + this.next() + this.next() - 2) * 1.732;
  }
}
/** A generator for one particle: rng(seed, i) gives the same numbers every frame. */
export const rng = (...ns) => new Rng(hash(...ns));
