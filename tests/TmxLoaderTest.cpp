#include <iostream>
#include <string>

#include <sol/sol.hpp>

#include "../src/Map/TmxLoader.hpp"
#include "../src/Map/TmxLua.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Se ejecuta desde la raiz del repo (make test)
static const char* MAP_PATH = "tests/fixtures/tmx/map.tmx";

static const tmx::Object* findObject(const tmx::Map& map, const std::string& name) {
  for (const auto& l : map.layers) {
    for (const auto& o : l.objects) {
      if (o.name == name) return &o;
    }
  }
  return nullptr;
}

static const tmx::Property* findProp(const tmx::Properties& props, const std::string& name) {
  for (const auto& p : props) {
    if (p.name == name) return &p;
  }
  return nullptr;
}

static void testBase64() {
  std::string out;
  CHECK(tmx::base64Decode("SGVsbG8=", out));
  CHECK(out == "Hello");
  CHECK(tmx::base64Decode("SGVs\n  bG8h", out));
  CHECK(out == "Hello!");
  CHECK(tmx::base64Decode("", out));
  CHECK(out.empty());
  CHECK(!tmx::base64Decode("SG!s", out));
}

static void testJoinPath() {
  CHECK(tmx::joinPath("a/b", "c.png") == "a/b/c.png");
  CHECK(tmx::joinPath("a/b", "../c.png") == "a/c.png");
  CHECK(tmx::joinPath("a/b", "./c/./d.png") == "a/b/c/d.png");
  CHECK(tmx::joinPath("", "c.png") == "c.png");
  CHECK(tmx::joinPath("a", "../../c.png") == "../c.png");
  CHECK(tmx::joinPath("a/b", "/abs/c.png") == "/abs/c.png");
}

static void testLayerEncodings() {
  tmx::Result r = tmx::loadFile(MAP_PATH);
  CHECK(r.ok);
  if (!r.ok) {
    std::cerr << r.error << std::endl;
    return;
  }
  const tmx::Map& m = r.map;
  CHECK(m.width == 4 && m.height == 3);
  CHECK(m.tileWidth == 16 && m.tileHeight == 16);
  CHECK(m.orientation == "orthogonal");
  CHECK(m.type == "town");
  CHECK(m.layers.size() == 4);
  if (m.layers.size() < 4) return;

  const std::vector<uint32_t> expected = {1, 2147483650u, 3, 4, 5, 6, 0, 8, 9, 10, 11, 12};
  CHECK(m.layers[0].name == "ground");
  CHECK(m.layers[0].data == expected);  // CSV
  CHECK(m.layers[1].data == expected);  // base64 + zlib
  CHECK(m.layers[2].data == expected);  // base64 + gzip
  CHECK((m.layers[0].data[1] & tmx::FLIP_H) != 0);
  CHECK(tmx::gidOf(m.layers[0].data[1]) == 2);

  const tmx::Property* title = findProp(m.properties, "title");
  CHECK(title && title->stringValue == "Test Town");
  const tmx::Property* diff = findProp(m.properties, "difficulty");
  CHECK(diff && diff->type == tmx::PropType::Int && diff->intValue == 3);
}

static void testTilesets() {
  tmx::Result r = tmx::loadFile(MAP_PATH);
  CHECK(r.ok);
  if (!r.ok || r.map.tilesets.size() != 2) {
    CHECK(false);
    return;
  }
  const tmx::Map& m = r.map;
  const tmx::Tileset& ext = m.tilesets[0];
  CHECK(ext.firstGid == 1);
  CHECK(ext.name == "terrain");
  CHECK(ext.columns == 4 && ext.tileCount == 8);
  CHECK(ext.imagePath == "tests/fixtures/tmx/gfx/tiles.png");
  CHECK(ext.tiles.count(1) == 1);
  if (ext.tiles.count(1)) {
    const auto& anim = ext.tiles.at(1).animation;
    CHECK(anim.size() == 2);
    if (anim.size() == 2) {
      CHECK(anim[0].tileId == 1 && anim[0].durationMs == 100);
      CHECK(anim[1].tileId == 2 && anim[1].durationMs == 200);
    }
  }
  CHECK(ext.tiles.count(3) == 1);
  if (ext.tiles.count(3)) {
    CHECK(ext.tiles.at(3).type == "water");
    const tmx::Property* solid = findProp(ext.tiles.at(3).properties, "solid");
    CHECK(solid && solid->type == tmx::PropType::Bool && solid->boolValue);
  }

  const tmx::Tileset& emb = m.tilesets[1];
  CHECK(emb.firstGid == 9);
  CHECK(emb.name == "props");
  CHECK(emb.source.empty());
  CHECK(emb.imagePath == "tests/fixtures/tmx/props.png");

  CHECK(tmx::tilesetForGid(m, 0) == nullptr);
  CHECK(tmx::tilesetForGid(m, 1) == &m.tilesets[0]);
  CHECK(tmx::tilesetForGid(m, 8) == &m.tilesets[0]);
  CHECK(tmx::tilesetForGid(m, 9) == &m.tilesets[1]);
  // los flags no cuentan
  CHECK(tmx::tilesetForGid(m, 2147483650u) == &m.tilesets[0]);
  CHECK(tmx::tilesetForGid(m, 9u | tmx::FLIP_H | tmx::FLIP_V) == &m.tilesets[1]);
}

static void testObjects() {
  tmx::Result r = tmx::loadFile(MAP_PATH);
  CHECK(r.ok);
  if (!r.ok) return;
  const tmx::Map& m = r.map;

  const tmx::Object* spawn = findObject(m, "player_spawn");
  CHECK(spawn != nullptr);
  if (spawn) {
    CHECK(spawn->shape == tmx::Shape::Rect);
    CHECK(spawn->type == "spawn");  // class
    CHECK(spawn->x == 16 && spawn->y == 16 && spawn->width == 16 && spawn->height == 16);
    const tmx::Property* label = findProp(spawn->properties, "label");
    CHECK(label && label->type == tmx::PropType::String && label->stringValue == "start");
    const tmx::Property* slots = findProp(spawn->properties, "slots");
    CHECK(slots && slots->type == tmx::PropType::Int && slots->intValue == 4);
    const tmx::Property* speed = findProp(spawn->properties, "speed");
    CHECK(speed && speed->type == tmx::PropType::Float && speed->floatValue == 2.5);
    const tmx::Property* active = findProp(spawn->properties, "active");
    CHECK(active && active->type == tmx::PropType::Bool && active->boolValue);
    const tmx::Property* note = findProp(spawn->properties, "note");
    CHECK(note && note->stringValue == "line1\nline2");
  }

  const tmx::Object* door = findObject(m, "door");
  CHECK(door && door->type == "door");  // atributo "type" del formato antiguo

  const tmx::Object* marker = findObject(m, "marker");
  CHECK(marker && marker->shape == tmx::Shape::Point);

  const tmx::Object* pond = findObject(m, "pond");
  CHECK(pond && pond->shape == tmx::Shape::Ellipse && pond->width == 24);

  const tmx::Object* roof = findObject(m, "roof");
  CHECK(roof && roof->shape == tmx::Shape::Polygon);
  if (roof) {
    CHECK(roof->points.size() == 3);
    if (roof->points.size() == 3) {
      CHECK(roof->points[1].first == 16 && roof->points[1].second == 0);
      CHECK(roof->points[2].first == 16 && roof->points[2].second == 16);
    }
  }

  const tmx::Object* crate = findObject(m, "crate");
  CHECK(crate && crate->shape == tmx::Shape::Tile);
  if (crate) {
    CHECK(crate->gid == 2147483657u);
    CHECK(tmx::gidOf(crate->gid) == 9);
    const tmx::Rect rect = tmx::objectRect(*crate);
    CHECK(rect.x == 48 && rect.y == 16 && rect.w == 16 && rect.h == 16);  // y de arriba
  }
}

static void testErrors() {
  tmx::Result missing = tmx::loadFile("tests/fixtures/tmx/no_existe.tmx");
  CHECK(!missing.ok && !missing.error.empty());

  tmx::Result inf = tmx::loadFile("tests/fixtures/tmx/infinite.tmx");
  CHECK(!inf.ok);
  CHECK(inf.error.find("infinit") != std::string::npos);

  tmx::Result bad = tmx::loadString("<map", "");
  CHECK(!bad.ok);

  tmx::Result iso = tmx::loadString("<map orientation=\"isometric\" width=\"1\" height=\"1\" tilewidth=\"1\" tileheight=\"1\"/>", "");
  CHECK(!iso.ok);
  CHECK(iso.error.find("isometric") != std::string::npos);

  tmx::Result zstd = tmx::loadString(
      "<map orientation=\"orthogonal\" width=\"1\" height=\"1\" tilewidth=\"1\" tileheight=\"1\">"
      "<layer id=\"1\" name=\"l\" width=\"1\" height=\"1\"><data encoding=\"base64\" compression=\"zstd\">AAAA</data></layer></map>",
      "");
  CHECK(!zstd.ok);
  CHECK(zstd.error.find("zstd") != std::string::npos);

  tmx::Result count = tmx::loadString(
      "<map orientation=\"orthogonal\" width=\"2\" height=\"2\" tilewidth=\"1\" tileheight=\"1\">"
      "<layer id=\"1\" name=\"l\" width=\"2\" height=\"2\"><data encoding=\"csv\">1,2,3</data></layer></map>",
      "");
  CHECK(!count.ok);

  tmx::Result xmlTiles = tmx::loadString(
      "<map orientation=\"orthogonal\" width=\"2\" height=\"1\" tilewidth=\"1\" tileheight=\"1\">"
      "<layer id=\"1\" name=\"l\" width=\"2\" height=\"1\"><data><tile gid=\"5\"/><tile gid=\"0\"/></data></layer></map>",
      "");
  CHECK(xmlTiles.ok);
  if (xmlTiles.ok) CHECK(xmlTiles.map.layers[0].data.size() == 2 && xmlTiles.map.layers[0].data[0] == 5);
}

static void testLua() {
  tmx::Result r = tmx::loadFile(MAP_PATH);
  CHECK(r.ok);
  if (!r.ok) return;

  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  lua["map"] = tmx::tmxToLua(lua, r.map);

  auto check = [&](const std::string& expr) {
    sol::object o = lua.script("return " + expr);
    const bool ok = o.is<bool>() && o.as<bool>();
    if (!ok) {
      std::cerr << "Lua check failed: " << expr << std::endl;
      failures++;
    }
  };

  check("map.width == 4 and map.height == 3 and map.orientation == 'orthogonal'");
  check("map.class == 'town'");
  check("math.type(map.properties.difficulty) == 'integer'");
  check("map.properties.title == 'Test Town'");
  check("#map.tilesets == 2 and map.tilesets[1].firstgid == 1");
  check("map.tilesets[1].tiles[1].animation[2].duration == 200");
  check("map.tilesets[1].tiles[3].type == 'water'");
  check("map.tilesets[1].tiles[3].properties.solid == true");
  check("#map.layers == 4 and map.layers[1].kind == 'tile' and map.layers[4].kind == 'object'");
  check("#map.layers[1].data == 12 and map.layers[1].data[2] == 2");  // flags quitados
  check("map.layers[1].flips[2].h == true and map.layers[1].flips[2].v == false");
  check("map.layers[1].flips[1] == nil");
  check("map.layers[2].data[2] == 2 and map.layers[3].data[12] == 12");
  check("#map.objects == 6");

  check("map.objects[1].name == 'player_spawn' and map.objects[1].class == nil and map.objects[1].type == 'spawn'");
  check("map.objects[1].layer == 'entities' and map.objects[1].shape == 'rect'");
  check("math.type(map.objects[1].properties.slots) == 'integer'");
  check("math.type(map.objects[1].properties.speed) == 'float'");
  check("map.objects[1].properties.speed == 2.5");
  check("type(map.objects[1].properties.active) == 'boolean' and map.objects[1].properties.active == true");
  check("type(map.objects[1].properties.label) == 'string' and map.objects[1].properties.label == 'start'");
  check("map.objects[1].rect.x == 16 and map.objects[1].rect.w == 16");
  check("map.objects[5].shape == 'polygon' and #map.objects[5].points == 3 and map.objects[5].points[2].x == 16");
  check("map.objects[6].shape == 'tile' and map.objects[6].gid == 9 and map.objects[6].flip_h == true and map.objects[6].flip_v == false");
  check("map.objects[6].rect.y == 16");
}

int main() {
  testBase64();
  testJoinPath();
  testLayerEncodings();
  testTilesets();
  testObjects();
  testErrors();
  testLua();

  if (failures == 0) {
    std::cout << "TmxLoaderTest: OK" << std::endl;
    return 0;
  }
  std::cerr << "TmxLoaderTest: " << failures << " fallo(s)" << std::endl;
  return 1;
}
