// Procedural town tileset generator (issue #55).
//   node gen.mjs                 write tilesets/town.png, tilesets/town.tsx and maps/tiles_demo.tmx
//   node gen.mjs --check         regenerate in memory and compare with the files on disk (exit 1 on drift)
//   node gen.mjs --preview DIR   write sheet_x4.png, demo_map.png, demo_map_night.png into DIR (never committed)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { encodePng } from "./png.mjs";
import { renderSheet, TILES } from "./catalog.mjs";
import { buildTsx } from "./tsx.mjs";
import { buildTmx, renderMap } from "./demo_map.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const game = resolve(here, "..", "..");
const out = {
  png: join(game, "tilesets", "town.png"),
  tsx: join(game, "tilesets", "town.tsx"),
  tmx: join(game, "maps", "tiles_demo.tmx"),
};

const pngOf = (f) => encodePng(f.w, f.h, f.data);
const products = () => [
  [out.png, pngOf(renderSheet())],
  [out.tsx, Buffer.from(buildTsx())],
  [out.tmx, Buffer.from(buildTmx())],
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
  console.log(`tilegen: ${TILES.length} tiles up to date`);
} else if (args.includes("--preview")) {
  const dir = resolve(args[args.indexOf("--preview") + 1] ?? ".");
  mkdirSync(dir, { recursive: true });
  const bg = [255, 0, 255, 255].map((v, i) => (i === 3 ? 255 : v === 255 ? 70 : 70));
  const sheet = renderSheet();
  writeFileSync(join(dir, "sheet_x4.png"), pngOf(sheet.onBackground([60, 60, 70, 255]).scaled(4)));
  writeFileSync(join(dir, "demo_map.png"), pngOf(renderMap(false).scaled(2)));
  writeFileSync(join(dir, "demo_map_night.png"), pngOf(renderMap(true).scaled(2)));
  console.log(`tilegen: previews in ${dir}`);
} else {
  for (const [path, data] of products()) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, data);
    console.log(`tilegen: wrote ${path} (${data.length} bytes)`);
  }
  console.log(`tilegen: ${TILES.length} tiles`);
}
