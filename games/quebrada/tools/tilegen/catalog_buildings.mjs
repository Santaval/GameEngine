// Single source of truth for buildings.png + buildings.tsx (issue #71).
// Sheet: 16 columns x 24 rows of 16x16 tiles, id = row * 16 + col. Landmarks are drawn whole on one canvas
// and sliced; fully transparent slices emit no tile (the map cell stays 0).
//
//   rows 0-11  cols 0-9    iglesia      10x12
//   rows 0-4   cols 10-15  casa_1       6x5   (red zinc, pale yellow walls, green trim)
//   rows 5-9   cols 10-15  casa_2       6x5   (blue zinc, light blue walls, white trim)
//   rows 12-17 cols 0-7    casa_mama    8x6
//   rows 12-16 cols 8-13   casa_3       6x5   (rust zinc, salmon walls, white trim, pink columns)
//   rows 18-19 (288-319)   lit window cells  <name>_lit_<cx>_<cy>
//   rows 20-22 (320-367)   interior furniture of mama's house  casa_mama_int_<cx>_<cy>
//   rows 24-28 cols 0-7    abastecedor  8x5 (yellow walls, striped awning)   cols 8-15: bar  8x5 (green walls, red sign band)
//   rows 29-33 cols 0-7    guarderia    8x5 (pastel blue walls, painted boats)
//   rows 36-41 cols 0-7    casa_paula   8x6 (wooden house of Abuela Paula y Abuelo Pepe, lit cells share rows 34-35)
//   rows 42-47             casa_paula interior furniture casa_paula_int_<cx>_<cy> (max 96);  rows 48-49  its wood back wall casa_paula_wall_<cx>_<cy> (16x2)
//   rows 50-55             tienda_abastecedor interior furniture tienda_abastecedor_int_<cx>_<cy> (max 96);  rows 56-57  its yellow back wall tienda_abastecedor_wall_<cx>_<cy> (16x2)
//   rows 34-35             lit window cells of the three shops (the casas use rows 18-19)
//   row 23 cols 0-11       interior back wall  casa_mama_wall_<cx>;  cols 12-13 two coloured hedges
//
// Building entry: { name, roof_of, col0,row0,w,h, roofRows, footRows:[r0,r1), open:[[cx,cy]], windows:[{x,y,w,h}],
//   door:{cx,cy,w}, draw(f), drawLit(f), cells, lit }.
import { Frame, rgb, shade, withAlpha } from "./draw.mjs";
import { C } from "./palette.mjs";
import { noise } from "./rng.mjs";
import * as D from "./building_draw.mjs";
import { drawText, textWidth } from "./font.mjs";

export const SIZE = 16;
export const B_COLS = 16;
export const B_ROWS = 58;
const B = C.bldg;
const id = (row, col) => row * B_COLS + col;

// ---------------------------------------------------------------- iglesia
const WALL_L = [[64, 56], [96, 56], [96, 80], [112, 94], [112, 106], [150, 123], [150, 192], [10, 192], [10, 123], [48, 106], [48, 94], [64, 80]];
// barge lines: from the inner high end to the outer low end (left side, mirrored for the right)
const BARGE_MID = { x0: 64, y0: 80, x1: 46, y1: 95 };
const BARGE_LOW = { x0: 48, y0: 106, x1: 6, y1: 125 };

const lineY = (b, x) => b.y0 + ((x - b.x0) * (b.y1 - b.y0)) / (b.x1 - b.x0);
const mirror = (x) => 159 - x;

function drawIglesia(f) {
  const put = (x, y, c) => { f.px(x, y, c); f.px(mirror(x), y, shade(c, 0.93)); };

  // dark nave roof bands behind the stepped facade, above each barge line
  for (const b of [BARGE_MID, BARGE_LOW]) {
    const lo = Math.min(b.x0, b.x1), hi = Math.max(b.x0, b.x1);
    for (let x = lo; x <= hi; x++) {
      const yl = Math.round(lineY(b, x));
      for (let k = 1; k <= 6; k++) put(x, yl - k, k === 6 ? B.naveLight : k >= 4 ? B.nave : B.naveDark);
    }
  }
  // stepped white facade
  D.fillPoly(f, WALL_L, (x, y) => {
    const base = (() => {
      const r = y % 4;
      let c = r === 3 ? B.clapLine : r === 0 ? B.whiteLight : B.whitewash;
      if ((r === 1 || r === 2) && noise("igl", x, y) < 0.06) c = shade(c, 0.95);
      return c;
    })();
    return base;
  });
  // fascia boards along the barge lines (white, over the top of the wall) with a shaded lip
  for (const b of [BARGE_MID, BARGE_LOW]) {
    const lo = Math.min(b.x0, b.x1), hi = Math.max(b.x0, b.x1);
    for (let x = lo; x <= hi; x++) {
      const yl = Math.round(lineY(b, x));
      put(x, yl, B.whiteTrim); put(x, yl + 1, B.whiteTrim); put(x, yl + 2, B.whiteTrimShade);
    }
  }
  // white corner boards and outline
  for (const x of [10, 11]) { f.vline(x, 124, 68, B.whiteTrim); f.vline(mirror(x), 124, 68, B.whiteTrimShade); }
  f.vline(9, 125, 67, B.outline); f.vline(150, 125, 67, B.outline);
  f.vline(64, 56, 24, B.whiteShade); f.vline(95, 56, 24, B.whiteShade);
  // barge end brackets (dark) under the overhang
  for (const [x, y] of [[44, 96], [4, 126]]) {
    put(x + 1, y, B.whiteTrim); put(x + 2, y, B.whiteTrim);
    for (let j = 1; j < 7; j++) for (let i = 0; i < 3; i++) put(x + i, y + j, i === 0 ? B.trimLight : B.trimDark);
  }

  // tower: spire, skirt, dark brackets
  D.cross(f, 80, 0);
  D.flaredSpire(f, 80, [[6, 0.8], [11, 1.6], [18, 2.7], [26, 4.1], [33, 6.2], [38, 9.5], [42, 14.5], [46, 21], [49, 26], [52, 28.5]]);
  for (const x0 of [60, 96]) {
    f.rect(x0, 56, 4, 19, B.trimDark);
    f.vline(x0 + (x0 === 60 ? 0 : 3), 56, 19, B.trim);
    for (let y = 58; y < 74; y += 3) f.hline(x0, y, 4, B.trim);
    f.rect(x0, 74, 4, 1, B.trim);
  }
  // louvered pointed windows high up
  D.louverWindow(f, 74, 62, 12, 20);
  D.louverWindow(f, 58, 98, 10, 18);
  D.louverWindow(f, 92, 98, 10, 18);

  // base: concrete skirt and the two steps in front of the main door
  f.rect(10, 188, 140, 4, B.skirt);
  f.hline(10, 188, 140, shade(B.skirt, 1.15));
  f.rect(58, 185, 44, 7, C.concrete.base);
  f.hline(58, 185, 44, C.concrete.light);
  f.hline(58, 188, 44, C.concrete.joint);
  f.hline(58, 191, 44, C.concrete.dark);
  // three wooden doors under dark pointed lintels; the centre double door has one leaf open
  D.pointedDoor(f, 66, 152, 28, 33, { n: 2, open: true });
  D.pointedDoor(f, 21, 158, 12, 27);
  D.pointedDoor(f, 127, 158, 12, 27);
}

function drawIglesiaLit(f) {
  D.pointedDoor(f, 66, 152, 28, 33, { n: 2, open: true, lit: true });
  D.pointedDoor(f, 21, 158, 12, 27, { lit: true });
  D.pointedDoor(f, 127, 158, 12, 27, { lit: true });
}

// ---------------------------------------------------------------- casa de mama
const ZINC = { base: B.zincBase, light: B.zincLight, dark: B.zincDark, line: B.zincLine, trim: B.trim, trimDark: B.trimDark };

function drawMama(f) {
  D.hipRoof(f, 2, 2, 124, 60, ZINC, { top: 22, side: 28, frontTrim: 4, salt: "mamaroof" });
  // stains and a few lighter patched sheets
  for (let i = 0; i < 40; i++) {
    const x = 6 + Math.floor(noise("ms", i, 1) * 114), y = 30 + Math.floor(noise("ms", i, 2) * 26);
    if (f.get(x, y)[0] > 150) f.px(x, y, B.zincRust);
  }
  // walls: main block up to the porch, porch back wall only one cell tall (the floor of the porch is the ground)
  D.plasterWall(f, 0, 64, 96, 32, { salt: "mamawall" });
  D.plasterWall(f, 96, 64, 32, 16, { salt: "mamawall", skirt: 2 });
  for (let y = 64; y < 68; y++) f.hline(0, y, 128, withAlpha([0, 0, 0, 255], 70 - (y - 64) * 15)); // eave shadow
  // windows
  D.plainWindow(f, 21, 69, 9, 22, { tint: "green", bar: true });
  D.archWindow(f, 49, 70, 14, 20, { curtain: true });
  // door in a green leaf, pot plants either side
  D.door(f, 82, 71, 12, 25, { base: B.doorGreen, light: shade(B.doorGreen, 1.25), dark: B.doorGreenDark });
  D.pottedPlant(f, 68, 95, { flowers: true });
  D.pottedPlant(f, 98, 95);
  // porch post
  D.post(f, 122, 66, 94);
  f.hline(96, 66, 28, B.whiteTrimShade); // porch beam
  // covered motorcycle
  D.tarpMoto(f, 1, 78, 16, 13);
}

function drawMamaLit(f) {
  D.plainWindow(f, 21, 69, 9, 22, { lit: true, bar: true });
  D.archWindow(f, 49, 70, 14, 20, { curtain: true, lit: true });
}

// ---------------------------------------------------------------- filler houses
/** One parametrised house, 96x80: roof rows 0-2, wall rows 3-4. */
function fillerHouse({ wall, roof, door, windows, hip = true, columns = null, shutters = null, tint = null }) {
  const draw = (f) => {
    if (hip) D.hipRoof(f, 2, 2, 92, 44, roof, { top: 17, side: 22, frontTrim: 3, salt: "fh" + roof.base.join("") });
    else D.gableRoof(f, 2, 2, 92, 44, roof, { ridge: 17, frontTrim: 3, salt: "fg" + roof.base.join("") });
    D.plasterWall(f, 0, 48, 96, 32, wall);
    for (let y = 48; y < 51; y++) f.hline(0, y, 96, withAlpha([0, 0, 0, 255], 70 - (y - 48) * 18));
    for (const wx of windows) D.plainWindow(f, wx, 55, 11, 14, { bar: true, tint, shutters, frame: columns ? B.whiteTrim : undefined });
    D.door(f, 42, 56, 12, 24, door);
    if (columns) {
      f.rect(0, 48, 96, 4, columns.base);
      f.hline(0, 51, 96, columns.dark);
      for (const x of [3, 86]) D.column(f, x, 52, 79, 6, { base: columns.base, light: columns.light, dark: columns.dark });
    }
  };
  const drawLit = (f) => { for (const wx of windows) D.plainWindow(f, wx, 55, 11, 14, { lit: true, bar: true }); };
  return {
    w: 6, h: 5, roofRows: 3, footRows: [1, 3], open: [],
    windows: windows.map((x) => ({ x, y: 55, w: 11, h: 14 })),
    door: { cx: 2, cy: 4, w: 32 }, draw, drawLit,
  };
}

const wallPal = (base, sh, hi, dark, salt) => ({ base, shade: sh, hi, dark, salt });

/** Shop / bar / nursery, 128x80 (8x5): roof rows 0-2, wall rows 3-4, a coloured sign band under the eave, a big window and a door. */
function shopBuilding({ wall, roof, door, sign, windows, deco, litWindows = windows, doorX = 58, salt }) {
  const draw = (f) => {
    D.hipRoof(f, 2, 2, 124, 44, roof, { top: 17, side: 22, frontTrim: 3, salt });
    D.plasterWall(f, 0, 48, 128, 32, wall);
    for (let y = 48; y < 51; y++) f.hline(0, y, 128, withAlpha([0, 0, 0, 255], 70 - (y - 48) * 18));
    f.rect(6, 51, 116, 7, sign.bg); f.hline(6, 51, 116, sign.light); f.hline(6, 57, 116, sign.dark);
    if (sign.text) { // the name, 3x5 px letters centred in the 5 px free inside the band (x 6..121, y 52..56)
      const w = textWidth(sign.text);
      if (w > 112) throw new Error(`shop sign "${sign.text}" is ${w} px wide, the band takes 112`);
      drawText(f, sign.text, 6 + Math.floor((116 - w) / 2), 52, sign.fg);
    }
    for (const w of windows) { if (w.awning) { for (let x = w.x - 2; x < w.x + w.w + 2; x += 4) { f.rect(x, 58, 4, 5, ((x - w.x + 2) / 4) % 2 ? w.awning[1] : w.awning[0]); } f.hline(w.x - 2, 63, w.w + 4, withAlpha([0, 0, 0, 255], 70)); } D.plainWindow(f, w.x, w.y, w.w, w.h, { bar: true, shutters: w.shutters, tint: w.tint }); }
    D.door(f, doorX, 58, 12, 22, door);
    if (deco) deco(f);
  };
  const drawLit = (f) => { for (const w of litWindows) D.plainWindow(f, w.x, w.y, w.w, w.h, { lit: true, bar: true }); };
  return { w: 8, h: 5, roofRows: 3, footRows: [1, 3], open: [], windows, door: { cx: Math.round((doorX + 6) / 16) - 1, cy: 4, w: 32 }, draw, drawLit };
}
const boat = (f, x, y, hull, sail) => {
  D.fillPoly(f, [[x, y + 8], [x + 14, y + 8], [x + 11, y + 12], [x + 3, y + 12]], () => hull);
  D.fillPoly(f, [[x + 7, y], [x + 7, y + 7], [x + 1, y + 7]], () => sail);
  D.fillPoly(f, [[x + 8, y + 2], [x + 8, y + 7], [x + 13, y + 7]], () => shade(sail, 0.85));
  f.vline(x + 7, y - 1, 9, B.woodDark);
};


// ---------------------------------------------------------------- casa de Abuela Paula y Abuelo Pepe (wooden, 8x6 = 128x96, lots of small details)
const WOOD = { base: rgb("#a06c3e"), light: rgb("#b98250"), dark: rgb("#7a4f2b"), deep: rgb("#4f3219"), grey: rgb("#8d7a62") };
const PAULA_WIN = [{ x: 14, y: 72, w: 11, h: 12 }, { x: 88, y: 72, w: 11, h: 12 }];
function drawPaula(f) {
  const PW = 128;
  // roof: old zinc, rust streaks, a stove chimney with a cap
  D.hipRoof(f, 2, 2, 124, 62, { base: rgb("#b4b8b8"), light: rgb("#d0d3d1"), dark: rgb("#8c9190"), line: rgb("#767b7a"), trim: WOOD.dark, trimDark: WOOD.deep }, { top: 22, side: 28, frontTrim: 4, salt: "paularoof" });
  for (let i = 0; i < 70; i++) {
    const x = 6 + Math.floor(noise("pr", i, 1) * 114), y = 8 + Math.floor(noise("pr", i, 2) * 50);
    if (f.get(x, y)[0] > 140) f.px(x, y, B.zincRust);
  }
  for (const y of [20, 38]) f.vline(30 + y, y, 10, withAlpha(B.zincRust, 150)); // rain streaks
  f.rect(98, 6, 6, 18, rgb("#5c5f63")); f.vline(98, 6, 18, rgb("#7a7e82")); f.rect(96, 4, 10, 3, rgb("#43464a")); f.hline(96, 4, 10, rgb("#6b6f74"));
  // deep porch: recessed wooden wall (vertical planks, a few patched boards), eave shadow
  for (let y = 64; y < 92; y++) for (let x = 0; x < PW; x++) {
    const plank = Math.floor(x / 4), edge = x % 4 === 3;
    let c = (plank % 3 === 0) ? WOOD.base : (plank % 3 === 1) ? shade(WOOD.base, 0.94) : shade(WOOD.base, 1.05);
    if (plank === 9 || plank === 23) c = shade(WOOD.grey, 1.0 + (plank === 9 ? 0.05 : 0)); // replaced boards, greyer
    if (edge) c = WOOD.dark;
    else if (noise("pw", x, y) < 0.05) c = shade(c, 0.9);
    f.px(x, y, c);
  }
  for (let y = 64; y < 70; y++) f.hline(0, y, PW, withAlpha([0, 0, 0, 255], 90 - (y - 64) * 14));
  f.rect(0, 64, PW, 3, WOOD.dark); f.hline(0, 64, PW, WOOD.light); // porch beam
  // windows with open turquoise shutters and a flower box
  for (const w of PAULA_WIN) {
    D.plainWindow(f, w.x, w.y, w.w, w.h, { bar: true, shutters: rgb("#4f9a9e"), frame: B.whiteTrim });
    f.rect(w.x - 2, w.y + w.h + 3, w.w + 4, 4, WOOD.dark); f.hline(w.x - 2, w.y + w.h + 3, w.w + 4, WOOD.light);
    for (let i = 0; i < w.w + 2; i += 2) { f.px(w.x - 1 + i, w.y + w.h + 2, i % 4 ? C.flower.pink : C.flower.yellow); f.px(w.x - 1 + i, w.y + w.h + 1, B.leaf); }
  }
  // door: dark wood, two panels, a little roof lamp, a doormat
  D.door(f, 58, 70, 12, 22, { base: WOOD.deep, light: shade(WOOD.deep, 1.5), dark: shade(WOOD.deep, 0.7) });
  f.rect(61, 66, 6, 3, B.zincDark); f.rect(62, 69, 4, 1, B.litGlow);
  f.rect(57, 92, 14, 2, rgb("#8a3d3a")); f.hline(57, 92, 14, rgb("#b25a52"));
  // rocking chair on the right of the door, a woven hammock bundle on the left, hanging plants from the beam
  f.rect(100, 82, 2, 10, WOOD.deep); f.vline(104, 82, 10, WOOD.deep); f.vline(106, 82, 10, WOOD.deep);
  for (const x of [101, 103, 105]) f.vline(x, 80, 6, WOOD.dark);
  f.rect(100, 85, 8, 3, WOOD.light); f.hline(100, 85, 8, shade(WOOD.light, 1.2));
  f.rect(100, 82, 9, 1, WOOD.dark); f.hline(98, 91, 12, WOOD.deep); f.hline(99, 92, 10, withAlpha([0, 0, 0, 255], 60));
  f.rect(38, 74, 14, 5, rgb("#d9b24a")); for (let i = 0; i < 14; i += 3) f.vline(38 + i, 74, 5, rgb("#b8932a")); f.hline(38, 79, 14, rgb("#8a6e1f")); // rolled hammock
  f.vline(37, 66, 9, B.rope); f.vline(52, 66, 9, B.rope);
  for (const x of [78, 112]) { f.vline(x + 3, 67, 6, B.rope); D.pottedPlant(f, x - 1, 80, { flowers: x === 78 }); }
  // porch posts (turned wood), railing on both sides, open steps in the middle
  for (const x of [3, 33, 91, 122]) { f.rect(x, 66, 3, 27, WOOD.base); f.vline(x, 66, 27, WOOD.light); f.vline(x + 2, 66, 27, WOOD.dark); f.rect(x - 1, 66, 5, 2, WOOD.light); f.rect(x - 1, 91, 5, 2, WOOD.dark); }
  for (const [a, b] of [[6, 33], [94, 122]]) { f.rect(a, 80, b - a, 2, WOOD.light); f.hline(a, 82, b - a, WOOD.dark); for (let x = a + 2; x < b; x += 5) f.vline(x, 82, 9, WOOD.base); }
  // deck planks and steps
  for (let y = 92; y < 96; y++) for (let x = 0; x < PW; x++) f.px(x, y, (x % 10 === 0) ? WOOD.deep : (y === 92 ? WOOD.light : y === 95 ? WOOD.dark : WOOD.base));
  f.rect(52, 93, 24, 3, shade(WOOD.base, 1.1)); f.hline(52, 93, 24, WOOD.light); f.hline(52, 95, 24, WOOD.deep);
  // firewood stack against the left end, and a wash tub with a hanging cloth
  for (let r = 0; r < 3; r++) for (let c = 0; c < 4 - r; c++) { const x = 8 + c * 5 + r * 2, y = 88 - r * 4; f.ellipse(x + 2, y + 1, 2.4, 2.4, WOOD.dark); f.ellipse(x + 2, y + 1, 1.5, 1.5, rgb("#c9a06a")); }
  f.hline(7, 91, 22, withAlpha([0, 0, 0, 255], 70));
  f.rect(110, 62, 14, 3, rgb("#d8d4c4")); f.rect(112, 65, 10, 4, rgb("#d8d4c4")); // cloth over the beam
  f.vline(116, 65, 4, rgb("#b9b5a4"));
}
const drawPaulaLit = (f) => { for (const w of PAULA_WIN) D.plainWindow(f, w.x, w.y, w.w, w.h, { lit: true, bar: true }); D.plainWindow(f, 62, 69, 4, 1, { lit: true }); };

const BUILDINGS = [
  {
    name: "iglesia", roof_of: "iglesia", col0: 0, row0: 0, w: 10, h: 12, roofRows: 8, footRows: [4, 8], open: [],
    windows: [], door: { cx: 4, cy: 11, w: 32 }, draw: drawIglesia, drawLit: drawIglesiaLit,
  },
  {
    name: "casa_1", roof_of: "casa_1", col0: 10, row0: 0,
    ...fillerHouse({
      wall: wallPal(B.yellowWall, B.yellowShade, B.creamHi, shade(B.yellowShade, 0.9), "c1"),
      roof: { base: B.redBase, light: B.redLight, dark: B.redDark, line: B.redLine, trim: B.greenTrim, trimDark: B.greenTrimDark },
      door: { base: B.greenTrim, light: shade(B.greenTrim, 1.25), dark: B.greenTrimDark },
      windows: [14, 71], hip: true, shutters: B.greenTrim,
    }),
  },
  {
    name: "casa_2", roof_of: "casa_2", col0: 10, row0: 5,
    ...fillerHouse({
      wall: wallPal(B.blueWall, B.blueWallShade, rgb("#d3e3f0"), shade(B.blueWallShade, 0.9), "c2"),
      roof: { base: B.blueBase, light: B.blueLight, dark: B.blueDark, line: B.blueLine, trim: B.whiteTrimShade, trimDark: B.zincDark },
      door: { base: B.whiteTrim, light: "#ffffff", dark: B.whiteTrimShade },
      windows: [12, 73], hip: false,
    }),
  },
  {
    name: "casa_mama", roof_of: "casa_mama", col0: 0, row0: 12, w: 8, h: 6, roofRows: 4, footRows: [1, 4],
    open: [[6, 5], [7, 5]],
    windows: [{ x: 49, y: 70, w: 14, h: 20 }, { x: 21, y: 69, w: 9, h: 22 }],
    door: { cx: 5, cy: 5, w: 32 }, draw: drawMama, drawLit: drawMamaLit,
  },
  {
    name: "casa_3", roof_of: "casa_3", col0: 8, row0: 12,
    ...fillerHouse({
      wall: wallPal(B.salmon, B.salmonShade, rgb("#f2c3b2"), shade(B.salmonShade, 0.88), "c3"),
      roof: { base: B.rustBase, light: B.rustLight, dark: B.rustDark, line: B.rustLine, trim: B.whiteTrim, trimDark: B.whiteTrimShade },
      door: { base: B.woodLight, light: shade(B.woodLight, 1.2), dark: B.woodDark },
      windows: [18, 67], hip: true,
      columns: { base: B.pinkColumn, light: B.pinkLight, dark: B.pinkColumnDark },
    }),
  },
  {
    name: "abastecedor", roof_of: "abastecedor", col0: 0, row0: 24, litBase: id(34, 0), litEnd: id(36, 0),
    ...shopBuilding({
      wall: wallPal(B.yellowWall, B.yellowShade, B.creamHi, shade(B.yellowShade, 0.9), "ab"),
      roof: { base: B.zincBase, light: B.zincLight, dark: B.zincDark, line: B.zincLine, trim: B.greenTrim, trimDark: B.greenTrimDark },
      door: { base: B.greenTrim, light: shade(B.greenTrim, 1.25), dark: B.greenTrimDark },
      sign: { bg: B.greenTrim, light: shade(B.greenTrim, 1.3), dark: B.greenTrimDark, text: "ABASTECEDOR EL JARDIN", fg: B.whiteTrim },
      windows: [{ x: 12, y: 64, w: 12, h: 12 }, { x: 78, y: 64, w: 40, h: 12, awning: [B.redBase, B.whiteTrim], shutters: B.greenTrim }], salt: "abz",
    }),
  },
  {
    name: "bar", roof_of: "bar", col0: 8, row0: 24, litBase: id(34, 0), litEnd: id(36, 0),
    ...shopBuilding({
      wall: wallPal(rgb("#b4d3a6"), rgb("#98b98a"), rgb("#d0e6c4"), rgb("#7a9a6d"), "br"),
      roof: { base: B.rustBase, light: B.rustLight, dark: B.rustDark, line: B.rustLine, trim: B.whiteTrim, trimDark: B.whiteTrimShade },
      door: { base: B.woodLight, light: shade(B.woodLight, 1.2), dark: B.woodDark },
      sign: { bg: B.redBase, light: B.redLight, dark: B.redDark, text: "BAR MATA DE CAÑA", fg: rgb("#f4e8a0") },
      windows: [{ x: 14, y: 64, w: 14, h: 12 }, { x: 88, y: 64, w: 14, h: 12 }, { x: 108, y: 64, w: 12, h: 12 }], salt: "brz",
      deco: (f) => { for (const x of [34, 38, 42]) { f.rect(x, 66, 3, 8, B.zincBase); f.rect(x + 1, 63, 1, 3, B.zincLight); f.px(x, 66, B.zincLight); } },
    }),
  },
  {
    name: "guarderia", roof_of: "guarderia", col0: 0, row0: 29, litBase: id(34, 0), litEnd: id(36, 0),
    ...shopBuilding({
      wall: wallPal(B.blueWall, B.blueWallShade, rgb("#d3e3f0"), shade(B.blueWallShade, 0.9), "gu"),
      roof: { base: B.redBase, light: B.redLight, dark: B.redDark, line: B.redLine, trim: B.whiteTrim, trimDark: B.whiteTrimShade },
      door: { base: rgb("#e8c442"), light: rgb("#f5dc72"), dark: rgb("#b8932a") },
      sign: { bg: rgb("#2f8f9a"), light: rgb("#58b3bd"), dark: rgb("#1f6a74"), text: "BARQUITOS DE ESPERANZA", fg: B.whiteTrim },
      windows: [{ x: 16, y: 64, w: 12, h: 12 }, { x: 100, y: 64, w: 12, h: 12 }], salt: "guz",
      deco: (f) => { boat(f, 34, 60, B.redBase, rgb("#f4e8a0")); boat(f, 78, 62, rgb("#2f8f9a"), B.whiteTrim); f.hline(32, 74, 22, shade(B.blueWall, 0.8)); f.hline(76, 75, 24, shade(B.blueWall, 0.8)); },
    }),
  },
  {
    name: "casa_paula", roof_of: "casa_paula", col0: 0, row0: 36, litBase: id(34, 0), litEnd: id(36, 0), w: 8, h: 6, roofRows: 4, footRows: [1, 4],
    open: Array.from({ length: 8 }, (_, cx) => [cx, 5]), // the porch row is walkable
    windows: PAULA_WIN, door: { cx: 3, cy: 5, w: 32 }, draw: drawPaula, drawLit: drawPaulaLit,
  },
];

// ---------------------------------------------------------------- interior of mama's house (12x9 cells)
export const INT_W = 12;
export const INT_H = 9;

const wood = { base: B.wood, light: B.woodLight, dark: B.woodDark };

function chair(f, x, y) {
  f.ellipse(x + 7, y + 14, 7, 2, D.SH);
  f.rect(x + 1, y + 1, 12, 6, B.woodLight); // seat seen from above
  f.hline(x + 1, y + 1, 12, shade(B.woodLight, 1.15));
  f.rect(x + 1, y + 7, 12, 7, B.wood); // backrest facing us
  for (let i = 0; i < 4; i++) f.vline(x + 2 + i * 3, y + 8, 5, B.woodDark);
  f.hline(x + 1, y + 7, 12, B.woodLight);
  f.hline(x + 1, y + 13, 12, B.woodDeep);
  f.rect(x + 2, y + 14, 2, 2, B.woodDeep); f.rect(x + 10, y + 14, 2, 2, B.woodDeep);
}

function drawInterior(f) {
  // table 24,24 48x32 with a red cloth runner, a cup and a bowl
  f.ellipse(48, 56, 25, 3, D.SH);
  D.plank(f, 24, 24, 48, 26, B.woodLight, shade(B.woodLight, 1.2), B.wood, "tbl");
  for (const y of [30, 36, 42]) f.hline(24, y, 48, shade(B.woodLight, 0.88));
  f.rect(31, 27, 34, 19, B.cloth);
  f.hline(31, 27, 34, B.clothLight);
  for (let x = 33; x < 64; x += 4) f.vline(x, 28, 17, B.clothShade);
  f.hline(31, 45, 34, B.clothShade);
  f.rect(37, 32, 4, 4, [242, 239, 230, 255]); f.px(41, 33, [242, 239, 230, 255]); f.hline(37, 32, 4, B.whiteTrimShade);
  f.ellipse(54, 37, 4, 2.4, [214, 214, 208, 255]); f.ellipse(54, 36.5, 2.8, 1.4, B.zincDark);
  f.rect(24, 50, 48, 4, B.wood);
  f.hline(24, 50, 48, B.woodLight);
  f.hline(24, 53, 48, B.woodDark);
  for (const x of [26, 68]) f.rect(x, 54, 3, 2, B.woodDeep);
  // two chairs; mama's is under her figure at 48,60
  chair(f, 24, 60);
  chair(f, 47, 60);
  // radio on a small stool at 72,60
  f.ellipse(80, 75, 7, 2, D.SH);
  f.rect(74, 70, 12, 3, B.woodLight); f.hline(74, 70, 12, shade(B.woodLight, 1.2)); f.hline(74, 73, 12, B.woodDark);
  f.vline(75, 73, 3, B.woodDeep); f.vline(84, 73, 3, B.woodDeep);
  f.rect(73, 63, 14, 7, B.radio); f.hline(73, 63, 14, B.radioLight); f.vline(73, 63, 7, B.radioLight); f.hline(73, 69, 14, shade(B.radio, 0.7));
  f.ellipse(77.5, 66.5, 3, 2.6, shade(B.radio, 0.7));
  for (const [x, y] of [[76, 65], [78, 65], [77, 67], [79, 67], [76, 68]]) f.px(x, y, B.radioLight);
  f.rect(82, 64, 4, 2, [190, 200, 180, 255]); f.px(83, 67, B.litRim); f.px(85, 67, B.metal);
  f.line(85, 63, 90, 55, B.metal); f.px(90, 54, B.metal);
  // wall shelf with a flashlight and the phone charger at 88..136
  f.rect(86, 34, 52, 3, B.wood); f.hline(86, 34, 52, B.woodLight); f.hline(86, 36, 52, B.woodDark);
  f.rect(88, 37, 2, 3, B.woodDeep); f.rect(134, 37, 2, 3, B.woodDeep);
  f.rect(91, 29, 9, 5, [236, 200, 70, 255]); f.rect(100, 28, 3, 6, B.zincDark); f.hline(91, 29, 9, [250, 226, 120, 255]);
  f.rect(106, 27, 7, 7, [196, 172, 120, 255]); f.hline(106, 27, 7, [216, 196, 150, 255]); // small box
  f.rect(121, 28, 10, 6, [236, 236, 230, 255]); f.hline(121, 28, 10, [255, 255, 255, 255]); f.px(129, 30, [200, 50, 50, 255]);
  f.vline(124, 24, 4, B.cross); f.px(124, 24, B.metal); // charger cable up the wall
  // bed at 144,24 24x32
  f.ellipse(156, 56, 13, 2.5, D.SH);
  f.rect(144, 24, 24, 5, B.woodDark); f.hline(144, 24, 24, B.wood);
  f.rect(145, 29, 22, 6, B.bedSheet);
  f.rect(147, 29, 8, 5, B.pillow); f.rect(157, 29, 8, 5, B.pillow); f.hline(147, 33, 8, B.bedSheetShade); f.hline(157, 33, 8, B.bedSheetShade);
  f.rect(145, 35, 22, 15, B.bedBlanket);
  f.hline(145, 35, 22, B.bedSheetShade); f.hline(145, 36, 22, B.bedSheet);
  for (let x = 147; x < 166; x += 5) f.vline(x, 38, 11, B.bedBlanketDark);
  f.hline(145, 49, 22, B.bedBlanketDark);
  f.rect(144, 50, 24, 5, B.wood); f.hline(144, 50, 24, B.woodLight); f.hline(144, 54, 24, B.woodDark);
  f.vline(144, 29, 21, B.woodDark); f.vline(167, 29, 21, B.woodDark);
}

// ---------------------------------------------------------------- interior of Abuela Paula y Abuelo Pepe (16x11 cells = 256x176 px, wooden house)
const CLAY = rgb("#a8542d"), CLAYDARK = rgb("#7c3a1e"), CLAYLIGHT = rgb("#c47440");
const IRON = rgb("#2e2e30"), IRONLIGHT = rgb("#55575a");
const TURQ = rgb("#4f9a9e"), TURQDARK = rgb("#357377");
const YARN = [rgb("#c4584a"), rgb("#e8c442"), rgb("#4f9a9e"), rgb("#8d5bb5"), rgb("#f1efe4"), rgb("#6bb03a")];

function stool(f, x, y) {
  f.ellipse(x + 7, y + 13, 7, 2, D.SH);
  f.ellipse(x + 7, y + 4, 7, 3.4, B.woodLight); f.ellipse(x + 7, y + 3.5, 5.5, 2.3, shade(B.woodLight, 1.15));
  f.rect(x + 2, y + 6, 2, 7, B.woodDark); f.rect(x + 10, y + 6, 2, 7, B.woodDark); f.vline(x + 6, y + 7, 6, B.woodDeep);
}

function drawPaulaInterior(f) {
  // wood stove (fogón) against the back wall at x8..44: clay body, iron top with two burners, firebox with a glow, a black pot and a blue enamel kettle
  f.ellipse(26, 53, 20, 3, D.SH);
  f.rect(8, 32, 36, 20, CLAY); f.hline(8, 32, 36, CLAYLIGHT); f.vline(8, 32, 20, CLAYLIGHT); f.vline(43, 32, 20, CLAYDARK); f.hline(8, 51, 36, CLAYDARK);
  for (let y = 36; y < 51; y += 5) for (let x = 9 + ((y / 5) % 2) * 4; x < 43; x += 8) f.px(x, y, CLAYDARK);
  f.rect(6, 28, 40, 5, IRON); f.hline(6, 28, 40, IRONLIGHT);
  f.ellipse(18, 30, 4.5, 1.6, IRONLIGHT); f.ellipse(34, 30, 4.5, 1.6, IRONLIGHT);
  f.rect(14, 40, 14, 10, IRON); f.rect(16, 46, 10, 3, rgb("#f08a2c")); f.rect(18, 47, 6, 2, rgb("#ffd27a")); f.hline(14, 40, 14, IRONLIGHT);
  f.rect(31, 41, 8, 7, IRON); f.hline(31, 41, 8, IRONLIGHT); f.px(38, 44, B.metal); // ash door
  f.rect(12, 21, 11, 8, rgb("#1f2022")); f.hline(12, 21, 11, IRONLIGHT); f.rect(11, 20, 13, 2, IRON); f.rect(23, 23, 3, 2, IRON); // black pot with its lid and handle
  f.rect(30, 23, 8, 6, TURQ); f.hline(30, 23, 8, shade(TURQ, 1.3)); f.hline(30, 28, 8, TURQDARK); f.rect(38, 24, 3, 1, TURQ); f.vline(29, 24, 4, TURQDARK); f.rect(32, 21, 4, 2, TURQDARK); // kettle
  // firewood stack beside the stove
  f.hline(46, 54, 17, withAlpha([0, 0, 0, 255], 70));
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3 - (r === 2 ? 1 : 0); c++) {
    const x = 49 + c * 5 + (r === 1 ? 2 : 0) + (r === 2 ? 2 : 0), y = 50 - r * 4;
    f.ellipse(x, y + 1, 2.7, 2.7, B.woodDark); f.ellipse(x, y + 1, 1.7, 1.7, rgb("#c9a06a")); f.px(x, y + 1, B.woodDark);
  }
  // clay water jar (tinaja) on a wooden ring
  f.ellipse(11, 85, 8, 2, D.SH);
  f.ellipse(11, 77, 7, 9, CLAY); f.ellipse(9, 74, 3, 5, CLAYLIGHT); f.rect(7, 66, 8, 4, CLAYDARK); f.rect(6, 65, 10, 2, CLAY); f.hline(7, 67, 8, CLAYLIGHT);
  f.rect(4, 83, 14, 2, B.woodDark);
  // table with a red and white check oilcloth, the greca (coffee pot), cups and a bread basket
  f.ellipse(124, 93, 31, 3, D.SH);
  D.plank(f, 96, 64, 56, 24, B.woodLight, shade(B.woodLight, 1.2), B.wood, "ptbl");
  for (let y = 66; y < 86; y++) for (let x = 99; x < 149; x++) f.px(x, y, ((x >> 2) + (y >> 2)) % 2 ? rgb("#f1efe4") : rgb("#c4584a"));
  f.hline(99, 66, 50, B.clothLight); f.hline(99, 85, 50, B.clothShade);
  f.rect(96, 88, 56, 4, B.wood); f.hline(96, 88, 56, B.woodLight); f.hline(96, 91, 56, B.woodDark);
  for (const x of [98, 146]) f.rect(x, 92, 3, 3, B.woodDeep);
  f.rect(106, 70, 5, 8, B.metal); f.hline(106, 70, 5, rgb("#e8eaec")); f.rect(105, 77, 7, 2, B.zincDark); f.px(111, 72, B.zincDark); f.px(112, 71, B.zincDark); f.rect(103, 71, 2, 5, B.cross); // greca
  for (const x of [118, 123]) { f.rect(x, 73, 4, 4, [242, 239, 230, 255]); f.px(x + 4, 74, [242, 239, 230, 255]); f.hline(x, 73, 4, B.whiteTrimShade); f.px(x + 1, 74, rgb("#5a3a1e")); }
  f.ellipse(137, 76, 6, 3.4, rgb("#c9a06a")); f.ellipse(137, 75, 4.6, 2.2, rgb("#e8cf9a")); for (const x of [134, 137, 140]) f.px(x, 75, rgb("#b78a4e"));
  stool(f, 100, 98); stool(f, 134, 98);
  // bed (right wall) with a crocheted granny-square blanket
  f.ellipse(228, 77, 21, 3, D.SH);
  f.rect(208, 30, 40, 6, B.woodDark); f.hline(208, 30, 40, B.wood);
  f.rect(209, 36, 38, 8, B.bedSheet);
  f.rect(212, 36, 14, 7, B.pillow); f.rect(230, 36, 14, 7, B.pillow); f.hline(212, 42, 14, B.bedSheetShade); f.hline(230, 42, 14, B.bedSheetShade);
  f.rect(209, 44, 38, 28, B.bedSheet);
  for (let gy = 0; gy < 3; gy++) for (let gx = 0; gx < 5; gx++) {
    const x = 209 + gx * 7.6, y = 45 + gy * 8.6, c = YARN[(gx * 2 + gy * 3) % YARN.length];
    f.rect(Math.round(x), Math.round(y), 7, 8, c); f.rect(Math.round(x) + 2, Math.round(y) + 2, 3, 4, YARN[(gx + gy * 2 + 3) % YARN.length]);
    f.hline(Math.round(x), Math.round(y) + 8, 8, rgb("#3f2916")); f.vline(Math.round(x) + 7, Math.round(y), 9, rgb("#3f2916"));
  }
  f.hline(209, 70, 38, B.bedBlanketDark);
  f.rect(208, 72, 40, 5, B.wood); f.hline(208, 72, 40, B.woodLight); f.hline(208, 76, 40, B.woodDark);
  f.vline(208, 36, 36, B.woodDark); f.vline(247, 36, 36, B.woodDark);
  // Abuela's rocking chair with a crochet basket at her feet
  f.ellipse(62, 124, 14, 2.5, D.SH);
  f.rect(52, 100, 18, 20, B.wood); for (let x = 54; x < 69; x += 3) f.vline(x, 101, 17, B.woodDark); f.hline(52, 100, 18, B.woodLight);
  f.rect(50, 112, 22, 6, B.woodLight); f.hline(50, 112, 22, shade(B.woodLight, 1.2)); f.hline(50, 117, 22, B.woodDark);
  f.rect(54, 108, 14, 5, rgb("#b04a6e")); f.hline(54, 108, 14, rgb("#d77a9a")); // her shawl
  f.line(48, 124, 56, 126, B.woodDeep); f.hline(56, 126, 12, B.woodDeep); f.line(68, 126, 76, 123, B.woodDeep); // rocker
  f.ellipse(86, 121, 5.5, 3, rgb("#c9a06a")); f.ellipse(86, 120, 4.2, 1.8, rgb("#e8cf9a")); f.ellipse(84, 119, 2, 1.6, YARN[0]); f.ellipse(88, 119, 2, 1.6, YARN[2]); f.line(88, 118, 94, 112, YARN[0]);
  // Abuelo's bench and the radio on a small table
  f.ellipse(178, 120, 14, 2.5, D.SH);
  f.rect(166, 104, 24, 5, B.woodLight); f.hline(166, 104, 24, shade(B.woodLight, 1.2)); f.hline(166, 108, 24, B.woodDark);
  f.rect(166, 98, 24, 6, B.wood); for (let x = 168; x < 189; x += 4) f.vline(x, 99, 5, B.woodDark);
  f.rect(168, 109, 3, 8, B.woodDeep); f.rect(185, 109, 3, 8, B.woodDeep);
  f.rect(196, 106, 18, 3, B.woodLight); f.hline(196, 106, 18, shade(B.woodLight, 1.2)); f.rect(198, 109, 2, 9, B.woodDeep); f.rect(210, 109, 2, 9, B.woodDeep);
  f.ellipse(205, 120, 9, 2, D.SH);
  f.rect(198, 96, 14, 10, B.radio); f.hline(198, 96, 14, B.radioLight); f.vline(198, 96, 10, B.radioLight); f.hline(198, 105, 14, shade(B.radio, 0.7));
  f.rect(200, 98, 6, 4, [190, 200, 180, 255]); f.px(209, 99, B.metal); f.px(209, 101, B.metal); f.ellipse(209, 103, 1.6, 1.4, B.radioLight);
  f.line(210, 96, 216, 86, B.metal); f.px(216, 85, B.metal);
}

function drawPaulaWall(f) {
  // 256 x 32: old vertical planks (a few replaced, greyer ones), baseboard, shuttered window, photos, calendar, saints' shelf, machete and hat, garlic and chili strings, the stove pipe
  for (let y = 0; y < 32; y++) for (let x = 0; x < 256; x++) {
    const plank = Math.floor(x / 4), edge = x % 4 === 3;
    let c = plank % 3 === 0 ? WOOD.base : plank % 3 === 1 ? shade(WOOD.base, 0.94) : shade(WOOD.base, 1.05);
    if (plank === 11 || plank === 37 || plank === 52) c = shade(WOOD.grey, 1.04);
    if (edge) c = WOOD.dark; else if (noise("piw", x, y) < 0.05) c = shade(c, 0.9);
    f.px(x, y, c);
  }
  f.rect(0, 26, 256, 6, WOOD.dark); f.hline(0, 26, 256, WOOD.light); f.hline(0, 31, 256, WOOD.deep); // baseboard
  // window with open turquoise shutters
  f.rect(111, 4, 34, 20, B.doorFrame); f.rect(113, 6, 30, 16, B.glass); f.rect(113, 6, 30, 5, B.glassHi); f.vline(127, 6, 16, B.doorFrame); f.hline(113, 14, 30, B.doorFrame);
  for (const [x0, dir] of [[110, -1], [145, 1]]) { f.rect(dir < 0 ? x0 - 8 : x0, 3, 8, 22, TURQ); f.vline(dir < 0 ? x0 - 8 : x0 + 7, 3, 22, TURQDARK); for (let j = 4; j < 24; j += 3) f.hline(dir < 0 ? x0 - 7 : x0 + 1, j, 7, TURQDARK); }
  f.rect(109, 24, 38, 2, B.whiteTrimShade); f.hline(109, 24, 38, B.whiteTrim);
  // old photographs and the calendar
  D.savedPicture(f, 40, 7, 10, 9);
  f.rect(58, 9, 10, 12, B.frameGold); f.rect(59, 10, 8, 10, rgb("#d9d2bd")); f.rect(61, 12, 4, 4, B.picSkin); f.rect(60, 16, 6, 4, rgb("#4f6fa8")); f.hline(58, 9, 10, shade(B.frameGold, 1.3));
  f.rect(76, 8, 12, 9, B.frameGold); f.rect(77, 9, 10, 7, rgb("#c9c2ad")); f.rect(79, 11, 3, 3, B.picSkin); f.rect(83, 11, 3, 3, rgb("#8d6a4a")); f.hline(76, 8, 12, shade(B.frameGold, 1.3));
  f.rect(176, 4, 14, 19, B.whiteTrim); f.rect(176, 4, 14, 5, rgb("#c4584a")); f.hline(176, 4, 14, rgb("#e07a68")); f.px(182, 6, rgb("#f1efe4")); f.px(183, 6, rgb("#f1efe4"));
  for (let j = 0; j < 4; j++) for (let i = 0; i < 5; i++) f.px(178 + i * 2, 11 + j * 3, rgb("#5a4a3a"));
  f.px(180, 14, rgb("#c4584a")); f.vline(183, 3, 1, B.zincDark);
  // saints' shelf with two candles, a Virgen picture and a vase of flowers
  f.rect(196, 17, 44, 3, B.wood); f.hline(196, 17, 44, B.woodLight); f.hline(196, 19, 44, B.woodDark); f.rect(199, 20, 2, 3, B.woodDeep); f.rect(236, 20, 2, 3, B.woodDeep);
  f.rect(209, 4, 12, 13, B.frameGold); f.rect(210, 5, 10, 11, rgb("#4f6fa8")); f.rect(214, 7, 2, 3, B.picSkin); f.rect(212, 10, 6, 5, rgb("#f1efe4")); f.hline(212, 6, 6, B.picGold); f.hline(209, 4, 12, shade(B.frameGold, 1.3));
  for (const x of [200, 226]) { f.rect(x, 11, 3, 6, B.whiteTrim); f.px(x + 1, 9, rgb("#ffd27a")); f.px(x + 1, 10, rgb("#f08a2c")); f.vline(x + 2, 11, 6, B.whiteTrimShade); }
  f.rect(231, 12, 5, 5, B.pot); f.hline(231, 12, 5, B.potLight); for (const [x, y] of [[231, 9], [233, 8], [235, 10], [232, 11]]) f.px(x, y, [C.flower.pink, C.flower.yellow][(x + y) % 2]); f.vline(233, 9, 3, B.leaf);
  // machete and straw hat
  f.line(246, 6, 253, 22, B.metal); f.line(247, 6, 254, 22, B.zincDark); f.rect(244, 3, 3, 4, B.woodDeep);
  f.ellipse(240, 24, 7, 2.4, rgb("#d9b86a")); f.ellipse(240, 22, 3.6, 3, rgb("#e8cf8a")); f.hline(236, 23, 9, rgb("#8a6e1f"));
  // garlic and chili strings
  f.vline(95, 2, 1, B.rope); f.vline(95, 3, 17, B.rope);
  for (let j = 0; j < 5; j++) { f.ellipse(94, 6 + j * 3, 2.2, 1.7, rgb("#efe6d0")); f.ellipse(97, 7 + j * 3, 2.2, 1.7, rgb("#e2d6bb")); }
  f.vline(160, 2, 18, B.rope);
  for (let j = 0; j < 5; j++) { f.rect(158, 5 + j * 3, 2, 3, rgb("#c1272f")); f.rect(161, 6 + j * 3, 2, 3, rgb("#a81f27")); }
  // the stove's pipe and its wall collar
  f.rect(24, 0, 5, 28, rgb("#4a4c50")); f.vline(24, 0, 28, IRONLIGHT); f.vline(28, 0, 28, IRON); f.rect(22, 9, 9, 2, IRON); f.hline(22, 9, 9, IRONLIGHT);
  for (let y = 0; y < 26; y += 3) f.px(26, y, rgb("#c9784a")); // rust
}

function drawBackWall(f) {
  // 192 x 16: plaster, green-grey wainscot, curtained window, two saint pictures
  D.plasterWall(f, 0, 0, 192, 16, { base: B.plaster, shade: B.plasterShade, hi: B.plaster, dark: B.plasterDark, salt: "iw", skirt: 0 });
  f.rect(0, 10, 192, 6, B.wainscot);
  f.hline(0, 10, 192, shade(B.wainscot, 1.25));
  for (let x = 4; x < 192; x += 8) f.vline(x, 11, 5, B.wainscotDark);
  f.hline(0, 15, 192, B.wainscotDark);
  // curtained window on the back wall: frame, daylight glass, white drapes tied to the sides
  f.rect(77, 1, 16, 11, B.doorFrame);
  f.rect(78, 2, 14, 9, B.glass); f.rect(78, 2, 14, 3, B.glassHi); f.vline(85, 2, 9, B.doorFrame); f.hline(78, 6, 14, B.doorFrame);
  for (const [x0, dir] of [[78, 1], [91, -1]]) for (let j = 0; j < 9; j++) { const wd = j < 6 ? 3 : 2; for (let i = 0; i < wd; i++) f.px(x0 + dir * i, 2 + j, (i + j) % 3 === 0 ? B.curtainShade : B.curtain); }
  f.rect(76, 12, 18, 2, B.whiteTrimShade); f.hline(76, 12, 18, B.whiteTrim);
  D.savedPicture(f, 122, 2, 10, 9);
  D.savedPicture(f, 32, 2, 10, 9);
  f.rect(54, 3, 8, 6, B.frameGold); f.rect(55, 4, 6, 4, [200, 170, 90, 255]); f.hline(54, 3, 8, shade(B.frameGold, 1.3));
}

// ---------------------------------------------------------------- hedges (two coloured variants of the town hedge)
function hedge(f, pal, salt) {
  f.ellipse(8, 14, 9, 2, D.SH);
  const lobes = [[4, 8, 6], [12, 8, 6], [20, 8, 6], [-4, 8, 6], [8, 6, 5.5], [0, 6, 5.5], [16, 6, 5.5]];
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let best = null;
    for (const [cx, cy, rad] of lobes) {
      const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / rad;
      if (d <= 1 && (!best || d < best.d)) best = { d, dy: (y + 0.5 - cy) / rad, dx: (x + 0.5 - cx) / rad };
    }
    if (!best) continue;
    const n = 0.6 * noise(salt + "c", x >> 1, y >> 1) + 0.4 * noise(salt + "p", x, y);
    let v = 0.5 - (best.dx * 0.4 + best.dy * 0.6) * 0.35 + (n - 0.5) * 0.45;
    if (best.d > 0.8 && best.dy > 0) v -= 0.25;
    f.px(x, y, v < 0.3 ? pal[1] : v < 0.65 ? pal[0] : pal[2]);
  }
}

const hedgeTiles = [
  { id: id(23, 12), name: "hedge_burgundy", layer: "ysort", solid: true, draw: (f) => hedge(f, [B.hedgeBurg, B.hedgeBurgDark, B.hedgeBurgLight], "hb") },
  { id: id(23, 13), name: "hedge_lime", layer: "ysort", solid: true, draw: (f) => hedge(f, [B.hedgeLime, B.hedgeLimeDark, B.hedgeLimeLight], "hl") },
];

// ---------------------------------------------------------------- assemble
const nonEmpty = (fr) => fr.data.some((v, i) => i % 4 === 3 && v > 0);
const cellKey = (cx, cy) => cx + "," + cy;

export const LIT_BASE_ID = id(18, 0);
export const INT_BASE_ID = id(20, 0);
export const WALL_BASE_ID = id(23, 0);
export const WALL_COLS = 12;

const canvases = new Map(); // building name -> { day, lit }
const litNext = new Map();

for (const b of BUILDINGS) {
  const day = new Frame(b.w * SIZE, b.h * SIZE);
  b.draw(day);
  const lit = new Frame(b.w * SIZE, b.h * SIZE);
  b.drawLit(lit);
  canvases.set(b.name, { day, lit });
  b.cells = [];
  b.lit = [];
  const litBase = b.litBase ?? LIT_BASE_ID, litEnd = b.litEnd ?? id(20, 0);
  let nextLit = litNext.get(litBase) ?? litBase;
  const open = new Set((b.open ?? []).map(([cx, cy]) => cellKey(cx, cy)));
  for (let cy = 0; cy < b.h; cy++) for (let cx = 0; cx < b.w; cx++) {
    const slice = day.slice(cx * SIZE, cy * SIZE, SIZE, SIZE);
    if (nonEmpty(slice)) {
      const isRoof = cy < b.roofRows;
      const cell = { cx, cy, id: id(b.row0 + cy, b.col0 + cx), name: `${b.name}_${cx}_${cy}`, layer: isRoof ? "above" : "ysort", building: b.name };
      if (!isRoof) {
        if (open.has(cellKey(cx, cy))) cell.sort_offset = -16;
        else cell.solid = true;
      }
      b.cells.push(cell);
    }
    const ls = lit.slice(cx * SIZE, cy * SIZE, SIZE, SIZE);
    if (nonEmpty(ls)) b.lit.push({ cx, cy, id: nextLit++, name: `${b.name}_lit_${cx}_${cy}`, layer: "ysort", sort_offset: 1, building: b.name });
  }
  litNext.set(litBase, nextLit);
  if (nextLit > litEnd) throw new Error(`too many lit cells in ${b.name}`);
}


// ---------------------------------------------------------------- interior of the abastecedor El Jardin (16x11 cells = 256x176 px, a small shop; Doña María stands behind the counter)
const SACK = rgb("#c9a96a"), SACKDARK = rgb("#9c7f48"), SACKLIGHT = rgb("#e0c58a");
const POTATO = rgb("#a8774a"), POTATODARK = rgb("#7d5530");

function sack(f, x, y, stripe) {
  f.ellipse(x + 9, y + 21, 10, 2, D.SH);
  f.rect(x, y + 4, 18, 16, SACK); f.vline(x, y + 4, 16, SACKLIGHT); f.vline(x + 17, y + 4, 16, SACKDARK); f.hline(x, y + 19, 18, SACKDARK);
  f.rect(x + 2, y + 1, 14, 4, SACKDARK); f.rect(x + 3, y + 2, 12, 2, SACK); f.hline(x + 5, y + 5, 8, SACKDARK); // tied neck
  f.rect(x + 3, y + 9, 12, 6, stripe); f.hline(x + 3, y + 9, 12, shade(stripe, 1.25));
  for (let i = 0; i < 6; i++) f.px(x + 2 + i * 3, y + 7 + (i % 2) * 11, SACKDARK);
}

function crate(f, x, y, fruit) {
  f.ellipse(x + 20, y + 25, 22, 2, D.SH);
  f.rect(x, y + 8, 40, 16, B.woodLight); f.hline(x, y + 8, 40, shade(B.woodLight, 1.2)); f.hline(x, y + 23, 40, B.woodDark);
  for (const yy of [12, 17, 21]) f.hline(x, y + yy, 40, B.woodDark);
  f.rect(x, y + 8, 3, 16, B.wood); f.rect(x + 37, y + 8, 3, 16, B.wood);
  for (let i = 0; i < 9; i++) f.ellipse(x + 4 + i * 4, y + 6 + (i % 2), 2.4, 2.4, fruit[i % fruit.length]);
}

function drawAbastecedorInterior(f) {
  // counter (mostrador) across the middle, with a scale, a cash register and a candy jar
  f.ellipse(128, 126, 58, 3, D.SH);
  D.plank(f, 72, 94, 112, 9, B.woodLight, shade(B.woodLight, 1.2), B.wood, "abc");
  f.rect(72, 103, 112, 19, B.wood); f.hline(72, 103, 112, B.woodDark); f.hline(72, 121, 112, B.woodDeep);
  for (let x = 72; x < 184; x += 14) { f.vline(x, 104, 17, B.woodDark); f.rect(x + 2, 106, 10, 12, shade(B.wood, 1.08)); }
  f.rect(72, 94, 112, 1, shade(B.woodLight, 1.3));
  // scale
  f.rect(82, 90, 18, 4, B.metal); f.hline(82, 90, 18, rgb("#e8eaec")); f.rect(90, 82, 3, 8, B.metal); f.ellipse(91, 80, 4, 4, rgb("#f1efe4")); f.px(91, 80, B.zincDark); f.line(91, 80, 93, 78, rgb("#c4584a"));
  // candy jar
  f.rect(120, 84, 12, 10, B.glassHi); f.rect(121, 85, 10, 8, B.glass); f.rect(119, 82, 14, 3, B.whiteTrimShade);
  for (const [dx, dy, c] of [[2, 3, "#c4584a"], [5, 2, "#e8c442"], [8, 4, "#6bb03a"], [3, 6, "#8d5bb5"], [7, 7, "#c4584a"]]) f.px(121 + dx, 85 + dy, rgb(c));
  // cash register
  f.rect(150, 82, 22, 12, rgb("#4a4d52")); f.hline(150, 82, 22, rgb("#6b6f75")); f.rect(153, 76, 10, 6, rgb("#2e2e30")); f.rect(155, 77, 6, 3, B.glass);
  for (let i = 0; i < 5; i++) f.px(154 + i * 3, 86, rgb("#c4c8cc")); f.rect(165, 85, 5, 4, rgb("#d9d2bd"));
  // sacks stacked on the left (rice, beans, sugar) and an open sack of potatoes
  sack(f, 8, 118, rgb("#c4584a")); sack(f, 28, 118, rgb("#4f6fa8")); sack(f, 46, 118, rgb("#e8c442"));
  sack(f, 17, 98, rgb("#6bb03a")); sack(f, 37, 98, rgb("#f1efe4"));
  f.ellipse(22, 166, 14, 2, D.SH);
  f.rect(10, 150, 24, 16, SACK); f.vline(10, 150, 16, SACKLIGHT); f.vline(33, 150, 16, SACKDARK); f.hline(10, 165, 24, SACKDARK);
  f.ellipse(22, 150, 12, 4, SACKDARK);
  for (const [dx, dy] of [[-8, 0], [-3, -2], [2, 0], [7, -1], [-5, 2], [4, 2]]) { f.ellipse(22 + dx, 149 + dy, 3.4, 2.6, POTATO); f.px(22 + dx - 1, 148 + dy, POTATODARK); }
  // refrigerator on the right with bottles
  f.ellipse(226, 114, 24, 3, D.SH);
  f.rect(204, 44, 44, 68, rgb("#e8eaec")); f.vline(204, 44, 68, rgb("#ffffff")); f.vline(247, 44, 68, rgb("#b4babf")); f.hline(204, 44, 44, rgb("#ffffff"));
  f.rect(208, 50, 36, 54, rgb("#26323c")); f.rect(209, 51, 34, 52, rgb("#34505f"));
  for (const yy of [64, 78, 92]) f.hline(209, yy, 34, rgb("#8d9aa3"));
  const COL = ["#c4584a", "#4f9a9e", "#e8c442", "#6bb03a", "#8d5bb5"];
  for (const [row, yy] of [[0, 54], [1, 68], [2, 82], [3, 96]]) for (let i = 0; i < 8; i++) { const c = rgb(COL[(i + row) % COL.length]); f.rect(211 + i * 4, yy, 3, 8, c); f.px(211 + i * 4 + 1, yy - 1, rgb("#c4c8cc")); }
  f.rect(204, 104, 44, 8, rgb("#c4c8cc")); f.vline(244, 60, 20, rgb("#8d9aa3"));
  // fruit crates (platanos and tomatoes) in the corner
  crate(f, 196, 144, [rgb("#e8c442"), rgb("#d4a82c")]);
  crate(f, 196, 124, [rgb("#c4584a"), rgb("#a8402f"), rgb("#d9654f")]);
}

function drawAbastecedorWall(f) {
  // 256 x 32: yellow plaster wall, green baseboard, two shelves with goods, the shop sign and a calendar
  for (let y = 0; y < 32; y++) for (let x = 0; x < 256; x++) {
    let c = B.yellowWall;
    if (noise("abw", x, y) < 0.06) c = shade(c, 0.94);
    if (y > 27) c = B.greenTrim;
    f.px(x, y, c);
  }
  f.hline(0, 27, 256, B.greenTrimDark); f.hline(0, 28, 256, shade(B.greenTrim, 1.2));
  const GOODS = ["#c4584a", "#4f9a9e", "#e8c442", "#6bb03a", "#8d5bb5", "#f1efe4", "#4f6fa8"];
  for (const [by, top] of [[13, 3], [24, 15]]) {
    for (let x = 8; x < 198; x += 7) {
      const h = 6 + Math.floor(noise("abg", x, by) * 4), c = rgb(GOODS[Math.floor(noise("abc", x, by) * GOODS.length)]);
      f.rect(x, by - h, 5, h, c); f.hline(x, by - h, 5, shade(c, 1.3)); f.px(x + 2, by - h + 2, rgb("#f1efe4"));
    }
    f.rect(6, by, 194, 3, B.wood); f.hline(6, by, 194, B.woodLight); f.hline(6, by + 2, 194, B.woodDark);
  }
  // sign
  f.rect(206, 3, 44, 14, B.greenTrimDark); f.rect(207, 4, 42, 12, B.greenTrim); f.hline(207, 4, 42, shade(B.greenTrim, 1.3));
  drawText(f, "EL JARDIN", 210, 8, B.whiteTrim);
  // calendar
  f.rect(222, 19, 12, 8, B.whiteTrim); f.rect(222, 19, 12, 2, rgb("#c4584a"));
}

// ---------------------------------------------------------------- interiors (maps/house_<name>.tmx): furniture + back wall drawn on canvases, sliced into sheet cells
// An interior spec: { name, w, h (tiles), intBase/intEnd (id range of the furniture cells), wallBase (first id of the wall cells), wallCols, wallRows, draw(f) furniture canvas, drawWall(f) wall canvas }.
// Furniture cells are named `${name}_int_${cx}_${cy}` (the non-empty cells of the canvas, ids handed out in reading order); wall cells `${name}_wall_${cx}` when the wall is one row tall,
// else `${name}_wall_${cx}_${cy}` (id = wallBase + cy * B_COLS + cx). Walls are solid ysort, furniture ysort without collision (the maps add collision rects).
const INTERIOR_SPECS = [
  { name: "casa_mama", w: INT_W, h: INT_H, intBase: INT_BASE_ID, intEnd: id(23, 0), wallBase: WALL_BASE_ID, wallCols: WALL_COLS, wallRows: 1, draw: drawInterior, drawWall: drawBackWall },
  { name: "casa_paula", w: 16, h: 11, intBase: id(42, 0), intEnd: id(48, 0), wallBase: id(48, 0), wallCols: 16, wallRows: 2, draw: drawPaulaInterior, drawWall: drawPaulaWall },
  { name: "tienda_abastecedor", w: 16, h: 11, intBase: id(50, 0), intEnd: id(56, 0), wallBase: id(56, 0), wallCols: 16, wallRows: 2, draw: drawAbastecedorInterior, drawWall: drawAbastecedorWall },
];
export const INTERIORS = INTERIOR_SPECS.map((spec) => {
  const furniture = new Frame(spec.w * SIZE, spec.h * SIZE);
  spec.draw(furniture);
  const wall = new Frame(spec.wallCols * SIZE, spec.wallRows * SIZE);
  spec.drawWall(wall);
  const cells = [];
  let n = spec.intBase;
  for (let cy = 0; cy < spec.h; cy++) for (let cx = 0; cx < spec.w; cx++) {
    if (nonEmpty(furniture.slice(cx * SIZE, cy * SIZE, SIZE, SIZE))) cells.push({ cx, cy, id: n++, name: `${spec.name}_int_${cx}_${cy}`, layer: "ysort" });
  }
  if (n > spec.intEnd) throw new Error(`too many interior cells in ${spec.name}: ${n - spec.intBase} (max ${spec.intEnd - spec.intBase})`);
  const wallCells = [];
  for (let cy = 0; cy < spec.wallRows; cy++) for (let cx = 0; cx < spec.wallCols; cx++) {
    wallCells.push({ cx, cy, id: spec.wallBase + cy * B_COLS + cx, name: spec.wallRows === 1 ? `${spec.name}_wall_${cx}` : `${spec.name}_wall_${cx}_${cy}`, layer: "ysort", solid: true });
  }
  return { ...spec, furnitureCanvas: furniture, wallCanvas: wall, cells, wallCells };
});
export const INTERIOR_BY_NAME = new Map(INTERIORS.map((i) => [i.name, i]));
// mama's house keeps its own exports (interior_map.mjs and the tests of #71 use them)
const MAMA = INTERIOR_BY_NAME.get("casa_mama");
export const INTERIOR_CELLS = MAMA.cells;
export const WALL_CELLS = MAMA.wallCells;

export { BUILDINGS };
export const BUILDING_BY_NAME = new Map(BUILDINGS.map((b) => [b.name, b]));

export const B_TILES = [];
for (const b of BUILDINGS) { for (const c of b.cells) B_TILES.push(c); for (const c of b.lit) B_TILES.push(c); }
for (const i of INTERIORS) { for (const c of i.cells) B_TILES.push(c); for (const c of i.wallCells) B_TILES.push(c); }
for (const t of hedgeTiles) B_TILES.push(t);
B_TILES.sort((a, b) => a.id - b.id);

// Sanity: ids unique and inside the sheet; names unique
{
  const seen = new Set(), names = new Set();
  for (const t of B_TILES) {
    if (t.id < 0 || t.id >= B_COLS * B_ROWS) throw new Error(`id out of sheet: ${t.name} ${t.id}`);
    if (seen.has(t.id)) throw new Error(`duplicate id ${t.id} (${t.name})`);
    if (names.has(t.name)) throw new Error(`duplicate name ${t.name}`);
    seen.add(t.id); names.add(t.name);
  }
}

/** Gid helper for maps: buildings tile name -> id (0-based within buildings.png). */
export const bIdByName = new Map(B_TILES.map((t) => [t.name, t.id]));

/** Render the sheet into a Frame of B_COLS*SIZE x B_ROWS*SIZE. */
export function renderBuildingSheet() {
  const sheet = new Frame(B_COLS * SIZE, B_ROWS * SIZE);
  const put = (tid, fr) => sheet.blit(fr, (tid % B_COLS) * SIZE, Math.floor(tid / B_COLS) * SIZE);
  for (const b of BUILDINGS) {
    const { day, lit } = canvases.get(b.name);
    for (const c of b.cells) put(c.id, day.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
    for (const c of b.lit) put(c.id, lit.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  for (const i of INTERIORS) {
    for (const c of i.cells) put(c.id, i.furnitureCanvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
    for (const c of i.wallCells) put(c.id, i.wallCanvas.slice(c.cx * SIZE, c.cy * SIZE, SIZE, SIZE));
  }
  for (const t of hedgeTiles) { const f = new Frame(SIZE, SIZE); t.draw(f); put(t.id, f); }
  return sheet;
}

/** Whole-building pictures for previews: { day, lit } canvases. */
export const buildingCanvas = (name) => canvases.get(name);
