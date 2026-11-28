// Zone 1 of Quebrada (issue #78): maps/zona1.tmx, rebuilt element by element (v2).
//
// SCALE: COMPRESSED, 2 m = 1 tile (16 px = 2 m, METRES_PER_TILE). The base is the church (iglesia, 10x12 tiles)
// standing north of a 100 m paver street (STREET_TILES = 50 tiles) that runs east-west, with the church door
// centred on the street. Known distortions: the street is 4 tiles wide (~8 m real) and the church is
// ~20 m wide at this scale (its drawing is unchanged).
// Everything else (houses, cafetal, trees, poles, roads, river...) is placed by the user one element at
// a time: add an entry to ELEMENTS below and run `node gen.mjs`.
//
// ELEMENTS is the single source of truth. Each entry has a `kind`:
//   street    { id, kind, surface: "paver"|"lastre", x, y, length, width }   horizontal band, tiles (x,y = top-left)
//   path      { id, kind, surface, x, y, w, h }                              any rectangle of ground, tiles
//   building  { id, kind, name, at: [tx, ty] }  name = a buildings tileset building (iglesia, casa_1...): walls,
//                                               roof layer (roof_<name>), roof_of rect, footprint collision,
//                                               lit windows and window lights are all derived from it
//   hedges    { id, kind, of }                  church-style hedges either side of the door of building `of`
//   tree      { id, kind, tree: "monte"|"guanacaste"|"platano"|"palm", at }  trunk on a free grass tile
//   prop      { id, kind, name, at }            single object tile on grass (weeds, rock, bench, stump...)
//   spawn     { id, kind, name, x, y, facing }  px
//   edge      { id, kind, edge, x, y, w, h, spawn: [x, y], facing }   px; empty connects_to for now
//   zone      { id, kind, zone, x, y, w, h, title, ambience }          px
//   interactable { id, kind, name, x, y, w, h, props }                 px
// The old (v1) switchback layout is superseded (see docs/zona1.md). The user's Chequelo layout is placed again: the cafetal (north,
// centred 50 m before the end of the paver), Chayo's house (casa_2) and mama's house (casa_mama) south of the lastre end with
// footpaths to their south-facing doors, the route (ROUTE / routeLength / pointAt), the triggers and the emitters.
//   door { id, kind, name, x, y, w, h, props }   emitter { id, kind, name, x, y, props }   surface { id, kind, name, x, y, w, h, surface }
// Helpers (autotiler, light) are copies of buildings_map.mjs: that file is NOT touched so the older
// generated outputs stay byte-identical.
import { TILES, SIZE, COLS, ROWS, renderSheet } from "./catalog.mjs";
import { BUILDINGS, BUILDING_BY_NAME, B_COLS, B_ROWS, B_TILES, bIdByName, renderBuildingSheet } from "./catalog_buildings.mjs";
import { PARK_OBJECT_BY_NAME, PARK_TILES, CIRCLE_CELLS, pIdByName, P_COLS, P_ROWS, renderParkSheet } from "./catalog_park.mjs";
import { SCHOOL_BUILDINGS, SCHOOL_BUILDING_BY_NAME, SCHOOL_OBJECT_BY_NAME, S_TILES, S_COLS, S_ROWS, sIdByName, renderSchoolSheet } from "./catalog_school.mjs";
import { EBAIS_BUILDINGS, EBAIS_BUILDING_BY_NAME, E_TILES, E_COLS, E_ROWS, eIdByName, renderEbaisSheet } from "./catalog_ebais.mjs";
import { M_TILES, M_COLS, M_ROWS, mIdByName, renderMonteSheet, ROTOR_CELLS, TOWER_H, ROTOR_N } from "./catalog_monte.mjs";
import { R_TILES, R_COLS, R_ROWS, rIdByName, renderRioSheet, RIO_SOLID_NAMES } from "./catalog_rio.mjs";
import { makeRiver } from "./river.mjs";
import { Frame } from "./draw.mjs";
import { noise as rawNoise } from "./rng.mjs";

// ---- map scale and the monte distance (first, because the left padding derives from them) ----
export const METRES_PER_TILE = 2; // compressed scale: 2 m = 1 tile
export const TILE = 16;
// THE MONTE (monte de hule y nispero + aerogeneradores) is EAST of the church = to the LEFT of the screen. In real life it is ~10 km away; simplified to 500 m.
// Measured from the church door centre to the centre of the monte zone: MONTE_DIST_T tiles. The zone is MONTE_W wide and must stay >= MONTE_MARGIN tiles from the map's left edge.
export const MONTE_DIST_M = 500; // real life 10 km, simplified
export const MONTE_DIST_T = MONTE_DIST_M / METRES_PER_TILE; // 250 tiles
export const MONTE_W = 60; // tiles = 120 m
export const MONTE_MARGIN = 10; // grass tiles between the map's left edge and the monte zone
// ---- left padding: the whole original layout is shifted LEFT_PAD columns to the right (room for the plots east of the asphalt street, and for the monte 500 m east of the church) ----
const BASE_PAD = 16; // the pad before the monte existed (room for the school / Olguita plots)
const BASE_DOOR_PX = 816; // church door centre x with BASE_PAD (= (CHURCH_X + 5) * TILE)
export const LEFT_PAD = BASE_PAD + Math.ceil((MONTE_DIST_T * TILE - BASE_DOOR_PX + (MONTE_MARGIN + MONTE_W / 2) * TILE) / TILE); // 255 tiles of grass / monte at the LEFT of the screen
const X = (x) => x + LEFT_PAD; // an original (pre-shift) absolute column -> current absolute column
// position noise is shift-invariant: the original layout keeps exactly its old textures / tree scatter
// ... and TOP_PAD rows of river / north land were added on top: positions are also measured from the old top row
const noise = (salt, x, y, v = 0) => rawNoise(salt, x - LEFT_PAD, y - TOP_PAD, v);

// ---- map size and scale ----
export const PX_PER_METRE = TILE / METRES_PER_TILE; // 8 px = 1 m
export const STREET_METRES = 100; // required: exactly 100 m
export const STREET_TILES = STREET_METRES / METRES_PER_TILE; // 50 tiles
// Orientation convention (the user's): WEST = RIGHT of the screen (increasing column), EAST = LEFT, SOUTH = bottom, NORTH = top.
// The main street grows west (to the right) from its original end at col 59: paver (cement) then 200 m of lastre (earth). The paver stretch was 550 m, cut to 310 m so that
// the cafetal / colegio lie ~50 m beyond Los Machillos (no dead land in between); mama's and Chayo's houses stay at the same place relative to the lastre end.
export const OLD_PAVER_TILES = 275;
export const EXT_PAVER_M = 310;
export const EXT_LASTRE_M = 200;
export const EXT_PAVER_TILES = EXT_PAVER_M / METRES_PER_TILE; // 275
export const EXT_LASTRE_TILES = EXT_LASTRE_M / METRES_PER_TILE; // 100
export const STREET_X = LEFT_PAD + 10; // first column of the original 100 m street (the east asphalt street and its sidewalks are west of it, cols 4-9)
export const STREET_LEN = STREET_TILES;
export const EXT_X0 = STREET_X + STREET_LEN; // 60: first column of the extension (paver)
export const EXT_PAVER_X1 = EXT_X0 + EXT_PAVER_TILES - 1; // 334
export const EXT_LASTRE_X0 = EXT_PAVER_X1 + 1; // 335
export const EXT_LASTRE_X1 = EXT_LASTRE_X0 + EXT_LASTRE_TILES - 1; // 434: last street column (open end, edge marker)
export const MARGIN_E = 10; // grass margin to the right of the lastre end
export const MAP_W = EXT_LASTRE_X1 + 1 + MARGIN_E; // 445 tiles = 890 m
// ---- THE QUEBRADA (river): runs the whole width of the map, north of everything (docs/rio.md). Its distances (north of the object, measured to the centre line) are the user's:
// "at the height of the church it is about 150-200 m away; at the height of the cafetal about 20 m; at the height of mama's house about 50 m".
export const RIVER_CHURCH_M = 175; // user said 150-200 m: the middle of the range
export const RIVER_CAFETAL_M = 20;
export const RIVER_MAMA_M = 50;
const OLD_CHURCH_Y = 6, OLD_CAF_Y0 = 5, OLD_MAMA_Y = 27; // top rows of the church, the cafetal's north fence and mama's house in the ORIGINAL (pre-TOP_PAD) row frame
const CUT = OLD_PAVER_TILES - EXT_PAVER_M / METRES_PER_TILE; // tiles removed from the paver stretch
const MAMA_CENTRE_COL = X(423 - CUT) + BUILDING_BY_NAME.get("casa_mama").w / 2;
export const RIVER_BRIDGE_CENTRE = LEFT_PAD + 7; // the asphalt street's cols LEFT_PAD+5..+8: boundary between its 2nd and 3rd column
export const RIVER = makeRiver({ mapW: MAP_W, bridgeCentre: RIVER_BRIDGE_CENTRE, anchors: [
  { id: "iglesia", col: STREET_X + STREET_LEN / 2, top: OLD_CHURCH_Y, tiles: Math.round(RIVER_CHURCH_M / METRES_PER_TILE) },
  { id: "cafetal", col: EXT_PAVER_X1 - 25, top: OLD_CAF_Y0, tiles: Math.round(RIVER_CAFETAL_M / METRES_PER_TILE) },
  { id: "casa_mama", col: MAMA_CENTRE_COL, top: OLD_MAMA_Y, tiles: Math.round(RIVER_MAMA_M / METRES_PER_TILE) },
] });
// TOP_PAD: rows of new land added on top of the original map (6 grass rows north of the river's northernmost bank). EVERY absolute row below derives from it.
export const TOP_PAD = RIVER.topPad;
export const MAP_H = 94 + TOP_PAD; // tiles: TOP_PAD new rows + the original 94 (church + street to the north, the park (37 rows) + its south street (rows 65-68), the Ebais plot (rows 70-90) + 3 rows of margin)
export const TOWN_FIRSTGID = 1;
export const B_FIRSTGID = COLS * ROWS + 1; // 145
export const PARK_FIRSTGID = B_FIRSTGID + B_COLS * B_ROWS; // 529 (town tilecount + buildings tilecount + 1)
export const SCHOOL_FIRSTGID = PARK_FIRSTGID + P_COLS * P_ROWS; // 721 (town + buildings + park tilecounts + 1)
export const EBAIS_FIRSTGID = SCHOOL_FIRSTGID + S_COLS * S_ROWS; // 945 (+ school tilecount 224)
export const MONTE_FIRSTGID = EBAIS_FIRSTGID + E_COLS * E_ROWS; // 1201 (+ ebais tilecount 256)
export const RIO_FIRSTGID = MONTE_FIRSTGID + M_COLS * M_ROWS; // 1457 (+ monte capacity 256)

// ---- base layout constants (tiles) ----
export const STREET_W = 4; // 4 tiles = ~8 m real at this scale (known distortion; kept for walkability)
export const STREET_Y = 21 + TOP_PAD; // (21 in the original frame) first street row (rows 21-24)
export const CHURCH_Y = OLD_CHURCH_Y + TOP_PAD; // church rows 6-17; hedges/doorstep row 18, path rows 18-20, street from row 21
// church origin column so that its door centre (door = cells 4-5, centre at 5 tiles from its left edge)
// is the middle of the street
export const CHURCH_X = STREET_X + STREET_LEN / 2 - 5; // 30 (map centre 35 = door centre)
// sidewalks (aceras): 1 tile each side of the street, rows 20 and 25
export const SIDEWALK_N_Y = STREET_Y - 1;
export const SIDEWALK_S_Y = STREET_Y + STREET_W;
// the park (a block = the street length, 50 tiles) starts one grass verge row south of the south sidewalk
export const PARK_X = STREET_X; // 10
export const PARK_Y = SIDEWALK_S_Y + 2; // 27
export const PARK_W = STREET_LEN; // 50
export const PARK_H = 37;
// ---- the street network around the park (absolute tiles) ----
export const PARK_X1 = PARK_X + PARK_W - 1; // 59
export const PARK_Y1 = PARK_Y + PARK_H - 1; // 63
// east street (left of the park): ASPHALT, cols 5-8, sidewalks col 9 (park side) and col 4 (far side), the full map height
export const EAST_X = LEFT_PAD + 5, EAST_W = 4, EAST_X1 = EAST_X + EAST_W - 1; // 5..8
export const EAST_SW_FAR = EAST_X - 1, EAST_SW_PARK = EAST_X1 + 1; // 4, 9
export const EAST_LINE_X = EAST_X + 1; // double yellow centre line (the line tile is centred in its tile, so it sits in col 6 of the 4)
// west street (right of the park): paver, cols 61-64, sidewalk only on the park side (col 60), from the main street south to the south street
export const WEST_SW_X = PARK_X1 + 1; // 60
export const WEST_X = WEST_SW_X + 1, WEST_W = 4, WEST_X1 = WEST_X + WEST_W - 1; // 61..64
export const SOUTH_SW_Y = PARK_Y1 + 1; // 64: sidewalk on the park side only
export const SOUTH_Y = SOUTH_SW_Y + 1, SOUTH_W = 4, SOUTH_Y1 = SOUTH_Y + SOUTH_W - 1; // rows 65..68
const pk = (lx, ly) => [PARK_X + lx, PARK_Y + ly]; // park-local tile -> absolute tile

const doorCx = (name) => BUILDING_BY_NAME.get(name).door.cx * SIZE + SIZE; // door centre, px from the building's left edge
const doorXpx = (name, at) => at[0] * SIZE + doorCx(name);
const doorBottomPx = (name, at) => (at[1] + BUILDING_BY_NAME.get(name).h) * SIZE;

// ---- park helpers: generate element entries (all coordinates absolute tiles; pk() converts park-local ones) ----
const rep2 = (n, v) => Array.from({ length: n }, () => v);
const stampOf = (id, layer, cells) => ({ id, kind: "stamp", layer, cells });
/** pyramid: ring of banks sloping down outward + a flat deck; pit: ring of banks with the high side outward + a bowl floor. */
function skateBlock(id, x, y, w, h, mode) {
  const cells = [];
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    const n = j === 0, s = j === h - 1, wv = i === 0, e = i === w - 1;
    let name;
    if (!(n || s || wv || e)) name = mode === "pyramid" ? "park_skate_deck" : "park_skate_bowl";
    else if (mode === "pyramid") name = (n && e) ? "park_bank_out_ne" : (s && e) ? "park_bank_out_se" : (s && wv) ? "park_bank_out_sw" : (n && wv) ? "park_bank_out_nw" : n ? "park_bank_s" : s ? "park_bank_n" : wv ? "park_bank_e" : "park_bank_w";
    else name = (n && e) ? "park_bank_in_ne" : (s && e) ? "park_bank_in_se" : (s && wv) ? "park_bank_in_sw" : (n && wv) ? "park_bank_in_nw" : n ? "park_bank_n" : s ? "park_bank_s" : wv ? "park_bank_w" : "park_bank_e";
    cells.push({ name, at: [x + i, y + j] });
  }
  return stampOf(id, "ground", cells);
}
// skate park: park-local cols 1-12, rows 12-27
const [SK_X, SK_Y] = pk(1, 12);
// playground: park-local cols 14-25, rows 16-23
const [PG_X, PG_Y] = pk(14, 16);
// court + walkway: park-local cols 27-49, rows 25-36; inner floor cols 28-48, rows 26-35
const [CT_X, CT_Y] = pk(27, 25);
// ---- the Chequelo places (user's layout: all measured along the main street, 2 m = 1 tile) ----
// CAFETAL (north of the street): 50 m wide = 25 tiles, centred 50 m (25 tiles) before the end of the paver street (col 334) = col 309.
export const CAF_X0 = EXT_PAVER_X1 - 25 - 12, CAF_X1 = CAF_X0 + 24; // cols 297..321 (centre col 309)
export const CAF_Y0 = OLD_CAF_Y0 + TOP_PAD, CAF_Y1 = 18 + TOP_PAD; // fence rows 5 (north) and 18 (south, with the gap); soil rows 6-17 (12 deep = 24 m); verge row 19, sidewalk row 20
export const CAF_GAP = [CAF_X0 + 11, CAF_X0 + 12]; // 2-tile gap in the south fence = the aisle (lastre) that meets the street's north sidewalk
// CASA DE MAMA at the end of the lastre, SOUTH of the street; CASA DE CHAYO (casa_2) 50 m = 25 tiles before it (centre to centre), also south.
// The building art faces SOUTH (door in the bottom wall): the door faces away from the street, so each house has a 2-tile lastre footpath
// from the street's south edge down its WEST side (one grass tile of gap beside the wall) to a lastre yard in front of the door.
export const MAMA_AT = [X(423 - CUT), OLD_MAMA_Y + TOP_PAD], CHAYO_AT = [X(399 - CUT), 27 + TOP_PAD];
export const MAMA_FOOT_X = MAMA_AT[0] + 8 + 1, CHAYO_FOOT_X = CHAYO_AT[0] + 6 + 1; // footpath first col (2 wide): wall + 1 gap tile
export const MAMA_DOOR_DX = 88, CHAYO_DOOR_DX = 48; // door centre, px from the building's left edge (as drawn)
// street lamps: on the grass outside each sidewalk (heads 2 rows above the base), clear of the church and the park path
// main street lamps: every 50 m = 25 tiles along the WHOLE street (original, paver extension and lastre), both sides: cols 10 + 25k
// ---- the main street's shops and houses (user's list; "N m" between two places = centre to centre, 2 m = 1 tile; WEST = to the right of the screen = increasing col) ----
// North-side houses stand with their doors facing the street (the art faces south); south-side ones face away, so each south group gets a 2-wide lastre footpath
// on its west end down to a lastre yard in front of the doors (like Chayo's house). Buildings are the casa_1/2/3 fillers and the new abastecedor / bar / guarderia.
const PL_YARD = 3; // lastre yard rows in front of the doors
const PL_SOUTH_Y = SIDEWALK_S_Y + 2, PL_NORTH_Y = SIDEWALK_N_Y - 1 - 5; // top row of a south house (verge row 119 stays free), of a north house (verge row 112 stays free)
const placeW = (n) => BUILDING_BY_NAME.get(n).w;
export const PLACE_DOORS = []; // [x px, y px] of each door-front rect centre (walkability checks)
export const PLACE_RANGES = { n: [], s: [] }; // inclusive column ranges that must stay free of street lamps
export const PLACE_FOOTS = { n: [], s: [] }; // inclusive column ranges [x0, x1] of the footpaths / lanes / streets that cross the north / south sidewalk row
const doorRect = (n, x, oyRow) => ({ x: x * SIZE + doorCx(n) - 16, y: (oyRow + BUILDING_BY_NAME.get(n).h) * SIZE, w: 32, h: 16 });
/** A row of touching buildings on the SOUTH side. items: [{ id, n (building), title?, line }]; dy rows below the verge; foot: 2-wide footpath from the sidewalk at the west end. */
const southBlock = (id, x0, items, { dy = 0, foot = true, yardFrom = x0, yardTo = null, title = null } = {}) => {
  const els = [], oy = PL_SOUTH_Y + dy;
  let x = x0;
  for (const it of items) {
    els.push({ id: `${id}_${it.id}`, kind: "building", name: it.n, at: [x, oy] });
    const r = doorRect(it.n, x, oy);
    PLACE_DOORS.push([r.x + 16, r.y + 8]);
    els.push({ id: `${id}_${it.id}_puerta`, kind: "interactable", name: `${id}_${it.id}_puerta`, ...r, props: { interact: "object", label: "Mirar la puerta", line: it.line } });
    x += placeW(it.n);
  }
  const end = x - 1, yardY = oy + 5, footX = end + 2;
  const yEnd = yardTo ?? (foot ? footX + 1 : end);
  els.push({ id: `${id}_patio`, kind: "path", surface: "lastre", x: yardFrom, y: yardY, w: yEnd - yardFrom + 1, h: PL_YARD });
  PLACE_RANGES.s.push([x0, end]);
  if (foot) { els.push({ id: `${id}_camino`, kind: "path", surface: "lastre", x: footX, y: SIDEWALK_S_Y, w: 2, h: yardY + PL_YARD - SIDEWALK_S_Y }); PLACE_RANGES.s.push([footX, footX + 1]); PLACE_FOOTS.s.push([footX, footX + 1]); }
  if (title) els.push({ id: `zona_${id}`, kind: "zone", zone: id, x: (x0 - 1) * SIZE, y: (oy - 1) * SIZE, w: (yEnd - x0 + 3) * SIZE, h: (PL_YARD + 7) * SIZE, title, ambience: "pueblo" });
  return els;
};
/** One building on the NORTH side, door facing the street: a 2-tile lastre path from the door to the sidewalk. */
const northHouse = (id, x, n, line, title = null) => {
  const oy = PL_NORTH_Y, r = doorRect(n, x, oy), c = Math.floor(r.x / SIZE);
  PLACE_DOORS.push([r.x + 16, r.y + 8]);
  PLACE_RANGES.n.push([x, x + placeW(n) - 1]);
  PLACE_FOOTS.n.push([c, c + 1]);
  return [
    { id, kind: "building", name: n, at: [x, oy] },
    { id: `${id}_camino`, kind: "path", surface: "lastre", x: c, y: oy + 5, w: 2, h: SIDEWALK_N_Y - (oy + 5) + 1 },
    { id: `${id}_puerta`, kind: "interactable", name: `${id}_puerta`, ...r, props: { interact: "object", label: "Mirar la puerta", line } },
    ...(title ? [{ id: `zona_${id}`, kind: "zone", zone: id, x: (x - 1) * SIZE, y: (oy - 1) * SIZE, w: (placeW(n) + 2) * SIZE, h: 8 * SIZE, title, ambience: "pueblo" }] : []),
  ];
};
const cen = (x, n) => x + placeW(n) / 2; // building centre column (boundary)
export const BERTA_X = WEST_X1 + 2; // 321: north-west corner of the park, just west of the west street
export const AB_X = BERTA_X + 3 + 15 - 4; // abastecedor centre 30 m (15 tiles) west of Berta's house centre
export const BAR_X = AB_X + 8 + 6;
export const CALILES_X = EXT_PAVER_X1 + 1 + 10; // the barrio's street: 4-wide lastre going south, 20 m (10 tiles) after the main street turns to lastre (the cafetal and the colegio lie between Los Machillos and here)
export const CAL_THIRD_X = CALILES_X + 4 + 10 + 12 + 3 + 10, ENR_LANE_X = CAL_THIRD_X + 10; // third house west of the mouth; Tío Enrique's lane 4 tiles past its footpath
// CASA DE ABUELA PAULA Y ABUELO PEPE: wooden house on the NORTH side, straight across the street from mama's house, set back by a ~15 m (8-tile, verge row included) fenced lane
const PAULA_X = MAMA_AT[0], PAULA_Y = SIDEWALK_N_Y - 1 - 7 - 6; // building 8x6, door faces the street
const PAULA_PX0 = PAULA_X - 3, PAULA_PX1 = PAULA_X + 10, PAULA_PY0 = PAULA_Y, PAULA_PY1 = SIDEWALK_N_Y - 1; // yard fence rectangle (14 wide)
const PAULA_LANE = [PAULA_X + 3, PAULA_X + 4];
const paulaFence = () => {
  const cells = [], add = (name, x, y) => cells.push({ name, at: [x, y] });
  add("wire_corner_es", PAULA_PX0, PAULA_PY0); add("wire_corner_ws", PAULA_PX1, PAULA_PY0); add("wire_corner_en", PAULA_PX0, PAULA_PY1); add("wire_corner_wn", PAULA_PX1, PAULA_PY1);
  for (let x = PAULA_PX0 + 1; x < PAULA_PX1; x++) { if (x < PAULA_X || x >= PAULA_X + 8) add("wire_h", x, PAULA_PY0); add(x === PAULA_LANE[0] || x === PAULA_LANE[1] ? "fence_gap" : "wire_h", x, PAULA_PY1); }
  for (let y = PAULA_PY0 + 1; y < PAULA_PY1; y++) { add("wire_v", PAULA_PX0, y); add("wire_v", PAULA_PX1, y); }
  return cells;
};
PLACE_RANGES.n.push([PAULA_PX0, PAULA_PX1]);
PLACE_FOOTS.n.push([PAULA_LANE[0], PAULA_LANE[1]]);
const PAULA_DOOR = doorRect("casa_paula", PAULA_X, PAULA_Y);
PLACE_DOORS.push([PAULA_DOOR.x + 16, PAULA_DOOR.y + 8]);
const LAME = "Está cerrado.";
const PLACE_ELEMENTS = [
  ...northHouse("berta", BERTA_X, "casa_1", "Casa de Berta. No hay nadie.", "Casa de Berta"),
  ...northHouse("abastecedor", AB_X, "abastecedor", `Abastecedor El Jardín. ${LAME}`, "Abastecedor El Jardín"),
  ...northHouse("maria_juvenal", AB_X + 8, "casa_2", "Casa de María y Juvenal. No hay nadie."),
  ...northHouse("bar", BAR_X, "bar", `Bar Mata de Caña. ${LAME}`, "Bar Mata de Caña"),
  ...southBlock("ingracia", AB_X + 4 - 3, [{ id: "casa", n: "casa_3", line: "Casa de Doña Ingracia. No hay nadie." }], { title: "Casa de Doña Ingracia" }),
  ...southBlock("guarderia", BAR_X, [{ id: "edificio", n: "guarderia", line: `Guardería Barquitos de Esperanza. ${LAME}` }], { title: "Guardería Barquitos de Esperanza" }),
  ...northHouse("isabel", BAR_X + 4 + 10 - 3, "casa_1", "Casa de Doña Isabel. No hay nadie.", "Casa de Doña Isabel"),
  ...northHouse("carmen", BAR_X + 4 + 10 + 20 - 3, "casa_2", "Casa de Carmen. No hay nadie.", "Casa de Carmen"),
  ...["casa_3", "casa_1", "casa_2"].flatMap((n, i) => northHouse(`machillo_${i + 1}`, BAR_X + 4 + 10 + 20 + 3 + 3 + i * 6, n, "Casa de Los Machillos. No hay nadie.", i === 0 ? "Los Machillos" : null)),
  ...southBlock("sur_machillos", BAR_X + 4 + 10 + 20 + 3 + 3 + 9 + 10 - 3, [{ id: "casa", n: "casa_3", line: "No hay nadie." }]),
  // LOS CALILES: lastre street south from the main street, houses on both sides (yards open onto the street); a house before the mouth, a pair 20 m after, one more 20 m later, then Tío Enrique's long lane
  { id: "caliles_calle", kind: "street", surface: "lastre", dir: "v", x: CALILES_X, y: SIDEWALK_S_Y, length: 40, width: 4, trail: true },
  ...southBlock("caliles_entrada", CALILES_X - 9, [{ id: "casa", n: "casa_1", line: "No hay nadie." }]),
  ...southBlock("caliles_o1", CALILES_X + 6, [{ id: "casa", n: "casa_3", line: "Los Caliles. No hay nadie." }], { dy: 4, foot: false, yardFrom: CALILES_X + 4, title: "Los Caliles" }),
  ...southBlock("caliles_o2", CALILES_X + 6, [{ id: "casa", n: "casa_1", line: "Los Caliles. No hay nadie." }], { dy: 14, foot: false, yardFrom: CALILES_X + 4 }),
  ...southBlock("caliles_o3", CALILES_X + 6, [{ id: "casa", n: "casa_2", line: "Los Caliles. No hay nadie." }], { dy: 24, foot: false, yardFrom: CALILES_X + 4 }),
  ...southBlock("caliles_e1", CALILES_X - 8, [{ id: "casa", n: "casa_2", line: "Los Caliles. No hay nadie." }], { dy: 12, foot: false, yardTo: CALILES_X - 1 }),
  ...southBlock("caliles_e2", CALILES_X - 8, [{ id: "casa", n: "casa_3", line: "Los Caliles. No hay nadie." }], { dy: 22, foot: false, yardTo: CALILES_X - 1 }),
  ...southBlock("caliles_par", CALILES_X + 4 + 10, [{ id: "casa_a", n: "casa_2", line: "No hay nadie." }, { id: "casa_b", n: "casa_3", line: "No hay nadie." }]),
  ...southBlock("caliles_tercera", CAL_THIRD_X, [{ id: "casa", n: "casa_1", line: "No hay nadie." }]),
  { id: "enrique_camino", kind: "path", surface: "lastre", x: ENR_LANE_X, y: SIDEWALK_S_Y, w: 2, h: PL_SOUTH_Y + 10 + 5 + PL_YARD - SIDEWALK_S_Y },
  // ---- CASA DE ABUELA PAULA Y ABUELO PEPE (wooden, special) ----
  stampOf("paula_cerca", "objects", paulaFence()),
  { id: "paula_camino", kind: "path", surface: "lastre", x: PAULA_LANE[0], y: PAULA_Y + 6, w: 2, h: SIDEWALK_N_Y - (PAULA_Y + 6) + 1 },
  { id: "casa_paula", kind: "building", name: "casa_paula", at: [PAULA_X, PAULA_Y] },
  { id: "paula_porche", kind: "surface", name: "paula_porche", x: PAULA_X * SIZE, y: (PAULA_Y + 5) * SIZE, w: 8 * SIZE, h: SIZE, surface: "madera" },
  { id: "paula_arbol_1", kind: "tree", tree: "platano", at: [PAULA_PX0 + 2, PAULA_Y + 3] },
  { id: "paula_arbol_2", kind: "tree", tree: "guanacaste", at: [PAULA_PX1 - 2, PAULA_Y + 4] },
  { id: "paula_arbol_3", kind: "tree", tree: "platano", at: [PAULA_PX1 - 3, PAULA_PY1 - 2] },
  { id: "paula_buganvilia_1", kind: "prop", name: "bougainvillea", at: [PAULA_X + 1, PAULA_PY1 - 1] },
  { id: "paula_buganvilia_2", kind: "prop", name: "bougainvillea", at: [PAULA_X + 6, PAULA_PY1 - 1] },
  { id: "paula_puerta", kind: "interactable", name: "paula_puerta", ...PAULA_DOOR, props: { interact: "object", label: "Mirar la puerta", line: "La casa de Abuela Paula y Abuelo Pepe. Huele a leña, a café recién colado y a hierba buena." } },
  { id: "zona_paula", kind: "zone", zone: "casa_paula", x: (PAULA_PX0 - 1) * SIZE, y: (PAULA_PY0 - 1) * SIZE, w: (PAULA_PX1 - PAULA_PX0 + 3) * SIZE, h: (PAULA_PY1 - PAULA_PY0 + 3) * SIZE, title: "Casa de Abuela Paula y Abuelo Pepe", ambience: "pueblo" },
  ...southBlock("enrique", ENR_LANE_X - 8, [{ id: "casa", n: "casa_2", line: "Casa de Tío Enrique. No hay nadie." }], { dy: 10, foot: false, yardTo: ENR_LANE_X + 1, title: "Casa de Tío Enrique" }),
];
PLACE_RANGES.s.push([ENR_LANE_X, ENR_LANE_X + 1], [CALILES_X, CALILES_X + 3]);
PLACE_FOOTS.s.push([ENR_LANE_X, ENR_LANE_X + 1], [CALILES_X, CALILES_X + 3]);

export const LAMP_EVERY_M = 50;
export const LAMP_EVERY = LAMP_EVERY_M / METRES_PER_TILE; // 25 tiles
export const LAMP_COLS = Array.from({ length: Math.floor((EXT_LASTRE_X1 - STREET_X) / LAMP_EVERY) + 1 }, (_, k) => STREET_X + LAMP_EVERY * k);
// posts that would collide are skipped (explicit, so nothing is hidden): the church path (cols 34-35, rows 18-20) takes the north post of col 35;
// the west street's park-side sidewalk (col 60, rows 25-64) takes the south post of col 60; the cafetal's fence and aisle take the north post of col 310.
export const LAMP_SKIP_N = [CHURCH_X + 5, ...LAMP_COLS.filter((x) => PLACE_RANGES.n.some(([a, b]) => x >= a && x <= b)), ...Array.from({ length: Math.floor((EXT_LASTRE_X1 - STREET_X) / 25) + 1 }, (_, k) => STREET_X + 25 * k).filter((x) => x >= CAF_X0 && x <= CAF_X1)];
export const LAMP_SKIP_S = [WEST_SW_X, ...LAMP_COLS.filter((x) => PLACE_RANGES.s.some(([a, b]) => x >= a && x <= b))];
const STREET_LAMPS_N = LAMP_COLS.filter((x) => !LAMP_SKIP_N.includes(x)).map((x) => ({ id: `farola_n_${x}`, kind: "lamp", at: [x, SIDEWALK_N_Y - 1] }));
const STREET_LAMPS_S = LAMP_COLS.filter((x) => !LAMP_SKIP_S.includes(x)).map((x) => ({ id: `farola_s_${x}`, kind: "lamp", at: [x, SIDEWALK_S_Y + 1] }));
// diagonal path: centreline y per column (3 tiles thick), flat at the top (park-local cols 28-33), then 3 down per 4 left
const pathCentre = (c) => PARK_Y + Math.round(Math.max(0, 28 - (c - PARK_X)) * 0.75);
const PATH_C0 = PARK_X + 33, PATH_C1 = PARK_X + 13;
const PATH_LAMPS = [31, 25, 19, 14].flatMap((lc) => {
  const c = PARK_X + lc, yc = pathCentre(c);
  return [{ id: `farola_camino_a_${lc}`, kind: "lamp", soft: true, at: [c, yc - 2] }, { id: `farola_camino_b_${lc}`, kind: "lamp", soft: true, at: [c, yc + 2] }];
});

// ---- cafetal, houses and their footpaths: element generators ----
const CAF_AISLE = [CAF_GAP[0], CAF_GAP[1]];
const inAisle = (x) => x >= CAF_AISLE[0] && x <= CAF_AISLE[1];
const cafetalFence = () => {
  const cells = [];
  const add = (name, x, y) => cells.push({ name, at: [x, y] });
  add("wire_corner_es", CAF_X0, CAF_Y0); add("wire_corner_ws", CAF_X1, CAF_Y0);
  add("wire_corner_en", CAF_X0, CAF_Y1); add("wire_corner_wn", CAF_X1, CAF_Y1);
  for (let x = CAF_X0 + 1; x < CAF_X1; x++) { add("wire_h", x, CAF_Y0); add(inAisle(x) ? "fence_gap" : "wire_h", x, CAF_Y1); }
  for (let y = CAF_Y0 + 1; y < CAF_Y1; y++) { add("wire_v", CAF_X0, y); add("wire_v", CAF_X1, y); }
  return cells;
};
const cafetalSoil = () => {
  const cells = [];
  for (let y = CAF_Y0 + 1; y < CAF_Y1; y++) for (let x = CAF_X0 + 1; x < CAF_X1; x++) {
    if (inAisle(x)) cells.push({ name: "lastre_ruts_v", at: [x, y] });
    else cells.push({ name: ["soil_terrace", "soil", "soil_furrow"][(y - CAF_Y0 - 1) % 3], at: [x, y] });
  }
  return cells;
};
const CAF_ROWS = [7, 10, 13, 16].map((y) => y + TOP_PAD); // cafeto rows (2 free rows between them)
const cafetos = () => CAF_ROWS.flatMap((y) => Array.from({ length: CAF_X1 - CAF_X0 - 1 }, (_, i) => CAF_X0 + 1 + i).filter((x) => !inAisle(x))
  .map((x) => ({ name: noise("cf", x, y) < 0.5 ? "cafeto_a" : "cafeto_b", at: [x, y] })));
const MAMA_PX = [MAMA_AT[0] * SIZE, MAMA_AT[1] * SIZE]; // top-left of casa_mama, px
const CHAYO_PX = [CHAYO_AT[0] * SIZE, CHAYO_AT[1] * SIZE];
export const MAMA_X = MAMA_PX[0] + MAMA_DOOR_DX; // door centre (px)
export const MAMA_DOOR_Y = (MAMA_AT[1] + BUILDING_BY_NAME.get("casa_mama").h) * SIZE; // door row bottom = house bottom edge (px)
export const CHAYO_X = CHAYO_PX[0] + CHAYO_DOOR_DX;
export const CHAYO_DOOR_Y = (CHAYO_AT[1] + BUILDING_BY_NAME.get("casa_2").h) * SIZE;
const MAMA_YARD_Y = MAMA_AT[1] + BUILDING_BY_NAME.get("casa_mama").h; // first yard row (33)
const CHAYO_YARD_Y = CHAYO_AT[1] + BUILDING_BY_NAME.get("casa_2").h; // 32
export const YARD_ROWS = 3;

// ---- the Escuela and Casa de Olguita: EAST of the asphalt street (LEFT of the screen), accompanying it ----
// Both plots share the same columns: PLOT_W = 14 wide (fence line included, 12 inside), the street side (right of the screen) is col PLOT_X1 = 18;
// col 19 is a grass verge and col 20 the far sidewalk. Olguita's plot starts level with the top of the park block (row 27) and is 8 tall; one grass row
// (35) separates it from the school plot, which runs 28 rows (3/4 of the park's 37) to the park's last row (63).
export const PLOT_W = 14;
export const PLOT_X1 = EAST_SW_FAR - 2, PLOT_X0 = PLOT_X1 - PLOT_W + 1; // 18, 5
export const OLG_Y0 = PARK_Y, OLG_H = 8, OLG_Y1 = OLG_Y0 + OLG_H - 1; // rows 27-34
export const ESC_Y0 = OLG_Y1 + 2, ESC_Y1 = PARK_Y1, ESC_H = ESC_Y1 - ESC_Y0 + 1; // rows 36-63 (28)
export const OLG_AT = [PLOT_X0 + 3, OLG_Y0 + 1]; // casa_3 (6x5): cols 8-13, rows 28-32, door front row 33
export const OLG_GATE = [OLG_Y1 - 2, OLG_Y1 - 1]; // rows 32-33 on col 18 (2-tile opening)
export const ESC_A_AT = [PLOT_X0 + 1, ESC_Y0 + 2], ESC_B_AT = [PLOT_X0 + 1, ESC_Y0 + 15]; // aulas A rows 38-43, aulas B rows 51-56 (10x6, cols 6-15)
export const ESC_GATE = [ESC_Y0 + 10, ESC_Y0 + 11]; // rows 46-47 on col 18 (2-tile opening)
export const ESC_FLAG_AT = [PLOT_X0 + 6, ESC_Y0 + 11]; // flagpole base (1x3, the two upper cells are the flag): col 11, row 47
export const ESC_SIGN_AT = [PLOT_X1 - 2, ESC_Y0 + 8]; // sign board 2x2 (top-left): cols 16-17, rows 44-45, beside the gate
// gate = rows of the opening on the x1 side; gateTop = cols of the opening on the y0 (north) side (the Ebais); gatePost = tile at both sides of an opening
const plotFence = (x0, y0, x1, y1, { corner, h, v, gate, gatePost, gateTop }) => {
  const cells = [];
  const add = (name, x, y) => cells.push({ name, at: [x, y] });
  add(corner, x0, y0); add(corner, x1, y0); add(corner, x0, y1); add(corner, x1, y1);
  for (let x = x0 + 1; x < x1; x++) {
    if (!gateTop || x < gateTop[0] || x > gateTop[1]) add(gateTop && gatePost && (x === gateTop[0] - 1 || x === gateTop[1] + 1) ? gatePost : h, x, y0);
    add(h, x, y1);
  }
  for (let y = y0 + 1; y < y1; y++) {
    add(v, x0, y);
    if (!gate || y < gate[0] || y > gate[1]) add(gate && gatePost && (y === gate[0] - 1 || y === gate[1] + 1) ? gatePost : v, x1, y);
  }
  return cells;
};
const doorRects = (b, at) => b.doors.map((dx) => ({ x: at[0] * SIZE + dx - 16, y: (at[1] + b.h - 1) * SIZE, w: 32, h: 16 })); // the corridor row in front of each door
const escDoors = [["escuela_aulas_a", ESC_A_AT], ["escuela_aulas_b", ESC_B_AT]].flatMap(([n, at]) =>
  doorRects(SCHOOL_BUILDING_BY_NAME.get(n), at).map((r, i) => ({ id: `${n}_puerta_${i + 1}`, ...r })));
export const OLG_DOOR_X = OLG_AT[0] * SIZE + 48, OLG_DOOR_Y = (OLG_AT[1] + BUILDING_BY_NAME.get("casa_3").h) * SIZE; // door centre x, house bottom edge (px)
const fillOf = (id, x0, y0, x1, y1) => ({ id, kind: "fill", x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1, tiles: ["escuela_patio_a", "escuela_patio_a", "escuela_patio_b", "escuela_patio_b", "escuela_patio_grieta"], salt: "ep" });

// ---- EL COLEGIO (Liceo): SOUTH of the main street, directly across from the cafetal (same 25 columns), gate on the north side facing the street ----
// plot cols CAF_X0..CAF_X1, one grass verge row (119) below the south sidewalk, 22 rows tall; the gate (2 tiles, rows of the fence line) sits on the cafetal's aisle columns,
// so the cafetal's lastre aisle and the colegio's gate path line up across the street. The aulas (10x6, doors on the south side) stand in the north-east part of the plot
// and face a concrete patio; the gate path runs south along their west end into the patio. Sign and flagpole beside the path.
export const COL_X0 = CAF_X0, COL_X1 = CAF_X1, COL_W = COL_X1 - COL_X0 + 1; // cols 297-321
export const COL_Y0 = SIDEWALK_S_Y + 2, COL_H = 22, COL_Y1 = COL_Y0 + COL_H - 1;
export const COL_GATE = [CAF_GAP[0], CAF_GAP[1]]; // cols on the north fence row (COL_Y0)
export const COL_AT = [COL_X1 - 11, COL_Y0 + 2]; // aulas origin: cols COL_X1-11..COL_X1-2, rows COL_Y0+2..COL_Y0+7 (corridor row COL_Y0+7)
export const COL_SIGN_AT = [COL_GATE[0] - 4, COL_Y0 + 1]; // sign 2x2 on the west side of the gate path, inside the plot
export const COL_FLAG_AT = [COL_X0 + 6, COL_Y0 + 11]; // flagpole base

// ---- the Ebais (health clinic): SOUTH of the south street, at the south-west corner of the park (cols 55-75, rows 70-90) ----
// The west street (cols 77-80) continues south of the south street as a LASTRE street (no sidewalks) to the map's bottom edge. The plot is 21x21 tiles,
// one grass verge row (69) below the south street, and its right edge (col 75) stops one grass column (76) before the lastre street.
export const EB_W = 21, EB_H = 21;
export const EB_X1 = WEST_X - 2, EB_X0 = EB_X1 - EB_W + 1; // 75, 55
export const EB_Y0 = SOUTH_Y1 + 2, EB_Y1 = EB_Y0 + EB_H - 1; // 70, 90
export const LASTRE_S_Y0 = SOUTH_Y1 + 1; // 69: first row of the lastre street south of the south street
export const EB_GATE = [EB_X0 + 2, EB_X0 + 3]; // cols 57-58 on row 70 (north side, near the east = left end)
export const EB_AT = [EB_X0 + 5, EB_Y0 + 2]; // ebais_edificio (12x7): cols 60-71, rows 72-78 (wall rows 75-76, porch rows 77-78)
export const EB_DOOR_X = EB_AT[0] * SIZE + 96, EB_DOOR_Y = (EB_AT[1] + 5) * SIZE; // door centre x, top of the porch row in front of the door (px)
export const EB_PATH_Y1 = EB_AT[1] + 6; // last row of the 2-wide path (78)
export const EB_YARD_Y0 = EB_AT[1] + 7; // 79: first patio row
export const EB_PARK_Y0 = EB_YARD_Y0 + 2, EB_PARK_Y1 = EB_PARK_Y0 + 3; // parking rows 81-84
const ebaisFloor = (id, x0, y0, x1, y1) => ({ id, kind: "fill", x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1, tiles: ["ebais_piso_a", "ebais_piso_a", "ebais_piso_b", "ebais_piso_b", "ebais_piso_grieta"], salt: "ebp" });
const ebStamp = (id, layer, list) => stampOf(id, layer, list.map(([name, x, y]) => ({ name, at: [x, y] })));

// ---- EL MONTE DE HULE Y NISPERO, the road that leads to it and the AEROGENERADORES (wind turbines): EAST of the church = LEFT of the screen ----
// The main street's line (rows 21-24) continues EAST (left) beyond the asphalt street as a 4-wide ASPHALT road with a double yellow centre line, through the monte, off the map's left edge.
export const MONTE_CX_PX = (CHURCH_X + 5) * TILE - MONTE_DIST_T * TILE; // zone centre x (px): church door centre minus 250 tiles (500 m) = 640
export const MONTE_X0 = MONTE_CX_PX / TILE - MONTE_W / 2, MONTE_X1 = MONTE_X0 + MONTE_W - 1; // cols 10-69, the full map height (rows 0-93)
export const MONTE_RAMP = 10; // the forest density ramps up over this many tiles from the zone's left / right border
export const ROAD_X0 = 0, ROAD_X1 = EAST_SW_FAR; // the road: cols 0..EAST_SW_FAR; the last column (the old far sidewalk position) is the junction, plain asphalt
export const ROAD_Y0 = STREET_Y, ROAD_Y1 = STREET_Y + STREET_W - 1; // rows 21-24
export const ROAD_VERGE = 3; // forest-free verge each side of the road (tiles)
export const ROAD_SPAWN = [28, (STREET_Y + 2) * TILE]; // edge_calle_principal_este spawn (px), inside the map
export const CLEAR_RX = 7, CLEAR_RY = 11; // turbine clearing: an ellipse centred 3 rows above the tower base (covers the rotor and the pad)
export const TRAIL_X0 = MONTE_X0 + 23, TRAIL_W = 2, TRAIL_Y0 = ROAD_Y1 + 1, TRAIL_LEN = 40; // camino de las carretas: lastre, cols 33-34, rows 25-64
// turbines [base col, base row] (the base = the solid cell at the foot of the tower; the rotor hub is 9 rows above it, the rotor top 13 rows above): 3 north (up on the screen) set back 6-7 tiles from the road, 3 south set back 11-12 (so the rotor does not hang over the road)
export const TURBINE_AT = [[MONTE_X0 + 9, 15], [MONTE_X0 + 30, 14], [MONTE_X0 + 51, 15], [MONTE_X0 + 14, 35], [MONTE_X0 + 32, 36], [MONTE_X0 + 50, 35]].map(([x, y]) => [x, y + TOP_PAD]);
export const TURBINE_BBOX = (() => { // tiles [x0, y0, x1, y1] around all the clearings, clipped to the map
  const xs = TURBINE_AT.map((t) => t[0]), ys = TURBINE_AT.map((t) => t[1]);
  return [Math.min(...xs) - CLEAR_RX, Math.max(0, Math.min(...ys) - 3 - CLEAR_RY), Math.max(...xs) + CLEAR_RX, Math.max(...ys) - 3 + CLEAR_RY];
})();

// ---- the quebrada in absolute tiles: the BRIDGE of the asphalt street and the zone strips (RIVER itself is in the original row frame: row y of the map = original row y - TOP_PAD) ----
export const isWaterCell = (x, y) => RIVER.isWater(x, y - TOP_PAD);
export const BRIDGE = (() => {
  // deck = the 4 asphalt columns + the 2 sidewalks (cols EAST_SW_FAR..EAST_SW_PARK) carried straight over the water; one more column each side holds the guard rail (concrete curb under it);
  // outside the rails stand the piers (abutments) in the water. The river is flat here (BRIDGE_FLAT), so every deck column crosses the same rows wr0..wr1.
  const railW = EAST_SW_FAR - 1, railE = EAST_SW_PARK + 1, pierW = railW - 1, pierE = railE + 1;
  let wr0 = Infinity, wr1 = -Infinity;
  for (let r = RIVER.rMin; r <= RIVER.rMax; r++) for (let x = pierW; x <= pierE; x++) if (RIVER.isWater(x, r)) { wr0 = Math.min(wr0, r + TOP_PAD); wr1 = Math.max(wr1, r + TOP_PAD); }
  return { railW, railE, pierW, pierE, deckW: EAST_SW_FAR, deckE: EAST_SW_PARK, wr0, wr1, rb0: wr0 - 3, rb1: wr1 + 3, beyond: 2 }; // the bridge rows rb0..rb1 reach 2 tiles past each bank row (wr0 - 1, wr1 + 1)
})();
export const RIVER_ZONE_LEN = 20; // tiles per zone strip
export const RIVER_ZONE_PAD = 8; // tiles each side of the water
export const RIVER_ZONES = (() => {
  const out = [];
  for (let x0 = 0, i = 1; x0 < MAP_W; x0 += RIVER_ZONE_LEN, i++) {
    const x1 = Math.min(MAP_W, x0 + RIVER_ZONE_LEN) - 1;
    let lo = Infinity, hi = -Infinity;
    for (let r = RIVER.rMin; r <= RIVER.rMax; r++) for (let x = x0; x <= x1; x++) if (RIVER.isWater(x, r)) { lo = Math.min(lo, r + TOP_PAD); hi = Math.max(hi, r + TOP_PAD); }
    const y0 = Math.max(0, lo - RIVER_ZONE_PAD), y1 = Math.min(MAP_H - 1, hi + RIVER_ZONE_PAD);
    out.push({ id: `zona_rio_${String(i).padStart(2, "0")}`, kind: "zone", zone: "rio", suffix: `_${String(i).padStart(2, "0")}`, x: x0 * SIZE, y: y0 * SIZE, w: (x1 - x0 + 1) * SIZE, h: (y1 - y0 + 1) * SIZE, title: "La quebrada", ambience: "quebrada" });
  }
  return out;
})();

// ---- THE ELEMENT LIST: add the next element here ----
export const ELEMENTS = [
  // 1. the main street: 100 m of pavers, east-west
  { id: "calle_principal", kind: "street", surface: "paver", x: STREET_X, y: STREET_Y, length: STREET_LEN, width: STREET_W },
  // sidewalks (aceras): 1 tile each side of the street; the church path (below) replaces the tiles it crosses
  { id: "acera_norte", kind: "path", surface: "sidewalk", x: STREET_X, y: SIDEWALK_N_Y, w: STREET_LEN, h: 1 },
  { id: "acera_sur", kind: "path", surface: "sidewalk", x: STREET_X, y: SIDEWALK_S_Y, w: STREET_LEN, h: 1 },
  // ---- the main street continues WEST (to the right of the screen): 550 m of cement (paver) then 200 m of lastre (earth), 4 wide ----
  { id: "calle_principal_oeste_cemento", kind: "street", surface: "paver", x: EXT_X0, y: STREET_Y, length: EXT_PAVER_TILES, width: STREET_W },
  { id: "calle_principal_oeste_lastre", kind: "street", surface: "lastre", x: EXT_LASTRE_X0, y: STREET_Y, length: EXT_LASTRE_TILES, width: STREET_W },
  // sidewalks of the paver extension (1 tile each side, ending at the last paver column; none along the lastre).
  // The south one stops at col 60 (it is the west street's park-side sidewalk) and resumes after the junction (cols 61-64).
  { id: "acera_norte_oeste", kind: "path", surface: "sidewalk", x: EXT_X0, y: SIDEWALK_N_Y, w: EXT_PAVER_TILES, h: 1 },
  { id: "acera_sur_oeste", kind: "path", surface: "sidewalk", x: WEST_X1 + 1, y: SIDEWALK_S_Y, w: EXT_PAVER_X1 - WEST_X1, h: 1 },
  // ---- the streets around the park ----
  // WEST street (right of the park): paver cols 61-64, from the main street (T junction at rows 25-..) south to the south street; sidewalk only on the park side (col 60)
  { id: "calle_parque_oeste", kind: "street", surface: "paver", dir: "v", x: WEST_X, y: SIDEWALK_S_Y, length: SOUTH_Y1 - SIDEWALK_S_Y + 1, width: WEST_W },
  { id: "acera_parque_oeste", kind: "path", surface: "sidewalk", x: WEST_SW_X, y: SIDEWALK_S_Y, w: 1, h: SOUTH_SW_Y - SIDEWALK_S_Y + 1 },
  // SOUTH street (below the park): paver rows 65-68, from the east asphalt street (col 9 is its mouth, no sidewalk) to the west street; sidewalk only on the park side (row 64)
  { id: "calle_parque_sur", kind: "street", surface: "paver", x: EAST_SW_PARK, y: SOUTH_Y, length: WEST_X - EAST_SW_PARK, width: SOUTH_W },
  { id: "acera_parque_sur", kind: "path", surface: "sidewalk", x: STREET_X, y: SOUTH_SW_Y, w: PARK_W, h: 1 },
  // EAST street (left of the park): ASPHALT cols 5-8 over the full map height, double yellow centre line (interrupted at the two junctions), sidewalks both sides
  { id: "calle_parque_este", kind: "street", surface: "asphalt", dir: "v", x: EAST_X, y: 0, length: MAP_H, width: EAST_W, line: EAST_LINE_X, gaps: [[STREET_Y, STREET_Y + STREET_W - 1], [SOUTH_Y, SOUTH_Y1]] },
  { id: "calle_principal_boca_este", kind: "path", surface: "paver", x: EAST_SW_PARK, y: STREET_Y, w: 1, h: STREET_W }, // the main street's mouth into the asphalt street (col 9)
  // far-side sidewalk (col 4): unbroken. Park-side sidewalk (col 9): open at the two mouths (rows 21-24 and 65-68); rows 20 and 25 are the corners of the main street's own sidewalks
  { id: "acera_este_lejos", kind: "path", surface: "sidewalk", x: EAST_SW_FAR, y: 0, w: 1, h: MAP_H },
  { id: "acera_este_cerca_a", kind: "path", surface: "sidewalk", x: EAST_SW_PARK, y: 0, w: 1, h: SIDEWALK_N_Y + 1 },
  { id: "acera_este_cerca_b", kind: "path", surface: "sidewalk", x: EAST_SW_PARK, y: SIDEWALK_S_Y, w: 1, h: SOUTH_SW_Y - SIDEWALK_S_Y + 1 },
  { id: "acera_este_cerca_c", kind: "path", surface: "sidewalk", x: EAST_SW_PARK, y: SOUTH_Y1 + 1, w: 1, h: MAP_H - SOUTH_Y1 - 1 },
  // 2. the church (iglesia), north of the street, door centred on it
  { id: "iglesia", kind: "building", name: "iglesia", at: [CHURCH_X, CHURCH_Y] },
  { id: "iglesia_setos", kind: "hedges", of: "iglesia" },
  // paver path from the door (doorstep row 18) to the street (row 21): the two door columns
  { id: "iglesia_camino", kind: "path", surface: "paver", x: CHURCH_X + 4, y: CHURCH_Y + 12, w: 2, h: STREET_Y - (CHURCH_Y + 12) },
  { id: "iglesia_puerta", kind: "interactable", name: "iglesia_puerta",
    x: CHURCH_X * SIZE + 56, y: (CHURCH_Y + 12) * SIZE, w: 48, h: 16,
    props: { interact: "object", label: "Mirar la puerta", line: "La iglesia está cerrada." } },
  { id: "spawn_default", kind: "spawn", name: "default", x: doorXpx("iglesia", [CHURCH_X, CHURCH_Y]), y: doorBottomPx("iglesia", [CHURCH_X, CHURCH_Y]) + 20, facing: "down" },
  { id: "zona_iglesia", kind: "zone", zone: "iglesia", x: (CHURCH_X - 1) * SIZE, y: (CHURCH_Y - 1) * SIZE, w: 13 * SIZE, h: 17 * SIZE, title: "La iglesia", ambience: "pueblo" },
  { id: "zona_zona1", kind: "zone", zone: "zona1", x: 0, y: 0, w: MAP_W * SIZE, h: MAP_H * SIZE, title: "La calle principal", ambience: "pueblo" },
  // the open ends of the street network (future connections; connects_to stays empty). The old calle_oeste/calle_este markers (cols 10 and 59) are gone:
  // the main street now connects to the east asphalt street at its left end.
  { id: "borde_calle_principal_oeste", kind: "edge", edge: "calle_principal_oeste", x: EXT_LASTRE_X1 * SIZE, y: STREET_Y * SIZE, w: SIZE, h: STREET_W * SIZE, spawn: [(EXT_LASTRE_X1 + 1) * SIZE - 28, (STREET_Y + 2) * SIZE], facing: "left" },
  { id: "borde_calle_este_norte", kind: "edge", edge: "calle_este_norte", x: EAST_X * SIZE, y: 0, w: EAST_W * SIZE, h: SIZE, spawn: [(EAST_X + EAST_W / 2) * SIZE, 28], facing: "down" },
  { id: "borde_calle_este_sur", kind: "edge", edge: "calle_este_sur", x: EAST_X * SIZE, y: (MAP_H - 1) * SIZE, w: EAST_W * SIZE, h: SIZE, spawn: [(EAST_X + EAST_W / 2) * SIZE, MAP_H * SIZE - 28], facing: "up" },
  { id: "zona_parque", kind: "zone", zone: "parque", x: PARK_X * SIZE, y: PARK_Y * SIZE, w: PARK_W * SIZE, h: PARK_H * SIZE, title: "El parque", ambience: "pueblo" },
  // ---- the park (a cuadra: 50 x 37 tiles = 100 x 74 m, directly south of the south sidewalk, one verge row between) ----
  // everything not covered below stays zacate grass (with the generic flowers) plus weeds
  { id: "parque_camino", kind: "diag", surface: "paver", c0: PATH_C0, c1: PATH_C1, centre: pathCentre, thick: 3 },
  // tree zone: park-local cols 1-15, rows 0-11 (walkable gaps between trunks)
  { id: "parque_arboles", kind: "tree_zone", rect: [...pk(1, 2), ...pk(15, 11)], seed: "arboles", trees: ["monte", "guanacaste", "palm", "guanacaste", "monte"], step: 3 },
  // skate park
  { id: "skate_suelo", kind: "fill", x: SK_X, y: SK_Y, w: 12, h: 16, tiles: [...rep2(6, "park_skate_plain"), "park_skate_cracked"], salt: "sk" },
  skateBlock("skate_piramide", SK_X + 6, SK_Y + 1, 5, 5, "pyramid"),
  skateBlock("skate_cuenco", SK_X + 1, SK_Y + 9, 6, 6, "pit"),
  stampOf("skate_pintura", "ground", [0, 1, 2, 3, 4].map((i) => ({ name: "park_skate_line_h", at: [SK_X + i, SK_Y + 7] }))
    .concat([9, 10, 11, 12].map((j) => ({ name: "park_skate_line_v", at: [SK_X + 8, SK_Y + j] })))
    .concat([{ name: "park_skate_dots", at: [SK_X + 10, SK_Y + 14] }, { name: "park_skate_dots", at: [SK_X + 2, SK_Y + 5] }])),
  stampOf("skate_rieles", "objects", [["park_rail_l", 1, 3], ["park_rail_m", 2, 3], ["park_rail_r", 3, 3], ["park_rail_l", 7, 8], ["park_rail_m", 8, 8], ["park_rail_r", 9, 8],
    ["park_box", 3, 6], ["park_box", 10, 10], ["park_box", 8, 13]].map(([name, x, y]) => ({ name, at: [SK_X + x, SK_Y + y] }))),
  // children's playground
  { id: "juegos_arena", kind: "fill", x: PG_X, y: PG_Y, w: 12, h: 8, tiles: [...rep2(4, "park_sand_a"), ...rep2(3, "park_sand_b"), "park_sand_pebbles"], salt: "pg" },
  { id: "juegos_columpios", kind: "object", name: "park_swing", at: [PG_X + 1, PG_Y + 1] },
  { id: "juegos_tobogan", kind: "object", name: "park_slide", at: [PG_X + 6, PG_Y + 1] },
  { id: "juegos_trepador", kind: "object", name: "park_climb", at: [PG_X + 9, PG_Y + 2] },
  stampOf("juegos_extras", "objects", [["park_seesaw_l", 2, 5], ["park_seesaw_r", 3, 5], ["park_bench", 6, 6], ["park_bench", 10, 6], ["park_bench", 0, 3]].map(([name, x, y]) => ({ name, at: [PG_X + x, PG_Y + y] }))),
  // basketball + football court
  { id: "cancha_acera", kind: "fill", x: CT_X, y: CT_Y, w: 23, h: 12, tiles: [...rep2(3, "park_walk_a"), "park_walk_b"], salt: "cw" },
  { id: "cancha_piso", kind: "fill", x: CT_X + 1, y: CT_Y + 1, w: 21, h: 10, tiles: ["park_court_green_a", "park_court_green_a", "park_court_green_b"], salt: "cp" },
  stampOf("cancha_pintura_azul", "ground", [[40, 57], [41, 57], [40, 58], [41, 58], [55, 57], [56, 57], [55, 58], [56, 58]].map(([x, y], i) => ({ name: i % 2 ? "park_court_blue_b" : "park_court_blue_a", at: [X(x), y + TOP_PAD] }))),
  { id: "cancha_lineas", kind: "court_lines", rect: [X(39), 54 + TOP_PAD, X(57), 61 + TOP_PAD], centre: X(48), boxes: [[X(39), 56 + TOP_PAD, X(42), 59 + TOP_PAD], [X(54), 56 + TOP_PAD, X(57), 59 + TOP_PAD]], circle: [X(45), 54 + TOP_PAD] },
  { id: "cancha_aro_oeste", kind: "object", name: "park_hoop_l", at: [X(40), 57 + TOP_PAD] },
  { id: "cancha_aro_este", kind: "object", name: "park_hoop_r", at: [X(56), 57 + TOP_PAD] },
  { id: "cancha_arco_oeste", kind: "object", name: "park_goal_l", at: [X(38), 55 + TOP_PAD] },
  { id: "cancha_arco_este", kind: "object", name: "park_goal_r", at: [X(58), 55 + TOP_PAD] },
  // lamp posts (town poste tiles; their light objects are on at dusk and at night)
  ...STREET_LAMPS_N, ...STREET_LAMPS_S, ...PATH_LAMPS,
  // texture: weeds over the park grass
  { id: "parque_maleza", kind: "scatter", rect: [...pk(0, 0), ...pk(49, 36)], name: "weeds", count: 40, seed: "maleza" },
  // ---- the Chequelo places (user's layout) ----
  // CAFETAL: north of the street, cols 297-321 (25 tiles = 50 m, centre col 309 = 50 m before the end of the paver), rows 5-18 (wire fence, soil terraces, cafeto rows, a 2-tile gap + lastre aisle to the street)
  { id: "cafetal_pasillo", kind: "path", surface: "lastre", x: CAF_GAP[0], y: CAF_Y0 + 1, w: 2, h: SIDEWALK_N_Y - CAF_Y0 - 1 }, // rows 6-19, meets the north sidewalk
  stampOf("cafetal_suelo", "ground", cafetalSoil()),
  stampOf("cafetal_cerca", "objects", cafetalFence()),
  stampOf("cafetal_cafetos", "objects", cafetos()),
  { id: "zona_cafetal", kind: "zone", zone: "cafetal", x: (CAF_X0 - 1) * SIZE, y: (CAF_Y0 - 1) * SIZE, w: (CAF_X1 - CAF_X0 + 3) * SIZE, h: (SIDEWALK_N_Y - CAF_Y0 + 1) * SIZE, title: "El cafetal", ambience: "monte" },
  { id: "rumor_cafetal", kind: "emitter", name: "rumor_cafetal", x: (CAF_GAP[0] + 1) * SIZE, y: (12 + TOP_PAD) * SIZE, props: {
    sound: "leaves_rustle", loop: "true", min_distance: 48, max_distance: 260, bus: "ambience", only: "night", when: "mission.chequelo.night_active" } },
  // CASA DE CHAYO (casa_2, blue zinc), south of the street, 25 tiles (50 m) before mama's house centre to centre. Footpath cols 406-407 rows 25-34, lastre yard rows 32-34
  { id: "casa_2", kind: "building", name: "casa_2", at: CHAYO_AT },
  { id: "chayo_camino", kind: "path", surface: "lastre", x: CHAYO_FOOT_X, y: SIDEWALK_S_Y, w: 2, h: CHAYO_YARD_Y + YARD_ROWS - SIDEWALK_S_Y },
  { id: "chayo_patio", kind: "path", surface: "lastre", x: CHAYO_AT[0] + 1, y: CHAYO_YARD_Y, w: CHAYO_FOOT_X + 2 - (CHAYO_AT[0] + 1), h: YARD_ROWS },
  { id: "puerta_abierta", kind: "interactable", name: "puerta_abierta", x: CHAYO_X - 16, y: CHAYO_DOOR_Y, w: 32, h: 16,
    props: { interact: "object", label: "Mirar la puerta", only: "night", line: "La puerta está abierta. Adentro no se oye nada." } },
  { id: "crujido_puerta", kind: "emitter", name: "crujido_puerta", x: CHAYO_X, y: CHAYO_DOOR_Y - 8, props: {
    sound: "door_creak_far", interval: 9, max_distance: 220, min_distance: 48, bus: "sfx", only: "night", when: "mission.chequelo.night_active" } },
  // CASA DE MAMA (casa_mama) at the end of the lastre, south of the street. Footpath cols 432-433 rows 25-35, lastre yard rows 33-35, porch planks on its two open cells
  { id: "casa_mama", kind: "building", name: "casa_mama", at: MAMA_AT },
  { id: "mama_camino", kind: "path", surface: "lastre", x: MAMA_FOOT_X, y: SIDEWALK_S_Y, w: 2, h: MAMA_YARD_Y + YARD_ROWS - SIDEWALK_S_Y },
  { id: "mama_patio", kind: "path", surface: "lastre", x: MAMA_AT[0] + 3, y: MAMA_YARD_Y, w: MAMA_FOOT_X + 2 - (MAMA_AT[0] + 3), h: YARD_ROWS },
  stampOf("mama_porche_tablas", "ground", [6, 7].map((i) => ({ name: "plank_h", at: [MAMA_AT[0] + i, MAMA_AT[1] + 5] }))),
  { id: "porche_mama", kind: "surface", name: "porche_mama", x: MAMA_PX[0] + 6 * SIZE, y: MAMA_PX[1] + 5 * SIZE, w: 32, h: 16, surface: "madera" },
  { id: "door_mama", kind: "door", name: "door_mama", x: MAMA_X - 16, y: MAMA_DOOR_Y, w: 32, h: 12, props: {
    target_map: "maps/house_mama.tmx", target_spawn: "inside_door", exit_spawn: "exit_mama", prompt: "E: entrar",
    locked: "mission.chequelo.failed,!mission.chequelo.next_day", locked_line: "Mamá cerró con llave: hoy no quiere ver a nadie. Mañana será otro día." } },
  { id: "spawn_exit_mama", kind: "spawn", name: "exit_mama", x: MAMA_X, y: MAMA_DOOR_Y + 24, facing: "down" },
  { id: "guanacaste_mama", kind: "tree", tree: "guanacaste", at: [MAMA_AT[0] - 3, MAMA_AT[1] + 5] }, // big guanacaste east (left) of the house
  // ---- CASA DE OLGUITA (casa_3, salmon pink): plot cols 5-18, rows 27-34, hedge fence, 2-tile gate on col 18 (rows 32-33) toward the asphalt street ----
  stampOf("casa_olguita_cerco", "objects", plotFence(PLOT_X0, OLG_Y0, PLOT_X1, OLG_Y1, { corner: "hedge", h: "hedge", v: "hedge", gate: OLG_GATE })),
  { id: "casa_olguita", kind: "building", name: "casa_3", at: OLG_AT },
  // lastre footpath: from the verge (col 19) through the gate along rows 32-33 to the house's door columns (10-11), then along its front (row 33)
  { id: "casa_olguita_camino_a", kind: "path", surface: "lastre", x: OLG_AT[0] + 6, y: OLG_GATE[0], w: PLOT_X1 + 2 - (OLG_AT[0] + 6), h: 2 },
  { id: "casa_olguita_camino_b", kind: "path", surface: "lastre", x: OLG_AT[0] + 2, y: OLG_GATE[1], w: 4, h: 1 },
  { id: "casa_olguita_arbol", kind: "tree", tree: "platano", at: [PLOT_X1 - 2, OLG_Y0 + 3] },
  { id: "casa_olguita_arbol_2", kind: "tree", tree: "monte", at: [PLOT_X0 + 1, OLG_Y1 - 2] },
  { id: "casa_olguita_buganvilia", kind: "prop", name: "bougainvillea", at: [PLOT_X0 + 2, OLG_Y1 - 1] },
  { id: "casa_olguita_puerta", kind: "interactable", name: "casa_olguita_puerta", x: OLG_DOOR_X - 16, y: OLG_DOOR_Y, w: 32, h: 16,
    props: { interact: "object", label: "Mirar la puerta", line: "Casa de Olguita. No hay nadie." } },
  { id: "zona_casa_olguita", kind: "zone", zone: "casa_olguita", x: (PLOT_X0 - 1) * SIZE, y: (OLG_Y0 - 1) * SIZE, w: (PLOT_W + 2) * SIZE, h: (OLG_H + 1) * SIZE, title: "Casa de Olguita", ambience: "pueblo" },
  // ---- LA ESCUELA: plot cols 5-18, rows 36-63 (28 tall), chain-link on a low whitewashed wall, 2-tile gate on col 18 (rows 46-47) ----
  stampOf("escuela_cerca", "objects", plotFence(PLOT_X0, ESC_Y0, PLOT_X1, ESC_Y1, { corner: "escuela_pilar", h: "escuela_cerca_h", v: "escuela_cerca_v", gate: ESC_GATE, gatePost: "escuela_pilar" })),
  // concreto: the patio between the blocks, the east passage (cols 16-17), the yard in front of aulas B (rows 57-58) and the gate apron
  fillOf("escuela_patio", PLOT_X0 + 1, ESC_Y0 + 8, PLOT_X1 - 1, ESC_Y0 + 14),
  fillOf("escuela_pasillo_norte", PLOT_X1 - 2, ESC_Y0 + 2, PLOT_X1 - 1, ESC_Y0 + 7),
  fillOf("escuela_pasillo_sur", PLOT_X1 - 2, ESC_Y0 + 15, PLOT_X1 - 1, ESC_Y0 + 20),
  fillOf("escuela_patio_sur", PLOT_X0 + 1, ESC_Y0 + 21, PLOT_X1 - 1, ESC_Y0 + 22),
  fillOf("escuela_entrada", PLOT_X1, ESC_GATE[0], PLOT_X1 + 1, ESC_GATE[1]),
  { id: "escuela_aulas_a", kind: "building", name: "escuela_aulas_a", at: ESC_A_AT },
  { id: "escuela_aulas_b", kind: "building", name: "escuela_aulas_b", at: ESC_B_AT },
  { id: "escuela_corredor_a", kind: "surface", name: "escuela_corredor_a", x: ESC_A_AT[0] * SIZE, y: (ESC_A_AT[1] + 5) * SIZE, w: 10 * SIZE, h: SIZE, surface: "concreto" },
  { id: "escuela_corredor_b", kind: "surface", name: "escuela_corredor_b", x: ESC_B_AT[0] * SIZE, y: (ESC_B_AT[1] + 5) * SIZE, w: 10 * SIZE, h: SIZE, surface: "concreto" },
  { id: "escuela_asta", kind: "object", name: "escuela_asta", at: ESC_FLAG_AT },
  { id: "escuela_rotulo", kind: "object", name: "escuela_rotulo", at: ESC_SIGN_AT },
  { id: "escuela_arbol_1", kind: "tree", tree: "guanacaste", at: [PLOT_X0 + 3, ESC_Y1 - 2] },
  { id: "escuela_arbol_2", kind: "tree", tree: "monte", at: [PLOT_X1 - 4, ESC_Y1 - 2] },
  ...escDoors.map((d) => ({ id: d.id, kind: "interactable", name: d.id, x: d.x, y: d.y, w: d.w, h: d.h, props: { interact: "object", label: "Mirar la puerta", line: "La escuela está cerrada." } })),
  { id: "zona_escuela", kind: "zone", zone: "escuela", x: (PLOT_X0 - 1) * SIZE, y: (ESC_Y0 - 1) * SIZE, w: (PLOT_W + 2) * SIZE, h: (ESC_H + 2) * SIZE, title: "La escuela", ambience: "pueblo" },
  // ---- the lastre street south of the south street (the west street's continuation), cols 77-80, rows 69-93: butt joint with the paver at rows 68|69, runs off the map's bottom edge ----
  { id: "calle_oeste_sur_lastre", kind: "street", surface: "lastre", dir: "v", x: WEST_X, y: LASTRE_S_Y0, length: MAP_H - LASTRE_S_Y0, width: WEST_W },
  { id: "borde_calle_oeste_sur", kind: "edge", edge: "calle_oeste_sur", x: WEST_X * SIZE, y: (MAP_H - 1) * SIZE, w: WEST_W * SIZE, h: SIZE, spawn: [(WEST_X + WEST_W / 2) * SIZE, MAP_H * SIZE - 28], facing: "up" },
  // ---- EL EBAIS: plot cols 55-75, rows 70-90 (21x21), chain-link on a low whitewashed wall (the school's pieces), 2-tile gate on the NORTH side (cols 57-58, row 70) ----
  stampOf("ebais_cerca", "objects", plotFence(EB_X0, EB_Y0, EB_X1, EB_Y1, { corner: "escuela_pilar", h: "escuela_cerca_h", v: "escuela_cerca_v", gateTop: EB_GATE, gatePost: "escuela_pilar" })),
  // concreto: the apron outside the gate (verge row 69), the 2-wide path down the east (left) side of the building, the front patio and the parking
  ebaisFloor("ebais_entrada", EB_GATE[0], EB_Y0 - 1, EB_GATE[1], EB_Y0),
  ebaisFloor("ebais_camino", EB_GATE[0], EB_Y0 + 1, EB_GATE[1], EB_PATH_Y1),
  ebaisFloor("ebais_patio", EB_GATE[0], EB_YARD_Y0, EB_X1 - 1, EB_PARK_Y1),
  ebStamp("ebais_parqueo_lineas", "ground", [6, 9, 12, 15, 18].map((d) => EB_X0 + d).flatMap((x) => [EB_PARK_Y0, EB_PARK_Y0 + 1, EB_PARK_Y0 + 2, EB_PARK_Y1].map((y) => ["ebais_parqueo_linea", x, y]))),
  { id: "ebais_edificio", kind: "building", name: "ebais_edificio", at: EB_AT },
  // objects: sign beside the gate (outside, on the verge), blue benches against the wall, potted plants, the bin
  ebStamp("ebais_objetos", "objects", [
    ["ebais_rotulo_0_0", EB_GATE[1] + 2, EB_Y0 - 1], ["ebais_rotulo_1_0", EB_GATE[1] + 3, EB_Y0 - 1],
    ["ebais_banca", EB_AT[0], EB_AT[1] + 5], ["ebais_banca", EB_AT[0] + 1, EB_AT[1] + 5], ["ebais_banca", EB_AT[0] + 10, EB_AT[1] + 5], ["ebais_banca", EB_AT[0] + 11, EB_AT[1] + 5],
    ["ebais_banca", EB_GATE[1] + 1, EB_AT[1] + 3], ["ebais_banca", EB_X0 + 8, EB_PARK_Y1 + 2],
    ["ebais_maceta", EB_AT[0], EB_AT[1] + 6], ["ebais_maceta", EB_AT[0] + 11, EB_AT[1] + 6], ["ebais_maceta", EB_GATE[0] - 1, EB_YARD_Y0], ["ebais_maceta", EB_X1 - 2, EB_AT[1] + 2],
    ["ebais_basurero", EB_X1 - 1, EB_YARD_Y0 + 1],
  ]),
  { id: "ebais_arbol_1", kind: "tree", tree: "guanacaste", at: [EB_X1 - 3, EB_Y1 - 2] },
  { id: "ebais_arbol_2", kind: "tree", tree: "monte", at: [EB_X0 + 5, EB_Y1 - 2] },
  { id: "ebais_arbol_3", kind: "tree", tree: "monte", at: [EB_X0 + 12, EB_Y1 - 1] },
  { id: "ebais_arbol_4", kind: "tree", tree: "platano", at: [EB_X1 - 2, EB_AT[1] + 4] },
  { id: "ebais_arbol_5", kind: "tree", tree: "guanacaste", at: [EB_X0 + 2, EB_Y1 - 4] },
  { id: "ebais_puerta", kind: "interactable", name: "ebais_puerta", x: EB_DOOR_X - 16, y: EB_DOOR_Y, w: 32, h: 16,
    props: { interact: "object", label: "Mirar la puerta", line: "El Ebais está cerrado." } },
  { id: "zona_ebais", kind: "zone", zone: "ebais", x: (EB_X0 - 1) * SIZE, y: (EB_Y0 - 1) * SIZE, w: (EB_W + 2) * SIZE, h: (EB_H + 2) * SIZE, title: "El Ebais", ambience: "pueblo" },
  // ---- EL COLEGIO: plot cols 297-321, rows 120-141, directly across the street from the cafetal; gate on the north fence (cols = the cafetal's aisle) ----
  stampOf("colegio_cerca", "objects", plotFence(COL_X0, COL_Y0, COL_X1, COL_Y1, { corner: "escuela_pilar", h: "escuela_cerca_h", v: "escuela_cerca_v", gateTop: COL_GATE, gatePost: "escuela_pilar" })),
  fillOf("colegio_acceso", COL_GATE[0], SIDEWALK_S_Y + 1, COL_GATE[1], COL_Y0 + 9),
  fillOf("colegio_patio", COL_X0 + 1, COL_Y0 + 8, COL_X1 - 1, COL_Y0 + 16),
  { id: "colegio_aulas", kind: "building", name: "escuela_colegio", at: COL_AT },
  { id: "colegio_corredor", kind: "surface", name: "colegio_corredor", x: COL_AT[0] * SIZE, y: (COL_AT[1] + 5) * SIZE, w: 10 * SIZE, h: SIZE, surface: "concreto" },
  { id: "colegio_asta", kind: "object", name: "escuela_asta", at: COL_FLAG_AT },
  { id: "colegio_rotulo", kind: "object", name: "escuela_rotulo_colegio", at: COL_SIGN_AT },
  { id: "colegio_arbol_1", kind: "tree", tree: "guanacaste", at: [COL_X0 + 3, COL_Y1 - 2] },
  { id: "colegio_arbol_2", kind: "tree", tree: "monte", at: [COL_X1 - 4, COL_Y1 - 2] },
  { id: "colegio_arbol_3", kind: "tree", tree: "platano", at: [COL_X0 + 3, COL_Y0 + 3] },
  ...[1, 2].map((i) => { const [x, y, w, h] = doorRects(SCHOOL_BUILDING_BY_NAME.get("escuela_colegio"), COL_AT).map((r) => [r.x, r.y, r.w, r.h])[i - 1]; return { id: `colegio_puerta_${i}`, kind: "interactable", name: `colegio_puerta_${i}`, x, y, w, h, props: { interact: "object", label: "Mirar la puerta", line: "El colegio está cerrado." } }; }),
  { id: "zona_colegio", kind: "zone", zone: "colegio", x: (COL_X0 - 1) * SIZE, y: (COL_Y0 - 1) * SIZE, w: (COL_W + 2) * SIZE, h: (COL_H + 2) * SIZE, title: "El colegio", ambience: "pueblo" },
  // ---- EL MONTE DE HULE Y NISPERO + the road to it + the AEROGENERADORES (docs/monte.md): 500 m EAST of the church (left of the screen) ----
  // the road: cols 0-259 rows 21-24. Its last column (the old far sidewalk position of the asphalt street) opens the sidewalk (plain asphalt, a clean cross junction);
  // the sidewalk keeps rows 20 and 25 on that column. Placed AFTER acera_este_lejos so it overrides those four cells.
  { id: "calle_monte", kind: "road", x: ROAD_X0, y: ROAD_Y0, length: ROAD_X1 - ROAD_X0 + 1, width: STREET_W },
  { id: "borde_calle_principal_este", kind: "edge", edge: "calle_principal_este", x: 0, y: STREET_Y * SIZE, w: SIZE, h: STREET_W * SIZE, spawn: ROAD_SPAWN, facing: "right" },
  { id: "camino_carretas", kind: "street", surface: "lastre", dir: "v", x: TRAIL_X0, y: TRAIL_Y0, length: TRAIL_LEN, width: TRAIL_W, trail: true },
  { id: "monte", kind: "forest", x0: MONTE_X0, x1: MONTE_X1, y0: 0, y1: MAP_H - 1, ramp: MONTE_RAMP, verge: ROAD_VERGE, seed: "mt",
    trees: [["hule", 26], ["nispero", 26], ["monte", 20], ["guanacaste", 14], ["palm", 14]], density: 0.9, props: 0.035, ferns: 0.11 },
  ...TURBINE_AT.map(([bx, by], i) => ({ id: `aerogenerador_${i + 1}`, kind: "turbine", at: [bx, by] })),
  { id: "zona_monte", kind: "zone", zone: "monte", x: MONTE_X0 * SIZE, y: 0, w: MONTE_W * SIZE, h: MAP_H * SIZE, title: "El monte de hule y níspero", ambience: "monte" },
  { id: "zona_aerogeneradores", kind: "zone", zone: "aerogeneradores", x: TURBINE_BBOX[0] * SIZE, y: TURBINE_BBOX[1] * SIZE, w: (TURBINE_BBOX[2] - TURBINE_BBOX[0] + 1) * SIZE, h: (TURBINE_BBOX[3] - TURBINE_BBOX[1] + 1) * SIZE, title: "Los aerogeneradores", ambience: "monte" },
  // ---- LA QUEBRADA (docs/rio.md): the river across the whole map north of the town, its bridge for the asphalt street, scattered trees on the new north land, the zone strips ----
  { id: "rio", kind: "river", river: RIVER },
  { id: "puente", kind: "bridge", ...BRIDGE },
  { id: "rio_arboles", kind: "north_trees", seed: "nt", density: 0.03, trees: ["monte", "guanacaste", "platano", "palm", "guanacaste"], buffer: 3, streetBuffer: 3 },
  ...RIVER_ZONES,
  ...PLACE_ELEMENTS,
  // ---- next elements go here (more houses, trees, poles, roads...) ----
];

// ---- base validation: used by gen.mjs and by buildTmx ----
export function baseReport(elements = ELEMENTS) {
  const street = elements.find((e) => e.kind === "street" && e.id === "calle_principal");
  const church = elements.find((e) => e.kind === "building" && e.name === "iglesia");
  if (!street) throw new Error("zona1: missing the calle_principal street element");
  if (!church) throw new Error("zona1: missing the iglesia building element");
  if (street.length !== STREET_TILES || street.length * METRES_PER_TILE !== STREET_METRES) throw new Error(`zona1: the street is ${street.length} tiles = ${street.length * METRES_PER_TILE} m, must be ${STREET_TILES} tiles = ${STREET_METRES} m`);
  const streetCentre = (street.x + street.length / 2) * SIZE; // px (boundary between tile columns)
  const doorCentre = doorXpx("iglesia", church.at);
  if (streetCentre !== doorCentre) throw new Error(`zona1: the church is not centred on the street (street centre ${streetCentre} px, door centre ${doorCentre} px)`);
  const extP = elements.find((e) => e.kind === "street" && e.id === "calle_principal_oeste_cemento");
  const extL = elements.find((e) => e.kind === "street" && e.id === "calle_principal_oeste_lastre");
  if (!extP || !extL) throw new Error("zona1: missing calle_principal_oeste_cemento / calle_principal_oeste_lastre");
  if (extP.length !== EXT_PAVER_TILES || extP.length * METRES_PER_TILE !== EXT_PAVER_M) throw new Error(`zona1: the paver extension is ${extP.length} tiles = ${extP.length * METRES_PER_TILE} m, must be ${EXT_PAVER_TILES} tiles = ${EXT_PAVER_M} m`);
  if (extL.length !== EXT_LASTRE_TILES || extL.length * METRES_PER_TILE !== EXT_LASTRE_M) throw new Error(`zona1: the lastre extension is ${extL.length} tiles = ${extL.length * METRES_PER_TILE} m, must be ${EXT_LASTRE_TILES} tiles = ${EXT_LASTRE_M} m`);
  if (extP.x !== street.x + street.length || extL.x !== extP.x + extP.length) throw new Error("zona1: the street extensions are not contiguous with calle_principal");
  // the user's layout: cafetal centred 25 tiles (50 m) before the end of the paver; Chayo's house centre 25 tiles before mama's
  const cafetalCentre = CAF_X0 + (CAF_X1 - CAF_X0) / 2;
  if (CAF_X1 - CAF_X0 + 1 !== 25 || cafetalCentre !== extP.x + extP.length - 1 - 25) throw new Error(`zona1: the cafetal (cols ${CAF_X0}-${CAF_X1}) must be 25 tiles wide, centred 25 tiles before the end of the paver (col ${extP.x + extP.length - 1})`);
  const mamaCentre = MAMA_AT[0] + BUILDING_BY_NAME.get("casa_mama").w / 2, chayoCentre = CHAYO_AT[0] + BUILDING_BY_NAME.get("casa_2").w / 2;
  if (mamaCentre - chayoCentre !== 25) throw new Error(`zona1: Chayo's house must be 25 tiles (50 m) before mama's, centre to centre (${mamaCentre - chayoCentre})`);
  const extTotalTiles = extP.length + extL.length;
  if (extTotalTiles * METRES_PER_TILE !== EXT_PAVER_M + EXT_LASTRE_M) throw new Error(`zona1: the extension must total ${EXT_PAVER_M + EXT_LASTRE_M} m`);
  // the monte: its zone centre is MONTE_DIST_T tiles (500 m) EAST (left) of the church door centre
  const zm = elements.find((e) => e.kind === "zone" && e.zone === "monte");
  if (!zm) throw new Error("zona1: missing the monte zone");
  const monteCentrePx = zm.x + zm.w / 2;
  const monteDistTiles = (doorCentre - monteCentrePx) / SIZE;
  if (monteDistTiles !== MONTE_DIST_T || monteDistTiles * METRES_PER_TILE !== MONTE_DIST_M) throw new Error(`zona1: the monte is ${monteDistTiles} tiles = ${monteDistTiles * METRES_PER_TILE} m east of the church door, must be ${MONTE_DIST_T} tiles = ${MONTE_DIST_M} m`);
  if (zm.x / SIZE < MONTE_MARGIN) throw new Error(`zona1: the monte zone starts ${zm.x / SIZE} tiles from the left edge, needs >= ${MONTE_MARGIN}`);
  // the river: the centre line must be exactly the user's distance north of the church, the cafetal and mama's house (+-1 tile)
  const riv = elements.find((e) => e.kind === "river"), brg = elements.find((e) => e.kind === "bridge");
  if (!riv || !brg) throw new Error("zona1: missing the river / bridge elements");
  const casaMama = elements.find((e) => e.kind === "building" && e.name === "casa_mama");
  const riverAt = [
    { id: "iglesia", col: church.at[0] + 5, top: church.at[1], wantM: RIVER_CHURCH_M },
    { id: "cafetal", col: CAF_X0 + (CAF_X1 - CAF_X0) / 2, top: CAF_Y0, wantM: RIVER_CAFETAL_M },
    { id: "casa_mama", col: casaMama.at[0] + BUILDING_BY_NAME.get("casa_mama").w / 2, top: casaMama.at[1], wantM: RIVER_MAMA_M },
  ].map((a) => {
    const run = riv.river.run(a.col), centreRow = run.centre + TOP_PAD, tiles = a.top - centreRow;
    if (Math.abs(tiles - Math.round(a.wantM / METRES_PER_TILE)) > 1) throw new Error(`zona1: the river is ${tiles} tiles = ${tiles * METRES_PER_TILE} m north of ${a.id} (col ${a.col}), must be ${a.wantM} m (${Math.round(a.wantM / METRES_PER_TILE)} tiles) +- 1 tile`);
    return { ...a, centreRow, tiles, metres: tiles * METRES_PER_TILE, rowsA: run.a + TOP_PAD, rowsB: run.b + TOP_PAD, thickness: run.thickness };
  });
  if (TOP_PAD !== riv.river.topPad || MAP_H !== 94 + TOP_PAD) throw new Error("zona1: TOP_PAD / MAP_H do not match the river course");
  if (riv.river.minWater + TOP_PAD - 1 < 6) throw new Error(`zona1: fewer than 6 grass rows north of the river's northernmost bank`);
  return {
    river: { anchors: riverAt, topPad: TOP_PAD, minThickness: riv.river.stats.minThickness, maxThickness: riv.river.stats.maxThickness, slopeMax: riv.river.stats.slopeMax, bridge: brg },
    monte: { distTiles: monteDistTiles, distMetres: monteDistTiles * METRES_PER_TILE, centrePx: monteCentrePx, centreCol: monteCentrePx / SIZE, x0: zm.x / SIZE, x1: (zm.x + zm.w) / SIZE - 1, leftMargin: zm.x / SIZE },
    ext: { paverTiles: extP.length, paverMetres: extP.length * METRES_PER_TILE, paverX0: extP.x, paverX1: extP.x + extP.length - 1,
      lastreTiles: extL.length, lastreMetres: extL.length * METRES_PER_TILE, lastreX0: extL.x, lastreX1: extL.x + extL.length - 1,
      totalTiles: extTotalTiles, totalMetres: extTotalTiles * METRES_PER_TILE },
    lengthTiles: street.length, lengthMetres: street.length * METRES_PER_TILE, metresPerTile: METRES_PER_TILE,
    width: street.width, x0: street.x, x1: street.x + street.length - 1, y0: street.y, y1: street.y + street.width - 1,
    streetCentrePx: streetCentre, doorCentrePx: doorCentre, streetCentreCol: street.x + street.length / 2,
    doorCentreCol: church.at[0] + 5, churchAt: church.at, centred: true,
  };
}

// ---- the Chequelo route (px): church door -> south along the church path -> east (increasing x) along the street centre line ->
// south along mama's footpath -> west along the yard -> mama's door. Also exports the trigger definitions (shared by the TMX and the preview).
export const WALK_SPEED = 60; // px/s
export const RUN_SPEED = 100; // px/s
const STREET_MID_Y = (STREET_Y + STREET_W / 2) * SIZE; // 368: the street centre line
const CHURCH_PX_X = (CHURCH_X + 5) * SIZE; // 560: church door centre = street centre
const YARD_LEG_Y = MAMA_DOOR_Y + 12; // 540: mama's door rect bottom edge, inside the first yard row
export const ROUTE = [
  [CHURCH_PX_X, (CHURCH_Y + 12) * SIZE + 16], // 304: just below the church door
  [CHURCH_PX_X, STREET_MID_Y],
  [(MAMA_FOOT_X + 1) * SIZE, STREET_MID_Y], // x of mama's footpath (2 tiles: cols 432-433, centre x = 6928)
  [(MAMA_FOOT_X + 1) * SIZE, YARD_LEG_Y],
  [MAMA_X, YARD_LEG_Y], // mama's door
];

export function routeLength() {
  let d = 0;
  for (let i = 1; i < ROUTE.length; i++) d += Math.abs(ROUTE[i][0] - ROUTE[i - 1][0]) + Math.abs(ROUTE[i][1] - ROUTE[i - 1][1]);
  return d;
}

/** Point at distance d (px) along the route (clamped). */
export function pointAt(d) {
  let left = Math.max(0, d);
  for (let i = 1; i < ROUTE.length; i++) {
    const [x0, y0] = ROUTE[i - 1], [x1, y1] = ROUTE[i];
    const len = Math.abs(x1 - x0) + Math.abs(y1 - y0);
    if (left <= len) return [x0 + Math.sign(x1 - x0) * left, y0 + Math.sign(y1 - y0) * left];
    left -= len;
  }
  return ROUTE[ROUTE.length - 1].slice();
}

const HW_STREET = 36; // half-width of the road rects on the main street leg
const HW_END = 20; // on the church path, the footpath and the yard leg

/** One rect per route segment (they overlap at the corners); the first starts at the church door, the last ends at mama's door. */
export function roadRects() {
  const rects = [];
  for (let i = 1; i < ROUTE.length; i++) {
    const [x0, y0] = ROUTE[i - 1], [x1, y1] = ROUTE[i];
    const first = i === 1, last = i === ROUTE.length - 1;
    const hw = i === 2 ? HW_STREET : HW_END; // segment 2 is the street leg
    if (x0 === x1) {
      const dir = Math.sign(y1 - y0);
      const a = first ? y0 : y0 - dir * hw, b = last ? y1 : y1 + dir * hw;
      rects.push({ x: x0 - hw, y: Math.min(a, b), w: hw * 2, h: Math.abs(b - a) });
    } else {
      const dir = Math.sign(x1 - x0);
      const a = first ? x0 : x0 - dir * hw, b = last ? x1 : x1 + dir * hw;
      rects.push({ x: Math.min(a, b), y: y0 - hw, w: Math.abs(b - a), h: hw * 2 });
    }
  }
  return rects;
}

export const doorMamaRect = () => ({ x: MAMA_X - 16, y: MAMA_DOOR_Y, w: 32, h: 12 });

export function triggerDefs() {
  const half = pointAt(routeLength() / 2);
  const dm = doorMamaRect();
  const gapX = CAF_GAP[0] * SIZE;
  return [
    { id: "walk_start", rects: [{ x: CHURCH_PX_X - 32, y: 272 + TOP_PAD * SIZE, w: 64, h: 48 }], requires: "mission.chequelo.accepted", sets: "chequelo.walk_started" },
    { id: "road", rects: roadRects(), requires: "mission.chequelo.night_active", sets: "" },
    {
      id: "light_appears", rects: [{ x: Math.round(half[0]) - 16, y: Math.round(half[1]) - 48, w: 32, h: 96 }],
      requires: "mission.chequelo.night_active,!chequelo.light_appears", sets: "chequelo.light_appears",
      line: "Una luz se enciende sobre el camino...",
    },
    // cafetal: the gap (row 18) and the aisle inside it (rows 17-19); stays north of the street's road rects (y < 332)
    { id: "detour_cafetal", rects: [{ x: gapX - 16, y: (CAF_Y1 - 1) * SIZE, w: 64, h: 48 }], requires: "mission.chequelo.night_active,!chequelo.detour_cafetal", sets: "chequelo.detour_cafetal" },
    // chayo's door: the yard in front of it (rows 32-33), on the footpath/yard area, far from the road rects
    { id: "detour_door", rects: [{ x: CHAYO_X - 24, y: CHAYO_DOOR_Y - 4, w: 48, h: 36 }], requires: "mission.chequelo.night_active,!chequelo.detour_door", sets: "chequelo.detour_door" },
    { id: "house_arrival", rects: [{ x: dm.x - 16, y: dm.y - 4, w: 64, h: 44 }], requires: "mission.chequelo.night_active", sets: "chequelo.arrived" },
  ];
}

// ---- tiles ----
const byName = new Map(TILES.map((t) => [t.name, t]));
const gid = (name) => {
  const t = byName.get(name);
  if (!t) throw new Error(`unknown tile ${name}`);
  return t.id + TOWN_FIRSTGID;
};
const bgid = (name) => {
  if (!bIdByName.has(name)) throw new Error(`unknown buildings tile ${name}`);
  return bIdByName.get(name) + B_FIRSTGID;
};
const pgid = (name) => {
  if (!pIdByName.has(name)) throw new Error(`unknown park tile ${name}`);
  return pIdByName.get(name) + PARK_FIRSTGID;
};
const sgid = (name) => {
  if (!sIdByName.has(name)) throw new Error(`unknown school tile ${name}`);
  return sIdByName.get(name) + SCHOOL_FIRSTGID;
};
const egid = (name) => {
  if (!eIdByName.has(name)) throw new Error(`unknown ebais tile ${name}`);
  return eIdByName.get(name) + EBAIS_FIRSTGID;
};
const rgid = (name) => {
  if (!rIdByName.has(name)) throw new Error(`unknown rio tile ${name}`);
  return rIdByName.get(name) + RIO_FIRSTGID;
};
const mgid = (name) => {
  if (!mIdByName.has(name)) throw new Error(`unknown monte tile ${name}`);
  return mIdByName.get(name) + MONTE_FIRSTGID;
};
/** gid of a tile by name in any of the six sheets (park_ names live in the park sheet, escuela_ in the school sheet, ebais_ in the ebais sheet, monte_ names in the monte sheet unless the town has the same name
 *  (monte_trunk, monte_canopy_*), buildings names in buildings). */
const anyGid = (name) => (name.startsWith("rio_") ? rgid(name) : name.startsWith("park_") ? pgid(name) : name.startsWith("escuela_") ? sgid(name) : name.startsWith("ebais_") ? egid(name) : byName.has(name) ? gid(name) : mIdByName.has(name) ? mgid(name) : bgid(name));
const ALL_BUILDINGS = [...BUILDINGS, ...SCHOOL_BUILDINGS, ...EBAIS_BUILDINGS];
const BUILDING_ANY = (name) => BUILDING_BY_NAME.get(name) ?? SCHOOL_BUILDING_BY_NAME.get(name) ?? EBAIS_BUILDING_BY_NAME.get(name);
const pick = (names, x, y, salt = "pk") => names[Math.floor(noise(salt, x, y) * names.length) % names.length];

const LAYER_ORDER = ["ground", "overlay", "objects", "buildings", "windows_lit", ...ALL_BUILDINGS.map((b) => `roof_${b.name}`), "canopy", "rotors"];
const SURFACE_MAT = { paver: "p", lastre: "l", sidewalk: "w", asphalt: "a" };
export const MONTE_REPORT = {}; // filled by buildZona1 / checkWalkable: tree counts, turbines, reachability (printed by gen.mjs)
const TREE_PART = { guanacaste: "trunk", platano: "stem", palm: "trunk", monte: "trunk" };

export function buildZona1(elements = ELEMENTS) {
  const N = MAP_W * MAP_H;
  const L = Object.fromEntries(LAYER_ORDER.map((n) => [n, new Array(N).fill(0)]));
  const at = (x, y) => y * MAP_W + x;
  const inb = (x, y) => x >= 0 && y >= 0 && x < MAP_W && y < MAP_H;
  const mat = Array.from({ length: MAP_H }, () => new Array(MAP_W).fill("g"));
  const setMat = (x, y, m) => { if (inb(x, y)) mat[y][x] = m; };
  const rectMat = (x0, y0, x1, y1, m) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) setMat(x, y, m); };
  const put = (layer, x, y, name) => { if (inb(x, y)) L[layer][at(x, y)] = anyGid(name); };
  const bput = (layer, x, y, name) => { if (inb(x, y)) L[layer][at(x, y)] = bgid(name); };
  const matOf = (e) => SURFACE_MAT[e.surface] ?? (() => { throw new Error(`element ${e.id}: unknown surface ${e.surface}`); })();
  const placed = [];

  // ---- materials ----
  const fillName = Array.from({ length: MAP_H }, () => new Array(MAP_W).fill(null));
  for (const e of elements) {
    if (e.kind === "street") {
      const [w, h] = e.dir === "v" ? [e.width, e.length] : [e.length, e.width];
      rectMat(e.x, e.y, e.x + w - 1, e.y + h - 1, matOf(e));
      if (e.line !== undefined) { // vertical centre line, interrupted over the junction rows (e.gaps)
        for (let y = e.y; y < e.y + e.length; y++) if (!(e.gaps ?? []).some(([a, b]) => y >= a && y <= b)) if (inb(e.line, y)) fillName[y][e.line] = "asphalt_line_v";
      }
    } else if (e.kind === "path") rectMat(e.x, e.y, e.x + e.w - 1, e.y + e.h - 1, matOf(e));
    else if (e.kind === "fill") { // rectangle of ground tiles from a sheet, picked by position noise; not grass any more
      for (let y = e.y; y < e.y + e.h; y++) for (let x = e.x; x < e.x + e.w; x++) { setMat(x, y, "x"); if (inb(x, y)) fillName[y][x] = pick(e.tiles, x, y, e.salt ?? e.id); }
    } else if (e.kind === "road") { // the east road: asphalt "r" (edge / line / plain tiles chosen below)
      rectMat(e.x, e.y, e.x + e.length - 1, e.y + e.width - 1, "r");
    } else if (e.kind === "turbine") { // concrete pad 3 x 2 under and in front of the tower base
      for (let dy = 0; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const x = e.at[0] + dx, y = e.at[1] + dy; setMat(x, y, "x"); if (inb(x, y)) fillName[y][x] = pick(["monte_pad_a", "monte_pad_a", "monte_pad_b"], x, y, "pad"); }
    } else if (e.kind === "diag") { // staircase band: for each column, `thick` rows around the centreline
      const half = Math.floor(e.thick / 2);
      for (let c = Math.min(e.c0, e.c1); c <= Math.max(e.c0, e.c1); c++) {
        const yc = e.centre(c);
        for (let y = yc - half; y <= yc - half + e.thick - 1; y++) setMat(c, y, matOf(e));
      }
    }
  }
  const vertLastre = new Set(); // cells of vertical lastre streets: ruts run along y
  for (const e of elements) if (e.kind === "street" && e.surface === "lastre" && e.dir === "v") for (let y = e.y; y < e.y + e.length; y++) for (let x = e.x; x < e.x + e.width; x++) vertLastre.add(y * MAP_W + x);
  const isGrass = (x, y) => inb(x, y) && mat[y][x] === "g";
  const isLastre = (x, y) => inb(x, y) && mat[y][x] === "l";

  // ---- the quebrada: water mask (from the course), distance-to-water, the bridge deck cells ----
  const riverEl = elements.find((e) => e.kind === "river"), bridgeEl = elements.find((e) => e.kind === "bridge"), northEl = elements.find((e) => e.kind === "north_trees");
  const wat = new Uint8Array(N); // 1 = water
  const DMAX = 9, distW = new Uint8Array(N).fill(DMAX); // Chebyshev distance to the nearest water cell (capped)
  let nWater = 0;
  if (riverEl) {
    const R = riverEl.river;
    if (R.rMin + TOP_PAD < -4 || R.rMax + TOP_PAD > MAP_H + 4) throw new Error("zona1: the river leaves the map");
    for (let r = R.rMin; r <= R.rMax; r++) { const y = r + TOP_PAD; if (y < 0 || y >= MAP_H) continue; for (let x = 0; x < MAP_W; x++) if (R.isWater(x, r)) { wat[y * MAP_W + x] = 1; nWater++; } }
    for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) if (wat[y * MAP_W + x]) {
      for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) { const nx = x + dx, ny = y + dy; if (inb(nx, ny)) { const d = Math.max(Math.abs(dx), Math.abs(dy)); if (d < distW[ny * MAP_W + nx]) distW[ny * MAP_W + nx] = d; } }
    }
  }
  const isW = (x, y) => (y < 0 || y >= MAP_H ? 0 : wat[y * MAP_W + Math.max(0, Math.min(MAP_W - 1, x))]);
  const dW = (x, y) => (inb(x, y) ? distW[y * MAP_W + x] : DMAX);
  const BR = bridgeEl;
  if (BR) { // the deck cells under the guard rails (concrete curb), 2 tiles past each bank
    for (let y = BR.rb0; y <= BR.rb1; y++) for (const [x, nm] of [[BR.railW, "rio_deck_curb_w"], [BR.railE, "rio_deck_curb_e"]]) { setMat(x, y, "x"); fillName[y][x] = nm; }
  }
  /** Bank tile of a land cell next to the water (edges, outer corners = two wet sides, inner corners = only the diagonal is wet). */
  const bankAt = (x, y) => {
    const n = isW(x, y - 1), e = isW(x + 1, y), so = isW(x, y + 1), w = isW(x - 1, y), c = n + e + so + w;
    if (c === 0) {
      const diag = [["ne", 1, -1], ["nw", -1, -1], ["se", 1, 1], ["sw", -1, 1]].find(([, dx, dy]) => isW(x + dx, y + dy));
      return diag ? `rio_bank_inner_${diag[0]}` : null;
    }
    if (c === 1) return `bank_${n ? "n" : e ? "e" : so ? "s" : "w"}`;
    if (c === 2 && !(n && so) && !(e && w)) return `bank_corner_${n ? "n" : "s"}${e ? "e" : "w"}`;
    throw new Error(`river: land cell (${x},${y}) has an impossible wet neighbourhood (${n}${e}${so}${w})`);
  };
  const bridgeBand = (x) => BR && x >= BR.pierW - 5 && x <= BR.pierE + 5; // calm water near the bridge: no rapids, no boulders

  // ---- the monte: forest geometry (ramp, road corridor, trail, turbine clearings) ----
  const forests = elements.filter((e) => e.kind === "forest");
  const roadEls = elements.filter((e) => e.kind === "road");
  const trailEls = elements.filter((e) => e.kind === "street" && e.trail);
  const turbEls = elements.filter((e) => e.kind === "turbine");
  const inClearing = (x, y) => turbEls.some((t) => ((x - t.at[0]) / CLEAR_RX) ** 2 + ((y - (t.at[1] - 3)) / CLEAR_RY) ** 2 <= 1);
  const forestRamp = (f, x, y) => (x < f.x0 || x > f.x1 || y < f.y0 || y > f.y1 ? 0 : Math.min(1, (Math.min(x - f.x0, f.x1 - x) + 1) / f.ramp)); // 0 outside, 0.1 on the border column ... 1 at 10 tiles in (trees, props and ferns use ramp^2: a softer start)
  const inCorridor = (f, x, y, extraSouth = 0) => roadEls.some((r) => y >= r.y - f.verge && y <= r.y + r.width - 1 + f.verge + extraSouth && x >= r.x && x < r.x + r.length + f.verge);
  const nearTrail = (x, y) => trailEls.some((t) => x >= t.x - 1 && x <= t.x + t.width && y >= t.y - 1 && y <= t.y + t.length);
  const forestOpen = (f, x, y, extraSouth = 0) => dW(x, y) > 2 && !inClearing(x, y) && !inCorridor(f, x, y, extraSouth) && !nearTrail(x, y); // cell where forest may grow
  const smooth = (t) => t * t * (3 - 2 * t);
  const vnoise = (salt, x, y0, sc) => { // smooth value noise (bilinear over a lattice of sc tiles): soft-edged blobs instead of tile-aligned squares
    const y = y0 - TOP_PAD; // measured from the original top row, so the original forest keeps its patches
    const gx = Math.floor(x / sc), gy = Math.floor(y / sc), fx = smooth(x / sc - gx), fy = smooth(y / sc - gy);
    const a = rawNoise(salt, gx - LEFT_PAD, gy), b = rawNoise(salt, gx + 1 - LEFT_PAD, gy), c = rawNoise(salt, gx - LEFT_PAD, gy + 1), d = rawNoise(salt, gx + 1 - LEFT_PAD, gy + 1); // (the same lattice values as before the shift)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  };
  const forestGroundName = (x, y, ramp) => {
    if (ramp < 0.5) return `monte_grass_${"abc"[Math.floor(noise("fv", x, y) * 3) % 3]}`; // soft border: only the dark grass (no isolated mud / litter tiles in the open)
    if (vnoise("fm", x, y, 7) > 0.74 && noise("fm2", x, y) < 0.85) return noise("fm3", x, y) < 0.5 ? "monte_mud_a" : "monte_mud_b"; // mud patches (lastre)
    if (vnoise("fb", x, y, 5) > 0.6 && noise("fb2", x, y) < 0.8) return noise("fl", x, y) < 0.5 ? "monte_litter_a" : "monte_litter_b"; // leaf litter
    return `monte_grass_${"abc"[Math.floor(noise("fv", x, y) * 3) % 3]}`; // darker monte grass
  };
  const joinsTrail = (x) => trailEls.some((t) => x >= t.x && x < t.x + t.width);

  for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
    const m = mat[y][x];
    let name;
    if (m === "r") { // the east road: edges with a grass shoulder on the outer rows, the double yellow line split over the two middle rows, plain asphalt (4% cracks) at the junction column
      const row = y - ROAD_Y0, rr = noise("as", x, y);
      const plain = rr < 0.04 ? "asphalt_crack" : noise("ab", x, y) < 0.5 ? "asphalt_a" : "asphalt_b";
      if (x >= ROAD_X1) name = plain;
      else if (row === 0) name = "monte_road_edge_n";
      else if (row === STREET_W - 1) name = joinsTrail(x) ? plain : "monte_road_edge_s";
      else name = row === 1 ? "monte_road_line_n" : "monte_road_line_s";
    } else if (m === "g") {
      const fo = forests.find((f) => forestRamp(f, x, y) > 0 && forestOpen(f, x, y) && noise(f.seed + "g", x, y) < forestRamp(f, x, y));
      const r = noise("gv", x, y);
      const dw = dW(x, y);
      if (wat[y * MAP_W + x]) { // water: calm a / b / ripples; rapids in the fast reaches, a darker pool where the river is wide
        const inner = isW(x - 1, y) && isW(x + 1, y) && isW(x, y - 1) && isW(x, y + 1);
        const fast = !bridgeBand(x) && vnoise("rp", x, 0, 16) > 0.7;
        const pool = inner && isW(x - 1, y - 1) && isW(x + 1, y - 1) && isW(x - 1, y + 1) && isW(x + 1, y + 1) && !bridgeBand(x) && vnoise("dp", x, y, 6) > 0.74;
        if (fast && inner && noise("rpv", x, y) < 0.6) name = noise("rpw", x, y) < 0.5 ? "rio_water_rapids_a" : "rio_water_rapids_b";
        else if (pool) name = "rio_water_dark";
        else { const q = noise("wv", x, y); name = q < 0.07 ? "water_ripple" : q < 0.55 ? "water_a" : "water_b"; }
      } else if (dw === 1) name = bankAt(x, y) ?? pick(["grass_a", "grass_b", "grass_c", "grass_d"], x, y);
      else if (dw === 2 && !fo && vnoise("rg", x, y, 9) > 0.62 && noise("rg2", x, y) < 0.7) name = noise("rg3", x, y) < 0.5 ? "rio_gravel_a" : "rio_gravel_b"; // gravel bars
      else if (dw === 2 && !fo && noise("rs", x, y) < 0.1) name = "river_stones";
      else if (dw <= 3 && !fo && noise("rw", x, y) < (dw === 2 ? 0.55 : 0.25)) name = "riverside_grass";
      else name = fo ? forestGroundName(x, y, forestRamp(fo, x, y)) : r < 0.05 ? "grass_flowers" : r < 0.08 ? "grass_dry" : r < 0.1 ? "grass_dirt" : pick(["grass_a", "grass_b", "grass_c", "grass_d"], x, y);
    } else if (m === "p") {
      name = rawNoise("pv", (x - LEFT_PAD) >> 1, y - TOP_PAD) < 0.1 ? "paver_b" : "paver_a";
    } else if (m === "a") {
      const r = noise("as", x, y);
      name = fillName[y][x] ?? (r < 0.04 ? "asphalt_crack" : noise("ab", x, y) < 0.5 ? "asphalt_a" : "asphalt_b");
    } else if (m === "w") {
      name = noise("sw", x, y) < 0.3 ? "sidewalk_b" : "sidewalk_a";
    } else if (m === "x") {
      name = fillName[y][x];
    } else { // lastre road (autotiled against grass; ruts on the inner rows)
      const miss = ["N", "E", "S", "W"].filter((s) => {
        const [dx, dy] = { N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0] }[s];
        if (s === "E" && x === EXT_LASTRE_X1) return false; // the street continues off its open end: no rounded end cap
        return isGrass(x + dx, y + dy);
      });
      if (miss.length === 0) {
        const diag = [["NW", -1, -1], ["NE", 1, -1], ["SW", -1, 1], ["SE", 1, 1]].find(([, dx, dy]) =>
          isGrass(x + dx, y + dy) && isLastre(x + dx, y) && isLastre(x, y + dy));
        name = diag ? `lastre_inner_${diag[0].toLowerCase()}` : (noise("lr", x, y) < 0.12 ? "lastre_b" : vertLastre.has(y * MAP_W + x) ? "lastre_ruts_v" : "lastre_ruts_h"); // wheel ruts along the road
      } else if (miss.length === 1) name = `lastre_edge_${miss[0].toLowerCase()}`;
      else if (miss.length === 2 && !(miss.includes("N") && miss.includes("S")) && !(miss.includes("E") && miss.includes("W"))) {
        name = `lastre_outer_${(["N", "S"].find((s) => miss.includes(s)) + ["W", "E"].find((s) => miss.includes(s))).toLowerCase()}`;
      } else name = "lastre_a";
    }
    put("ground", x, y, name);
  }

  const occupiedByBuilding = (x, y) => LAYER_ORDER.some((n) => (n === "buildings" || n.startsWith("roof_")) && L[n][at(x, y)] !== 0);
  const needFree = (what, x, y) => {
    if (!isGrass(x, y)) throw new Error(`${what} at (${x},${y}) is not on a grass cell (${inb(x, y) ? mat[y][x] : "outside"})`);
    if (L.objects[at(x, y)] !== 0 || occupiedByBuilding(x, y)) throw new Error(`${what} at (${x},${y}) overlaps another object`);
  };

  // ---- buildings, then the things that hang off them ----
  for (const e of elements.filter((e) => e.kind === "building")) {
    const b = BUILDING_ANY(e.name);
    if (!b) throw new Error(`element ${e.id}: unknown building ${e.name}`);
    const [ox, oy] = e.at;
    const bp = b.sheet ? put : bput; // school / ebais buildings live in their own sheets (resolved by name prefix)
    for (const c of b.cells) {
      if (c.layer === "above") bp(`roof_${b.name}`, ox + c.cx, oy + c.cy, c.name);
      else bp("buildings", ox + c.cx, oy + c.cy, c.name);
    }
    for (const c of b.lit) bp("windows_lit", ox + c.cx, oy + c.cy, c.name);
    placed.push({ id: e.id, b, ox, oy });
  }
  for (const e of elements.filter((e) => e.kind === "hedges")) {
    const p = placed.find((q) => q.id === e.of);
    if (!p) throw new Error(`element ${e.id}: no building ${e.of}`);
    const { ox: ix, oy: iy } = p;
    for (const x of [ix + 1, ix + 2, ix + 3]) bput("objects", x, iy + 12, "hedge_burgundy");
    for (const x of [ix + 6, ix + 7, ix + 8]) bput("objects", x, iy + 12, "hedge_lime");
    for (const x of [ix + 1, ix + 3, ix + 6, ix + 8]) put("objects", x, iy + 13, "hedge");
    // the doorstep and the first path rows stay paver even without a path element
    for (const x of [ix + 4, ix + 5]) put("ground", x, iy + 12, "paver_a");
  }

  for (const p of placed) for (let y = p.oy; y < p.oy + p.b.h; y++) for (let x = p.ox; x < p.ox + p.b.w; x++) {
    if (mat[y][x] !== "g") throw new Error(`building ${p.id} at (${x},${y}) stands on a ${mat[y][x]} surface`);
  }

  // ---- park pieces: ground stamps, court lines, objects from the park sheet, lamps ----
  const objFree = (what, x, y) => {
    if (!inb(x, y)) throw new Error(`${what} at (${x},${y}) is outside the map`);
    if (L.objects[at(x, y)] !== 0 || occupiedByBuilding(x, y)) throw new Error(`${what} at (${x},${y}) overlaps another object`);
  };
  for (const e of elements.filter((e) => e.kind === "stamp")) {
    for (const c of e.cells) {
      if (e.layer === "objects") objFree(c.name, c.at[0], c.at[1]);
      else setMat(c.at[0], c.at[1], "x");
      put(e.layer, c.at[0], c.at[1], c.name);
    }
  }
  for (const e of elements.filter((e) => e.kind === "court_lines")) {
    const [x0, y0, x1, y1] = e.rect;
    const set = new Set();
    const mark = (x, y) => set.add(`${x},${y}`);
    const box = (a, b, c, d) => { for (let x = a; x <= c; x++) { mark(x, b); mark(x, d); } for (let y = b; y <= d; y++) { mark(a, y); mark(c, y); } };
    box(x0, y0, x1, y1);
    for (const b of e.boxes) box(...b);
    for (let y = y0; y <= y1; y++) mark(e.centre, y);
    const has = (x, y) => set.has(`${x},${y}`);
    for (const key of set) {
      const [x, y] = key.split(",").map(Number);
      const arms = (has(x, y - 1) ? "n" : "") + (has(x, y + 1) ? "s" : "") + (has(x + 1, y) ? "e" : "") + (has(x - 1, y) ? "w" : "");
      put("ground", x, y, `park_line_${arms}`);
    }
    for (const c of CIRCLE_CELLS) put("ground", e.circle[0] + c.cx, e.circle[1] + c.cy, c.name);
  }
  for (const e of elements.filter((e) => e.kind === "object")) {
    const o = PARK_OBJECT_BY_NAME.get(e.name) ?? SCHOOL_OBJECT_BY_NAME.get(e.name);
    if (!o) throw new Error(`element ${e.id}: unknown park object ${e.name}`);
    for (const c of o.cells) {
      const x = e.at[0] + c.cx, y = e.at[1] + c.cy;
      if (c.layer === "above") put("canopy", x, y, c.name);
      else { objFree(`${e.name} (${e.id})`, x, y); put("objects", x, y, c.name); }
    }
  }
  const lamps = [];
  for (const e of elements.filter((e) => e.kind === "lamp")) {
    const [cx, cy] = e.at;
    if (e.soft && !(isGrass(cx, cy) && L.objects[at(cx, cy)] === 0)) continue; // optional lamp: skipped where the cell is not free grass
    needFree(`lamp ${e.id}`, cx, cy);
    put("objects", cx, cy, "poste_base");
    put("canopy", cx, cy - 2, "poste_head_top");
    put("canopy", cx, cy - 1, "poste_head_shaft");
    lamps.push({ id: e.id, x: cx * SIZE + 14, y: (cy - 2) * SIZE + 11 }); // the lamp of the head tile sits at (14, 11) of its 16x32 picture
  }

  // ---- trees and props (trunk on a free grass cell) ----
  const treeEls = elements.filter((e) => e.kind === "tree").map((e) => ({ kind: e.tree, at: e.at }));
  const treeFree = (x, y) => isGrass(x, y) && L.objects[at(x, y)] === 0 && !occupiedByBuilding(x, y);
  for (const e of elements.filter((e) => e.kind === "tree_zone")) { // seeded jittered grid, trunks never touch each other
    const [x0, y0, x1, y1] = e.rect, placedHere = [];
    for (let gy = y0; gy <= y1; gy += e.step) for (let gx = x0; gx <= x1; gx += e.step) {
      if (noise(e.seed + "p", gx, gy) < 0.2) continue;
      const x = gx + Math.floor(noise(e.seed + "x", gx, gy) * 3) - 1, y = gy + Math.floor(noise(e.seed + "y", gx, gy) * 3) - 1;
      if (x < x0 || x > x1 || y < y0 || y > y1 || !treeFree(x, y)) continue;
      if ([...placedHere, ...treeEls.map((t) => ({ at: t.at }))].some((t) => Math.abs(t.at[0] - x) < 2 && Math.abs(t.at[1] - y) < 2)) continue;
      const kind = e.trees[Math.floor(noise(e.seed + "k", gx, gy) * e.trees.length) % e.trees.length];
      placedHere.push({ at: [x, y] });
      treeEls.push({ kind, at: [x, y] });
    }
  }
  /** Trunk on a free grass cell + canopy above it (+ shadow blobs and fallen leaves). hule: trunk + shaft (above) + 3x3 canopy; nispero: monte_nispero_*; the rest: the town trees. */
  const drawTree = (kind, cx, cy) => {
    needFree(`${kind} tree`, cx, cy);
    if (kind === "hule") {
      put("objects", cx, cy, "monte_hule_trunk");
      put("canopy", cx, cy - 1, "monte_hule_shaft");
      for (let j = 0; j < 3; j++) for (let i = 0; i < 3; i++) put("canopy", cx - 1 + i, cy - 4 + j, `monte_hule_canopy_${i}_${j}`);
    } else if (kind === "nispero") {
      put("objects", cx, cy, "monte_nispero_trunk");
      for (let j = 0; j < 2; j++) for (let i = 0; i < 3; i++) put("canopy", cx - 1 + i, cy - 2 + j, `monte_nispero_canopy_${i}_${j}`);
    } else {
      put("objects", cx, cy, `${kind}_${TREE_PART[kind]}`);
      for (let j = 0; j < 2; j++) for (let i = 0; i < 3; i++) put("canopy", cx - 1 + i, cy - 2 + j, `${kind}_canopy_${i}_${j}`);
    }
    if (kind !== "palm") {
      if (isGrass(cx - 1, cy)) put("overlay", cx - 1, cy, "shadow_blob");
      if (isGrass(cx + 1, cy)) put("overlay", cx + 1, cy, "shadow_blob");
    }
    if (isGrass(cx, cy + 1)) put("overlay", cx, cy + 1, "fallen_leaves");
  };
  for (const { kind, at: [cx, cy] } of treeEls) drawTree(kind, cx, cy);
  for (const e of elements.filter((e) => e.kind === "prop")) {
    needFree(e.name, e.at[0], e.at[1]);
    put("objects", e.at[0], e.at[1], e.name);
  }
  let nScatter = 0;
  for (const e of elements.filter((e) => e.kind === "scatter")) { // props on random free grass cells (seeded)
    const [x0, y0, x1, y1] = e.rect;
    for (let i = 0, n = 0; i < e.count * 8 && n < e.count; i++) {
      const x = x0 + Math.floor(rawNoise(e.seed + "x", i, 0) * (x1 - x0 + 1)), y = y0 + Math.floor(rawNoise(e.seed + "y", i, 1) * (y1 - y0 + 1));
      if (!treeFree(x, y) || L.canopy[at(x, y)] !== 0) continue;
      put("objects", x, y, e.name); n++; nScatter++;
    }
  }

  // ---- the aerogeneradores: tower (base solid in objects; shaft + nacelle above in canopy), rotor (9x9 cells, animated, own `rotors` layer above), warning light ----
  const turbines = [];
  for (const e of turbEls) {
    const [bx, by] = e.at;
    if (by - (TOWER_H - 1) - Math.floor(ROTOR_N / 2) < 0) throw new Error(`turbine ${e.id}: the rotor would leave the top of the map (base row ${by})`);
    objFree(`turbine ${e.id}`, bx, by);
    put("objects", bx, by, `monte_tower_0_${TOWER_H - 1}`);
    for (let cy = 0; cy < TOWER_H - 1; cy++) put("canopy", bx, by - (TOWER_H - 1) + cy, `monte_tower_0_${cy}`);
    for (const c of ROTOR_CELLS) put("rotors", bx - Math.floor(ROTOR_N / 2) + c.cx, by - (TOWER_H - 1) - Math.floor(ROTOR_N / 2) + c.cy, c.name);
    turbines.push({ id: e.id, bx, by, light: [bx * SIZE + 8, (by - (TOWER_H - 1)) * SIZE + 1] });
  }

  // ---- the forest: seeded scatter of trees (solid trunks, spacing >= 2 so no pocket is ever closed), undergrowth props and ferns ----
  const stats = { trees: {}, solidProps: {}, ferns: 0, forestCells: 0, eligible: 0, solidCells: 0 };
  for (const f of forests) {
    const solid = new Set(); // "x,y" of solid trunks / props placed here (a new one never touches another, diagonals included)
    const solidNear = (x, y) => { for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if (solid.has(`${x + dx},${y + dy}`) || (inb(x + dx, y + dy) && L.objects[at(x + dx, y + dy)] !== 0)) return true; return false; };
    const total = f.trees.reduce((a, [, w]) => a + w, 0);
    const kindOf = (u) => { let acc = 0; for (const [k, w] of f.trees) { acc += w / total; if (u < acc) return k; } return f.trees[0][0]; };
    const free = (x, y, extraSouth = 0) => inb(x, y) && isGrass(x, y) && L.objects[at(x, y)] === 0 && !occupiedByBuilding(x, y) && forestOpen(f, x, y, extraSouth);
    const PROPS = ["monte_bush", "monte_bush", "monte_log", "monte_rock_moss"];
    // Two passes keep the ORIGINAL monte byte-identical under TOP_PAD: pass A = the original rows (row-major, exactly as before: trees need their canopy rows inside the ORIGINAL map);
    // pass B = the new north rows plus the first original rows (which could not hold a tree before), adapting to whatever pass A placed.
    const cell = (x, y, top0, count) => { // a solid prop (bush, log, rock) or a tree per free cell, never touching another solid
      const ramp = forestRamp(f, x, y);
      if (ramp === 0) return;
      if (count) { stats.forestCells++; if (free(x, y)) stats.eligible++; }
      if (!free(x, y) || solidNear(x, y)) return;
      if (noise(f.seed + "p", x, y) < f.props * ramp * ramp) {
        const name = PROPS[Math.floor(noise(f.seed + "q", x, y) * PROPS.length) % PROPS.length];
        put("objects", x, y, name);
        solid.add(`${x},${y}`); stats.solidProps[name] = (stats.solidProps[name] ?? 0) + 1; stats.solidCells++;
        return;
      }
      const kind = kindOf(noise(f.seed + "k", x, y));
      const top = kind === "hule" ? 4 : 2; // canopy rows above the trunk
      if (y - top0 < top || !free(x, y, kind === "hule" ? 2 : 0) || noise(f.seed + "t", x, y) >= f.density * ramp * ramp) return;
      drawTree(kind, x, y);
      solid.add(`${x},${y}`); stats.trees[kind] = (stats.trees[kind] ?? 0) + 1; stats.solidCells++;
    };
    for (let y = TOP_PAD; y < MAP_H; y++) for (let x = f.x0; x <= f.x1; x++) cell(x, y, TOP_PAD, true);
    for (let y = 0; y < TOP_PAD + 4; y++) for (let x = f.x0; x <= f.x1; x++) cell(x, y, 0, y < TOP_PAD);
    for (let y = 0; y < MAP_H; y++) for (let x = f.x0; x <= f.x1; x++) { // ferns: walk-through, any free cell
      const ramp = forestRamp(f, x, y);
      if (ramp === 0 || !free(x, y) || noise(f.seed + "f", x, y) >= f.ferns * ramp * ramp) continue;
      put("objects", x, y, noise(f.seed + "fv", x, y) < 0.5 ? "monte_fern_a" : "monte_fern_b");
      stats.ferns++;
    }
  }
  MONTE_REPORT.stats = stats;
  MONTE_REPORT.turbines = turbines;

  // ---- the quebrada's objects: bridge rails / posts / piers, boulders in the stream, scattered trees on the new north land ----
  const rstats = { waterCells: nWater, boulders: 0, northTrees: 0, rapidsCells: 0 };
  if (BR) {
    const putObj = (x, y, name) => { objFree(name, x, y); put("objects", x, y, name); };
    for (let y = BR.rb0; y <= BR.rb1; y++) { // guard rails along both sides of the deck; a square concrete post at each end
      const end = y === BR.rb0 || y === BR.rb1;
      putObj(BR.railW, y, end ? "rio_post" : "rio_rail_w"); putObj(BR.railE, y, end ? "rio_post" : "rio_rail_e");
    }
    for (const y of [BR.wr0, (BR.wr0 + BR.wr1) >> 1, BR.wr1]) { putObj(BR.pierW, y, "rio_abutment_w"); putObj(BR.pierE, y, "rio_abutment_e"); } // piers in the water outside the rails
  }
  if (riverEl) {
    const BOULDERS = ["rio_boulder_a", "rio_boulder_b", "rio_boulder_c"];
    for (let y = 1; y < MAP_H - 1; y++) for (let x = 1; x < MAP_W - 1; x++) {
      if (!wat[y * MAP_W + x] || bridgeBand(x) || dW(x, y) !== 0) continue;
      const inner = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]].every(([dx, dy]) => isW(x + dx, y + dy));
      if (!inner) continue;
      const fast = vnoise("rp", x, 0, 16) > 0.7;
      if (fast) rstats.rapidsCells++;
      if (noise("bo", x, y) >= (fast ? 0.07 : 0.018)) continue;
      let clear = true;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if (L.objects[at(x + dx, y + dy)] !== 0) clear = false;
      if (!clear) continue;
      put("objects", x, y, BOULDERS[Math.floor(noise("bk", x, y) * 3) % 3]);
      rstats.boulders++;
    }
  }
  if (northEl) { // plain grass with a few scattered trees (seeded): everything above the original map, outside the monte zone (it has its own forest), away from the streets and the river
    const sb = northEl.streetBuffer;
    for (let y = 2; y < TOP_PAD; y++) for (let x = 1; x < MAP_W - 1; x++) {
      if (x >= MONTE_X0 - 1 && x <= MONTE_X1 + 1) continue;
      if (x >= EAST_SW_FAR - sb && x <= EAST_SW_PARK + sb) continue;
      if (dW(x, y) <= northEl.buffer || !treeFree(x, y) || noise(northEl.seed + "p", x, y) >= northEl.density) continue;
      let clear = true;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if (L.objects[at(x + dx, y + dy)] !== 0) clear = false;
      if (!clear) continue;
      drawTree(northEl.trees[Math.floor(noise(northEl.seed + "k", x, y) * northEl.trees.length) % northEl.trees.length], x, y);
      rstats.northTrees++;
    }
  }
  if (riverEl) { // nothing but boulders and piers may stand on the water, and nothing at all on the bank cells
    const okOnWater = new Set(["rio_boulder_a", "rio_boulder_b", "rio_boulder_c", "rio_abutment_w", "rio_abutment_e"].map(rgid));
    for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
      const i = y * MAP_W + x;
      if (wat[i] && mat[y][x] === "g" && ((L.objects[i] !== 0 && !okOnWater.has(L.objects[i])) || L.buildings[i] !== 0)) throw new Error(`river: an object stands on the water at (${x},${y})`);
      if (distW[i] === 1 && !wat[i] && mat[y][x] === "g" && (L.objects[i] !== 0 || L.buildings[i] !== 0)) throw new Error(`river: an object stands on the bank at (${x},${y})`);
      if (wat[i] && mat[y][x] !== "g" && !(BR && x >= BR.railW && x <= BR.railE && y >= BR.wr0 && y <= BR.wr1)) throw new Error(`river: water under a ${mat[y][x]} surface at (${x},${y})`);
    }
  }
  MONTE_REPORT.river = rstats;
  return { L, placed, lamps, turbines, stats, wat, riverEl, bridgeEl };
}

// ---------------------------------------------------------------- TMX
function csv(arr) {
  const rows = [];
  for (let y = 0; y < MAP_H; y++) rows.push(arr.slice(y * MAP_W, (y + 1) * MAP_W).join(","));
  return rows.join(",\n");
}

const prop = (name, value, type) => `    <property name="${name}"${type ? ` type="${type}"` : ""} value="${value}"/>`;

// ---- generation-time collision-trap check: flood fill (tile resolution) from the church spawn over every non-solid tile ----
function checkWalkable(L, placed, defs, turbines = [], river = {}) {
  const solidGids = new Set([...TILES.filter((t) => t.solid).map((t) => t.id + TOWN_FIRSTGID), ...B_TILES.filter((t) => t.solid).map((t) => t.id + B_FIRSTGID),
    ...PARK_TILES.filter((t) => t.solid).map((t) => t.id + PARK_FIRSTGID), ...S_TILES.filter((t) => t.solid).map((t) => t.id + SCHOOL_FIRSTGID), ...E_TILES.filter((t) => t.solid).map((t) => t.id + EBAIS_FIRSTGID), ...M_TILES.filter((t) => t.solid).map((t) => t.id + MONTE_FIRSTGID), ...R_TILES.filter((t) => t.solid).map((t) => t.id + RIO_FIRSTGID)]);
  const blocked = new Uint8Array(MAP_W * MAP_H);
  for (let i = 0; i < blocked.length; i++) if (solidGids.has(L.objects[i]) || solidGids.has(L.buildings[i]) || solidGids.has(L.ground[i])) blocked[i] = 1; // water is a solid GROUND tile
  for (const p of placed) { // footprint rows (same rect as the collision object)
    const [r0, r1] = p.b.footRows;
    for (let y = p.oy + r0; y < p.oy + r1; y++) for (let x = p.ox; x < p.ox + p.b.w; x++) blocked[y * MAP_W + x] = 1;
  }
  const start = [Math.floor(CHURCH_PX_X / SIZE), Math.floor((308 + TOP_PAD * SIZE) / SIZE)];
  const flood = (blk) => { // flood fill (tile resolution) from the church spawn over every non-blocked tile
    const sn = new Uint8Array(MAP_W * MAP_H);
    const q = [start]; sn[start[1] * MAP_W + start[0]] = 1;
    while (q.length) {
      const [x, y] = q.pop();
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= MAP_W || ny >= MAP_H || sn[ny * MAP_W + nx] || blk[ny * MAP_W + nx]) continue;
        sn[ny * MAP_W + nx] = 1; q.push([nx, ny]);
      }
    }
    return sn;
  };
  const seen = flood(blocked);
  const reach = (r) => { // is any tile of the px rect reachable?
    for (let y = Math.floor(r.y / SIZE); y <= Math.floor((r.y + r.h - 1) / SIZE); y++) for (let x = Math.floor(r.x / SIZE); x <= Math.floor((r.x + r.w - 1) / SIZE); x++) if (seen[y * MAP_W + x]) return true;
    return false;
  };
  const tile = (px, py) => seen[Math.floor(py / SIZE) * MAP_W + Math.floor(px / SIZE)] === 1;
  const gx = PLOT_X1 * SIZE + 8;
  const schoolMust = [
    ["escuela gate (2 tiles)", tile(gx, ESC_GATE[0] * SIZE + 8) && tile(gx, ESC_GATE[1] * SIZE + 8)], ["escuela apron outside the gate", tile((PLOT_X1 + 1) * SIZE + 8, ESC_GATE[0] * SIZE + 8)],
    ["escuela patio", tile((PLOT_X0 + 6) * SIZE + 8, (ESC_Y0 + 9) * SIZE + 8)], ["escuela flagpole surroundings", tile((ESC_FLAG_AT[0] + 1) * SIZE + 8, ESC_FLAG_AT[1] * SIZE + 8)],
    ["escuela east passage (south)", tile((PLOT_X1 - 1) * SIZE + 8, (ESC_Y0 + 18) * SIZE + 8)], ["escuela yard in front of aulas B", tile((PLOT_X0 + 5) * SIZE + 8, (ESC_Y0 + 21) * SIZE + 8)],
    ...escDoors.map((d) => [`${d.id} front`, tile(d.x + d.w / 2, d.y + 8)]),
    ["casa olguita gate (2 tiles)", tile(gx, OLG_GATE[0] * SIZE + 8) && tile(gx, OLG_GATE[1] * SIZE + 8)], ["casa olguita door front", tile(OLG_DOOR_X, OLG_DOOR_Y + 8)],
    ["casa olguita footpath", tile((OLG_AT[0] + 4) * SIZE + 8, OLG_GATE[1] * SIZE + 8)],
  ];
  const ebaisMust = [
    ["ebais gate (2 tiles)", EB_GATE.every((x) => tile(x * SIZE + 8, EB_Y0 * SIZE + 8))], ["ebais apron outside the gate", EB_GATE.every((x) => tile(x * SIZE + 8, (EB_Y0 - 1) * SIZE + 8))],
    ["ebais path (2 wide, down the east side)", EB_GATE.every((x) => tile(x * SIZE + 8, (EB_AT[1] + 2) * SIZE + 8)) && EB_GATE.every((x) => tile(x * SIZE + 8, EB_PATH_Y1 * SIZE + 8))],
    ["ebais front patio", tile(EB_DOOR_X, EB_YARD_Y0 * SIZE + 8)], ["ebais front door", tile(EB_DOOR_X, EB_DOOR_Y + 8)], ["ebais parking", tile((EB_X0 + 11) * SIZE + 8, EB_PARK_Y0 * SIZE + 8)],
    ["lastre street south end", [WEST_X + 1, WEST_X + 2].every((x) => tile(x * SIZE + 8, (MAP_H - 2) * SIZE + 8))], ["lastre street joint with the south street", tile((WEST_X + 1) * SIZE + 8, LASTRE_S_Y0 * SIZE + 8)],
  ];
  const roadY = (ROAD_Y0 + 1) * SIZE + 8; // second road row (the line row)
  const monteMust = [
    ["the junction of the east road with the asphalt street", [ROAD_X1 + 1, ROAD_X1, ROAD_X1 - 1].every((x) => [ROAD_Y0, ROAD_Y0 + 1, ROAD_Y1].every((y) => tile(x * SIZE + 8, y * SIZE + 8)))],
    ["the east road's left end (col 0, all 4 rows)", Array.from({ length: STREET_W }, (_, i) => tile(8, (ROAD_Y0 + i) * SIZE + 8)).every(Boolean)], ["spawn edge_calle_principal_este", tile(ROAD_SPAWN[0], ROAD_SPAWN[1])],
    ["the east road through the monte (every column)", Array.from({ length: ROAD_X1 + 1 }, (_, x) => tile(x * SIZE + 8, roadY)).every(Boolean)],
    ["camino de las carretas (its far end)", [TRAIL_X0, TRAIL_X0 + TRAIL_W - 1].every((x) => tile(x * SIZE + 8, (TRAIL_Y0 + TRAIL_LEN - 1) * SIZE + 8))],
    ...turbines.flatMap((t) => [[`${t.id} clearing (front of the pad)`, tile(t.bx * SIZE + 8, (t.by + 2) * SIZE + 8)], [`${t.id} pad beside the base`, tile((t.bx - 1) * SIZE + 8, t.by * SIZE + 8) && tile((t.bx + 1) * SIZE + 8, t.by * SIZE + 8)],
      [`${t.id} clearing (north of the tower)`, tile(t.bx * SIZE + 8, (t.by - 4) * SIZE + 8)]]),
  ];
  // the monte as a whole: every free (non-blocked) cell of its zone must be reachable (no pockets)
  {
    const z = { x0: MONTE_X0, x1: MONTE_X1 };
    let freeCells = 0, reach = 0;
    for (let y = 0; y < MAP_H; y++) for (let x = z.x0; x <= z.x1; x++) { if (blocked[y * MAP_W + x]) continue; freeCells++; if (seen[y * MAP_W + x]) reach++; }
    MONTE_REPORT.walk = { freeCells, reachable: reach, blockedCells: (z.x1 - z.x0 + 1) * MAP_H - freeCells };
    if (reach !== freeCells) throw new Error(`zona1: ${freeCells - reach} free cells of the monte are not reachable from the church spawn (closed pockets)`);
  }
  // the river: water is blocked everywhere except under the bridge deck, the north bank is reached over the bridge ONLY (flood again with the deck blocked: the north must be cut off)
  const riverMust = [];
  if (river.wat && river.bridge) {
    const B = river.bridge, wat = river.wat;
    let walkableWater = 0, deckWater = 0, deckOpen = 0;
    for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) if (wat[y * MAP_W + x]) {
      const deck = x >= B.railW && x <= B.railE && y >= B.wr0 && y <= B.wr1;
      if (deck) { deckWater++; if (x >= B.deckW && x <= B.deckE) { if (!blocked[y * MAP_W + x]) deckOpen++; } } else if (!blocked[y * MAP_W + x]) walkableWater++;
    }
    if (walkableWater) throw new Error(`zona1: ${walkableWater} water cells are walkable`);
    const mid = (B.wr0 + B.wr1) >> 1, cx = EAST_X + 1;
    const northPt = [cx, B.rb0 - 3], southPt = [cx, B.rb1 + 3];
    const cut = blocked.slice();
    for (let y = B.wr0; y <= B.wr1; y++) for (let x = B.deckW; x <= B.deckE; x++) cut[y * MAP_W + x] = 1;
    const seenCut = flood(cut);
    const north2 = [Math.floor(river.northX), river.northRow];
    riverMust.push(["the bridge deck (every deck column, every water row)", deckOpen === (B.deckE - B.deckW + 1) * (B.wr1 - B.wr0 + 1)],
      ["south approach of the bridge", tile(southPt[0] * SIZE + 8, southPt[1] * SIZE + 8)], ["bridge deck centre", tile(cx * SIZE + 8, mid * SIZE + 8)],
      ["north approach of the bridge (reached over the deck)", tile(northPt[0] * SIZE + 8, northPt[1] * SIZE + 8)],
      ["the north bank far from the bridge (reached over the deck)", seen[north2[1] * MAP_W + north2[0]] === 1],
      ["the river cuts the north off without the bridge", seenCut[northPt[1] * MAP_W + northPt[0]] === 0 && seenCut[north2[1] * MAP_W + north2[0]] === 0 && seenCut[southPt[1] * MAP_W + southPt[0]] === 1]);
    MONTE_REPORT.riverWalk = { waterCells: river.nWater, deckWater, deckOpen, walkableWater, northPt, southPt, north2 };
  }
  const must = [...riverMust, ...monteMust, ...ebaisMust, ["mama's door front", tile(MAMA_X, MAMA_DOOR_Y + 8)], ["exit_mama spawn", tile(MAMA_X, MAMA_DOOR_Y + 24)], ["chayo's door front", tile(CHAYO_X, CHAYO_DOOR_Y + 8)],
    ["cafetal gap", tile(CAF_GAP[0] * SIZE + 8, CAF_Y1 * SIZE + 8) && tile(CAF_GAP[1] * SIZE + 8, CAF_Y1 * SIZE + 8)], ["cafetal aisle (inside)", tile(CAF_GAP[0] * SIZE + 8, (8 + TOP_PAD) * SIZE)],
    ["colegio gate (2 tiles)", tile(COL_GATE[0] * SIZE + 8, COL_Y0 * SIZE + 8) && tile(COL_GATE[1] * SIZE + 8, COL_Y0 * SIZE + 8)], ["colegio patio", tile((COL_X0 + 6) * SIZE + 8, (COL_Y0 + 9) * SIZE + 8)],
    ["colegio corridor", tile((COL_AT[0] + 4) * SIZE + 8, (COL_AT[1] + 5) * SIZE + 8)], ["colegio yard in front of the aulas", tile((COL_AT[0] + 4) * SIZE + 8, (COL_AT[1] + 6) * SIZE + 8)],
    ...PLACE_DOORS.map(([x, y], i) => [`place door ${i}`, tile(x, y)]),
    ...schoolMust, ["footpath mama", tile(MAMA_FOOT_X * SIZE + 8, (30 + TOP_PAD) * SIZE) && tile((MAMA_FOOT_X + 1) * SIZE + 8, (30 + TOP_PAD) * SIZE)], ["footpath chayo", tile(CHAYO_FOOT_X * SIZE + 8, (28 + TOP_PAD) * SIZE) && tile((CHAYO_FOOT_X + 1) * SIZE + 8, (28 + TOP_PAD) * SIZE)]];
  for (const [what, ok] of must) if (!ok) throw new Error(`zona1: ${what} is not reachable from the church spawn (collision trap)`);
  for (const d of defs) for (const r of d.rects) if (!reach(r)) throw new Error(`zona1: trigger ${d.id} rect (${r.x},${r.y}) is not reachable`);
  for (let i = 0; i < ROUTE.length; i++) if (!tile(ROUTE[i][0], ROUTE[i][1])) throw new Error(`zona1: route point ${i} (${ROUTE[i]}) is on a blocked tile`);
  // the route itself: every tile along each segment must be walkable
  for (let i = 1; i < ROUTE.length; i++) {
    const [x0, y0] = ROUTE[i - 1], [x1, y1] = ROUTE[i], n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
    for (let k = 0; k <= n; k += 8) if (!tile(x0 + Math.sign(x1 - x0) * k, y0 + Math.sign(y1 - y0) * k)) throw new Error(`zona1: the route is blocked near (${x0 + Math.sign(x1 - x0) * k},${y0 + Math.sign(y1 - y0) * k})`);
  }
}

export function buildTmx(elements = ELEMENTS) {
  const rep = baseReport(elements);
  const buildResult = buildZona1(elements);
  const { L, placed, lamps: lampPosts, turbines } = buildResult;
  let nid = 1;
  const oid = () => nid++;
  const px = (p) => ({ x: p.ox * SIZE, y: p.oy * SIZE, w: p.b.w * SIZE, h: p.b.h * SIZE });
  const props = (list) => `   <properties>\n${list.join("\n")}\n   </properties>`;
  const obj = (name, cls, r, plist, extra = "") =>
    `  <object id="${oid()}" name="${name}"${cls ? ` class="${cls}"` : ""} x="${r.x}" y="${r.y}"${r.w !== undefined ? ` width="${r.w}" height="${r.h}"` : ""}>\n${plist ? props(plist) + "\n" : ""}${extra}  </object>`;
  const pt = (name, cls, x, y, plist) => `  <object id="${oid()}" name="${name}"${cls ? ` class="${cls}"` : ""} x="${x}" y="${y}">\n${plist ? props(plist) + "\n" : ""}   <point/>\n  </object>`;
  const kv = (o) => Object.entries(o).map(([k, v]) => prop(k, v));
  const W = MAP_W * SIZE, H = MAP_H * SIZE;
  const of = (kind) => elements.filter((e) => e.kind === kind);

  // collision: map border + one footprint per building (the roof cells cannot be solid)
  const coll = [
    ["wall_top", -16, -16, W + 32, 16], ["wall_bottom", -16, H, W + 32, 16], ["wall_left", -16, 0, 16, H], ["wall_right", W, 0, 16, H],
  ].map(([n, x, y, w, h]) => `  <object id="${oid()}" name="${n}" x="${x}" y="${y}" width="${w}" height="${h}"></object>`);
  for (const p of placed) {
    const o = px(p);
    const [r0, r1] = p.b.footRows;
    coll.push(`  <object id="${oid()}" name="${p.b.name}_footprint" x="${o.x}" y="${o.y + r0 * SIZE}" width="${o.w}" height="${(r1 - r0) * SIZE}"></object>`);
  }

  const interact = of("interactable").map((e) => obj(e.name, "interactable", e, kv(e.props)));
  const spawns = of("spawn").map((e) => pt(e.name, "spawn", e.x, e.y, [prop("facing", e.facing)]));
  for (const e of of("edge")) spawns.push(pt(`edge_${e.edge}`, "spawn", e.spawn[0], e.spawn[1], [prop("facing", e.facing)]));
  const edgeObjs = of("edge").map((e) => obj(`edge_${e.edge}`, "edge", e, [prop("edge", e.edge), prop("connects_to", "")]));
  const zones = of("zone").map((e) => obj(`zone_${e.zone}${e.suffix ?? ""}`, "zone", e, [prop("zone", e.zone), prop("title", e.title), prop("ambience", e.ambience)]));
  const doors = of("door").map((e) => obj(e.name, "door", e, kv(e.props)));
  const surfaces = of("surface").map((e) => obj(e.name, "surface", e, [prop("surface", e.surface)]));
  const emitters = of("emitter").map((e) => pt(e.name, "emitter", e.x, e.y, kv(e.props)));
  const roofs = placed.map((p) => obj(`roof_${p.b.name}`, "roof", px(p), [prop("roof_of", p.b.roof_of)]));

  const triggers = [];
  for (const t of triggerDefs()) {
    t.rects.forEach((r, i) => {
      const plist = [prop("trigger", t.id), prop("mission", "chequelo")];
      if (t.requires) plist.push(prop("requires", t.requires));
      if (t.sets) plist.push(prop("sets", t.sets));
      if (t.line) plist.push(prop("line", t.line));
      triggers.push(obj(t.rects.length > 1 ? `${t.id}_${String(i).padStart(2, "0")}` : t.id, "trigger", r, plist));
    });
  }
  const route = ROUTE.map(([x, y], i) => pt(`route_${String(i).padStart(2, "0")}`, "route", x, y));
  const walkPx = routeLength();
  const R = buildResult;
  checkWalkable(L, placed, triggerDefs(), turbines, { wat: R.wat, bridge: R.bridgeEl, nWater: MONTE_REPORT.river.waterCells,
    northX: 400, northRow: Math.round(RIVER.centre(400)) + TOP_PAD - 6 });

  const light = (name, x, y, radius, only, rgbv = [255, 190, 100], intensity = 0.8, flicker = 0.1) =>
    `  <object id="${oid()}" name="${name}" class="light" x="${x - 4}" y="${y - 4}" width="8" height="8">
${props([prop("radius", radius, "int"), prop("r", rgbv[0], "int"), prop("g", rgbv[1], "int"), prop("b", rgbv[2], "int"),
    prop("intensity", intensity, "float"), prop("flicker", flicker, "float"), prop("only", only)])}
  </object>`;
  const lights = [];
  for (const p of placed) {
    const o = px(p);
    p.b.windows.forEach((w, i) => lights.push(light(`luz_${p.b.name}_${i + 1}`, o.x + w.x + w.w / 2, o.y + w.y + w.h / 2, p.b.name === "casa_mama" ? 36 : 30, "dusk,night")));
    if (p.b.name === "iglesia") lights.push(light("luz_iglesia_puerta", o.x + 80, o.y + 150, 40, "dusk,night"));
    if (p.b.name === "ebais_edificio") lights.push(light("luz_ebais_puerta", o.x + 96, o.y + 98, 40, "dusk,night"));
  }

  // wind turbines: a tiny red warning light on each nacelle (dusk and night, flickering)
  for (const t of turbines) lights.push(light(`luz_${t.id}`, t.light[0], t.light[1], 20, "dusk,night", [255, 50, 40], 0.9, 0.35));
  // street / path lamp posts: lit at dusk and at night
  for (const l of lampPosts) lights.push(light(`luz_${l.id}`, l.x, l.y, 52, "dusk,night", [255, 205, 120], 0.85, 0.05));

  const layer = (id, name, arr, p = "") =>
    ` <layer id="${id}" name="${name}" width="${MAP_W}" height="${MAP_H}">\n${p}  <data encoding="csv">\n${csv(arr)}\n</data>\n </layer>`;
  const prp = (list) => `  <properties>\n${list.map(([k, v, t]) => `   <property name="${k}"${t ? ` type="${t}"` : ""} value="${v}"/>`).join("\n")}\n  </properties>\n`;
  const ysort = prp([["ysort", "true", "bool"]]);
  const above = (name) => prp([["above", "true", "bool"], ["roof_of", name]]);
  let lid = 1;
  const layers = [
    layer(lid++, "ground", L.ground),
    layer(lid++, "overlay", L.overlay),
    layer(lid++, "objects", L.objects, ysort),
    layer(lid++, "buildings", L.buildings, ysort),
    layer(lid++, "windows_lit", L.windows_lit, ysort),
    ...ALL_BUILDINGS.map((b) => layer(lid++, `roof_${b.name}`, L[`roof_${b.name}`], above(b.roof_of))),
    layer(lid++, "canopy", L.canopy, prp([["above", "true", "bool"]])),
    layer(lid++, "rotors", L.rotors, prp([["above", "true", "bool"]])), // the animated turbine rotors (their own layer so the big canopy layer stays static)
  ];
  const grp = (name, body) => ` <objectgroup id="${lid++}" name="${name}">${body ? `\n${body}` : ""}\n </objectgroup>`;
  const groups = [
    grp("collision", coll.join("\n")),
    grp("doors", doors.join("\n")),
    grp("interactables", interact.join("\n")),
    grp("spawns", spawns.join("\n")),
    grp("zones", zones.join("\n")),
    grp("surfaces", surfaces.join("\n")),
    grp("roofs", roofs.join("\n")),
    grp("lights", lights.join("\n")),
    grp("emitters", emitters.join("\n")),
    grp("triggers", triggers.join("\n")),
    grp("route", route.join("\n")),
    grp("edges", edgeObjs.join("\n")),
  ];

  return `<?xml version="1.0" encoding="UTF-8"?>
<!-- GENERATED by games/quebrada/tools/tilegen (make tiles): zone 1 rebuilt element by element (issue #78).
     ${MAP_W}x${MAP_H} tiles of ${SIZE} px, ${METRES_PER_TILE} m = 1 tile. Base: ${rep.lengthTiles} tiles (${rep.lengthMetres} m) paver street (cols ${rep.x0}-${rep.x1}, rows ${rep.y0}-${rep.y1}) with the
     church centred on it. Tilesets: town (firstgid 1), buildings (firstgid ${B_FIRSTGID}), park (firstgid ${PARK_FIRSTGID}), school (firstgid ${SCHOOL_FIRSTGID}), ebais (firstgid ${EBAIS_FIRSTGID}), monte (firstgid ${MONTE_FIRSTGID}) and rio (firstgid ${RIO_FIRSTGID}). Tile layers as in buildings_demo.tmx
     (ground, overlay, objects, buildings, windows_lit, roof_<name>, canopy) + rotors (above, animated turbine rotors). Object layers: collision, doors, interactables,
     spawns, zones, surfaces, roofs, lights, emitters, triggers (Chequelo night, see scripts/triggers.lua), route (the walk, ${walkPx} px),
     edges. See games/quebrada/docs/zona1.md. -->
<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" width="${MAP_W}" height="${MAP_H}" tilewidth="${SIZE}" tileheight="${SIZE}" infinite="0" nextlayerid="${lid}" nextobjectid="${nid}">
 <properties>
${prop("street_tiles", rep.lengthTiles, "int")}
${prop("metres_per_tile", METRES_PER_TILE, "int")}
${prop("px_per_metre", PX_PER_METRE, "int")}
${prop("walk_px", walkPx, "int")}
${prop("walk_speed", WALK_SPEED, "int")}
 </properties>
 <tileset firstgid="${TOWN_FIRSTGID}" source="../tilesets/town.tsx"/>
 <tileset firstgid="${B_FIRSTGID}" source="../tilesets/buildings.tsx"/>
 <tileset firstgid="${PARK_FIRSTGID}" source="../tilesets/park.tsx"/>
 <tileset firstgid="${SCHOOL_FIRSTGID}" source="../tilesets/school.tsx"/>
 <tileset firstgid="${EBAIS_FIRSTGID}" source="../tilesets/ebais.tsx"/>
 <tileset firstgid="${MONTE_FIRSTGID}" source="../tilesets/monte.tsx"/>
 <tileset firstgid="${RIO_FIRSTGID}" source="../tilesets/rio.tsx"/>
${layers.join("\n")}
${groups.join("\n")}
</map>
`;
}

/** Compose a picture of the map. opts: { night, roofs, triggers } (roofs defaults to true). triggers marks the street / door / spawns / edges. */
export function renderZona1({ night = false, roofs = true, triggers = false, glow = false } = {}, elements = ELEMENTS) {
  const town = renderSheet();
  const bsheet = renderBuildingSheet();
  const psheet = renderParkSheet();
  const ssheet = renderSchoolSheet();
  const esheet = renderEbaisSheet();
  const msheet = renderMonteSheet();
  const rsheet = renderRioSheet();
  const { L, turbines } = buildZona1(elements);
  const draw = (out, name) => {
    for (let i = 0; i < L[name].length; i++) {
      const g = L[name][i];
      if (!g) continue;
      const [sheet, id, cols] = g >= RIO_FIRSTGID ? [rsheet, g - RIO_FIRSTGID, R_COLS] : g >= MONTE_FIRSTGID ? [msheet, g - MONTE_FIRSTGID, M_COLS] : g >= EBAIS_FIRSTGID ? [esheet, g - EBAIS_FIRSTGID, E_COLS] : g >= SCHOOL_FIRSTGID ? [ssheet, g - SCHOOL_FIRSTGID, S_COLS] : g >= PARK_FIRSTGID ? [psheet, g - PARK_FIRSTGID, P_COLS] : g >= B_FIRSTGID ? [bsheet, g - B_FIRSTGID, B_COLS] : [town, g - TOWN_FIRSTGID, COLS];
      out.blit(sheet.slice((id % cols) * SIZE, Math.floor(id / cols) * SIZE, SIZE, SIZE), (i % MAP_W) * SIZE, Math.floor(i / MAP_W) * SIZE);
    }
  };
  const out = new Frame(MAP_W * SIZE, MAP_H * SIZE);
  for (const n of ["ground", "overlay", "objects", "buildings"]) draw(out, n);
  if (roofs) for (const b of ALL_BUILDINGS) draw(out, `roof_${b.name}`);
  draw(out, "canopy");
  draw(out, "rotors"); // the rotors at angle 0 (the game animates them)
  let img = out;
  if (night) {
    img = out.darkened(0.35);
    draw(img, "windows_lit");
    if (glow) { // red warning lights of the turbines (preview only): a soft halo of radius 20 px + the core
      for (const t of turbines) {
        const [lx, ly] = t.light;
        for (let y = ly - 20; y <= ly + 20; y++) for (let x = lx - 20; x <= lx + 20; x++) {
          const d = Math.hypot(x - lx, y - ly) / 20;
          if (d <= 1) img.px(x, y, [255, 60, 45, Math.round(110 * (1 - d) ** 2)]);
        }
        img.rect(lx - 1, ly - 1, 3, 2, [255, 120, 100, 255]);
      }
    }
  }
  if (triggers) {
    const rep = baseReport(elements);
    img.rect(rep.x0 * SIZE, rep.y0 * SIZE, rep.lengthTiles * SIZE, rep.width * SIZE, [60, 140, 255, 70]); // street
    img.line(rep.streetCentrePx, 0, rep.streetCentrePx, MAP_H * SIZE - 1, [255, 0, 0, 255]); // centre column
    const colors = { road: [60, 140, 255, 70], walk_start: [255, 220, 40, 120], light_appears: [255, 255, 255, 130], detour_cafetal: [255, 140, 0, 130], detour_door: [255, 60, 200, 130], house_arrival: [60, 255, 90, 130] };
    for (const t of triggerDefs()) for (const r of t.rects) img.rect(r.x, r.y, r.w, r.h, colors[t.id] ?? [255, 0, 0, 100]);
    for (let i = 1; i < ROUTE.length; i++) img.line(ROUTE[i - 1][0], ROUTE[i - 1][1], ROUTE[i][0], ROUTE[i][1], [255, 0, 0, 255]);
    for (const e of elements) {
      if (e.kind === "door") img.rect(e.x, e.y, e.w, e.h, [255, 255, 255, 200]);
      if (e.kind === "edge") img.rect(e.x, e.y, e.w, e.h, [255, 140, 0, 160]);
      if (e.kind === "interactable") img.rect(e.x, e.y, e.w, e.h, [255, 255, 255, 160]);
      if (e.kind === "spawn") img.rect(e.x - 2, e.y - 2, 4, 4, [60, 255, 90, 255]);
    }
  }
  return img;
}
