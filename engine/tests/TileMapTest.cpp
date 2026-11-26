#include <algorithm>
#include <iostream>
#include <string>
#include <vector>

#include "../src/Map/TileMap.hpp"
#include "../src/Map/TileMath.hpp"
#include "../src/Map/TmxLoader.hpp"
#include "../src/Util/YSort.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Se ejecuta desde engine/ (make test)
static const char* RENDER_PATH = "tests/fixtures/tmx/render.tmx";

static void testFloorDiv() {
  CHECK(tilemap::floorDiv(-1, 16) == -1);
  CHECK(tilemap::floorDiv(0, 16) == 0);
  CHECK(tilemap::floorDiv(-16, 16) == -1);
  CHECK(tilemap::floorDiv(-17, 16) == -2);
  CHECK(tilemap::floorDiv(15, 16) == 0);
  CHECK(tilemap::floorDiv(31, 16) == 1);
}

static void testVisibleTiles() {
  tilemap::TileRange r = tilemap::visibleTiles(0, 0, 480, 270, 0, 0, 16, 16, 200, 200, 0, 0);
  CHECK(r.col0 == 0 && r.col1 == 30 && r.row0 == 0 && r.row1 == 17);
  CHECK(!r.empty());

  // Una camara a mitad de tile necesita una columna mas
  r = tilemap::visibleTiles(8, 0, 480, 270, 0, 0, 16, 16, 200, 200, 0, 0);
  CHECK(r.col0 == 0 && r.col1 == 31);

  // Camara con coordenadas negativas: se recorta a 0
  r = tilemap::visibleTiles(-50, -50, 480, 270, 0, 0, 16, 16, 200, 200, 0, 0);
  CHECK(r.col0 == 0 && r.row0 == 0 && r.col1 == 27 && r.row1 == 14);

  // Camara pasada el mapa: vacio
  r = tilemap::visibleTiles(5000, 0, 480, 270, 0, 0, 16, 16, 200, 200, 0, 0);
  CHECK(r.empty());
  r = tilemap::visibleTiles(0, 5000, 480, 270, 0, 0, 16, 16, 200, 200, 0, 0);
  CHECK(r.empty());

  // Tiles mas altos que la rejilla: una fila de mas por abajo
  r = tilemap::visibleTiles(0, 0, 480, 270, 0, 0, 16, 16, 200, 200, 0, 16);
  CHECK(r.row1 == 18);
  // Mas anchos: una columna de mas por la izquierda
  r = tilemap::visibleTiles(64, 0, 480, 270, 0, 0, 16, 16, 200, 200, 0, 0);
  const int plainCol0 = r.col0;
  r = tilemap::visibleTiles(64, 0, 480, 270, 0, 0, 16, 16, 200, 200, 16, 0);
  CHECK(r.col0 == plainCol0 - 1);

  // El origen de la capa desplaza el rango
  r = tilemap::visibleTiles(0, 0, 480, 270, 32, 0, 16, 16, 200, 200, 0, 0);
  CHECK(r.col0 == 0 && r.col1 == 28);

  // El numero de celdas no depende del tamaño del mapa
  for (int camX = 0; camX < 60; camX += 7) {
    for (int camY = 0; camY < 60; camY += 7) {
      r = tilemap::visibleTiles(camX, camY, 480, 270, 0, 0, 16, 16, 100000, 100000, 0, 0);
      CHECK(r.col1 - r.col0 <= 32);
      CHECK(r.row1 - r.row0 <= 19);
    }
  }
}

static void testAnimFrame() {
  const std::vector<int> d = {100, 200};
  CHECK(tilemap::animFrame(d, 0) == 0);
  CHECK(tilemap::animFrame(d, 99) == 0);
  CHECK(tilemap::animFrame(d, 100) == 1);
  CHECK(tilemap::animFrame(d, 299) == 1);
  CHECK(tilemap::animFrame(d, 300) == 0);
  const int big = tilemap::animFrame(d, 1e9);
  CHECK(big == 0 || big == 1);
  CHECK(tilemap::animFrame({}, 50) == 0);

  // Duracion 0 = 100 ms
  const std::vector<int> z = {0, 0};
  CHECK(tilemap::animFrame(z, 0) == 0);
  CHECK(tilemap::animFrame(z, 99) == 0);
  CHECK(tilemap::animFrame(z, 100) == 1);
  CHECK(tilemap::animFrame(z, 200) == 0);
}

// Aplica los flags al estilo Tiled (transponer si D, luego H, luego V)
static void tiledApply(uint32_t raw, int x, int y, int& ox, int& oy) {
  if (raw & tmx::FLIP_D) std::swap(x, y);
  if (raw & tmx::FLIP_H) x = -x;
  if (raw & tmx::FLIP_V) y = -y;
  ox = x;
  oy = y;
}

// Y al estilo SDL: voltear y despues girar en sentido horario (y hacia abajo)
static void sdlApply(const tilemap::TileTransform& t, int x, int y, int& ox, int& oy) {
  if (t.flipH) x = -x;
  if (t.flipV) y = -y;
  const int angle = static_cast<int>(t.angle);
  if (angle == 90) {
    ox = -y;
    oy = x;
  } else if (angle == 180) {
    ox = -x;
    oy = -y;
  } else if (angle == 270) {
    ox = y;
    oy = -x;
  } else {
    ox = x;
    oy = y;
  }
}

static void testFlipTransform() {
  const uint32_t bits[3] = {tmx::FLIP_H, tmx::FLIP_V, tmx::FLIP_D};
  for (int mask = 0; mask < 8; mask++) {
    uint32_t raw = 5;
    for (int b = 0; b < 3; b++) {
      if (mask & (1 << b)) raw |= bits[b];
    }
    const tilemap::TileTransform t = tilemap::flipTransform(raw);
    int ex, ey, gx, gy;
    tiledApply(raw, 2, 3, ex, ey);
    sdlApply(t, 2, 3, gx, gy);
    CHECK(ex == gx && ey == gy);
    tiledApply(raw, -1, 4, ex, ey);
    sdlApply(t, -1, 4, gx, gy);
    CHECK(ex == gx && ey == gy);
  }
  // Sin D no hay giro
  CHECK(tilemap::flipTransform(tmx::FLIP_H).angle == 0 && tilemap::flipTransform(tmx::FLIP_H).flipH);
  CHECK(tilemap::flipTransform(0).angle == 0 && !tilemap::flipTransform(0).flipH &&
        !tilemap::flipTransform(0).flipV);
  CHECK(tilemap::flipTransform(tmx::FLIP_D | tmx::FLIP_H).angle == 90);
  CHECK(tilemap::flipTransform(tmx::FLIP_D | tmx::FLIP_V).angle == 270);
}

static void testYSort() {
  ysort::Item tileA = {10, ysort::KindTile, 5, 0};
  ysort::Item spriteA = {10, ysort::KindSprite, 1, 0};
  CHECK(ysort::less(tileA, spriteA));
  CHECK(!ysort::less(spriteA, tileA));

  ysort::Item low = {9, ysort::KindSprite, 9, 0};
  CHECK(ysort::less(low, tileA));
  CHECK(!ysort::less(tileA, low));

  ysort::Item s1 = {10, ysort::KindSprite, 1, 0};
  ysort::Item s2 = {10, ysort::KindSprite, 2, 1};
  CHECK(ysort::less(s1, s2));
  CHECK(!ysort::less(s2, s1));
  CHECK(!ysort::less(s1, s1));

  CHECK(ysort::spriteSortY(100, -1, 32, 1.0) == 132);
  CHECK(ysort::spriteSortY(100, 16, 32, 1.0) == 116);
  CHECK(ysort::spriteSortY(100, -1, 32, 2.0) == 164);
  CHECK(ysort::spriteSortY(100, 8, 32, 2.0) == 116);
  CHECK(ysort::spriteSortY(100.7, -1, 10, 1.0) == 110);

  // Aceptacion: tronco con sortY 100; el jugador con los pies en 90 queda detras
  // y con los pies en 110, delante
  for (int feet : {90, 110}) {
    std::vector<ysort::Item> items;
    items.push_back({100, ysort::KindTile, 0, 0});
    items.push_back({ysort::spriteSortY(feet - 32, -1, 32, 1.0), ysort::KindSprite, 1, 0});
    std::sort(items.begin(), items.end(), ysort::less);
    if (feet == 90) {
      CHECK(items[0].kind == ysort::KindSprite);
    } else {
      CHECK(items[0].kind == ysort::KindTile);
    }
  }
}

static const tilemap::Layer* findLayer(const tilemap::TileMap& map, const std::string& name) {
  for (const auto& l : map.layers) {
    if (!l.names.empty() && l.names.front() == name) return &l;
  }
  return nullptr;
}

static void testBuild() {
  tmx::Result loaded = tmx::loadFile(RENDER_PATH);
  CHECK(loaded.ok);
  if (!loaded.ok) {
    std::cerr << loaded.error << std::endl;
    return;
  }

  tilemap::BuildResult built = tilemap::build(loaded.map, tilemap::BuildOptions());
  CHECK(built.ok);
  if (!built.ok) return;
  CHECK(built.warnings.empty());
  tilemap::TileMap& map = built.map;

  CHECK(map.tileWidth == 16 && map.tileHeight == 16);
  CHECK(map.width == 8 && map.height == 6);
  CHECK(map.pixelWidth() == 128 && map.pixelHeight() == 96);
  CHECK(map.maxTileW == 16 && map.maxTileH == 32);

  // Pasadas; la capa de colisiones (solo datos) no se guarda
  CHECK(map.layers.size() == 4);
  CHECK(findLayer(map, "collision") == nullptr);
  const tilemap::Layer* ground = findLayer(map, "ground");
  const tilemap::Layer* trees = findLayer(map, "trees");
  const tilemap::Layer* roof = findLayer(map, "roof");
  const tilemap::Layer* props = findLayer(map, "props");
  CHECK(ground && trees && roof && props);
  if (!ground || !trees || !roof || !props) return;
  CHECK(ground->pass == tilemap::Pass::Ground && !ground->isObjects);
  CHECK(trees->pass == tilemap::Pass::YSort && !trees->isObjects);
  CHECK(roof->pass == tilemap::Pass::Above && !roof->isObjects);
  CHECK(props->pass == tilemap::Pass::YSort && props->isObjects);
  CHECK(ground->hasAnimatedTiles);
  CHECK(!trees->hasAnimatedTiles);

  // El tejado hereda del grupo: nombres, roof_of, offset y opacidad
  CHECK(roof->names.size() == 2 && roof->names[0] == "roof" && roof->names[1] == "casa_mama");
  CHECK(roof->roofOf == "casa_mama");
  CHECK(roof->originX == 8);
  CHECK(roof->opacity == 0.5);
  CHECK(ground->originX == 0 && ground->opacity == 1.0);

  std::vector<tilemap::TileInstance> out;

  // Capa ysort: tiles altos alineados abajo y con sortY
  tilemap::appendLayerInstances(map, *trees, 0, 0, 128, 96, out);
  CHECK(out.size() == 3);
  if (out.size() == 3) {
    // fila a fila: (0,0) con volteo H, (3,2), (5,4)
    CHECK((out[0].flags & tmx::FLIP_H) != 0);
    CHECK(out[0].dx == 0 && out[0].dy == 16 - 32);
    CHECK(out[1].dx == 48 && out[1].dy == 3 * 16 - 32);
    CHECK(out[1].sortY == 48);
    CHECK(out[1].flags == 0);
    CHECK(out[1].dw == 16 && out[1].dh == 32);
    CHECK(out[2].sortY == 5 * 16 - 4);
    CHECK(out[2].sx == 16 && out[2].sy == 0);
  }

  // Tile object
  out.clear();
  tilemap::appendLayerInstances(map, *props, 0, 0, 128, 96, out);
  CHECK(out.size() == 1);
  if (out.size() == 1) {
    CHECK(out[0].sortY == 80);
    CHECK(out[0].dx == 64 && out[0].dy == 48);
    CHECK(out[0].dw == 16 && out[0].dh == 32);
    CHECK(out[0].rotation == 0 && !out[0].pivotBottomLeft);
  }
  // Fuera de camara
  out.clear();
  tilemap::appendLayerInstances(map, *props, 0, 0, 32, 32, out);
  CHECK(out.empty());

  // Tejado: alpha = opacidad * alpha
  out.clear();
  tilemap::appendLayerInstances(map, *roof, 0, 0, 128, 96, out);
  CHECK(out.size() == 2);
  if (out.size() == 2) {
    CHECK(out[0].alpha == 128);
    CHECK(out[0].dx == 8 + 16 && out[0].dy == 2 * 16 - 16);
  }
  int touched = 0;
  tilemap::forEachLayerNamed(map, "casa_mama", [&](tilemap::Layer& l) {
    l.alpha = 128;
    touched++;
  });
  CHECK(touched == 1);
  out.clear();
  tilemap::appendLayerInstances(map, *roof, 0, 0, 128, 96, out);
  CHECK(out.size() == 2 && out[0].alpha == 64);
  touched = 0;
  tilemap::forEachLayerNamed(map, "roof", [&](tilemap::Layer&) { touched++; });
  CHECK(touched == 1);
  touched = 0;
  tilemap::forEachLayerNamed(map, "nothing", [&](tilemap::Layer&) { touched++; });
  CHECK(touched == 0);

  // alpha 0 o capa oculta: no se dibuja
  tilemap::Layer hidden = *roof;
  hidden.alpha = 0;
  out.clear();
  tilemap::appendLayerInstances(map, hidden, 0, 0, 128, 96, out);
  CHECK(out.empty());
  hidden.alpha = 255;
  hidden.visible = false;
  tilemap::appendLayerInstances(map, hidden, 0, 0, 128, 96, out);
  CHECK(out.empty());

  // Una camara pequeña limita las celdas (la fila extra es por los tiles altos)
  out.clear();
  tilemap::appendLayerInstances(map, *ground, 0, 0, 16, 16, out);
  CHECK(out.size() == 2);
  out.clear();
  tilemap::appendLayerInstances(map, *ground, 0, 0, 128, 96, out);
  CHECK(out.size() == 48);

  // Animacion: el gid 2 alterna con el 3 (frames de 100 y 200 ms)
  CHECK(map.displayGid(2) == 2);
  CHECK(map.displayGid(1) == 1);
  CHECK(out.size() == 48 && out[7].sx == 16);
  map.advance(100);
  CHECK(map.displayGid(2) == 3);
  out.clear();
  tilemap::appendLayerInstances(map, *ground, 0, 0, 128, 96, out);
  CHECK(out.size() == 48 && out[7].sx == 32);
  map.advance(200);
  CHECK(map.displayGid(2) == 2);

  CHECK(map.def(0) == nullptr);
  CHECK(map.def(9999) == nullptr);
  CHECK(map.def(9) != nullptr);
}

static void testBuildOptionsAndErrors() {
  tmx::Result loaded = tmx::loadFile(RENDER_PATH);
  CHECK(loaded.ok);
  if (!loaded.ok) return;

  tilemap::BuildOptions opts;
  opts.x = 100;
  opts.y = 50;
  tilemap::BuildResult built = tilemap::build(loaded.map, opts);
  CHECK(built.ok);
  if (built.ok) {
    const tilemap::Layer* ground = findLayer(built.map, "ground");
    const tilemap::Layer* props = findLayer(built.map, "props");
    CHECK(ground && ground->originX == 100 && ground->originY == 50);
    CHECK(props && props->objects.size() == 1 && props->objects[0].x == 164 && props->objects[0].y == 130);
  }

  tmx::Map iso = loaded.map;
  iso.orientation = "isometric";
  tilemap::BuildResult bad = tilemap::build(iso, tilemap::BuildOptions());
  CHECK(!bad.ok && !bad.error.empty());
}

int main() {
  testFloorDiv();
  testVisibleTiles();
  testAnimFrame();
  testFlipTransform();
  testYSort();
  testBuild();
  testBuildOptionsAndErrors();

  if (failures == 0) {
    std::cout << "TileMapTest: OK" << std::endl;
    return 0;
  }
  std::cerr << "TileMapTest: " << failures << " fallo(s)" << std::endl;
  return 1;
}
