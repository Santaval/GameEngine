#pragma once

// Lector de mapas de Tiled (.tmx / .tsx). Sin SDL ni sol: solo datos. El paso a
// Lua vive en TmxLua.hpp. Ninguna funcion lanza excepciones hacia fuera; los
// errores vuelven en Result::error.

#include <cstdint>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace tmx {

// Flags de volteo en los bits altos de un gid
constexpr uint32_t FLIP_H = 0x80000000u;
constexpr uint32_t FLIP_V = 0x40000000u;
constexpr uint32_t FLIP_D = 0x20000000u;
constexpr uint32_t FLIP_HEX_ROT = 0x10000000u;
constexpr uint32_t GID_MASK = 0x0FFFFFFFu;

inline uint32_t gidOf(uint32_t raw) { return raw & GID_MASK; }

enum class PropType { String, Int, Float, Bool, Color, File, Object };

struct Property {
  std::string name;
  PropType type = PropType::String;
  std::string stringValue;  // String, Color y File
  int64_t intValue = 0;     // Int y Object (id del objeto)
  double floatValue = 0.0;
  bool boolValue = false;
};
using Properties = std::vector<Property>;

struct AnimationFrame {
  int tileId = 0;
  int durationMs = 0;
};

struct TileInfo {
  int id = 0;  // id local dentro del tileset
  std::string type;  // "class" (1.9+) o "type"
  Properties properties;
  std::vector<AnimationFrame> animation;
};

struct Tileset {
  int firstGid = 1;
  std::string name;
  std::string source;  // ruta del .tsx resuelta; vacia si va embebido
  int tileWidth = 0;
  int tileHeight = 0;
  int tileCount = 0;
  int columns = 0;
  int spacing = 0;
  int margin = 0;
  std::string imagePath;  // resuelta respecto al directorio del .tsx
  int imageWidth = 0;
  int imageHeight = 0;
  Properties properties;
  std::map<int, TileInfo> tiles;  // solo los tiles con tipo/propiedades/animacion
};

enum class Shape { Rect, Ellipse, Point, Polygon, Polyline, Text, Tile };

struct Object {
  int id = 0;
  std::string name;
  std::string type;  // "class" (1.9+) o "type"
  Shape shape = Shape::Rect;
  double x = 0, y = 0, width = 0, height = 0;  // tal cual en el TMX
  double rotation = 0;
  uint32_t gid = 0;  // crudo, con flags (solo Shape::Tile)
  bool visible = true;
  std::vector<std::pair<double, double>> points;  // relativos a (x, y)
  std::string text;
  Properties properties;
};

struct Rect {
  double x, y, w, h;
};

// Caja con la esquina superior izquierda. Tiled da la y de un tile object en su
// esquina inferior izquierda.
inline Rect objectRect(const Object& o) {
  if (o.shape == Shape::Tile) return {o.x, o.y - o.height, o.width, o.height};
  return {o.x, o.y, o.width, o.height};
}

enum class LayerKind { Tile, Object, Image, Group };

struct Layer {
  LayerKind kind = LayerKind::Tile;
  int id = 0;
  std::string name;
  std::string type;  // class
  bool visible = true;
  double opacity = 1.0;
  double offsetX = 0, offsetY = 0;
  int width = 0, height = 0;  // en tiles (solo Tile)
  Properties properties;
  std::vector<uint32_t> data;  // gids crudos (con flags), width*height
  std::vector<Object> objects;
  std::string imagePath;  // capas de imagen
  std::vector<Layer> children;  // grupos
};

struct Map {
  std::string version;
  std::string orientation;
  std::string renderOrder;
  std::string type;  // class
  std::string backgroundColor;
  int width = 0, height = 0;
  int tileWidth = 0, tileHeight = 0;
  Properties properties;
  std::vector<Tileset> tilesets;  // ordenados por firstGid
  std::vector<Layer> layers;
};

struct Result {
  bool ok = false;
  std::string error;
  Map map;
};

Result loadFile(const std::string& path);
// baseDir resuelve los .tsx externos y las imagenes de capas
Result loadString(const std::string& xml, const std::string& baseDir);

// Tileset al que pertenece un gid (los flags se ignoran). nullptr si gid == 0 o
// no cae en ninguno.
const Tileset* tilesetForGid(const Map& map, uint32_t gid);

// Decodifica base64 (ignora espacios). false si hay caracteres invalidos.
bool base64Decode(const std::string& in, std::string& out);

// Une dos rutas normalizando "./" y ".."
std::string joinPath(const std::string& base, const std::string& rel);

}  // namespace tmx
