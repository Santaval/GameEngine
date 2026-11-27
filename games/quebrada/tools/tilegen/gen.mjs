// Procedural town tileset + buildings generator (issues #55, #71).
//   node gen.mjs                 write tilesets/town.{png,tsx}, maps/tiles_demo.tmx, tilesets/buildings.{png,tsx},
//                                maps/buildings_demo.tmx, maps/house_mama.tmx (interior of mama's house) and
//                                maps/zona1.tmx (zone 1, issue #78: church + 100 m paver street at 2 m = 1 tile (50 tiles);
//                                prints the metres-per-tile scale, the street length in tiles / metres and the church centring check)
//   node gen.mjs --check         regenerate in memory and compare with the files on disk (exit 1 on drift)
//   node gen.mjs --preview DIR   write sheet_x4.png, demo_map.png, demo_map_night.png, buildings_sheet_x4.png,
//                                buildings_demo{,_noroof,_night}.png, house_mama.png, crop_iglesia_x4.png and
//                                crop_casa_mama_x4.png, park_sheet_x4.png, zona1_park_x2.png, zona1_street_x2.png, zona1.png, zona1_night.png and zona1_triggers.png into DIR
//                                (never committed)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { encodePng } from "./png.mjs";
import { renderSheet, TILES } from "./catalog.mjs";
import { buildTsx, buildTsxFor } from "./tsx.mjs";
import { buildTmx, renderMap } from "./demo_map.mjs";
import { renderBuildingSheet, B_TILES, B_COLS, B_ROWS, buildingCanvas } from "./catalog_buildings.mjs";
import { renderParkSheet, PARK_TILES, P_COLS, P_ROWS } from "./catalog_park.mjs";
import { buildTmx as buildBuildingsTmx, renderBuildingsMap } from "./buildings_map.mjs";
import { buildTmx as buildInteriorTmx, renderInterior } from "./interior_map.mjs";
import { buildTmx as buildZona1Tmx, renderZona1, baseReport, routeLength, pointAt, WALK_SPEED, RUN_SPEED, MAP_W, MAP_H, EXT_PAVER_X1, EXT_LASTRE_X1 } from "./zona1_map.mjs";

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
  btmx: join(game, "maps", "buildings_demo.tmx"),
  house: join(game, "maps", "house_mama.tmx"),
  zona1: join(game, "maps", "zona1.tmx"),
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
  [out.btmx, Buffer.from(buildBuildingsTmx())],
  [out.house, Buffer.from(buildInteriorTmx())],
  [out.zona1, Buffer.from(buildZona1Tmx())],
];

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
  console.log(`tilegen: ${TILES.length} town + ${B_TILES.length} buildings + ${PARK_TILES.length} park tiles up to date`);
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
  const grass = [96, 150, 70, 255];
  writeFileSync(join(dir, "crop_iglesia_x4.png"), pngOf(buildingCanvas("iglesia").day.onBackground(grass).scaled(4)));
  writeFileSync(join(dir, "crop_casa_mama_x4.png"), pngOf(buildingCanvas("casa_mama").day.onBackground(grass).scaled(4)));
  writeFileSync(join(dir, "zona1.png"), pngOf(renderZona1({ night: false, roofs: true })));
  writeFileSync(join(dir, "zona1_night.png"), pngOf(renderZona1({ night: true, roofs: true })));
  writeFileSync(join(dir, "park_sheet_x4.png"), pngOf(renderParkSheet().onBackground([60, 60, 70, 255]).scaled(4)));
  const z1 = renderZona1({ night: false, roofs: true });
  writeFileSync(join(dir, "zona1_park_x2.png"), pngOf(z1.slice(9 * 16, 18 * 16, 52 * 16, 48 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_street_x2.png"), pngOf(z1.slice(9 * 16, 4 * 16, 52 * 16, 28 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_triggers.png"), pngOf(renderZona1({ night: false, roofs: false, triggers: true })));
  // street-network crops (tile rectangles [col, row, cols, rows], x2): east asphalt street + main street + park corner, the paver -> lastre joint,
  // the SE corner (south street + west street), the main street / west street T junction, the lastre end, the asphalt/south street mouth
  const crop = (name, c, r, w, h) => writeFileSync(join(dir, `zona1_${name}_x2.png`), pngOf(z1.slice(c * 16, r * 16, w * 16, h * 16).scaled(2)));
  crop("junction_este", 0, 14, 24, 20);
  crop("joint_lastre", EXT_PAVER_X1 - 12, 14, 26, 16);
  crop("esquina_se", 50, 56, 22, 16);
  crop("junction_oeste", 52, 14, 22, 18);
  crop("fin_lastre", EXT_LASTRE_X1 - 20, 14, 31, 16);
  crop("boca_sur", 0, 58, 24, 14);
  // the Chequelo places: the cafetal with the street, and the east end (Chayo's and mama's houses) with and without the trigger overlay
  crop("cafetal", 290, 2, 40, 26);
  crop("casas_oeste", 388, 17, 57, 22);
  const trg = renderZona1({ night: false, roofs: false, triggers: true });
  writeFileSync(join(dir, "zona1_triggers_casas_x2.png"), pngOf(trg.slice(388 * 16, 17 * 16, 57 * 16, 22 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_triggers_cafetal_x2.png"), pngOf(trg.slice(290 * 16, 2 * 16, 40 * 16, 26 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_night_casas_x2.png"), pngOf(renderZona1({ night: true, roofs: true }).slice(388 * 16, 17 * 16, 57 * 16, 22 * 16).scaled(2)));
  writeFileSync(join(dir, "zona1_street_night_x2.png"), pngOf(renderZona1({ night: true, roofs: true }).slice(0, 14 * 16, 90 * 16, 20 * 16).scaled(2)));
  console.log(`tilegen: previews in ${dir}`);
} else {
  for (const [path, data] of products()) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, data);
    console.log(`tilegen: wrote ${path} (${data.length} bytes)`);
  }
  console.log(`tilegen: ${TILES.length} town + ${B_TILES.length} buildings + ${PARK_TILES.length} park tiles`);
  const r = baseReport(); // throws if the street is not 50 tiles = 100 m or the church is not centred on it
  console.log(`tilegen: zona1 ${MAP_W}x${MAP_H} tiles; scale ${r.metresPerTile} m = 1 tile; street ${r.lengthTiles} tiles = ${r.lengthMetres} m (cols ${r.x0}-${r.x1}, rows ${r.y0}-${r.y1}, ${r.width} wide)`);
  console.log(`tilegen: zona1 extension west (to the right): paver cols ${r.ext.paverX0}-${r.ext.paverX1} = ${r.ext.paverTiles} t = ${r.ext.paverMetres} m, lastre cols ${r.ext.lastreX0}-${r.ext.lastreX1} = ${r.ext.lastreTiles} t = ${r.ext.lastreMetres} m, total ${r.ext.totalTiles} t = ${r.ext.totalMetres} m`);
  const len = routeLength(), half = pointAt(len / 2); // reported only (the user's layout is longer than the old ~60 s target)
  console.log(`tilegen: zona1 Chequelo route ${len} px = ${(len / 16).toFixed(0)} tiles = ${(len / 8).toFixed(0)} m; walk ${(len / WALK_SPEED).toFixed(1)} s at ${WALK_SPEED} px/s, run ${(len / RUN_SPEED).toFixed(1)} s at ${RUN_SPEED} px/s; middle (light_appears) at (${half[0]}, ${half[1]})`);
  console.log(`tilegen: zona1 church centring: street centre col ${r.streetCentreCol} (${r.streetCentrePx} px) vs church door centre col ${r.doorCentreCol} (${r.doorCentrePx} px): ${r.centred ? "OK" : "OFF"}`);
}
