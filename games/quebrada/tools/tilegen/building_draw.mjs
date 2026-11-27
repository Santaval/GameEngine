// Drawing helpers for the buildings sheet (issue #71). Every helper paints onto a Frame `f` in
// pixel coordinates of the building canvas. Windows and doors take `lit` to paint only the glass in
// the warm night colours (same pixels as the daytime glass) for the windows_lit layer.
import { C } from "./palette.mjs";
import { noise } from "./rng.mjs";
import { shade, mix, withAlpha } from "./draw.mjs";

const B = C.bldg;
const SH = withAlpha([0, 0, 0, 255], 60);

// ---------- geometry ----------
/** Even-odd point in polygon test at the pixel centre. */
export function inPoly(pts, x, y) {
  const px = x + 0.5, py = y + 0.5;
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** Fill a polygon; fn(x, y) returns a colour (or null to skip). */
export function fillPoly(f, pts, fn) {
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (const [x, y] of pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  for (let y = Math.floor(y0); y <= Math.ceil(y1); y++)
    for (let x = Math.floor(x0); x <= Math.ceil(x1); x++)
      if (inPoly(pts, x, y)) f.px(x, y, typeof fn === "function" ? fn(x, y) : fn);
}

const speck = (c, salt, x, y, p = 0.05, k = 0.93) => (noise(salt, x, y) < p ? shade(c, k) : c);

// ---------- walls ----------
/** White-grey wooden clapboard: a darker joint every 4 px with a light edge above it. */
export function clapboard(f, x, y, w, h, o = {}) {
  const base = o.base ?? B.whitewash, line = o.line ?? B.clapLine, light = o.light ?? B.whiteLight, salt = o.salt ?? "clap";
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    const r = (y + j) % 4;
    let c = r === 3 ? line : r === 0 ? light : base;
    if (r === 1 || r === 2) c = speck(c, salt, x + i, y + j, 0.06, 0.95);
    f.px(x + i, y + j, c);
  }
}

/** Painted plaster wall: speckled, light top edge, darker skirt at the bottom. */
export function plasterWall(f, x, y, w, h, o = {}) {
  const base = o.base ?? B.cream, sh = o.shade ?? B.creamShade, hi = o.hi ?? B.creamHi, dark = o.dark ?? B.creamDark, salt = o.salt ?? "plast";
  const skirt = o.skirt ?? 3;
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    let c = base;
    const n = noise(salt, x + i, y + j);
    if (n < 0.07) c = sh;
    else if (n > 0.95) c = hi;
    if (j === 0) c = hi;
    if (j >= h - skirt) c = j === h - skirt ? dark : sh;
    f.px(x + i, y + j, c);
  }
}

// ---------- roofs ----------
/** Corrugation: a lit ridge and a dark valley every 3 px across `u`. */
function corrugate(base, light, dark, u, salt, x, y) {
  const k = ((u % 3) + 3) % 3;
  let c = k === 0 ? light : k === 1 ? base : dark;
  return speck(c, salt, x, y, 0.04, 0.92);
}

/**
 * Hip roof seen from above. Rectangle (x,y,w,h); ridge at y + top; sides inset by `side`.
 * pal: { base, light, dark, line, trim, trimDark }. Eave trim all around, thicker at the front (bottom).
 */
export function hipRoof(f, x, y, w, h, pal, o = {}) {
  const top = o.top ?? Math.round(h * 0.36), bot = h - top, side = o.side ?? Math.min(top + 6, Math.floor(w / 2) - 2);
  const salt = o.salt ?? "hip";
  const front = o.frontTrim ?? 3, edge = o.edgeTrim ?? 1;
  const rect = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
  fillPoly(f, rect, (px, py) => {
    const lx = px - x + 0.5, ly = py - y + 0.5;
    const dl = lx / side, dr = (w - lx) / side, dt = ly / top, db = (h - ly) / bot;
    const m = Math.min(dl, dr, dt, db);
    let c;
    if (m === dt) c = corrugate(pal.base, pal.light, pal.dark, px, salt + "t", px, py);
    else if (m === db) c = corrugate(shade(pal.base, 1.05), shade(pal.light, 1.03), pal.base, px, salt + "b", px, py);
    else if (m === dl) c = corrugate(shade(pal.base, 1.08), shade(pal.light, 1.05), pal.base, py, salt + "l", px, py);
    else c = corrugate(shade(pal.base, 0.8), shade(pal.base, 0.95), shade(pal.dark, 0.9), py, salt + "r", px, py);
    if (m === dt) c = shade(c, 0.92);
    if (((m === dt || m === db) && (py - y) % 13 === 0) || ((m === dl || m === dr) && (px - x) % 13 === 0)) c = shade(c, 0.85);
    // hip lines: darker seams where two planes meet
    const near = (a, b) => Math.abs(a - b) < 0.045;
    if (!near(dt, db) && ((near(dl, dt) && dl < 1) || (near(dr, dt) && dr < 1) || (near(dl, db) && dl < 1) || (near(dr, db) && dr < 1))) c = pal.line;
    // ridge cap
    if (near(dt, db) && dl > 1 && dr > 1) c = pal.light;
    return c;
  });
  // trim
  const tr = pal.trim ?? pal.dark, td = pal.trimDark ?? pal.line;
  f.rect(x, y + h - front, w, front, tr);
  f.hline(x, y + h - front, w, shade(tr, 1.25));
  f.hline(x, y + h - 1, w, td);
  f.rect(x, y, edge, h, tr); f.rect(x + w - edge, y, edge, h, tr);
  f.hline(x, y, w, tr);
  // shadow strip under the front eave (bleeds past the roof bottom; the wall below is a different layer)
  return { ridgeY: y + top };
}

/** Gable roof seen from above: ridge along x at y + ridge, two planes, plain trim. */
export function gableRoof(f, x, y, w, h, pal, o = {}) {
  const ridge = o.ridge ?? Math.round(h * 0.4), salt = o.salt ?? "gab";
  const front = o.frontTrim ?? 3;
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    const back = j < ridge;
    let c = back
      ? corrugate(pal.dark, pal.base, shade(pal.dark, 0.9), x + i, salt + "b", x + i, y + j)
      : corrugate(shade(pal.base, 1.04), pal.light, pal.base, x + i, salt + "f", x + i, y + j);
    if (j === ridge - 1 || j === ridge) c = j === ridge - 1 ? pal.line : pal.light;
    f.px(x + i, y + j, c);
  }
  const tr = pal.trim ?? pal.dark;
  f.rect(x, y + h - front, w, front, tr);
  f.hline(x, y + h - front, w, shade(tr, 1.25));
  f.hline(x, y + h - 1, w, pal.trimDark ?? pal.line);
  f.rect(x, y, 1, h, tr); f.rect(x + w - 1, y, 1, h, tr);
  f.hline(x, y, w, tr);
}

/**
 * Red flared bell spire: needle widening into a wide skirt, left side lit. prof = [[y, halfWidth], ...].
 */
export function flaredSpire(f, cx, prof, o = {}) {
  const lerp = (y) => {
    for (let i = 0; i < prof.length - 1; i++) {
      const [ya, ha] = prof[i], [yb, hb] = prof[i + 1];
      if (y >= ya && y <= yb) return ha + ((hb - ha) * (y - ya)) / (yb - ya);
    }
    return null;
  };
  const yTop = prof[0][0], yBot = prof[prof.length - 1][0];
  for (let y = yTop; y <= yBot; y++) {
    const hw = lerp(y + 0.5);
    if (hw === null) continue;
    const a = Math.round(cx - hw), b = Math.round(cx + hw) - 1;
    for (let x = a; x <= b; x++) {
      const u = (x + 0.5 - cx) / Math.max(hw, 0.6);
      let c = u < -0.55 ? B.spireLight : u < 0.05 ? B.spire : u < 0.55 ? shade(B.spire, 0.9) : B.spireDark;
      if (Math.abs(Math.abs(u) - 0.5) < 0.09 && hw > 5) c = shade(c, 0.88); // facet seam
      if (x === a) c = shade(B.spireLight, 1.08);
      if (x === b) c = B.spireDark;
      if (y >= yBot - 1 && hw > 8) c = shade(c, 0.78);
      f.px(x, y, c);
    }
  }
  // dark under-eave band below the skirt
  const hwB = lerp(yBot);
  const ex0 = Math.round(cx - hwB), ex1 = Math.round(cx + hwB) - 1;
  f.rect(ex0, yBot + 1, ex1 - ex0 + 1, 3, B.spireEdge);
  f.hline(ex0, yBot + 1, ex1 - ex0 + 1, shade(B.spireEdge, 1.5));
  return { x0: ex0, x1: ex1, bottom: yBot + 3 };
}

export function cross(f, cx, y, c = B.cross) {
  f.vline(cx, y, 6, c);
  f.hline(cx - 1, y + 1, 3, c);
}

// ---------- windows ----------
/** Warm lit glass: bright core, 1 px darker rim. */
function litFill(f, pts) {
  for (const [x, y, edge] of pts) f.px(x, y, edge ? B.litRim : (x + y) % 5 === 0 ? B.litCore : B.litGlow);
}

function glassColour(tint, x, y, x0, y0, w, h) {
  const g = tint === "green" ? [B.greenGlass, B.greenGlassHi, B.greenGlassDark] : [B.glass, B.glassHi, B.glassDark];
  const diag = (x - x0 + (y - y0) * 0.6) % 9;
  if (diag >= 1 && diag < 2.3) return g[1];
  return y - y0 < h * 0.4 ? mix(g[0], g[1], 0.15) : (y - y0 > h * 0.8 ? g[2] : g[0]);
}

/** Pixels of an arched pane (x,y,w,h): [x,y,isEdge]. Arch radius = w/2. */
function archPixels(x, y, w, h) {
  const r = w / 2, out = [];
  const inside = (px, py) => {
    const lx = px - x, ly = py - y;
    if (lx < 0 || lx >= w || ly < 0 || ly >= h) return false;
    if (ly < r) { const dx = lx + 0.5 - r, dy = ly + 0.5 - r; return dx * dx + dy * dy <= r * r; }
    return true;
  };
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    if (!inside(x + i, y + j)) continue;
    const edge = !inside(x + i - 1, y + j) || !inside(x + i + 1, y + j) || !inside(x + i, y + j - 1) || !inside(x + i, y + j + 1);
    out.push([x + i, y + j, edge]);
  }
  return out;
}

/**
 * Arched window. Outer frame 1 px white, glass inside. curtain: white drapes tied back at the sides.
 * lit: paints only the glass (warm) plus the curtain silhouettes in a darker amber.
 */
export function archWindow(f, x, y, w, h, o = {}) {
  const px = archPixels(x, y, w, h);
  const inner = new Set(px.filter((p) => !p[2]).map((p) => p[0] + "," + p[1]));
  if (!o.lit) {
    for (const [ax, ay] of px) f.px(ax, ay, B.doorFrame);
    f.rect(x - 1, y + h, w + 2, 2, B.whiteTrimShade); // sill
    f.hline(x - 1, y + h, w + 2, B.whiteTrim);
    for (const [ax, ay, e] of px) if (!e) f.px(ax, ay, glassColour(o.tint, ax, ay, x, y, w, h));
  } else {
    litFill(f, px.map(([ax, ay, e]) => [ax, ay, e]));
  }
  if (o.curtain) {
    const cw = Math.max(3, Math.round(w * 0.2));
    const drape = (x0, dir) => {
      for (let j = 3; j < h; j++) {
        const pinch = j > h * 0.58 ? Math.min(2, Math.floor((j - h * 0.58) / 3)) : 0; // tied back
        const wid = cw - pinch + (j > h * 0.85 ? 1 : 0);
        for (let i = 0; i < wid; i++) {
          const gx = dir > 0 ? x0 + i : x0 - i;
          if (!inner.has(gx + "," + (y + j))) continue;
          const fold = (i + j) % 3 === 0;
          f.px(gx, y + j, o.lit ? (fold ? B.litRim : B.litCurtain) : (fold ? B.curtainShade : B.curtain));
        }
      }
    };
    drape(x + 1, 1);
    drape(x + w - 2, -1);
    // gathered valance across the top of the straight part
    for (let i = 1; i < w - 1; i++) if (inner.has(x + i + "," + (y + Math.round(w / 2 - 1)))) f.px(x + i, y + Math.round(w / 2 - 1), o.lit ? B.litRim : B.curtainShade);
  }
}

/** Rectangular window with optional green tint / mullion (tall window of mama's house). */
export function plainWindow(f, x, y, w, h, o = {}) {
  if (o.lit) {
    const pts = [];
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) pts.push([x + i, y + j, i === 0 || j === 0 || i === w - 1 || j === h - 1]);
    litFill(f, pts);
    if (o.bar) f.hline(x, y + Math.round(h / 2), w, B.litRim);
    return;
  }
  f.rect(x - 1, y - 1, w + 2, h + 2, o.frame ?? B.doorFrame);
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) f.px(x + i, y + j, glassColour(o.tint, x + i, y + j, x, y, w, h));
  if (o.bar) { f.hline(x, y + Math.round(h / 2) - 1, w, o.frame ?? B.doorFrame); f.hline(x, y + Math.round(h / 2), w, shade(o.frame ?? B.doorFrame, 0.85)); }
  f.rect(x - 2, y + h + 1, w + 4, 2, B.whiteTrimShade);
  f.hline(x - 2, y + h + 1, w + 4, B.whiteTrim);
  if (o.shutters) {
    f.rect(x - 4, y - 1, 3, h + 2, o.shutters); f.rect(x + w + 1, y - 1, 3, h + 2, o.shutters);
    for (let j = 0; j < h + 2; j += 2) { f.hline(x - 4, y - 1 + j, 3, shade(o.shutters, 0.8)); f.hline(x + w + 1, y - 1 + j, 3, shade(o.shutters, 0.8)); }
  }
}

/** Pixels of a pointed (gothic-ish) window: straight sides, gable-shaped top of height w*0.7. */
function pointedPixels(x, y, w, h) {
  const out = [], peak = Math.round(w * 0.7);
  const inside = (px, py) => {
    const lx = px - x, ly = py - y;
    if (lx < 0 || lx >= w || ly < 0 || ly >= h) return false;
    if (ly >= peak) return true;
    const hw = ((ly + 0.5) / peak) * (w / 2);
    return Math.abs(lx + 0.5 - w / 2) <= hw;
  };
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    if (!inside(x + i, y + j)) continue;
    const edge = !inside(x + i - 1, y + j) || !inside(x + i + 1, y + j) || !inside(x + i, y + j - 1) || !inside(x + i, y + j + 1);
    out.push([x + i, y + j, edge]);
  }
  return out;
}

/** Narrow louvered pointed window with a white frame and sill (church). */
export function louverWindow(f, x, y, w, h, o = {}) {
  const px = pointedPixels(x, y, w, h);
  if (o.lit) { litFill(f, px); return; }
  for (const [ax, ay, e] of px) {
    if (e) f.px(ax, ay, B.doorFrame);
    else f.px(ax, ay, (ay - y) % 2 === 0 ? B.slatLight : B.slatDark);
  }
  f.rect(x - 1, y + h, w + 2, 2, B.doorFrame);
  f.hline(x - 1, y + h + 1, w + 2, B.whiteTrimShade);
}

// ---------- doors ----------
/** Plain rectangular door with panels, white frame and a knob. pal: { base, light, dark } */
export function door(f, x, y, w, h, pal) {
  f.rect(x - 1, y - 1, w + 2, h + 1, B.doorFrame);
  f.rect(x, y, w, h, pal.base);
  f.vline(x, y, h, pal.light);
  f.vline(x + w - 1, y, h, pal.dark);
  f.hline(x, y, w, pal.dark);
  const pw = w - 4, ph = Math.floor((h - 6) / 2);
  for (const py of [y + 2, y + 4 + ph]) {
    f.rect(x + 2, py, pw, ph, shade(pal.base, 0.88));
    f.hline(x + 2, py, pw, pal.dark);
    f.hline(x + 2, py + ph - 1, pw, pal.light);
  }
  f.px(x + w - 3, y + Math.floor(h / 2), B.metal);
  f.px(x + w - 3, y + Math.floor(h / 2) + 1, B.zincDark);
}

/**
 * Pointed church door: wooden leaf (or leaves) under a dark pointed-gable lintel with white trim.
 * n = 1 single leaf, 2 = double door; open: the right leaf is open (dark gap).
 * lit paints only the lintel triangle.
 */
export function pointedDoor(f, x, y, w, h, o = {}) {
  const lh = Math.round(w * 0.38) + 3; // lintel height
  const tri = [[x - 3, y - 1], [x + w / 2, y - lh], [x + w + 3, y - 1]];
  if (o.lit) {
    fillPoly(f, [[x - 1, y - 1], [x + w / 2, y - lh + 3], [x + w + 1, y - 1]], B.litGlow);
    f.hline(x + 1, y - 2, w - 2, B.litRim);
    return;
  }
  // white outline gable and dark inside
  fillPoly(f, tri, B.doorFrame);
  fillPoly(f, [[x - 1, y - 1], [x + w / 2, y - lh + 3], [x + w + 1, y - 1]], B.doorInside);
  f.rect(x - 2, y - 1, w + 4, 1, B.doorFrame);
  // frame
  f.rect(x - 1, y, w + 2, h, B.doorFrame);
  if (o.n === 2) {
    const half = Math.floor(w / 2);
    leaf(f, x, y, half, h);
    if (o.open) {
      f.rect(x + half, y, w - half, h, B.doorInside);
      f.vline(x + half, y, h, shade(B.doorBrown, 0.6)); // edge of the open leaf
      f.vline(x + w - 1, y, h, shade(B.doorBrown, 0.45));
      f.hline(x + half, y + h - 2, w - half, B.skirt); // threshold glimpsed inside
    } else leaf(f, x + half, y, w - half, h);
  } else leaf(f, x, y, w, h);
}

function leaf(f, x, y, w, h) {
  f.rect(x, y, w, h, B.doorBrown);
  f.vline(x, y, w > 3 ? h : 0, B.doorLight);
  f.vline(x + w - 1, y, h, B.doorDark);
  f.hline(x, y, w, B.doorDark);
  // two raised panels
  const ph = Math.floor((h - 8) / 2);
  for (const py of [y + 3, y + 5 + ph]) {
    f.rect(x + 2, py, w - 4, ph, shade(B.doorBrown, 0.9));
    f.hline(x + 2, py, w - 4, B.doorDark);
    f.hline(x + 2, py + ph - 1, w - 4, B.doorLight);
    f.vline(x + 2, py, ph, B.doorDark);
  }
  for (let j = 0; j < h; j += 3) f.px(x + 1 + ((j / 3) | 0) % 2, y + j, B.doorLight);
}

// ---------- small props ----------
export function post(f, x, y0, y1, w = 2) {
  f.rect(x, y0, w, y1 - y0 + 1, B.whiteTrim);
  f.vline(x + w - 1, y0, y1 - y0 + 1, B.whiteTrimShade);
  f.rect(x - 1, y1 - 1, w + 2, 2, B.whiteTrimShade);
  f.rect(x - 1, y0, w + 2, 1, B.whiteTrimShade);
}

export function column(f, x, y0, y1, w, pal) {
  f.rect(x, y0, w, y1 - y0 + 1, pal.base);
  f.vline(x, y0, y1 - y0 + 1, pal.light);
  f.vline(x + w - 1, y0, y1 - y0 + 1, pal.dark);
  f.rect(x - 1, y0, w + 2, 2, pal.light);
  f.rect(x - 1, y1 - 1, w + 2, 2, pal.dark);
}

export function pottedPlant(f, x, y, o = {}) {
  // x = left of a 9 px wide plant, y = bottom
  f.ellipse(x + 4.5, y - 0.5, 5.5, 1.6, SH);
  f.rect(x + 2, y - 4, 5, 4, B.pot);
  f.hline(x + 1, y - 5, 7, B.potLight);
  f.vline(x + 2, y - 4, 4, B.potLight);
  f.vline(x + 6, y - 4, 4, B.potDark);
  f.hline(x + 2, y - 1, 5, B.potDark);
  const g = o.flowers ? [B.leaf, B.leafLight] : [B.leafPlant2, B.leafLight];
  for (const [dx, dy, r] of [[4.5, -9, 3.4], [2, -8, 2.6], [7, -8, 2.6], [4.5, -12, 2.4]]) f.ellipse(x + dx, y + dy, r, r * 0.9, B.leafDark);
  for (const [dx, dy, r] of [[4.5, -9.5, 2.6], [2.3, -8.5, 1.8], [6.8, -8.5, 1.8], [4.5, -12.3, 1.6]]) f.ellipse(x + dx, y + dy, r, r * 0.9, g[0]);
  f.px(x + 3, y - 10, g[1]); f.px(x + 5, y - 12, g[1]); f.px(x + 6, y - 9, g[1]);
  if (o.flowers) for (const [dx, dy] of [[2, -10], [6, -11], [4, -7], [7, -8]]) f.px(x + dx, y + dy, C.flower.pink);
}

/** Motorcycle under a dark tarp, side view: lump, folds, rope, wheel bottoms, a mirror poking out. */
export function tarpMoto(f, x, y, w, h) {
  // x,y = top-left of the lump area, h = lump height; wheels drawn below y + h
  f.ellipse(x + w / 2, y + h + 3, w / 2 + 1, 2, SH);
  f.ellipse(x + 3.5, y + h + 1, 3.2, 3.2, B.tire);
  f.ellipse(x + w - 3.5, y + h + 1, 3.2, 3.2, B.tire);
  f.px(x + 3, y + h + 1, B.zincDark); f.px(x + w - 4, y + h + 1, B.zincDark);
  const pts = [[x, y + h], [x + 1, y + h * 0.55], [x + w * 0.3, y + h * 0.15], [x + w * 0.55, y + 1], [x + w * 0.85, y + h * 0.3], [x + w, y + h * 0.7], [x + w, y + h]];
  fillPoly(f, pts, (px, py) => {
    const lx = (px - x) / w, ly = (py - y) / h;
    let c = lx < 0.35 ? B.tarpLight : lx < 0.7 ? B.tarp : B.tarpDark;
    if (ly > 0.8) c = shade(c, 0.8);
    if (((px * 3 + py * 2) % 11 === 0) && ly < 0.8) c = B.tarpDark; // folds
    return c;
  });
  f.line(Math.round(x + w * 0.25), Math.round(y + h * 0.25), Math.round(x + w * 0.3), y + h - 1, B.tarpDark);
  f.hline(x + 1, y + Math.round(h * 0.7), w - 2, B.rope); // tie-down rope
  f.px(x + w - 2, y + 1, B.metal); f.px(x + w - 3, y, B.metal); // mirror
  f.px(x + w - 1, y + 1, B.metal);
}

// ---------- interior furniture ----------
export function plank(f, x, y, w, h, base, light, dark, salt) {
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    let c = base;
    if (j === 0) c = light;
    else if (j === h - 1) c = dark;
    else if (noise(salt, x + i, y + j) < 0.12) c = shade(base, 0.93);
    f.px(x + i, y + j, c);
  }
}

export function savedPicture(f, x, y, w, h) {
  f.rect(x, y, w, h, B.frameGold);
  f.hline(x, y, w, shade(B.frameGold, 1.3));
  f.rect(x + 1, y + 1, w - 2, h - 2, B.picBlue);
  const cx = x + w / 2;
  f.rect(Math.floor(cx) - 1, y + 3, 3, 3, B.picSkin); // head
  f.rect(Math.floor(cx) - 2, y + 6, 5, h - 8, B.picRed); // robe
  f.hline(Math.floor(cx) - 2, y + 2, 5, B.picGold); // halo
  f.px(Math.floor(cx) - 3, y + 3, B.picGold); f.px(Math.floor(cx) + 3, y + 3, B.picGold);
}

export { B, SH };
