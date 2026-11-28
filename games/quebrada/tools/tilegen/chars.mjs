// Placeholder character sprite generator (issue #56, part of #37).
//   node chars.mjs   write sprites/dummy.png and sprites/dummy.json (grey 24x38 dummy, pixelfx-style)
// Sheet = 20 frames of 24x38 in one row (480x38), same tag layout as sprites/hero.json:
//   0-3 idle_down/up/left/right, 4-7 walk_down, 8-11 walk_up, 12-15 walk_left, 16-19 walk_right.
// The left walk is the right walk mirrored horizontally (no flip needed at runtime).
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Frame, rgb } from "./draw.mjs";
import { encodePng } from "./png.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SPRITES = join(HERE, "..", "..", "sprites");

const W = 24;
const H = 38;
const FRAME_MS = 120;

const BODY = rgb("#9a9a9a");
const SHADE = rgb("#737373");
const LIGHT = rgb("#c4c4c4");
const HAIR = rgb("#4d4d4d");
const EYE = rgb("#1e1e1e");
const OUTLINE = rgb("#2a2a2a");

/** Silhouette for one pose. dir: "down" | "up" | "right". s: stride phase in {-1, 0, 1}. */
function pose(dir, s) {
  const f = new Frame(W, H);
  if (dir === "right") {
    f.ellipse(12.5, 8.5, 5, 6.5, BODY); // head
    f.rect(9, 15, 7, 11, BODY); // torso
    f.rect(13, 16 - s, 2, 8, BODY); // front arm
    f.rect(9, 16 + s, 2, 7, SHADE); // back arm
    const frontLift = s > 0 ? 1 : 0;
    const backLift = s < 0 ? 1 : 0;
    f.rect(9 - s, 26, 3, 11 - backLift, BODY); // back leg
    f.rect(12 + s, 26, 3, 11 - frontLift, BODY); // front leg
    f.px(15, 7, EYE); // eye on the facing side
    f.px(15, 10, SHADE); // mouth-side cue
    return f;
  }
  // down / up: front-on or back-on silhouette
  f.ellipse(12, 8.5, 5.5, 6.5, BODY); // head
  f.rect(8, 15, 8, 11, BODY); // torso
  f.rect(6, 16 - s, 2, 9, BODY); // left arm (swings against the legs)
  f.rect(16, 16 + s, 2, 9, BODY); // right arm
  const leftLift = s > 0 ? 1 : 0;
  const rightLift = s < 0 ? 1 : 0;
  f.rect(8, 26, 4, 11 - leftLift, BODY); // left leg
  f.rect(12, 26, 4, 11 - rightLift, BODY); // right leg
  if (dir === "down") {
    f.px(10, 7, EYE);
    f.px(13, 7, EYE);
    f.hline(11, 10, 2, SHADE); // mouth
  } else {
    f.rect(7, 2, 10, 3, HAIR); // back of the head: hair band
  }
  return f;
}

/** Shading: lighter top-left of the head, darker right side of the body. */
function tone(f) {
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) {
    const c = f.get(x, y);
    if (c[3] === 0 || c[0] !== BODY[0] || c[1] !== BODY[1] || c[2] !== BODY[2]) continue;
    if (y < 14 && x < 10 && y > 3) f.set(x, y, LIGHT);
    else if (x >= 15 && y >= 15) f.set(x, y, SHADE);
  }
  return f;
}

/** 1 px dark outline around every opaque pixel (4-neighbourhood). */
function outline(f) {
  const o = new Frame(f.w, f.h);
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) o.set(x, y, f.get(x, y));
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) {
    if (f.get(x, y)[3]) continue;
    const near = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => f.get(x + dx, y + dy)[3] > 0);
    if (near) o.set(x, y, OUTLINE);
  }
  return o;
}

function mirror(f) {
  const o = new Frame(f.w, f.h);
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) o.set(f.w - 1 - x, y, f.get(x, y));
  return o;
}

const render = (dir, s) => outline(tone(pose(dir, s)));
const WALK_PHASES = [0, 1, 0, -1];

// Frame order mirrors sprites/hero.json.
const frames = [];
for (const dir of ["down", "up", "left", "right"]) {
  const base = dir === "left" ? mirror(render("right", 0)) : render(dir, 0);
  frames.push(base);
}
for (const dir of ["down", "up", "left", "right"]) {
  for (const s of WALK_PHASES) {
    const img = dir === "left" ? mirror(render("right", s)) : render(dir, s);
    frames.push(img);
  }
}

const sheet = new Frame(W * frames.length, H);
frames.forEach((f, i) => sheet.blit(f, i * W, 0));
writeFileSync(join(SPRITES, "dummy.png"), encodePng(sheet.w, sheet.h, sheet.data));

const DIRS = ["down", "up", "left", "right"];
const frameTags = [
  ...DIRS.map((d, i) => ({ name: `idle_${d}`, from: i, to: i, direction: "forward" })),
  ...DIRS.map((d, i) => ({ name: `walk_${d}`, from: 4 + i * 4, to: 4 + i * 4 + 3, direction: "forward" })),
];
const json = {
  frames: frames.map((_, i) => ({
    filename: `dummy ${i}`,
    frame: { x: i * W, y: 0, w: W, h: H },
    rotated: false,
    trimmed: false,
    spriteSourceSize: { x: 0, y: 0, w: W, h: H },
    sourceSize: { w: W, h: H },
    duration: FRAME_MS,
  })),
  meta: {
    app: "pixelfx-demo",
    version: "1.0",
    format: "RGBA8888",
    size: { w: sheet.w, h: sheet.h },
    scale: "1",
    frameTags,
  },
};
writeFileSync(join(SPRITES, "dummy.json"), JSON.stringify(json, null, 1) + "\n");
console.log(`chars: wrote sprites/dummy.png (${sheet.w}x${sheet.h}, ${frames.length} frames) and sprites/dummy.json`);
