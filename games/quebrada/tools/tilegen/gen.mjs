// Procedural town tileset + buildings generator (issues #55, #71).
//   node gen.mjs                 write tilesets/town.{png,tsx}, maps/tiles_demo.tmx, tilesets/buildings.{png,tsx},
//                                maps/buildings_demo.tmx and maps/house_mama.tmx (interior of mama's house)
//   node gen.mjs --check         regenerate in memory and compare with the files on disk (exit 1 on drift)
//   node gen.mjs --preview DIR   write sheet_x4.png, demo_map.png, demo_map_night.png, buildings_sheet_x4.png,
//                                buildings_demo{,_noroof,_night}.png, house_mama.png, crop_iglesia_x4.png and
//                                crop_casa_mama_x4.png into DIR (never committed)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { encodePng } from "./png.mjs";
import { renderSheet, TILES } from "./catalog.mjs";
import { buildTsx, buildTsxFor } from "./tsx.mjs";
import { buildTmx, renderMap } from "./demo_map.mjs";
import { renderBuildingSheet, B_TILES, B_COLS, B_ROWS, buildingCanvas } from "./catalog_buildings.mjs";
import { buildTmx as buildBuildingsTmx, renderBuildingsMap } from "./buildings_map.mjs";
import { buildTmx as buildInteriorTmx, renderInterior } from "./interior_map.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const game = resolve(here, "..", "..");
const out = {
  png: join(game, "tilesets", "town.png"),
  tsx: join(game, "tilesets", "town.tsx"),
  tmx: join(game, "maps", "tiles_demo.tmx"),
  bpng: join(game, "tilesets", "buildings.png"),
  btsx: join(game, "tilesets", "buildings.tsx"),
  btmx: join(game, "maps", "buildings_demo.tmx"),
  house: join(game, "maps", "house_mama.tmx"),
};

const pngOf = (f) => encodePng(f.w, f.h, f.data);
const products = () => [
  [out.png, pngOf(renderSheet())],
  [out.tsx, Buffer.from(buildTsx())],
  [out.tmx, Buffer.from(buildTmx())],
  [out.bpng, pngOf(renderBuildingSheet())],
  [out.btsx, Buffer.from(buildTsxFor({ name: "buildings", image: "buildings.png", tiles: B_TILES, cols: B_COLS, rows: B_ROWS }))],
  [out.btmx, Buffer.from(buildBuildingsTmx())],
  [out.house, Buffer.from(buildInteriorTmx())],
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
  console.log(`tilegen: ${TILES.length} town + ${B_TILES.length} buildings tiles up to date`);
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
  console.log(`tilegen: previews in ${dir}`);
} else {
  for (const [path, data] of products()) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, data);
    console.log(`tilegen: wrote ${path} (${data.length} bytes)`);
  }
  console.log(`tilegen: ${TILES.length} town + ${B_TILES.length} buildings tiles`);
}
