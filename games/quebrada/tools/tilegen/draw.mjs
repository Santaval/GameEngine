// Tiny RGBA canvas ("Frame") with the drawing helpers the tile catalogue needs.

/** '#rrggbb' or '#rrggbbaa' -> [r,g,b,a] */
export function rgb(hex) {
  const h = hex.replace("#", "");
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16), h.length > 6 ? parseInt(h.slice(6, 8), 16) : 255];
}
export const withAlpha = (c, a) => [c[0], c[1], c[2], a];
export const mix = (a, b, t) => [0, 1, 2, 3].map((i) => Math.round(a[i] + (b[i] - a[i]) * t));
export const shade = (c, f) => [Math.min(255, Math.round(c[0] * f)), Math.min(255, Math.round(c[1] * f)), Math.min(255, Math.round(c[2] * f)), c[3]];

export class Frame {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.data = new Uint8Array(w * h * 4);
  }
  inside(x, y) {
    return x >= 0 && y >= 0 && x < this.w && y < this.h;
  }
  get(x, y) {
    if (!this.inside(x, y)) return [0, 0, 0, 0];
    const i = (y * this.w + x) * 4;
    return [this.data[i], this.data[i + 1], this.data[i + 2], this.data[i + 3]];
  }
  /** Plot with "over" alpha blending. */
  px(x, y, c) {
    x = Math.round(x);
    y = Math.round(y);
    if (!this.inside(x, y) || !c) return;
    const a = c[3] / 255;
    const i = (y * this.w + x) * 4;
    if (a >= 1) {
      this.data[i] = c[0]; this.data[i + 1] = c[1]; this.data[i + 2] = c[2]; this.data[i + 3] = 255;
      return;
    }
    const da = this.data[i + 3] / 255;
    const oa = a + da * (1 - a);
    if (oa <= 0) return;
    for (let k = 0; k < 3; k++) this.data[i + k] = Math.round((c[k] * a + this.data[i + k] * da * (1 - a)) / oa);
    this.data[i + 3] = Math.round(oa * 255);
  }
  /** Replace without blending (used to erase). */
  set(x, y, c) {
    if (!this.inside(x, y)) return;
    const i = (y * this.w + x) * 4;
    this.data[i] = c[0]; this.data[i + 1] = c[1]; this.data[i + 2] = c[2]; this.data[i + 3] = c[3];
  }
  rect(x, y, w, h, c) {
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.px(x + i, y + j, c);
  }
  hline(x, y, len, c) { this.rect(x, y, len, 1, c); }
  vline(x, y, len, c) { this.rect(x, y, 1, len, c); }
  line(x0, y0, x1, y1, c) {
    let dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.px(x0, y0, c);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }
  /** Fill every pixel from fn(x, y) -> colour | null. */
  fill(fn) {
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) this.px(x, y, fn(x, y));
  }
  ellipse(cx, cy, rx, ry, c) {
    for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++)
      for (let x = Math.floor(cx - rx); x <= Math.ceil(cx + rx); x++) {
        const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
        if (dx * dx + dy * dy <= 1) this.px(x, y, c);
      }
  }
  /** Draw src onto this at (dx, dy). */
  blit(src, dx, dy) {
    for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
      const c = src.get(x, y);
      if (c[3]) this.px(dx + x, dy + y, c);
    }
  }
  /** Copy a w*h window starting at (sx, sy) into a new frame. */
  slice(sx, sy, w, h) {
    const f = new Frame(w, h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) f.set(x, y, this.get(sx + x, sy + y));
    return f;
  }
  /** Scale up by an integer factor (nearest). */
  scaled(k) {
    const f = new Frame(this.w * k, this.h * k);
    for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) f.set(x, y, this.get((x / k) | 0, (y / k) | 0));
    return f;
  }
  /** Multiply colour by factor (night preview). */
  darkened(f, tint = [1, 1, 1.25]) {
    const o = new Frame(this.w, this.h);
    for (let i = 0; i < this.data.length; i += 4) {
      o.data[i] = Math.min(255, this.data[i] * f * tint[0]);
      o.data[i + 1] = Math.min(255, this.data[i + 1] * f * tint[1]);
      o.data[i + 2] = Math.min(255, this.data[i + 2] * f * tint[2]);
      o.data[i + 3] = this.data[i + 3];
    }
    return o;
  }
  /** Composite onto an opaque background colour. */
  onBackground(bg) {
    const o = new Frame(this.w, this.h);
    o.rect(0, 0, this.w, this.h, bg);
    o.blit(this, 0, 0);
    return o;
  }
}
