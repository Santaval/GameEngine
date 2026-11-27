// Seeded randomness. hash / Rng come from pixelfx (vendor/pixelfx/math.mjs).
import { hash, rand, Rng } from "./vendor/pixelfx/math.mjs";

export { hash, rand, Rng };

export const GLOBAL_SEED = 5501;

/** Stable 32 bit hash of a string. */
export function strHash(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

/** Per-tile generator: editing one tile never changes the others. */
export const tileRng = (name) => new Rng(hash(GLOBAL_SEED, strHash(name)));

/** Position-only noise in [0,1): the same pixel always gets the same value. */
export const noise = (salt, x, y, v = 0) => rand(GLOBAL_SEED, strHash(salt), v, x, y);

/** Periodic wobble with period 16 so edge tiles line up with their neighbours. */
export function wobble(salt, u, amp = 1.5) {
  const p = (strHash(salt) % 628) / 100;
  const t = (u * Math.PI * 2) / 16;
  return amp * (0.6 * Math.sin(t + p) + 0.4 * Math.sin(2 * t + p * 2.3));
}
