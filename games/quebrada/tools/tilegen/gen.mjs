// Procedural town tileset + buildings generator (issues #55, #71).
//   node gen.mjs                 write tilesets/town.{png,tsx}, maps/tiles_demo.tmx, tilesets/buildings.{png,tsx}, tilesets/ebais.{png,tsx}, tilesets/monte.{png,tsx} (and park, school),
//                                maps/buildings_demo.tmx, maps/house_mama.tmx (interior of mama's house) and
//                                maps/zona1.tmx (zone 1, issue #78: church + 100 m paver street at 2 m = 1 tile (50 tiles);
//                                prints the metres-per-tile scale, the street length in tiles / metres and the church centring check)
//   node gen.mjs --check         regenerate in memory and compare with the files on disk (exit 1 on drift)
//   node gen.mjs --preview DIR   write sheet_x4.png, demo_map.png, demo_map_night.png, buildings_sheet_x4.png,
//                                buildings_demo{,_noroof,_night}.png, house_mama.png, crop_iglesia_x4.png and
//                                crop_casa_mama_x4.png, park_sheet_x4.png, zona1_park_x2.png, zona1_street_x2.png, zona1.png, zona1_night.png and zona1_triggers.png into DIR
//                                plus the Ebais previews: ebais_sheet_x4.png, crop_ebais_edificio_x4.png, zona1_ebais{,_night,_noroof,_triggers}_x2.png, zona1_lastre_sur_x2.png
//                                plus the monte previews: monte_sheet_x4.png, crop_turbine_x4.png, zona1_cruce_monte_x2.png (the cross junction), zona1_borde_monte_x2.png (the forest edge),
//                                zona1_claro_x2.png (a turbine clearing), zona1_claro_noche_x2.png (night, red lights), zona1_monte_x1.png (the whole monte), zona1_monte_arboles_x2.png, zona1_borde_izq_x2.png
//                                (never committed)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { encodePng } from "./png.mjs";
import { Frame, rgb } from "./draw.mjs";
import { GLYPHS, drawText, ADVANCE } from "./font.mjs";
import { renderSheet, TILES } from "./catalog.mjs";
import { buildTsx, buildTsxFor } from "./tsx.mjs";
import { buildTmx, renderMap } from "./demo_map.mjs";
import { renderBuildingSheet, B_TILES, B_COLS, B_ROWS, buildingCanvas } from "./catalog_buildings.mjs";
import { renderParkSheet, PARK_TILES, P_COLS, P_ROWS } from "./catalog_park.mjs";
import { buildZona1ConstsLua } from "./zona1_consts.mjs";
import { renderSchoolSheet, S_TILES, S_COLS, S_ROWS, schoolBuildingCanvas } from "./catalog_school.mjs";
import { renderEbaisSheet, E_TILES, E_COLS, E_ROWS, ebaisBuildingCanvas } from "./catalog_ebais.mjs";
import { renderMonteSheet, M_TILES, M_COLS, M_ROWS, turbineCanvas, MONTE_TILE_COUNT, MONTE_ROTOR_TILE_COUNT } from "./catalog_monte.mjs";
import { renderRioSheet, R_TILES, R_COLS, R_ROWS, RIO_TILE_COUNT } from "./catalog_rio.mjs";
import { renderVidaSheet, V_TILES, V_COLS, V_ROWS, VIDA_TILE_COUNT } from "./catalog_vida.mjs";
import { buildTmx as buildBuildingsTmx, renderBuildingsMap } from "./buildings_map.mjs";
import { buildTmx as buildInteriorTmx, buildPaulaTmx, renderInterior } from "./interior_map.mjs";
import { POTRERO, MAMA_AT, BERTA_X, CALILES_X, SIDEWALK_N_Y, COL_X0, COL_Y0, COL_W, COL_H, CAF_Y0, buildTmx as buildZona1Tmx, renderZona1, baseReport, routeLength, pointAt, WALK_SPEED, RUN_SPEED, MAP_W, MAP_H, EXT_PAVER_X1, EXT_LASTRE_X1, LEFT_PAD, SCHOOL_FIRSTGID, EBAIS_FIRSTGID, MONTE_FIRSTGID, RIO_FIRSTGID, TOP_PAD, BRIDGE, RIVER, RIVER_ZONES, RIVER_CHURCH_M, RIVER_CAFETAL_M, RIVER_MAMA_M, MONTE_REPORT, MONTE_X0, MONTE_X1, MONTE_W, ROAD_X1, ROAD_Y0, TRAIL_X0, TRAIL_Y0, TRAIL_LEN, TURBINE_AT, TURBINE_BBOX, EB_X0, EB_X1, EB_Y0, EB_Y1, EB_AT, PLOT_X0, PLOT_X1, ESC_Y0, ESC_Y1, OLG_Y0, OLG_AT, ESC_A_AT, ESC_B_AT, ESC_GATE, OLG_GATE } from "./zona1_map.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const game = resolve(here, "..", "..");
const out = {
  png: join(game, "tilesets", "town.png"),
  tsx: join(game, "tilesets", "town.tsx"),
  tmx: join(game, "maps", "tiles_demo.tmx"),
  bpng: join(game, "tilesets", "buildings.png"),
  btsx: join(game, "tilesets", "buildings.tsx"),
  ppng: join(game, "tilesets", "park.png"),
  ptsx: join(game, "tilesets", "park.tsx"),
  spng: join(game, "tilesets", "school.png"),
  stsx: join(game, "tilesets", "school.tsx"),
  epng: join(game, "tilesets", "ebais.png"),
  etsx: join(game, "tilesets", "ebais.tsx"),
  mpng: join(game, "tilesets", "monte.png"),
  mtsx: join(game, "tilesets", "monte.tsx"),
  rpng: join(game, "tilesets", "rio.png"),
  rtsx: join(game, "tilesets", "rio.tsx"),
  vpng: join(game, "tilesets", "vida.png"),
  vtsx: join(game, "tilesets", "vida.tsx"),
  btmx: join(game, "maps", "buildings_demo.tmx"),
  house: join(game, "maps", "house_mama.tmx"),
  housePaula: join(game, "maps", "house_paula.tmx"),
  zona1: join(game, "maps", "zona1.tmx"),
  consts: join(game, "tests", "zona1_consts.lua"),
};

const pngOf = (f) => encodePng(f.w, f.h, f.data);
const products = () => [
  [out.png, pngOf(renderSheet())],
  [out.tsx, Buffer.from(buildTsx())],
  [out.tmx, Buffer.from(buildTmx())],
  [out.bpng, pngOf(renderBuildingSheet())],
  [out.btsx, Buffer.from(buildTsxFor({ name: "buildings", image: "buildings.png", tiles: B_TILES, cols: B_COLS, rows: B_ROWS }))],
  [out.ppng, pngOf(renderParkSheet())],
  [out.ptsx, Buffer.from(buildTsxFor({ name: "park", image: "park.png", tiles: PARK_TILES, cols: P_COLS, rows: P_ROWS }))],
  [out.spng, pngOf(renderSchoolSheet())],
  [out.stsx, Buffer.from(buildTsxFor({ name: "school", image: "school.png", tiles: S_TILES, cols: S_COLS, rows: S_ROWS }))],
  [out.epng, pngOf(renderEbaisSheet())],
  [out.etsx, Buffer.from(buildTsxFor({ name: "ebais", image: "ebais.png", tiles: E_TILES, cols: E_COLS, rows: E_ROWS }))],
  [out.mpng, pngOf(renderMonteSheet())],
  [out.mtsx, Buffer.from(buildTsxFor({ name: "monte", image: "monte.png", tiles: M_TILES, cols: M_COLS, rows: M_ROWS }))],
  [out.rpng, pngOf(renderRioSheet())],
  [out.rtsx, Buffer.from(buildTsxFor({ name: "rio", image: "rio.png", tiles: R_TILES, cols: R_COLS, rows: R_ROWS }))],
  [out.vpng, pngOf(renderVidaSheet())],
  [out.vtsx, Buffer.from(buildTsxFor({ name: "vida", image: "vida.png", tiles: V_TILES, cols: V_COLS, rows: V_ROWS }))],
  [out.consts, Buffer.from(buildZona1ConstsLua())],
  [out.btmx, Buffer.from(buildBuildingsTmx())],
  [out.house, Buffer.from(buildInteriorTmx())],
  [out.housePaula, Buffer.from(buildPaulaTmx())],
  [out.zona1, Buffer.from(buildZona1Tmx())],
];

/** The river previews (day + night crops x2 of the river at the church, the cafetal, mama's house, the bridge, inside the monte; the whole map downscaled; the rio sheet x4). */
function riverPreviews(dir, day, night) {
  const T = TOP_PAD, A = RIVER.anchors;
  const clip = (img, name, c, r, w, h, k = 2) => {
    const c0 = Math.max(0, c), r0 = Math.max(0, r), c1 = Math.min(MAP_W, c + w), r1 = Math.min(MAP_H, r + h);
    writeFileSync(join(dir, name), pngOf(img.slice(c0 * 16, r0 * 16, (c1 - c0) * 16, (r1 - r0) * 16).scaled(k)));
  };
  const cen = (col) => Math.round(RIVER.centre(col)) + T; // centre row of the river at a column
  const [church, cafetal, mama] = A;
  clip(day, "rio_iglesia_x2.png", church.col - 30, cen(church.col) - 10, 60, 22);
  clip(day, "rio_iglesia_distancia_x1.png", church.col - 25, cen(church.col) - 8, 50, church.top + T + 14 - cen(church.col) + 8, 1); // the river, the 88 rows of land and the church
  clip(day, "rio_cafetal_x2.png", cafetal.col - 30, cen(cafetal.col) - 10, 60, cafetal.top + T + 16 - cen(cafetal.col) + 10);
  clip(day, "rio_mama_x2.png", mama.col - 40, cen(mama.col) - 10, 60, mama.top + T + 10 - cen(mama.col) + 10);
  clip(day, "rio_puente_x2.png", BRIDGE.pierW - 12, BRIDGE.rb0 - 8, 32, BRIDGE.rb1 - BRIDGE.rb0 + 17);
  clip(night, "rio_puente_noche_x2.png", BRIDGE.pierW - 12, BRIDGE.rb0 - 8, 32, BRIDGE.rb1 - BRIDGE.rb0 + 17);
  clip(day, "rio_puente_x4.png", BRIDGE.pierW - 3, BRIDGE.rb0 - 3, 16, BRIDGE.rb1 - BRIDGE.rb0 + 7, 4);
  clip(day, "rio_monte_x2.png", 0, cen(40) - 14, 100, 30);
  clip(night, "rio_monte_noche_x2.png", 0, cen(40) - 14, 100, 30);
  clip(day, "rio_curva_x2.png", 380, cen(420) - 14, 90, 30);
  writeFileSync(join(dir, "rio_sheet_x4.png"), pngOf(renderRioSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  writeFileSync(join(dir, "rio_mapa_x1.png"), pngOf(day.slice(0, 0, MAP_W * 16, (cen(cafetal.col) + 30) * 16).scaled(1)));
}

const args = process.argv.slice(2);
if (args.includes("--check")) {
  let bad = 0;
  for (const [path, data] of products()) {
    if (!existsSync(path) || !readFileSync(path).equals(data)) {
      console.error(`tilegen: ${path} is out of date (run: make tiles)`);
      bad++;
    }
  }
  if (bad) process.exit(1);
  console.log(`tilegen: ${TILES.length} town + ${B_TILES.length} buildings + ${PARK_TILES.length} park + ${S_TILES.length} school + ${E_TILES.length} ebais + ${M_TILES.length} monte + ${V_TILES.length} vida tiles up to date`);
} else if (args.includes("--rio-preview")) { // only the river previews (faster than --preview)
  const dir = resolve(args[args.indexOf("--rio-preview") + 1] ?? ".");
  mkdirSync(dir, { recursive: true });
  riverPreviews(dir, renderZona1({ night: false, roofs: true }), renderZona1({ night: true, roofs: true }));
  console.log(`tilegen: river previews in ${dir}`);
} else if (args.includes("--preview")) {
  const dir = resolve(args[args.indexOf("--preview") + 1] ?? ".");
  mkdirSync(dir, { recursive: true });
  const bg = [255, 0, 255, 255].map((v, i) => (i === 3 ? 255 : v === 255 ? 70 : 70));
  const sheet = renderSheet();
  writeFileSync(join(dir, "sheet_x4.png"), pngOf(sheet.onBackground([60, 60, 70, 255]).scaled(4)));
  writeFileSync(join(dir, "demo_map.png"), pngOf(renderMap(false).scaled(2)));
  writeFileSync(join(dir, "demo_map_night.png"), pngOf(renderMap(true).scaled(2)));
  writeFileSync(join(dir, "buildings_sheet_x4.png"), pngOf(renderBuildingSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  writeFileSync(join(dir, "buildings_demo.png"), pngOf(renderBuildingsMap({ night: false, roofs: true }).scaled(2)));
  writeFileSync(join(dir, "buildings_demo_noroof.png"), pngOf(renderBuildingsMap({ night: false, roofs: false }).scaled(2)));
  writeFileSync(join(dir, "buildings_demo_night.png"), pngOf(renderBuildingsMap({ night: true, roofs: true }).scaled(2)));
  writeFileSync(join(dir, "house_mama.png"), pngOf(renderInterior().scaled(4)));
  writeFileSync(join(dir, "house_paula.png"), pngOf(renderInterior("casa_paula").scaled(4)));
  const grass = [96, 150, 70, 255];
  writeFileSync(join(dir, "vida_sheet_x4.png"), pngOf(renderVidaSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  { // every glyph of the shared font, x8
    const keys = Object.keys(GLYPHS), per = 16, f = new Frame(per * ADVANCE + 2, Math.ceil(keys.length / per) * 7 + 2);
    keys.forEach((k, i) => drawText(f, k === " " ? "-" : k, 1 + (i % per) * ADVANCE, 1 + Math.floor(i / per) * 7, rgb("#f1f1ec")));
    writeFileSync(join(dir, "font_x8.png"), pngOf(f.onBackground([40, 60, 110, 255]).scaled(8)));
  }
  writeFileSync(join(dir, "crop_iglesia_x4.png"), pngOf(buildingCanvas("iglesia").day.onBackground(grass).scaled(4)));
  for (const n of ["abastecedor", "bar", "guarderia"]) writeFileSync(join(dir, `crop_${n}_x4.png`), pngOf(buildingCanvas(n).day.onBackground(grass).scaled(4)));
  writeFileSync(join(dir, "crop_casa_mama_x4.png"), pngOf(buildingCanvas("casa_mama").day.onBackground(grass).scaled(4)));
  writeFileSync(join(dir, "zona1.png"), pngOf(renderZona1({ night: false, roofs: true })));
  writeFileSync(join(dir, "zona1_night.png"), pngOf(renderZona1({ night: true, roofs: true })));
  writeFileSync(join(dir, "park_sheet_x4.png"), pngOf(renderParkSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  const z1 = renderZona1({ night: false, roofs: true });
  riverPreviews(dir, z1, renderZona1({ night: true, roofs: true }));
  const P = LEFT_PAD; // the crops below are in original columns; P shifts them
  const T = TOP_PAD; // ... and in original rows: T shifts them
  writeFileSync(join(dir, "zona1_park_x2.png"), pngOf(z1.slice((9 + P) * 16, (18 + T) * 16, 52 * 16, 48 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_street_x2.png"), pngOf(z1.slice((9 + P) * 16, (4 + T) * 16, 52 * 16, 28 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_triggers.png"), pngOf(renderZona1({ night: false, roofs: false, triggers: true })));
  // street-network crops (tile rectangles [col, row, cols, rows], x2): east asphalt street + main street + park corner, the paver -> lastre joint,
  // the SE corner (south street + west street), the main street / west street T junction, the lastre end, the asphalt/south street mouth
  const crop = (name, c, r, w, h) => writeFileSync(join(dir, `zona1_${name}_x2.png`), pngOf(z1.slice(c * 16, r * 16, w * 16, h * 16).scaled(2)));
  crop("junction_este", P, 14 + T, 24, 20);
  crop("joint_lastre", EXT_PAVER_X1 - 12, 14 + T, 26, 16);
  crop("esquina_se", 50 + P, 56 + T, 22, 16);
  crop("junction_oeste", 52 + P, 14 + T, 22, 18);
  crop("fin_lastre", EXT_LASTRE_X1 - 20, 14 + T, 31, 16);
  crop("boca_sur", P, 58 + T, 24, 14);
  // the Chequelo places: the cafetal with the street, and the east end (Chayo's and mama's houses) with and without the trigger overlay
  crop("cafetal", 290 + P, 2 + T, 40, 26);
  // the Colegio across the street from the cafetal (x2): day, no roofs, night, interactables overlay
  const col = (img, name) => writeFileSync(join(dir, name), pngOf(img.slice((COL_X0 - 6) * 16, (CAF_Y0 - 2) * 16, (COL_W + 12) * 16, (COL_Y0 + COL_H + 3 - CAF_Y0 + 2) * 16).scaled(2)));
  col(z1, "zona1_colegio_x2.png");
  col(renderZona1({ night: false, roofs: false }), "zona1_colegio_noroof_x2.png");
  col(renderZona1({ night: true, roofs: true }), "zona1_colegio_night_x2.png");
  writeFileSync(join(dir, "crop_escuela_colegio_x4.png"), pngOf(schoolBuildingCanvas("escuela_colegio").day.onBackground(grass).scaled(4)));
  // the main street's shops and houses (x2): Berta .. Isabel, Carmen .. Los Machillos, and Los Caliles + Tío Enrique
  const stR = SIDEWALK_N_Y - 12;
  for (const [nm, c0, w] of [["pueblo_1", BERTA_X - 4, 56], ["pueblo_2", BERTA_X + 50, 76]]) crop(nm, c0, stR, w, 36);
  crop("caliles", CALILES_X - 14, stR, 66, 70);
  writeFileSync(join(dir, "zona1_cables_x2.png"), pngOf(z1.slice((BERTA_X + 124) * 16, (SIDEWALK_N_Y - 8) * 16, 100 * 16, 22 * 16).scaled(2))); // the cables between the lamps of the lastre
  crop("potrero", POTRERO.x0 - 6, POTRERO.y0 - 4, POTRERO.x1 - POTRERO.x0 + 13, SIDEWALK_N_Y - POTRERO.y0 + 10); // the fenced potrero north of the street
  crop("bananal", BERTA_X + 60 - 6, SIDEWALK_N_Y - 24, 36, 30);
  crop("tierra_sur", BERTA_X + 10, SIDEWALK_N_Y + 34, 100, 40); // the scrub and trees behind the shops
  // Casa de Abuela Paula y Abuelo Pepe, across the street from mama's house (x2) + the building at x4
  crop("paula", MAMA_AT[0] - 12, SIDEWALK_N_Y - 18, 34, 36);
  writeFileSync(join(dir, "crop_casa_paula_x4.png"), pngOf(buildingCanvas("casa_paula").day.onBackground(grass).scaled(4)));
  crop("casas_oeste", 388 + P, 17 + T, 57, 22);
  const trg = renderZona1({ night: false, roofs: false, triggers: true });
  writeFileSync(join(dir, "zona1_triggers_casas_x2.png"), pngOf(trg.slice((388 + P) * 16, (17 + T) * 16, 57 * 16, 22 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_triggers_cafetal_x2.png"), pngOf(trg.slice((290 + P) * 16, (2 + T) * 16, 40 * 16, 26 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_night_casas_x2.png"), pngOf(renderZona1({ night: true, roofs: true }).slice((388 + P) * 16, (17 + T) * 16, 57 * 16, 22 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_street_night_x2.png"), pngOf(renderZona1({ night: true, roofs: true }).slice(P * 16, (14 + T) * 16, 90 * 16, 20 * 16).scaled(2)));
  // school + Casa de Olguita: x2 crops with the asphalt street (day, night, triggers/interactables overlay), the sheet x4 and the buildings
  writeFileSync(join(dir, "school_sheet_x4.png"), pngOf(renderSchoolSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  writeFileSync(join(dir, "crop_escuela_aulas_a_x4.png"), pngOf(schoolBuildingCanvas("escuela_aulas_a").day.onBackground(grass).scaled(4)));
  const sc = (img, name) => writeFileSync(join(dir, name), pngOf(img.slice(0, (OLG_Y0 - 3) * 16, (PLOT_X1 + 12) * 16, (ESC_Y1 - OLG_Y0 + 7) * 16).scaled(2)));
  sc(z1, "zona1_escuela_x2.png");
  sc(renderZona1({ night: true, roofs: true }), "zona1_escuela_night_x2.png");
  sc(trg, "zona1_escuela_triggers_x2.png");
  sc(renderZona1({ night: false, roofs: false }), "zona1_escuela_noroof_x2.png");
  // Ebais: the plot with the south street and the lastre continuation (day, night), the sheet x4 and the building
  const eb = (img, name) => writeFileSync(join(dir, name), pngOf(img.slice((EB_X0 - 5) * 16, (EB_Y0 - 8) * 16, (EB_X1 - EB_X0 + 1 + 5 + 9) * 16, (EB_Y1 - EB_Y0 + 1 + 8 + 3) * 16).scaled(2)));
  crop("lastre_sur", EB_X1 - 6, 60 + T, 16, MAP_H - 60 - T); // the south street / west street corner and the lastre continuation down to the bottom edge
  eb(z1, "zona1_ebais_x2.png");
  eb(renderZona1({ night: true, roofs: true }), "zona1_ebais_night_x2.png");
  eb(renderZona1({ night: false, roofs: false }), "zona1_ebais_noroof_x2.png");
  eb(trg, "zona1_ebais_triggers_x2.png");
  writeFileSync(join(dir, "ebais_sheet_x4.png"), pngOf(renderEbaisSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  writeFileSync(join(dir, "crop_ebais_edificio_x4.png"), pngOf(ebaisBuildingCanvas("ebais_edificio").day.onBackground(grass).scaled(4)));
  // the monte: the sheet x4, a whole turbine x4, the cross junction, the forest edge, a clearing (day + night with the red lights), the whole monte, a dense stretch
  writeFileSync(join(dir, "monte_sheet_x4.png"), pngOf(renderMonteSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  writeFileSync(join(dir, "crop_turbine_x4.png"), pngOf(turbineCanvas(0).frame.onBackground(grass).scaled(4)));
  crop("cruce_monte", ROAD_X1 - 14, 14 + T, 36, 16); // the cross junction of the east road with the asphalt street
  const mx0 = MONTE_X1 - 24; // right border of the monte (the forest edge, seen from the road side); the left border is at MONTE_X0
  crop("borde_monte", mx0 - 5, 6 + T, 36, 32);
  crop("borde_izq", 0, 6 + T, 36, 32); // the left end of the map: the monte's far border + the road leaving the map
  const [cx0, cy0] = TURBINE_AT[1];
  crop("claro", cx0 - 15, T, 30, 36); // the clearing of aerogenerador_2 (north side)
  const nz = renderZona1({ night: true, roofs: true, glow: true });
  writeFileSync(join(dir, "zona1_claro_noche_x2.png"), pngOf(nz.slice((TURBINE_AT[4][0] - 20) * 16, (6 + T) * 16, 40 * 16, 40 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_monte_x1.png"), pngOf(z1.slice(0, 0, (MONTE_X1 + 12) * 16, MAP_H * 16)));
  writeFileSync(join(dir, "zona1_monte_arboles_x2.png"), pngOf(z1.slice((MONTE_X0 + 12) * 16, (44 + T) * 16, 34 * 16, 40 * 16).scaled(2)));
  console.log(`tilegen: previews in ${dir}`);
} else {
  for (const [path, data] of products()) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, data);
    console.log(`tilegen: wrote ${path} (${data.length} bytes)`);
  }
  console.log(`tilegen: ${TILES.length} town + ${B_TILES.length} buildings + ${PARK_TILES.length} park + ${S_TILES.length} school + ${E_TILES.length} ebais + ${MONTE_TILE_COUNT} monte + ${VIDA_TILE_COUNT} vida tiles (ebais firstgid ${EBAIS_FIRSTGID}, monte firstgid ${MONTE_FIRSTGID})`);
  const r = baseReport(); // throws if the street is not 50 tiles = 100 m or the church is not centred on it
  console.log(`tilegen: zona1 ${MAP_W}x${MAP_H} tiles; scale ${r.metresPerTile} m = 1 tile; street ${r.lengthTiles} tiles = ${r.lengthMetres} m (cols ${r.x0}-${r.x1}, rows ${r.y0}-${r.y1}, ${r.width} wide)`);
  console.log(`tilegen: zona1 extension west (to the right): paver cols ${r.ext.paverX0}-${r.ext.paverX1} = ${r.ext.paverTiles} t = ${r.ext.paverMetres} m, lastre cols ${r.ext.lastreX0}-${r.ext.lastreX1} = ${r.ext.lastreTiles} t = ${r.ext.lastreMetres} m, total ${r.ext.totalTiles} t = ${r.ext.totalMetres} m`);
  const len = routeLength(), half = pointAt(len / 2); // reported only (the user's layout is longer than the old ~60 s target)
  console.log(`tilegen: zona1 Chequelo route ${len} px = ${(len / 16).toFixed(0)} tiles = ${(len / 8).toFixed(0)} m; walk ${(len / WALK_SPEED).toFixed(1)} s at ${WALK_SPEED} px/s, run ${(len / RUN_SPEED).toFixed(1)} s at ${RUN_SPEED} px/s; middle (light_appears) at (${half[0]}, ${half[1]})`);
  const m = r.monte, st = MONTE_REPORT.stats, wk = MONTE_REPORT.walk;
  console.log(`tilegen: zona1 monte: zone cols ${m.x0}-${m.x1} (${MONTE_W} t = ${MONTE_W * 2} m wide, ${m.leftMargin} t from the left edge), centre col ${m.centreCol}; distance from the church door centre (${r.doorCentrePx} px) to the zone centre (${m.centrePx} px) = ${m.distTiles} t = ${m.distMetres} m (OK, must be 250 t = 500 m; real life 10 km, simplified)`);
  console.log(`tilegen: zona1 east road: cols 0-${ROAD_X1} rows ${ROAD_Y0}-${ROAD_Y0 + 3} asphalt, junction col ${ROAD_X1} with the asphalt street (cols ${ROAD_X1 + 1}-${ROAD_X1 + 4}); trail cols ${TRAIL_X0}-${TRAIL_X0 + 1} rows ${TRAIL_Y0}-${TRAIL_Y0 + TRAIL_LEN - 1}; turbines (base col,row): ${TURBINE_AT.map((t) => `(${t[0]},${t[1]})`).join(" ")}; map ${MAP_W}x${MAP_H}, LEFT_PAD ${LEFT_PAD}`);
  console.log(`tilegen: zona1 forest: trees ${JSON.stringify(st.trees)} (total ${Object.values(st.trees).reduce((a, b) => a + b, 0)}), solid props ${JSON.stringify(st.solidProps)}, ferns ${st.ferns}; solid cells ${st.solidCells} of ${st.forestCells} zone cells (${(100 * st.solidCells / st.forestCells).toFixed(1)}%), of ${st.eligible} forest-eligible cells (outside clearings / road corridor / trail): solid ${(100 * st.solidCells / st.eligible).toFixed(1)}%, solid + ferns ${(100 * (st.solidCells + st.ferns) / st.eligible).toFixed(1)}%; free cells ${wk.freeCells}, reachable ${wk.reachable}; monte sheet ${MONTE_TILE_COUNT} tiles (${MONTE_ROTOR_TILE_COUNT} rotor tiles, animated)`);
  const rv = r.river, rw = MONTE_REPORT.river, ww = MONTE_REPORT.riverWalk;
  for (const a of rv.anchors) console.log(`tilegen: zona1 river at ${a.id} (col ${a.col}): centre row ${a.centreRow} (water rows ${a.rowsA}-${a.rowsB}), ${a.tiles} tiles = ${a.metres} m north of row ${a.top} (asked ${a.wantM} m${a.id === "iglesia" ? "; the user said 150-200 m, 175 m = 87.5 tiles rounded to 88" : ""}) OK`);
  console.log(`tilegen: zona1 MAP ${MAP_W}x${MAP_H}, TOP_PAD ${TOP_PAD} rows (hero start y = ${300 + TOP_PAD * 16}); river thickness ${rv.minThickness}-${rv.maxThickness} tiles, max slope ${rv.slopeMax.toFixed(2)} rows/col, ${rw.waterCells} water cells, ${rw.boulders} boulders, ${rw.rapidsCells} rapids-reach cells, ${rw.northTrees} north trees, ${RIVER_ZONES.length} zone strips; rio sheet ${RIO_TILE_COUNT} tiles (firstgid ${RIO_FIRSTGID})`);
  console.log(`tilegen: zona1 bridge: asphalt cols 260-263 + sidewalks ${BRIDGE.deckW}/${BRIDGE.deckE}, rails cols ${BRIDGE.railW}/${BRIDGE.railE}, piers cols ${BRIDGE.pierW}/${BRIDGE.pierE}; water rows ${BRIDGE.wr0}-${BRIDGE.wr1}, bridge rows ${BRIDGE.rb0}-${BRIDGE.rb1} (2 tiles past each bank); walk: ${ww.deckOpen} deck cells open, ${ww.walkableWater} walkable water cells elsewhere, north bank reachable only over the bridge`);
  const sc = readFileSync(join(game, "scenes", "zona1.lua"), "utf8"), want = 300 + TOP_PAD * 16;
  if (!new RegExp(`position = \\{ x = 4632, y = ${want} \\}`).test(sc)) throw new Error(`scenes/zona1.lua: the hero must start at y = ${want} (300 + TOP_PAD * 16)`);
  console.log(`tilegen: zona1 church centring: street centre col ${r.streetCentreCol} (${r.streetCentrePx} px) vs church door centre col ${r.doorCentreCol} (${r.doorCentrePx} px): ${r.centred ? "OK" : "OFF"}`);
}
