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
import { BUILDINGS, BUILDING_BY_NAME, B_COLS, B_ROWS, bIdByName, renderBuildingSheet } from "./catalog_buildings.mjs";
import { PARK_OBJECT_BY_NAME, CIRCLE_CELLS, pIdByName, P_COLS, renderParkSheet } from "./catalog_park.mjs";
import { Frame } from "./draw.mjs";
import { noise } from "./rng.mjs";

// ---- map size and scale ----
export const METRES_PER_TILE = 2; // compressed scale: 2 m = 1 tile
export const TILE = 16;
export const PX_PER_METRE = TILE / METRES_PER_TILE; // 8 px = 1 m
export const STREET_METRES = 100; // required: exactly 100 m
export const STREET_TILES = STREET_METRES / METRES_PER_TILE; // 50 tiles
// Orientation convention (the user's): WEST = RIGHT of the screen (increasing column), EAST = LEFT, SOUTH = bottom, NORTH = top.
// The main street grows west (to the right) from its original end at col 59: 550 m of paver (cement) then 200 m of lastre (earth).
export const EXT_PAVER_M = 550;
export const EXT_LASTRE_M = 200;
export const EXT_PAVER_TILES = EXT_PAVER_M / METRES_PER_TILE; // 275
export const EXT_LASTRE_TILES = EXT_LASTRE_M / METRES_PER_TILE; // 100
export const STREET_X = 10; // first column of the original 100 m street (the east asphalt street and its sidewalks are west of it, cols 4-9)
export const STREET_LEN = STREET_TILES;
export const EXT_X0 = STREET_X + STREET_LEN; // 60: first column of the extension (paver)
export const EXT_PAVER_X1 = EXT_X0 + EXT_PAVER_TILES - 1; // 334
export const EXT_LASTRE_X0 = EXT_PAVER_X1 + 1; // 335
export const EXT_LASTRE_X1 = EXT_LASTRE_X0 + EXT_LASTRE_TILES - 1; // 434: last street column (open end, edge marker)
export const MARGIN_E = 10; // grass margin to the right of the lastre end
export const MAP_W = EXT_LASTRE_X1 + 1 + MARGIN_E; // 445 tiles = 890 m
export const MAP_H = 72; // tiles = 144 m: church + street to the north, the park (37 rows) + its south street (rows 65-68) + 3 rows of margin
export const TOWN_FIRSTGID = 1;
export const B_FIRSTGID = COLS * ROWS + 1; // 145
export const PARK_FIRSTGID = B_FIRSTGID + B_COLS * B_ROWS; // 529 (town tilecount + buildings tilecount + 1)

// ---- base layout constants (tiles) ----
export const STREET_W = 4; // 4 tiles = ~8 m real at this scale (known distortion; kept for walkability)
export const STREET_Y = 21; // first street row (rows 21-24)
export const CHURCH_Y = 6; // church rows 6-17; hedges/doorstep row 18, path rows 18-20, street from row 21
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
export const EAST_X = 5, EAST_W = 4, EAST_X1 = EAST_X + EAST_W - 1; // 5..8
export const EAST_SW_FAR = EAST_X - 1, EAST_SW_PARK = EAST_X1 + 1; // 4, 9
export const EAST_LINE_X = 6; // double yellow centre line (the line tile is centred in its tile, so it sits in col 6 of the 4)
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
export const CAF_Y0 = 5, CAF_Y1 = 18; // fence rows 5 (north) and 18 (south, with the gap); soil rows 6-17 (12 deep = 24 m); verge row 19, sidewalk row 20
export const CAF_GAP = [308, 309]; // 2-tile gap in the south fence = the aisle (lastre) that meets the street's north sidewalk
// CASA DE MAMA at the end of the lastre, SOUTH of the street; CASA DE CHAYO (casa_2) 50 m = 25 tiles before it (centre to centre), also south.
// The building art faces SOUTH (door in the bottom wall): the door faces away from the street, so each house has a 2-tile lastre footpath
// from the street's south edge down its WEST side (one grass tile of gap beside the wall) to a lastre yard in front of the door.
export const MAMA_AT = [423, 27], CHAYO_AT = [399, 27];
export const MAMA_FOOT_X = MAMA_AT[0] + 8 + 1, CHAYO_FOOT_X = CHAYO_AT[0] + 6 + 1; // footpath first col (2 wide): wall + 1 gap tile
export const MAMA_DOOR_DX = 88, CHAYO_DOOR_DX = 48; // door centre, px from the building's left edge (as drawn)
// street lamps: on the grass outside each sidewalk (heads 2 rows above the base), clear of the church and the park path
// main street lamps: every 50 m = 25 tiles along the WHOLE street (original, paver extension and lastre), both sides: cols 10 + 25k
export const LAMP_EVERY_M = 50;
export const LAMP_EVERY = LAMP_EVERY_M / METRES_PER_TILE; // 25 tiles
export const LAMP_COLS = Array.from({ length: Math.floor((EXT_LASTRE_X1 - STREET_X) / LAMP_EVERY) + 1 }, (_, k) => STREET_X + LAMP_EVERY * k);
// posts that would collide are skipped (explicit, so nothing is hidden): the church path (cols 34-35, rows 18-20) takes the north post of col 35;
// the west street's park-side sidewalk (col 60, rows 25-64) takes the south post of col 60; the cafetal's fence and aisle take the north post of col 310.
export const LAMP_SKIP_N = [CHURCH_X + 5, ...Array.from({ length: Math.floor((EXT_LASTRE_X1 - STREET_X) / 25) + 1 }, (_, k) => STREET_X + 25 * k).filter((x) => x >= CAF_X0 && x <= CAF_X1)];
export const LAMP_SKIP_S = [WEST_SW_X];
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
const CAF_ROWS = [7, 10, 13, 16]; // cafeto rows (2 free rows between them)
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
  stampOf("cancha_pintura_azul", "ground", [[40, 57], [41, 57], [40, 58], [41, 58], [55, 57], [56, 57], [55, 58], [56, 58]].map(([x, y], i) => ({ name: i % 2 ? "park_court_blue_b" : "park_court_blue_a", at: [x, y] }))),
  { id: "cancha_lineas", kind: "court_lines", rect: [39, 54, 57, 61], centre: 48, boxes: [[39, 56, 42, 59], [54, 56, 57, 59]], circle: [45, 54] },
  { id: "cancha_aro_oeste", kind: "object", name: "park_hoop_l", at: [40, 57] },
  { id: "cancha_aro_este", kind: "object", name: "park_hoop_r", at: [56, 57] },
  { id: "cancha_arco_oeste", kind: "object", name: "park_goal_l", at: [38, 55] },
  { id: "cancha_arco_este", kind: "object", name: "park_goal_r", at: [58, 55] },
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
  { id: "rumor_cafetal", kind: "emitter", name: "rumor_cafetal", x: (CAF_GAP[0] + 1) * SIZE, y: 12 * SIZE, props: {
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
  if (extTotalTiles * METRES_PER_TILE !== EXT_PAVER_M + EXT_LASTRE_M) throw new Error("zona1: the extension must total 750 m");
  return {
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
    { id: "walk_start", rects: [{ x: CHURCH_PX_X - 32, y: 272, w: 64, h: 48 }], requires: "mission.chequelo.accepted", sets: "chequelo.walk_started" },
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
/** gid of a tile by name in any of the three sheets (park_ names live in the park sheet, buildings names in buildings). */
const anyGid = (name) => (name.startsWith("park_") ? pgid(name) : byName.has(name) ? gid(name) : bgid(name));
const pick = (names, x, y, salt = "pk") => names[Math.floor(noise(salt, x, y) * names.length) % names.length];

const LAYER_ORDER = ["ground", "overlay", "objects", "buildings", "windows_lit", ...BUILDINGS.map((b) => `roof_${b.name}`), "canopy"];
const SURFACE_MAT = { paver: "p", lastre: "l", sidewalk: "w", asphalt: "a" };
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
    } else if (e.kind === "diag") { // staircase band: for each column, `thick` rows around the centreline
      const half = Math.floor(e.thick / 2);
      for (let c = Math.min(e.c0, e.c1); c <= Math.max(e.c0, e.c1); c++) {
        const yc = e.centre(c);
        for (let y = yc - half; y <= yc - half + e.thick - 1; y++) setMat(c, y, matOf(e));
      }
    }
  }
  const isGrass = (x, y) => inb(x, y) && mat[y][x] === "g";
  const isLastre = (x, y) => inb(x, y) && mat[y][x] === "l";

  for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
    const m = mat[y][x];
    let name;
    if (m === "g") {
      const r = noise("gv", x, y);
      name = r < 0.05 ? "grass_flowers" : r < 0.08 ? "grass_dry" : r < 0.1 ? "grass_dirt" : pick(["grass_a", "grass_b", "grass_c", "grass_d"], x, y);
    } else if (m === "p") {
      name = noise("pv", x >> 1, y) < 0.1 ? "paver_b" : "paver_a";
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
        name = diag ? `lastre_inner_${diag[0].toLowerCase()}` : (noise("lr", x, y) < 0.12 ? "lastre_b" : "lastre_ruts_h"); // wheel ruts along the road
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
    const b = BUILDING_BY_NAME.get(e.name);
    if (!b) throw new Error(`element ${e.id}: unknown building ${e.name}`);
    const [ox, oy] = e.at;
    for (const c of b.cells) {
      if (c.layer === "above") bput(`roof_${b.name}`, ox + c.cx, oy + c.cy, c.name);
      else bput("buildings", ox + c.cx, oy + c.cy, c.name);
    }
    for (const c of b.lit) bput("windows_lit", ox + c.cx, oy + c.cy, c.name);
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
    const o = PARK_OBJECT_BY_NAME.get(e.name);
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
  for (const { kind, at: [cx, cy] } of treeEls) {
    needFree(`${kind} tree`, cx, cy);
    put("objects", cx, cy, `${kind}_${TREE_PART[kind]}`);
    for (let j = 0; j < 2; j++) for (let i = 0; i < 3; i++) put("canopy", cx - 1 + i, cy - 2 + j, `${kind}_canopy_${i}_${j}`);
    if (kind !== "palm") {
      if (isGrass(cx - 1, cy)) put("overlay", cx - 1, cy, "shadow_blob");
      if (isGrass(cx + 1, cy)) put("overlay", cx + 1, cy, "shadow_blob");
    }
    if (isGrass(cx, cy + 1)) put("overlay", cx, cy + 1, "fallen_leaves");
  }
  for (const e of elements.filter((e) => e.kind === "prop")) {
    needFree(e.name, e.at[0], e.at[1]);
    put("objects", e.at[0], e.at[1], e.name);
  }
  let nScatter = 0;
  for (const e of elements.filter((e) => e.kind === "scatter")) { // props on random free grass cells (seeded)
    const [x0, y0, x1, y1] = e.rect;
    for (let i = 0, n = 0; i < e.count * 8 && n < e.count; i++) {
      const x = x0 + Math.floor(noise(e.seed + "x", i, 0) * (x1 - x0 + 1)), y = y0 + Math.floor(noise(e.seed + "y", i, 1) * (y1 - y0 + 1));
      if (!treeFree(x, y) || L.canopy[at(x, y)] !== 0) continue;
      put("objects", x, y, e.name); n++; nScatter++;
    }
  }
  return { L, placed, lamps };
}

// ---------------------------------------------------------------- TMX
function csv(arr) {
  const rows = [];
  for (let y = 0; y < MAP_H; y++) rows.push(arr.slice(y * MAP_W, (y + 1) * MAP_W).join(","));
  return rows.join(",\n");
}

const prop = (name, value, type) => `    <property name="${name}"${type ? ` type="${type}"` : ""} value="${value}"/>`;

// ---- generation-time collision-trap check: flood fill (tile resolution) from the church spawn over every non-solid tile ----
function checkWalkable(L, placed, defs) {
  const solidGids = new Set([...TILES.filter((t) => t.solid).map((t) => t.id + TOWN_FIRSTGID)]);
  const blocked = new Uint8Array(MAP_W * MAP_H);
  for (let i = 0; i < blocked.length; i++) if (solidGids.has(L.objects[i])) blocked[i] = 1;
  for (const p of placed) { // footprint rows (same rect as the collision object)
    const [r0, r1] = p.b.footRows;
    for (let y = p.oy + r0; y < p.oy + r1; y++) for (let x = p.ox; x < p.ox + p.b.w; x++) blocked[y * MAP_W + x] = 1;
  }
  const seen = new Uint8Array(MAP_W * MAP_H);
  const start = [Math.floor(CHURCH_PX_X / SIZE), Math.floor(308 / SIZE)];
  const q = [start]; seen[start[1] * MAP_W + start[0]] = 1;
  while (q.length) {
    const [x, y] = q.pop();
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= MAP_W || ny >= MAP_H || seen[ny * MAP_W + nx] || blocked[ny * MAP_W + nx]) continue;
      seen[ny * MAP_W + nx] = 1; q.push([nx, ny]);
    }
  }
  const reach = (r) => { // is any tile of the px rect reachable?
    for (let y = Math.floor(r.y / SIZE); y <= Math.floor((r.y + r.h - 1) / SIZE); y++) for (let x = Math.floor(r.x / SIZE); x <= Math.floor((r.x + r.w - 1) / SIZE); x++) if (seen[y * MAP_W + x]) return true;
    return false;
  };
  const tile = (px, py) => seen[Math.floor(py / SIZE) * MAP_W + Math.floor(px / SIZE)] === 1;
  const must = [["mama's door front", tile(MAMA_X, MAMA_DOOR_Y + 8)], ["exit_mama spawn", tile(MAMA_X, MAMA_DOOR_Y + 24)], ["chayo's door front", tile(CHAYO_X, CHAYO_DOOR_Y + 8)],
    ["cafetal gap", tile(CAF_GAP[0] * SIZE + 8, CAF_Y1 * SIZE + 8) && tile(CAF_GAP[1] * SIZE + 8, CAF_Y1 * SIZE + 8)], ["cafetal aisle (inside)", tile(CAF_GAP[0] * SIZE + 8, 8 * SIZE)],
    ["footpath mama", tile(MAMA_FOOT_X * SIZE + 8, 30 * SIZE) && tile((MAMA_FOOT_X + 1) * SIZE + 8, 30 * SIZE)], ["footpath chayo", tile(CHAYO_FOOT_X * SIZE + 8, 28 * SIZE) && tile((CHAYO_FOOT_X + 1) * SIZE + 8, 28 * SIZE)]];
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
  const { L, placed, lamps: lampPosts } = buildZona1(elements);
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
  const zones = of("zone").map((e) => obj(`zone_${e.zone}`, "zone", e, [prop("zone", e.zone), prop("title", e.title), prop("ambience", e.ambience)]));
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
  checkWalkable(L, placed, triggerDefs());

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
  }

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
    ...BUILDINGS.map((b) => layer(lid++, `roof_${b.name}`, L[`roof_${b.name}`], above(b.roof_of))),
    layer(lid++, "canopy", L.canopy, prp([["above", "true", "bool"]])),
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
     church centred on it. Tilesets: town (firstgid 1), buildings (firstgid ${B_FIRSTGID}) and park (firstgid ${PARK_FIRSTGID}). Tile layers as in buildings_demo.tmx
     (ground, overlay, objects, buildings, windows_lit, roof_<name>, canopy). Object layers: collision, doors, interactables,
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
${layers.join("\n")}
${groups.join("\n")}
</map>
`;
}

/** Compose a picture of the map. opts: { night, roofs, triggers } (roofs defaults to true). triggers marks the street / door / spawns / edges. */
export function renderZona1({ night = false, roofs = true, triggers = false } = {}, elements = ELEMENTS) {
  const town = renderSheet();
  const bsheet = renderBuildingSheet();
  const psheet = renderParkSheet();
  const { L } = buildZona1(elements);
  const draw = (out, name) => {
    for (let i = 0; i < L[name].length; i++) {
      const g = L[name][i];
      if (!g) continue;
      const [sheet, id, cols] = g >= PARK_FIRSTGID ? [psheet, g - PARK_FIRSTGID, P_COLS] : g >= B_FIRSTGID ? [bsheet, g - B_FIRSTGID, B_COLS] : [town, g - TOWN_FIRSTGID, COLS];
      out.blit(sheet.slice((id % cols) * SIZE, Math.floor(id / cols) * SIZE, SIZE, SIZE), (i % MAP_W) * SIZE, Math.floor(i / MAP_W) * SIZE);
    }
  };
  const out = new Frame(MAP_W * SIZE, MAP_H * SIZE);
  for (const n of ["ground", "overlay", "objects", "buildings"]) draw(out, n);
  if (roofs) for (const b of BUILDINGS) draw(out, `roof_${b.name}`);
  draw(out, "canopy");
  let img = out;
  if (night) {
    img = out.darkened(0.35);
    draw(img, "windows_lit");
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
