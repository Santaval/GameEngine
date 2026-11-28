// VFX sprite generator for the legends (issue #74, part of #37).
//   node vfx.mjs   write sprites/vfx_*.png and sprites/vfx_*.json (Aseprite array format, one sheet per effect)
// Every sheet is a single row of equal frames; transparent background, self-lit cores, calm pacing, deterministic.
//   vfx_luz      32x32  appear (6f fwd, 140ms) | idle (6f pingpong, 200ms) | fade (6f fwd, 140ms)
//   vfx_chispa   32x32  spark  (6f fwd, 70ms)  | arc  (6f fwd, 60ms)
//   vfx_machete  32x32  slash  (5f fwd, 50ms)  | hit  (4f fwd, 60ms)
//   vfx_llorona  48x48  form   (8f fwd, 160ms) | idle (6f pingpong, 220ms) | dissolve (8f fwd, 160ms)
// Optional preview: PREVIEW_DIR=/some/dir node vfx.mjs also writes x4 previews on the night colour (20,26,51).
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Frame, rgb, mix } from "./draw.mjs";
import { encodePng } from "./png.mjs";
import { rng, rand } from "./vendor/pixelfx/math.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SPRITES = join(HERE, "..", "..", "sprites");

const clamp01 = (v) => Math.max(0, Math.min(1, v));
const smooth = (t) => t * t * (3 - 2 * t);
/** Quantise alpha to a few steps so glows stay pixel-art (banded) instead of smooth gradients. */
const band = (a, steps = 5) => Math.round(clamp01(a) * steps) / steps;
const col = (c, a) => [c[0], c[1], c[2], Math.round(clamp01(a) * 255)];

/** Writes sheet PNG + Aseprite JSON. tags: [{name, from, to, direction, ms}] over `frames`. */
function writeSheet(name, fw, fh, frames, tags) {
  const sheet = new Frame(fw * frames.length, fh);
  frames.forEach((f, i) => sheet.blit(f, i * fw, 0));
  writeFileSync(join(SPRITES, `${name}.png`), encodePng(sheet.w, sheet.h, sheet.data));
  const dur = new Array(frames.length).fill(100);
  for (const t of tags) for (let i = t.from; i <= t.to; i++) dur[i] = t.ms;
  const json = {
    frames: frames.map((_, i) => ({
      filename: `${name} ${i}`,
      frame: { x: i * fw, y: 0, w: fw, h: fh },
      rotated: false,
      trimmed: false,
      spriteSourceSize: { x: 0, y: 0, w: fw, h: fh },
      sourceSize: { w: fw, h: fh },
      duration: dur[i],
    })),
    meta: {
      app: "pixelfx-demo",
      version: "1.0",
      format: "RGBA8888",
      size: { w: sheet.w, h: sheet.h },
      scale: "1",
      frameTags: tags.map(({ name: n, from, to, direction }) => ({ name: n, from, to, direction })),
    },
  };
  writeFileSync(join(SPRITES, `${name}.json`), JSON.stringify(json, null, 1) + "\n");
  console.log(`vfx: wrote sprites/${name}.png (${sheet.w}x${sheet.h}, ${frames.length} frames) and ${name}.json`);
  if (process.env.PREVIEW_DIR) {
    mkdirSync(process.env.PREVIEW_DIR, { recursive: true });
    const p = sheet.onBackground([20, 26, 51, 255]).scaled(4);
    writeFileSync(join(process.env.PREVIEW_DIR, `${name}_night.png`), encodePng(p.w, p.h, p.data));
  }
}

// ---------------------------------------------------------------- luz
const LUZ_CORE = rgb("#fffbe0");
const LUZ_MID = rgb("#ffe58a");
const LUZ_OUT = rgb("#ffb347");

function luzFrame(radius, intensity, seed, tick, motes) {
  const f = new Frame(32, 32);
  const cx = 16, cy = 16;
  if (radius > 0.3) {
    f.fill((x, y) => {
      const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / radius;
      if (d >= 1) return null;
      const a = band(Math.pow(1 - d, 1.8) * intensity * 0.85, 6);
      if (a <= 0) return null;
      const c = d < 0.35 ? mix(LUZ_MID, LUZ_OUT, d / 0.35 * 0.3) : mix(LUZ_MID, LUZ_OUT, clamp01((d - 0.35) / 0.65));
      return col(c, a);
    });
    // bright self-lit core
    const cr = Math.max(0.8, radius * 0.2);
    f.ellipse(cx, cy, cr * 1.8, cr * 1.8, col(LUZ_MID, 0.9 * intensity));
    f.ellipse(cx, cy, cr * 1.1, cr * 1.1, col(LUZ_CORE, intensity));
  }
  for (let i = 0; i < motes; i++) {
    const r = rng(seed, i);
    const ang = r.range(0, Math.PI * 2);
    const dist = r.range(6, 13);
    const ph = r.range(0, 1);
    const t = (tick / 6 + ph) % 1;
    const x = cx + Math.cos(ang) * dist * (0.7 + 0.3 * t);
    const y = cy + Math.sin(ang) * dist * (0.7 + 0.3 * t) - t * 4;
    f.px(x, y, col(LUZ_CORE, intensity * Math.sin(Math.PI * t) * 0.95));
  }
  return f;
}

function genLuz() {
  const frames = [];
  for (let i = 0; i < 6; i++) { // appear: grows from a point
    const t = (i + 1) / 6;
    frames.push(luzFrame(2 + 11 * smooth(t), 0.35 + 0.65 * t, 11, i, i >= 3 ? 3 : 0));
  }
  for (let i = 0; i < 6; i++) { // idle: slow pulse (pingpong)
    const p = i / 5;
    frames.push(luzFrame(11 + 2.2 * p, 0.85 + 0.15 * p, 11, i, 4));
  }
  for (let i = 0; i < 6; i++) { // fade: shrinks and dims
    const t = i / 6;
    frames.push(luzFrame(13 - 11 * smooth(t), 1 - 0.85 * t, 11, i + 2, i < 3 ? 2 : 0));
  }
  writeSheet("vfx_luz", 32, 32, frames, [
    { name: "appear", from: 0, to: 5, direction: "forward", ms: 140 },
    { name: "idle", from: 6, to: 11, direction: "pingpong", ms: 200 },
    { name: "fade", from: 12, to: 17, direction: "forward", ms: 140 },
  ]);
}

// ---------------------------------------------------------------- chispa
const SP_CYAN = rgb("#5fe6ff");
const SP_WHITE = rgb("#f4fdff");
const SP_YEL = rgb("#fff3a0");

function genChispa() {
  const frames = [];
  // spark: scattered seeded sparks burst outward from the centre, fading and falling a little
  const N = 14;
  for (let i = 0; i < 6; i++) {
    const f = new Frame(32, 32);
    const t = i / 5;
    for (let k = 0; k < N; k++) {
      const r = rng(5, k);
      const ang = r.range(0, Math.PI * 2);
      const speed = r.range(5, 12);
      const delay = r.range(0, 0.25);
      const tt = clamp01((t - delay) / (1 - delay));
      if (t < delay) continue;
      const x = 16 + Math.cos(ang) * speed * tt;
      const y = 16 + Math.sin(ang) * speed * tt + 4 * tt * tt;
      const life = 1 - tt * tt * 0.85;
      const c = k % 3 === 0 ? SP_YEL : k % 3 === 1 ? SP_WHITE : SP_CYAN;
      // short trail
      const tx = x - Math.cos(ang) * 2, ty = y - Math.sin(ang) * 2 - 1.5 * tt;
      f.px(tx, ty, col(SP_CYAN, 0.6 * life));
      f.px(x, y, col(c, life));
      if (tt < 0.6) f.px(x + 1, y, col(SP_CYAN, 0.4 * life));
    }
    if (i < 2) { // initial flash
      f.ellipse(16, 16, 3 - i, 3 - i, col(SP_CYAN, 0.45));
      f.px(16, 16, col(SP_WHITE, 1));
      f.px(15, 16, col(SP_WHITE, 1)); f.px(16, 15, col(SP_WHITE, 1)); f.px(17, 16, col(SP_WHITE, 0.8));
    }
    frames.push(f);
  }
  // arc: jagged 3-segment electric arc between two points, re-rolled every frame (flicker)
  const A = [4, 21], B = [27, 11];
  for (let i = 0; i < 6; i++) {
    const f = new Frame(32, 32);
    const r = rng(23, i);
    const segs = i % 3 === 2 ? 2 : 3;
    const pts = [A];
    for (let s = 1; s < segs; s++) {
      const u = s / segs;
      pts.push([
        Math.round(A[0] + (B[0] - A[0]) * u + r.range(-2, 2)),
        Math.round(A[1] + (B[1] - A[1]) * u + r.range(-5, 5)),
      ]);
    }
    pts.push(B);
    const bright = i % 2 === 0 ? 1 : 0.75;
    for (let s = 0; s < pts.length - 1; s++) { // glow pass
      const [x0, y0] = pts[s], [x1, y1] = pts[s + 1];
      f.line(x0, y0 - 1, x1, y1 - 1, col(SP_CYAN, 0.22 * bright));
      f.line(x0, y0 + 1, x1, y1 + 1, col(SP_CYAN, 0.22 * bright));
      f.line(x0 + 1, y0, x1 + 1, y1, col(SP_CYAN, 0.18 * bright));
    }
    for (let s = 0; s < pts.length - 1; s++) f.line(pts[s][0], pts[s][1], pts[s + 1][0], pts[s + 1][1], col(SP_CYAN, bright));
    for (let s = 0; s < pts.length - 1; s++) { // hot core, skip first pixels so cyan shows at the ends
      const [x0, y0] = pts[s], [x1, y1] = pts[s + 1];
      f.line(x0, y0, x1, y1, col(SP_WHITE, 0.9 * bright));
    }
    for (const p of [A, B]) { f.px(p[0], p[1], col(SP_YEL, 1)); f.px(p[0] - 1, p[1], col(SP_CYAN, 0.5)); f.px(p[0] + 1, p[1], col(SP_CYAN, 0.5)); }
    // a stray spark or two
    for (let k = 0; k < 2; k++) {
      const q = pts[1 + (k % (pts.length - 2 || 1))] || A;
      f.px(q[0] + r.int(-4, 4), q[1] + r.int(-4, 4), col(SP_YEL, 0.9));
    }
    frames.push(f);
  }
  writeSheet("vfx_chispa", 32, 32, frames, [
    { name: "spark", from: 0, to: 5, direction: "forward", ms: 70 },
    { name: "arc", from: 6, to: 11, direction: "forward", ms: 60 },
  ]);
}

// ---------------------------------------------------------------- machete
const M_WHITE = rgb("#ffffff");
const M_STEEL = rgb("#c4d4e6");
const M_DEEP = rgb("#7f9ab8");

function genMachete() {
  const frames = [];
  // slash: crescent swept from upper-left over to lower-right; the head advances, the tail fades
  const cx = 11, cy = 26, R = 18;
  const a0 = -Math.PI * 0.62, a1 = Math.PI * 0.02; // angular sweep range (screen angles, y down)
  const N = 5;
  for (let i = 0; i < N; i++) {
    const f = new Frame(32, 32);
    const head = a0 + (a1 - a0) * ((i + 1) / N) * 1.0;
    const tail = a0 + (a1 - a0) * Math.max(0, (i - 2) / N);
    f.fill((x, y) => {
      const dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      const d = Math.hypot(dx, dy);
      const a = Math.atan2(dy, dx);
      if (a < tail || a > head) return null;
      const u = (a - tail) / (head - tail || 1); // 0 tail .. 1 head
      const width = 1 + 4.5 * Math.sin(Math.PI * Math.min(1, u * 0.9 + 0.1)) * (0.5 + 0.5 * u);
      const off = d - (R - 2.5 + 2.5 * u);
      if (Math.abs(off) > width) return null;
      const edge = 1 - Math.abs(off) / width;
      const fade = clamp01(0.25 + u * 0.9) * (1 - Math.max(0, i - 3) * 0.3);
      const v = band(edge * fade * 1.25, 4);
      if (v <= 0) return null;
      const c = edge > 0.65 && u > 0.35 ? M_WHITE : edge > 0.3 ? M_STEEL : M_DEEP;
      return col(c, v);
    });
    frames.push(f);
  }
  // hit: starburst flash expanding then fading
  const radii = [4, 9, 12, 13];
  for (let i = 0; i < 4; i++) {
    const f = new Frame(32, 32);
    const al = [1, 0.95, 0.65, 0.3][i];
    const rr = radii[i];
    const rays = 8;
    for (let k = 0; k < rays; k++) {
      const ang = (k / rays) * Math.PI * 2 + 0.2;
      const len = rr * (k % 2 === 0 ? 1 : 0.6);
      const inner = i * 1.6;
      f.line(Math.round(16 + Math.cos(ang) * inner), Math.round(16 + Math.sin(ang) * inner),
        Math.round(16 + Math.cos(ang) * len), Math.round(16 + Math.sin(ang) * len), col(M_STEEL, al));
    }
    if (i < 3) f.ellipse(16, 16, 3.5 - i, 3.5 - i, col(M_WHITE, al));
    if (i === 0) f.ellipse(16, 16, 5, 5, col(M_STEEL, 0.45));
    if (i >= 2) { // debris sparks
      for (let k = 0; k < 6; k++) {
        const ang = rand(9, k) * Math.PI * 2;
        const d = rr + 2 + k % 3;
        f.px(16 + Math.cos(ang) * d, 16 + Math.sin(ang) * d, col(M_WHITE, al));
      }
    }
    frames.push(f);
  }
  writeSheet("vfx_machete", 32, 32, frames, [
    { name: "slash", from: 0, to: 4, direction: "forward", ms: 50 },
    { name: "hit", from: 5, to: 8, direction: "forward", ms: 60 },
  ]);
}

// ---------------------------------------------------------------- llorona
const MIST_LIGHT = rgb("#c9d8ea");
const MIST_DARK = rgb("#7e8fb0");

function vnoise(x, y, seed) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const fx = smooth(x - xi), fy = smooth(y - yi);
  const v = (a, b) => rand(seed, a, b);
  const top = v(xi, yi) * (1 - fx) + v(xi + 1, yi) * fx;
  const bot = v(xi, yi + 1) * (1 - fx) + v(xi + 1, yi + 1) * fx;
  return top * (1 - fy) + bot * fy;
}

/** Hooded silhouette weight in [0,1] at (x,y) of a 48x48 frame. */
function hoodShape(x, y) {
  const cx = 24;
  const dx = Math.abs(x + 0.5 - cx);
  // head/hood: oval near the top
  const head = 1 - Math.hypot(dx / 6.5, (y - 12) / 8);
  // body: widens downward like a cloak, tapering into wisps at the bottom
  const t = clamp01((y - 16) / 28);
  const half = 6 + 10 * t;
  const body = y >= 15 ? clamp01(1 - dx / half) * clamp01(1 - Math.pow(clamp01((y - 30) / 16), 1.4)) : 0;
  // darker hollow where the face would be
  return Math.max(clamp01(head * 1.4), body);
}

function llFrame(tick, strength, shapeAmt, spread) {
  const f = new Frame(48, 48);
  const drift = tick * 0.55;
  f.fill((x, y) => {
    const sx = x + Math.sin(drift + y * 0.12) * 1.5 * spread;
    const n = vnoise((sx + drift * 2) / 5, (y + drift) / 5, 31) * 0.65 + vnoise((sx - drift) / 2.5, (y + drift * 2) / 2.5, 77) * 0.35;
    const shape = hoodShape(sx, y);
    const blob = Math.max(0, 1 - Math.hypot((x - 24) / (17 * spread), (y - 26) / (21 * spread)));
    const base = shapeAmt * shape + (1 - shapeAmt) * blob;
    let a = base * (0.35 + n * 0.9) - 0.12;
    // hollow face: slightly darker, even less opaque, and a hint of eyes
    const hollow = shapeAmt * clamp01(1 - Math.hypot((x - 24) / 3.5, (y - 12) / 4.5));
    a -= hollow * 0.25;
    a = band(clamp01(a) * 0.5 * strength, 14) * 1; // top out ~0.35 alpha after strength
    if (a <= 0.02) return null;
    const dark = hollow > 0.3 || n < 0.35;
    return col(dark ? MIST_DARK : MIST_LIGHT, Math.min(0.35, a * 0.7));
  });
  return f;
}

function genLlorona() {
  const frames = [];
  for (let i = 0; i < 8; i++) { // form: diffuse cloud condenses into the figure
    const t = (i + 1) / 8;
    frames.push(llFrame(i, 0.35 + 0.65 * smooth(t), smooth(t) * 0.9, 1.35 - 0.35 * smooth(t)));
  }
  for (let i = 0; i < 6; i++) frames.push(llFrame(8 + i, 1, 0.9, 1)); // idle drift (pingpong)
  for (let i = 0; i < 8; i++) { // dissolve: figure unravels and thins out
    const t = (i + 1) / 8;
    frames.push(llFrame(14 + i, 1 - 0.95 * smooth(t), 0.9 * (1 - smooth(t)), 1 + 0.5 * smooth(t)));
  }
  writeSheet("vfx_llorona", 48, 48, frames, [
    { name: "form", from: 0, to: 7, direction: "forward", ms: 160 },
    { name: "idle", from: 8, to: 13, direction: "pingpong", ms: 220 },
    { name: "dissolve", from: 14, to: 21, direction: "forward", ms: 160 },
  ]);
}

genLuz();
genChispa();
genMachete();
genLlorona();
