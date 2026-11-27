// Proof map for the buildings sheet: maps/buildings_demo.tmx (40x30 tiles of 16 px).
// Church east of the lastre camino, mama's house south of the street with its dirt yard and guanacaste,
// three filler houses north of the street. Uses both tilesets: town (firstgid 1) and buildings (firstgid 145).
import { TILES, SIZE, COLS, ROWS, renderSheet } from "./catalog.mjs";
import { BUILDINGS, BUILDING_BY_NAME, B_COLS, bIdByName, renderBuildingSheet } from "./catalog_buildings.mjs";
import { Frame } from "./draw.mjs";
import { noise } from "./rng.mjs";

export const MAP_W = 40;
export const MAP_H = 30;
export const TOWN_FIRSTGID = 1;
export const B_FIRSTGID = COLS * ROWS + 1; // 145

const byName = new Map(TILES.map((t) => [t.name, t]));
const gid = (name) => {
  const t = byName.get(name);
  if (!t) throw new Error(`unknown tile ${name}`);
  return t.id + TOWN_FIRSTGID;
};
export const bgid = (name) => {
  if (!bIdByName.has(name)) throw new Error(`unknown buildings tile ${name}`);
  return bIdByName.get(name) + B_FIRSTGID;
};
const pick = (names, x, y, salt = "pk") => names[Math.floor(noise(salt, x, y) * names.length) % names.length];

// building origins in tiles
export const PLACE = {
  iglesia: [30, 2],
  casa_mama: [14, 20],
  casa_1: [2, 6],
  casa_2: [10, 6],
  casa_3: [18, 6],
};

const LAYER_ORDER = ["ground", "overlay", "objects", "buildings", "windows_lit", "roof_iglesia", "roof_casa_mama", "roof_casa_1", "roof_casa_2", "roof_casa_3", "canopy"];

export function buildDemo() {
  const N = MAP_W * MAP_H;
  const L = Object.fromEntries(LAYER_ORDER.map((n) => [n, new Array(N).fill(0)]));
  const at = (x, y) => y * MAP_W + x;
  const inb = (x, y) => x >= 0 && y >= 0 && x < MAP_W && y < MAP_H;
  const mat = Array.from({ length: MAP_H }, () => new Array(MAP_W).fill("g"));
  const setMat = (x, y, m) => { if (inb(x, y)) mat[y][x] = m; };
  const put = (layer, x, y, name) => { if (inb(x, y)) L[layer][at(x, y)] = gid(name); };
  const bput = (layer, x, y, name) => { if (inb(x, y)) L[layer][at(x, y)] = bgid(name); };

  // ---- materials ----
  for (let y = 0; y < MAP_H; y++) for (let x = 26; x <= 29; x++) setMat(x, y, "l"); // camino
  // street: sidewalk 12, gutter 13, asphalt 14-16, gutter 17, sidewalk 18 (cols 0-25)
  for (let x = 0; x <= 25; x++) {
    setMat(x, 12, "s"); setMat(x, 13, "s"); setMat(x, 17, "s"); setMat(x, 18, "s");
    for (let y = 14; y <= 16; y++) setMat(x, y, "a");
  }
  // church path: pavers from the door down and across to the camino
  for (let y = 14; y <= 17; y++) for (const x of [34, 35]) setMat(x, y, "p");
  for (let x = 30; x <= 33; x++) setMat(x, 17, "p");
  // dirt yard in front of mama's house
  for (let y = 26; y <= 29; y++) for (let x = 8; x <= 25; x++) setMat(x, y, "l");
  const isGrass = (x, y) => inb(x, y) && mat[y][x] === "g";

  for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
    const m = mat[y][x];
    let name;
    switch (m) {
      case "g": {
        const r = noise("gv", x, y);
        name = r < 0.05 ? "grass_flowers" : r < 0.08 ? "grass_dry" : r < 0.1 ? "grass_dirt" : pick(["grass_a", "grass_b", "grass_c", "grass_d"], x, y);
        break;
      }
      case "l": {
        const miss = ["N", "E", "S", "W"].filter((s) => {
          const [dx, dy] = { N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0] }[s];
          return isGrass(x + dx, y + dy);
        });
        if (miss.length === 0) {
          const diag = [["NW", -1, -1], ["NE", 1, -1], ["SW", -1, 1], ["SE", 1, 1]].find(([, dx, dy]) => isGrass(x + dx, y + dy));
          name = diag ? `lastre_inner_${diag[0].toLowerCase()}` : x === 27 ? "lastre_ruts_v" : pick(["lastre_a", "lastre_b"], x, y);
        } else if (miss.length === 1) name = `lastre_edge_${miss[0].toLowerCase()}`;
        else if (miss.length === 2 && !(miss.includes("N") && miss.includes("S")) && !(miss.includes("E") && miss.includes("W"))) {
          const key = ["N", "S"].find((s) => miss.includes(s)) + ["W", "E"].find((s) => miss.includes(s));
          name = `lastre_outer_${key.toLowerCase()}`;
        } else name = "lastre_a";
        break;
      }
      case "a": name = y === 15 ? "asphalt_line_h" : pick(["asphalt_a", "asphalt_a", "asphalt_b"], x, y); break;
      case "s": name = y === 13 || y === 17 ? "gutter_h" : pick(["sidewalk_a", "sidewalk_b"], x, y); break;
      case "p": name = noise("pv", x >> 1, y) < 0.1 ? "paver_b" : "paver_a"; break;
    }
    put("ground", x, y, name);
  }
  for (const y of [14, 15, 16]) put("ground", 25, y, "seam_asphalt_w");
  put("ground", 20, 15, "manhole");
  put("ground", 7, 16, "asphalt_crack");
  put("ground", 12, 14, "asphalt_patch");
  put("ground", 5, 14, "drain");
  // porch floor of mama's house, and the church doorstep
  const [mx, my] = PLACE.casa_mama;
  for (const x of [mx + 6, mx + 7]) put("ground", x, my + 5, "plank_h");
  const [ix, iy] = PLACE.iglesia;
  for (const x of [ix + 4, ix + 5]) put("ground", x, iy + 12, "paver_a");

  // ---- buildings (base cells ysort, roofs per building, lit windows) ----
  for (const b of BUILDINGS) {
    const [ox, oy] = PLACE[b.name];
    for (const c of b.cells) {
      if (c.layer === "above") bput(`roof_${b.name}`, ox + c.cx, oy + c.cy, c.name);
      else bput("buildings", ox + c.cx, oy + c.cy, c.name);
    }
    for (const c of b.lit) bput("windows_lit", ox + c.cx, oy + c.cy, c.name);
  }

  // ---- hedges along the church path ----
  for (const x of [31, 32, 33]) bput("objects", x, iy + 12, "hedge_burgundy");
  for (const x of [36, 37, 38]) bput("objects", x, iy + 12, "hedge_lime");
  put("objects", 33, iy + 13, "hedge"); put("objects", 36, iy + 13, "hedge");
  put("objects", 31, iy + 13, "hedge");
  put("objects", 38, iy + 13, "hedge");

  // ---- trees and props ----
  const tree = (kind, cx, cy) => {
    put("objects", cx, cy, `${kind}_${{ guanacaste: "trunk", platano: "stem", palm: "trunk", monte: "trunk" }[kind]}`);
    for (let j = 0; j < 2; j++) for (let i = 0; i < 3; i++) put("canopy", cx - 1 + i, cy - 2 + j, `${kind}_canopy_${i}_${j}`);
    if (kind !== "palm") { put("overlay", cx - 1, cy, "shadow_blob"); put("overlay", cx + 1, cy, "shadow_blob"); }
    put("overlay", cx, cy + 1, "fallen_leaves");
  };
  tree("guanacaste", 10, 27); // big tree in front-left of mama's house
  tree("monte", 3, 3); tree("monte", 7, 2); tree("monte", 22, 3);
  tree("palm", 13, 3);
  tree("palm", 24, 24);
  tree("monte", 37, 22); tree("monte", 33, 26);
  put("objects", 8, 12 - 1, "weeds"); put("objects", 15, 11, "weeds");
  put("objects", 6, 11, "bougainvillea"); put("objects", 15, 22, "bougainvillea");
  put("objects", 22, 23, "rock");
  put("objects", 19, 19, "bench");
  put("objects", 28, 22, "weeds");
  return { L };
}

function csv(arr) {
  const rows = [];
  for (let y = 0; y < MAP_H; y++) rows.push(arr.slice(y * MAP_W, (y + 1) * MAP_W).join(","));
  return rows.join(",\n");
}

const prop = (name, value, type) => `    <property name="${name}"${type ? ` type="${type}"` : ""} value="${value}"/>`;

export function buildTmx() {
  const { L } = buildDemo();
  let nid = 1;
  const oid = () => nid++;
  const px = (b) => ({ x: PLACE[b.name][0] * SIZE, y: PLACE[b.name][1] * SIZE, w: b.w * SIZE, h: b.h * SIZE });

  // collision: map border + one footprint per building (the roof cells cannot be solid)
  const coll = [
    [`wall_top`, -16, -16, 672, 16], [`wall_bottom`, -16, 480, 672, 16], [`wall_left`, -16, 0, 16, 480], [`wall_right`, 640, 0, 16, 480],
  ].map(([n, x, y, w, h]) => `  <object id="${oid()}" name="${n}" x="${x}" y="${y}" width="${w}" height="${h}"/>`);
  for (const b of BUILDINGS) {
    const o = px(b);
    const [r0, r1] = b.footRows;
    coll.push(`  <object id="${oid()}" name="${b.name}_footprint" x="${o.x}" y="${o.y + r0 * SIZE}" width="${o.w}" height="${(r1 - r0) * SIZE}"/>`);
  }

  // door to mama's house (32x12 just below the door cell)
  const mama = BUILDING_BY_NAME.get("casa_mama");
  const mo = px(mama);
  const doorCx = mo.x + mama.door.cx * SIZE + SIZE / 2;
  const doorY = mo.y + mo.h;
  const doors = `  <object id="${oid()}" name="door_mama" class="door" x="${doorCx - 16}" y="${doorY}" width="32" height="12">
   <properties>
${prop("target_map", "maps/house_mama.tmx")}
${prop("target_spawn", "inside_door")}
${prop("exit_spawn", "exit_mama")}
${prop("prompt", "E: entrar")}
   </properties>
  </object>`;

  const io = px(BUILDING_BY_NAME.get("iglesia"));
  const interact = `  <object id="${oid()}" name="iglesia_puerta" class="interactable" x="${io.x + 56}" y="${io.y + io.h}" width="48" height="16">
   <properties>
${prop("interact", "object")}
${prop("label", "Mirar la puerta")}
${prop("line", "La iglesia está cerrada.")}
   </properties>
  </object>`;

  const spawns = `  <object id="${oid()}" name="default" class="spawn" x="328" y="296">
   <point/>
  </object>
  <object id="${oid()}" name="exit_mama" class="spawn" x="${doorCx}" y="${doorY + 28}">
   <point/>
  </object>`;

  const zones = `  <object id="${oid()}" name="zone_buildings_demo" class="zone" x="0" y="0" width="640" height="480">
   <properties>
${prop("zone", "buildings_demo")}
${prop("title", "Demo de edificios")}
${prop("ambience", "pueblo")}
   </properties>
  </object>`;

  const surfaces = `  <object id="${oid()}" name="porche_mama" class="surface" x="${mo.x + 6 * SIZE}" y="${mo.y + 5 * SIZE}" width="32" height="16">
   <properties>
${prop("surface", "madera")}
   </properties>
  </object>`;

  const roofs = BUILDINGS.map((b) => {
    const o = px(b);
    return `  <object id="${oid()}" name="roof_${b.name}" class="roof" x="${o.x}" y="${o.y}" width="${o.w}" height="${o.h}">
   <properties>
${prop("roof_of", b.roof_of)}
   </properties>
  </object>`;
  }).join("\n");

  const light = (name, x, y, radius) => `  <object id="${oid()}" name="${name}" class="light" x="${x - 4}" y="${y - 4}" width="8" height="8">
   <properties>
${prop("radius", radius, "int")}
${prop("r", 255, "int")}
${prop("g", 190, "int")}
${prop("b", 100, "int")}
${prop("intensity", 0.8, "float")}
${prop("flicker", 0.1, "float")}
${prop("only", "dusk,night")}
   </properties>
  </object>`;
  const lights = [];
  for (const b of BUILDINGS) {
    const o = px(b);
    b.windows.forEach((w, i) => lights.push(light(`luz_${b.name}_${i + 1}`, o.x + w.x + w.w / 2, o.y + w.y + w.h / 2, b.name === "casa_mama" ? 36 : 30)));
  }
  lights.push(light("luz_iglesia_puerta", io.x + 80, io.y + 150, 40));

  const layer = (id, name, arr, props = "") =>
    ` <layer id="${id}" name="${name}" width="${MAP_W}" height="${MAP_H}">\n${props}  <data encoding="csv">\n${csv(arr)}\n</data>\n </layer>`;
  const prp = (kv) => `  <properties>\n${kv.map(([k, v, t]) => `   <property name="${k}"${t ? ` type="${t}"` : ""} value="${v}"/>`).join("\n")}\n  </properties>\n`;
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
  const grp = (name, body) => ` <objectgroup id="${lid++}" name="${name}">\n${body}\n </objectgroup>`;
  const groups = [
    grp("collision", coll.join("\n")),
    grp("doors", doors),
    grp("interactables", interact),
    grp("spawns", spawns),
    grp("zones", zones),
    grp("surfaces", surfaces),
    grp("roofs", roofs),
    grp("lights", lights.join("\n")),
  ];

  return `<?xml version="1.0" encoding="UTF-8"?>
<!-- GENERATED by games/quebrada/tools/tilegen (make tiles): demo of the buildings sheet (issue #71).
     40x30 tiles of 16 px. Tilesets: town (firstgid 1) and buildings (firstgid ${B_FIRSTGID}). Layers: ground, overlay,
     objects (ysort: trunks, hedges), buildings (ysort: walls of every building), windows_lit (ysort, alpha follows
     dusk/night), roof_<name> (above, roof_of = <name>, faded by scripts/roofs.lua), canopy (above).
     The footprint rects in "collision" cover the roof-covered part of each building (roof tiles cannot be solid).
     See games/quebrada/docs/buildings.md. -->
<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" width="${MAP_W}" height="${MAP_H}" tilewidth="${SIZE}" tileheight="${SIZE}" infinite="0" nextlayerid="${lid}" nextobjectid="${nid}">
 <tileset firstgid="${TOWN_FIRSTGID}" source="../tilesets/town.tsx"/>
 <tileset firstgid="${B_FIRSTGID}" source="../tilesets/buildings.tsx"/>
${layers.join("\n")}
${groups.join("\n")}
</map>
`;
}

/** Compose a picture of the map. opts: { night, roofs } (roofs defaults to true). */
export function renderBuildingsMap({ night = false, roofs = true } = {}) {
  const town = renderSheet();
  const bsheet = renderBuildingSheet();
  const { L } = buildDemo();
  const draw = (out, name) => {
    for (let i = 0; i < L[name].length; i++) {
      const g = L[name][i];
      if (!g) continue;
      const [sheet, id, cols] = g >= B_FIRSTGID ? [bsheet, g - B_FIRSTGID, B_COLS] : [town, g - TOWN_FIRSTGID, COLS];
      out.blit(sheet.slice((id % cols) * SIZE, Math.floor(id / cols) * SIZE, SIZE, SIZE), (i % MAP_W) * SIZE, Math.floor(i / MAP_W) * SIZE);
    }
  };
  const out = new Frame(MAP_W * SIZE, MAP_H * SIZE);
  for (const n of ["ground", "overlay", "objects", "buildings"]) draw(out, n);
  if (roofs) for (const b of BUILDINGS) draw(out, `roof_${b.name}`);
  draw(out, "canopy");
  if (!night) return out;
  const dark = out.darkened(0.35);
  draw(dark, "windows_lit");
  return dark;
}
