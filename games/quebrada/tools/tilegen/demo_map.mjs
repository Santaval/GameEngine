// Proof map for the tileset: maps/tiles_demo.tmx (40x30 tiles of 16 px), built from a material grid
// plus a small autotiler. It follows docs/reference/croquis.svg loosely: lastre camino to the east,
// asphalt street across, calle 2 in pavers, cafetal terraces to the west, river on the far east.
import { TILES, SIZE, renderSheet } from "./catalog.mjs";
import { Frame } from "./draw.mjs";
import { noise, wobble } from "./rng.mjs";

export const MAP_W = 40;
export const MAP_H = 30;

const byName = new Map(TILES.map((t) => [t.name, t]));
const gid = (name) => {
  const t = byName.get(name);
  if (!t) throw new Error(`unknown tile ${name}`);
  return t.id + 1;
};
const pick = (names, x, y, salt = "pk") => names[Math.floor(noise(salt, x, y) * names.length) % names.length];

export function buildDemo() {
  const N = MAP_W * MAP_H;
  const L = { ground: new Array(N).fill(0), overlay: new Array(N).fill(0), objects: new Array(N).fill(0), canopy: new Array(N).fill(0) };
  const at = (x, y) => y * MAP_W + x;
  const inb = (x, y) => x >= 0 && y >= 0 && x < MAP_W && y < MAP_H;
  const mat = Array.from({ length: MAP_H }, () => new Array(MAP_W).fill("g"));
  const setMat = (x, y, m) => { if (inb(x, y)) mat[y][x] = m; };
  const put = (layer, x, y, name) => { if (inb(x, y)) L[layer][at(x, y)] = gid(name); };

  // ---- materials ----
  for (let y = 0; y < MAP_H; y++) {
    for (let x = 36; x < MAP_W; x++) setMat(x, y, "w");
    setMat(35, y, "b");
    for (let x = 29; x <= 32; x++) setMat(x, y, "l");
  }
  // street (rows 11-17, cols 0-28) and calle 2 (cols 15-17)
  for (let x = 0; x <= 28; x++) for (let y = 11; y <= 17; y++) setMat(x, y, y === 12 || y === 16 || y === 11 || y === 17 ? "s" : "a");
  for (let y = 0; y < MAP_H; y++) for (let x = 15; x <= 17; x++) setMat(x, y, "p");
  for (let x = 15; x <= 17; x++) for (let y = 13; y <= 15; y++) setMat(x, y, "a");
  // cafetal
  for (let y = 19; y <= 28; y++) for (let x = 0; x <= 11; x++) setMat(x, y, "c");
  // lastre plazoleta (L shape, exercises edges and inner corners)
  for (let y = 19; y <= 22; y++) for (let x = 19; x <= 26; x++) setMat(x, y, "l");
  for (let y = 23; y <= 27; y++) for (let x = 19; x <= 22; x++) setMat(x, y, "l");
  // planks
  for (let y = 20; y <= 21; y++) for (let x = 12; x <= 14; x++) setMat(x, y, "k");

  const isGrass = (x, y) => inb(x, y) && mat[y][x] === "g";
  // ---- ground ----
  for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
    const m = mat[y][x];
    let name;
    switch (m) {
      case "g": {
        const r = noise("gv", x, y);
        name = r < 0.06 ? "grass_flowers" : r < 0.1 ? "grass_dry" : r < 0.13 ? "grass_dirt" : pick(["grass_a", "grass_b", "grass_c", "grass_d"], x, y);
        break;
      }
      case "l": {
        const miss = ["N", "E", "S", "W"].filter((s) => {
          const [dx, dy] = { N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0] }[s];
          return isGrass(x + dx, y + dy);
        });
        if (miss.length === 0) {
          const diag = [["NW", -1, -1], ["NE", 1, -1], ["SW", -1, 1], ["SE", 1, 1]].find(([, dx, dy]) => isGrass(x + dx, y + dy));
          name = diag ? `lastre_inner_${diag[0].toLowerCase()}` : x === 30 ? "lastre_ruts_v" : pick(["lastre_a", "lastre_b"], x, y);
        } else if (miss.length === 1) name = `lastre_edge_${miss[0].toLowerCase()}`;
        else if (miss.length === 2 && !(miss.includes("N") && miss.includes("S")) && !(miss.includes("E") && miss.includes("W"))) {
          const key = ["N", "S"].find((s) => miss.includes(s)) + ["W", "E"].find((s) => miss.includes(s));
          name = `lastre_outer_${key.toLowerCase()}`;
        } else name = "lastre_a";
        break;
      }
      case "a": name = y === 14 && x < 28 && !(x >= 15 && x <= 17) ? "asphalt_line_h" : pick(["asphalt_a", "asphalt_a", "asphalt_b"], x, y); break;
      case "s": name = y === 12 || y === 16 ? "gutter_h" : pick(["sidewalk_a", "sidewalk_b"], x, y); break;
      case "p": name = noise("pv", x >> 1, y) < 0.09 ? "paver_b" : "paver_a"; break;
      case "w": name = pick(["water_a", "water_b", "water_a", "water_ripple"], x, y); break;
      case "b": name = "bank_e"; break;
      case "c": { const k = (y - 19) % 3; name = k === 0 ? "soil_terrace" : k === 1 ? "soil" : "soil_furrow"; break; }
      case "k": name = (y === 20) ? "plank_h" : "plank_h"; break;
    }
    put("ground", x, y, name);
  }
  // street details
  for (let x = 0; x <= 28; x++) {
    put("ground", x, 14, x >= 15 && x <= 17 ? "asphalt_a" : "asphalt_line_h");
  }
  for (const y of [13, 14, 15]) put("ground", 12, y, "crosswalk_h");
  for (const y of [13, 14, 15]) put("ground", 28, y, "seam_asphalt_w");
  put("ground", 22, 13, "manhole");
  put("ground", 7, 15, "asphalt_crack");
  put("ground", 24, 15, "asphalt_patch");
  put("ground", 19, 16, "drain");
  put("ground", 4, 13, "asphalt_patch");
  // gutters meet calle 2: pavers continue across
  for (const x of [15, 16, 17]) for (const y of [11, 12, 16, 17]) put("ground", x, y, "paver_a");
  // the crossing in pavers keeps the asphalt strip; paver edge tiles are the same material so no seam needed
  // junction between sidewalk end and the camino
  // river bank details
  for (const y of [4, 11, 21, 26]) put("ground", 35, y, "river_stones");
  for (const y of [8, 15, 24]) put("ground", 34, y, "riverside_grass");
  // lot interior
  for (let y = 4; y <= 8; y++) for (let x = 21; x <= 26; x++) put("ground", x, y, noise("lot", x, y) < 0.5 ? "grass_tall" : "grass_c");
  // puddle of mud near the plazoleta
  put("ground", 24, 21, "mud");
  put("ground", 25, 22, "mud");
  // gap in the cafetal rows: a path of lastre
  for (let y = 19; y <= 28; y++) for (const x of [5, 6]) put("ground", x, y, x === 5 ? "lastre_ruts_v" : "lastre_ruts_v");

  // ---- objects ----
  const fence = (name, x, y) => put("objects", x, y, name);
  // barbed wire lot (20..27, 3..9)
  fence("wire_corner_es", 20, 3); fence("wire_corner_ws", 27, 3);
  for (let x = 21; x <= 26; x++) fence("wire_h", x, 3);
  for (let y = 4; y <= 8; y++) { fence("wire_v", 20, y); fence("wire_v", 27, y); }
  fence("wire_corner_en", 20, 9); fence("wire_corner_wn", 27, 9);
  for (const x of [21, 22, 24, 25, 26]) fence("wire_h", x, 9);
  fence("fence_gap", 23, 9);
  // chainlink along the north verge and a hedge
  for (let x = 6; x <= 11; x++) fence("chainlink_h", x, 10);
  for (let x = 1; x <= 4; x++) fence("hedge", x, 10);
  // cafetal
  for (let y = 19; y <= 28; y++) if ((y - 19) % 3 === 1) for (let x = 0; x <= 11; x++) {
    if (x === 5 || x === 6) continue;
    fence(noise("cf", x, y) < 0.5 ? "cafeto_a" : "cafeto_b", x, y);
  }

  const tree = (kind, cx, cy) => {
    // trunk at (cx, cy); canopy 3x2 above, centered
    put("objects", cx, cy, `${kind}_${{ guanacaste: "trunk", platano: "stem", palm: "trunk", monte: "trunk" }[kind]}`);
    for (let j = 0; j < 2; j++) for (let i = 0; i < 3; i++) put("canopy", cx - 1 + i, cy - 2 + j, `${kind}_canopy_${i}_${j}`);
    if (kind !== "palm") { put("overlay", cx - 1, cy, "shadow_blob"); put("overlay", cx + 1, cy, "shadow_blob"); }
    put("overlay", cx, cy + 1, "fallen_leaves");
  };
  tree("guanacaste", 8, 8);
  tree("guanacaste", 24, 25);
  tree("palm", 13, 5);
  tree("palm", 34, 6);
  tree("monte", 2, 4); tree("monte", 5, 3); tree("monte", 10, 3);
  tree("platano", 22, 6); tree("platano", 25, 6); tree("platano", 23, 8);
  tree("platano", 34, 23);
  // power poles: base on the south sidewalk
  const pole = (cx, baseRow) => {
    put("objects", cx, baseRow, "poste_base");
    put("canopy", cx, baseRow - 2, "poste_head_top");
    put("canopy", cx, baseRow - 1, "poste_head_shaft");
  };
  pole(5, 17); pole(21, 17); pole(26, 17); pole(14, 9);
  for (let x = 6; x <= 20; x++) put("canopy", x, 15, "power_wire");
  for (let x = 22; x <= 25; x++) put("canopy", x, 15, "power_wire");
  // props
  put("objects", 19, 10, "bench");
  put("objects", 3, 8, "stump");
  put("objects", 30 + 0, 20, "rock");
  put("objects", 18, 21, "rock");
  put("objects", 33, 10, "rock");
  put("objects", 8, 18, "weeds"); put("objects", 9, 18, "weeds"); put("objects", 28, 9, "weeds");
  put("objects", 22, 18, "bougainvillea"); put("objects", 23, 18, "bougainvillea");
  put("objects", 28, 22, "bougainvillea");
  put("overlay", 3, 20 - 1, "puddle");
  put("overlay", 24, 20, "puddle");

  // keep the pole bases clear of ground clutter: bases stand on sidewalk
  return { L, spawn: { x: 8 * 16 + 8, y: 11 * 16 + 8 } };
}

function csv(arr) {
  const rows = [];
  for (let y = 0; y < MAP_H; y++) rows.push(arr.slice(y * MAP_W, (y + 1) * MAP_W).join(","));
  return rows.join(",\n");
}

export function buildTmx() {
  const { L, spawn } = buildDemo();
  const lights = [[5, 17], [21, 17], [26, 17], [14, 9]].map(([cx, base], i) => {
    const x = cx * SIZE + 14, y = (base - 2) * SIZE + 11;
    return `  <object id="${30 + i}" name="poste_tiles_${i + 1}" class="light" x="${x - 4}" y="${y - 4}" width="8" height="8">
   <properties>
    <property name="radius" type="int" value="70"/>
    <property name="r" type="int" value="255"/>
    <property name="g" type="int" value="220"/>
    <property name="b" type="int" value="150"/>
    <property name="intensity" type="float" value="0.9"/>
    <property name="only" value="dusk,night"/>
   </properties>
  </object>`;
  }).join("\n");
  const layer = (id, name, arr, props = "") =>
    ` <layer id="${id}" name="${name}" width="${MAP_W}" height="${MAP_H}">\n${props}  <data encoding="csv">\n${csv(arr)}\n</data>\n </layer>`;
  return `<?xml version="1.0" encoding="UTF-8"?>
<!-- GENERATED by games/quebrada/tools/tilegen (make tiles): demo of the town tileset (issue #55).
     40x30 tiles of 16 px. Layers: ground (plain), overlay (plain, after ground), objects (ysort: trunks, fences,
     posts), canopy (above: treetops, pole heads). See games/quebrada/docs/tileset.md. -->
<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" width="${MAP_W}" height="${MAP_H}" tilewidth="${SIZE}" tileheight="${SIZE}" infinite="0" nextlayerid="10" nextobjectid="40">
 <tileset firstgid="1" source="../tilesets/town.tsx"/>
${layer(1, "ground", L.ground)}
${layer(2, "overlay", L.overlay)}
${layer(3, "objects", L.objects, `  <properties>\n   <property name="ysort" type="bool" value="true"/>\n  </properties>\n`)}
${layer(4, "canopy", L.canopy, `  <properties>\n   <property name="above" type="bool" value="true"/>\n  </properties>\n`)}
 <objectgroup id="5" name="collision"/>
 <objectgroup id="6" name="spawns">
  <object id="20" name="default" class="spawn" x="${spawn.x}" y="${spawn.y}">
   <point/>
  </object>
 </objectgroup>
 <objectgroup id="7" name="zones">
  <object id="25" name="zone_tiles_demo" class="zone" x="0" y="0" width="640" height="480">
   <properties>
    <property name="zone" value="tiles_demo"/>
    <property name="title" value="Demo de tiles"/>
    <property name="ambience" value="pueblo"/>
   </properties>
  </object>
 </objectgroup>
 <objectgroup id="8" name="lights">
${lights}
 </objectgroup>
</map>
`;
}

/** Compose a picture of the map (no y-sorting needed: there is no player). */
export function renderMap(night = false) {
  const sheet = renderSheet();
  const { L } = buildDemo();
  const out = new Frame(MAP_W * SIZE, MAP_H * SIZE);
  for (const name of ["ground", "overlay", "objects", "canopy"]) {
    for (let i = 0; i < L[name].length; i++) {
      const g = L[name][i];
      if (!g) continue;
      const id = g - 1;
      out.blit(sheet.slice((id % 16) * SIZE, Math.floor(id / 16) * SIZE, SIZE, SIZE), (i % MAP_W) * SIZE, Math.floor(i / MAP_W) * SIZE);
    }
  }
  return night ? out.darkened(0.35) : out;
}
