// Row 5: fences and hedges (ysort + solid). Transparent background: drawn over a ground tile.
import { C } from "./palette.mjs";
import { noise } from "./rng.mjs";
import { mix, shade, withAlpha } from "./draw.mjs";

const id = (row, col) => row * 16 + col;
const SH = withAlpha([0, 0, 0, 255], 55);

// wooden post seen from the front, base at y = bottom
function post(f, x, top, bottom) {
  f.rect(x, top, 3, bottom - top + 1, C.wire.post);
  f.vline(x, top, bottom - top + 1, C.wire.postLight);
  f.vline(x + 2, top, bottom - top + 1, C.wire.postDark);
  f.hline(x, top, 3, C.wire.postLight);
  f.hline(x, bottom, 3, C.wire.postDark);
}

function barbedH(f, x0, x1) {
  for (const y of [4, 7, 10]) {
    f.hline(x0, y, x1 - x0 + 1, C.wire.metal);
    for (let x = x0; x <= x1; x++) if (x % 4 === 1) { f.px(x, y - 1, C.wire.barb); f.px(x, y + 1, C.wire.dark); }
  }
}

export function fenceTiles() {
  const T = [];
  const fence = { solid: true };
  const add = (row, col, name, props, draw) => T.push({ id: id(row, col), name, layer: "ysort", ...props, draw });

  add(5, 0, "wire_h", fence, (f) => {
    f.hline(0, 13, 16, SH); f.hline(2, 14, 12, SH);
    barbedH(f, 0, 15);
    post(f, 6, 2, 13);
  });
  add(5, 1, "wire_v", fence, (f) => {
    f.rect(6, 15, 4, 1, SH);
    f.vline(7, 0, 16, C.wire.metal); f.vline(8, 0, 16, C.wire.dark);
    for (let y = 1; y < 16; y += 4) { f.px(6, y, C.wire.barb); f.px(9, y, C.wire.dark); }
    post(f, 6, 3, 12);
    post(f, 6, 14, 15);
  });
  add(5, 2, "post_wood", fence, (f) => {
    f.hline(4, 13, 8, SH);
    post(f, 6, 2, 13);
  });
  // corners are named by the two directions the wire leaves in
  const corner = (f, dirs) => {
    f.hline(4, 13, 8, SH);
    for (const d of dirs) {
      if (d === "e") { barbedH(f, 8, 15); }
      if (d === "w") { barbedH(f, 0, 7); }
      if (d === "s") { f.vline(7, 8, 8, C.wire.metal); f.vline(8, 8, 8, C.wire.dark); for (let y = 9; y < 16; y += 4) { f.px(6, y, C.wire.barb); f.px(9, y, C.wire.dark); } }
      if (d === "n") { f.vline(7, 0, 8, C.wire.metal); f.vline(8, 0, 8, C.wire.dark); for (let y = 1; y < 8; y += 4) { f.px(6, y, C.wire.barb); f.px(9, y, C.wire.dark); } }
    }
    post(f, 6, 2, 13);
  };
  add(5, 3, "wire_corner_es", fence, (f) => corner(f, ["e", "s"]));
  add(5, 4, "wire_corner_ws", fence, (f) => corner(f, ["w", "s"]));
  add(5, 5, "wire_corner_en", fence, (f) => corner(f, ["e", "n"]));
  add(5, 6, "wire_corner_wn", fence, (f) => corner(f, ["w", "n"]));
  add(5, 7, "wire_end_e", fence, (f) => corner(f, ["e"]));
  add(5, 8, "fence_gap", {}, (f) => {
    f.hline(0, 13, 16, withAlpha([0, 0, 0, 255], 30));
    post(f, 0, 2, 13);
    post(f, 13, 2, 13);
    // gate swung open, resting against the right post
    f.vline(12, 4, 8, C.wire.metal); f.vline(12, 7, 5, C.wire.metal);
  });
  const chainMesh = (f, x0, y0, x1, y1) => {
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      if ((x + y) % 4 === 0 || (x - y + 64) % 4 === 0) f.px(x, y, withAlpha(C.wire.metal, 200));
    }
  };
  add(5, 9, "chainlink_h", fence, (f) => {
    f.hline(0, 14, 16, SH);
    chainMesh(f, 0, 4, 15, 12);
    f.hline(0, 3, 16, C.wire.dark); f.hline(0, 13, 16, C.wire.dark);
    f.rect(0, 2, 2, 12, C.wire.metal); f.vline(1, 2, 12, C.wire.dark);
  });
  add(5, 10, "chainlink_v", fence, (f) => {
    f.rect(6, 15, 4, 1, SH);
    chainMesh(f, 6, 0, 9, 15);
    f.vline(6, 0, 16, C.wire.dark); f.vline(9, 0, 16, C.wire.dark);
    f.rect(5, 0, 6, 2, C.wire.metal); f.hline(5, 1, 6, C.wire.dark);
  });
  add(5, 11, "hedge", fence, (f, r) => {
    f.ellipse(8, 14, 9, 2, SH);
    const lobes = [[4, 8, 6], [12, 8, 6], [20, 8, 6], [-4, 8, 6], [8, 6, 5.5], [0, 6, 5.5], [16, 6, 5.5]];
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      let best = null;
      for (const [cx, cy, rad] of lobes) {
        const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / rad;
        if (d <= 1 && (!best || d < best.d)) best = { d, dy: (y + 0.5 - cy) / rad, dx: (x + 0.5 - cx) / rad };
      }
      if (!best) continue;
      const n = 0.6 * noise("hc", x >> 1, y >> 1) + 0.4 * noise("hp", x, y);
      let v = 0.5 - (best.dx * 0.4 + best.dy * 0.6) * 0.35 + (n - 0.5) * 0.45;
      if (best.d > 0.8 && best.dy > 0) v -= 0.25;
      f.px(x, y, v < 0.3 ? C.hedge.dark : v < 0.65 ? C.hedge.base : C.hedge.light);
    }
  });
  return T;
}
