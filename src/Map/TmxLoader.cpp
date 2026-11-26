#define PUGIXML_HEADER_ONLY
#include "pugixml/pugixml.hpp"

#include "TmxLoader.hpp"

#include <zlib.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <sstream>
#include <stdexcept>

namespace tmx {

namespace {

[[noreturn]] void fail(const std::string& msg) { throw std::runtime_error(msg); }

// ---- rutas -----------------------------------------------------------------

std::string dirName(const std::string& path) {
  const size_t pos = path.find_last_of("/\\");
  if (pos == std::string::npos) return "";
  return path.substr(0, pos);
}

bool isAbsolute(const std::string& p) {
  if (!p.empty() && (p[0] == '/' || p[0] == '\\')) return true;
  return p.size() > 1 && p[1] == ':';  // "C:"
}

// ---- helpers de XML --------------------------------------------------------

int attrInt(const pugi::xml_node& n, const char* name, int def = 0) {
  return n.attribute(name).as_int(def);
}

double attrDouble(const pugi::xml_node& n, const char* name, double def = 0.0) {
  return n.attribute(name).as_double(def);
}

// "class" (Tiled 1.9+) con respaldo en "type" (formato anterior)
std::string classOf(const pugi::xml_node& n) {
  pugi::xml_attribute a = n.attribute("class");
  if (a) return a.as_string();
  return n.attribute("type").as_string();
}

Properties parseProperties(const pugi::xml_node& node) {
  Properties out;
  pugi::xml_node props = node.child("properties");
  for (pugi::xml_node p : props.children("property")) {
    Property prop;
    prop.name = p.attribute("name").as_string();
    const std::string type = p.attribute("type").as_string("string");
    // Los strings multilinea van en el texto del elemento, no en "value"
    std::string value = p.attribute("value") ? p.attribute("value").as_string() : p.text().as_string();
    if (type == "int") {
      prop.type = PropType::Int;
      prop.intValue = std::strtoll(value.c_str(), nullptr, 10);
    } else if (type == "float") {
      prop.type = PropType::Float;
      prop.floatValue = std::strtod(value.c_str(), nullptr);
    } else if (type == "bool") {
      prop.type = PropType::Bool;
      prop.boolValue = (value == "true" || value == "1");
    } else if (type == "color") {
      prop.type = PropType::Color;
      prop.stringValue = value;
    } else if (type == "file") {
      prop.type = PropType::File;
      prop.stringValue = value;
    } else if (type == "object") {
      prop.type = PropType::Object;
      prop.intValue = std::strtoll(value.c_str(), nullptr, 10);
    } else {
      prop.type = PropType::String;
      prop.stringValue = value;
    }
    out.push_back(std::move(prop));
  }
  return out;
}

// ---- datos de las capas ----------------------------------------------------

int base64Value(unsigned char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+' || c == '-') return 62;
  if (c == '/' || c == '_') return 63;
  return -1;
}

// zlib y gzip se distinguen solos con windowBits 15+32
bool inflateAuto(const std::string& in, std::string& out) {
  z_stream zs;
  std::memset(&zs, 0, sizeof(zs));
  if (inflateInit2(&zs, 15 + 32) != Z_OK) return false;
  zs.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(in.data()));
  zs.avail_in = static_cast<uInt>(in.size());
  char buf[16384];
  int rc = Z_OK;
  while (rc == Z_OK) {
    zs.next_out = reinterpret_cast<Bytef*>(buf);
    zs.avail_out = sizeof(buf);
    rc = inflate(&zs, Z_NO_FLUSH);
    if (rc != Z_OK && rc != Z_STREAM_END) break;
    out.append(buf, sizeof(buf) - zs.avail_out);
  }
  inflateEnd(&zs);
  return rc == Z_STREAM_END;
}

void parseTileData(const pugi::xml_node& data, Layer& layer) {
  const std::string encoding = data.attribute("encoding").as_string();
  const std::string compression = data.attribute("compression").as_string();
  const size_t expected = static_cast<size_t>(layer.width) * static_cast<size_t>(layer.height);

  if (data.child("chunk")) fail("mapas infinitos (chunks) no soportados (capa '" + layer.name + "')");

  if (encoding.empty()) {
    for (pugi::xml_node t : data.children("tile")) {
      layer.data.push_back(static_cast<uint32_t>(t.attribute("gid").as_ullong(0)));
    }
  } else if (encoding == "csv") {
    const std::string text = data.text().as_string();
    size_t i = 0;
    while (i < text.size()) {
      while (i < text.size() && (text[i] == ',' || std::isspace(static_cast<unsigned char>(text[i])))) i++;
      if (i >= text.size()) break;
      char* end = nullptr;
      const unsigned long long v = std::strtoull(text.c_str() + i, &end, 10);
      if (end == text.c_str() + i) fail("CSV invalido en la capa '" + layer.name + "'");
      layer.data.push_back(static_cast<uint32_t>(v));
      i = static_cast<size_t>(end - text.c_str());
    }
  } else if (encoding == "base64") {
    std::string bytes;
    if (!base64Decode(data.text().as_string(), bytes)) fail("base64 invalido en la capa '" + layer.name + "'");
    if (compression == "zstd") fail("compresion zstd no soportada (capa '" + layer.name + "'); usa zlib, gzip o ninguna");
    if (compression == "zlib" || compression == "gzip") {
      std::string raw;
      if (!inflateAuto(bytes, raw)) fail("no se pudo descomprimir la capa '" + layer.name + "'");
      bytes.swap(raw);
    } else if (!compression.empty()) {
      fail("compresion desconocida '" + compression + "'");
    }
    if (bytes.size() % 4 != 0) fail("datos de la capa '" + layer.name + "' no son multiplo de 4 bytes");
    const unsigned char* p = reinterpret_cast<const unsigned char*>(bytes.data());
    for (size_t i = 0; i + 3 < bytes.size(); i += 4) {
      layer.data.push_back(static_cast<uint32_t>(p[i]) | (static_cast<uint32_t>(p[i + 1]) << 8) |
                           (static_cast<uint32_t>(p[i + 2]) << 16) | (static_cast<uint32_t>(p[i + 3]) << 24));
    }
  } else {
    fail("encoding '" + encoding + "' no soportado");
  }

  if (layer.data.size() != expected) {
    std::ostringstream os;
    os << "la capa '" << layer.name << "' tiene " << layer.data.size() << " tiles y se esperaban " << expected;
    fail(os.str());
  }
}

// ---- objetos ---------------------------------------------------------------

std::vector<std::pair<double, double>> parsePoints(const char* s) {
  std::vector<std::pair<double, double>> pts;
  std::istringstream in(s);
  std::string tok;
  while (in >> tok) {
    const size_t comma = tok.find(',');
    if (comma == std::string::npos) fail("puntos de polygon/polyline invalidos");
    pts.emplace_back(std::strtod(tok.substr(0, comma).c_str(), nullptr),
                     std::strtod(tok.substr(comma + 1).c_str(), nullptr));
  }
  return pts;
}

Object parseObject(const pugi::xml_node& n) {
  if (n.attribute("template")) fail("plantillas de objeto (template) no soportadas");
  Object o;
  o.id = attrInt(n, "id");
  o.name = n.attribute("name").as_string();
  o.type = classOf(n);
  o.x = attrDouble(n, "x");
  o.y = attrDouble(n, "y");
  o.width = attrDouble(n, "width");
  o.height = attrDouble(n, "height");
  o.rotation = attrDouble(n, "rotation");
  o.visible = n.attribute("visible").as_int(1) != 0;
  o.properties = parseProperties(n);
  if (n.attribute("gid")) {
    o.shape = Shape::Tile;
    o.gid = static_cast<uint32_t>(n.attribute("gid").as_ullong(0));
  } else if (n.child("ellipse")) {
    o.shape = Shape::Ellipse;
  } else if (n.child("point")) {
    o.shape = Shape::Point;
  } else if (pugi::xml_node poly = n.child("polygon")) {
    o.shape = Shape::Polygon;
    o.points = parsePoints(poly.attribute("points").as_string());
  } else if (pugi::xml_node line = n.child("polyline")) {
    o.shape = Shape::Polyline;
    o.points = parsePoints(line.attribute("points").as_string());
  } else if (pugi::xml_node text = n.child("text")) {
    o.shape = Shape::Text;
    o.text = text.text().as_string();
  }
  return o;
}

// ---- capas -----------------------------------------------------------------

Layer parseLayer(const pugi::xml_node& n, const std::string& kindName, const Map& map, const std::string& baseDir) {
  Layer l;
  l.id = attrInt(n, "id");
  l.name = n.attribute("name").as_string();
  l.type = classOf(n);
  l.visible = n.attribute("visible").as_int(1) != 0;
  l.opacity = attrDouble(n, "opacity", 1.0);
  l.offsetX = attrDouble(n, "offsetx");
  l.offsetY = attrDouble(n, "offsety");
  l.properties = parseProperties(n);

  if (kindName == "layer") {
    l.kind = LayerKind::Tile;
    l.width = attrInt(n, "width", map.width);
    l.height = attrInt(n, "height", map.height);
    parseTileData(n.child("data"), l);
  } else if (kindName == "objectgroup") {
    l.kind = LayerKind::Object;
    for (pugi::xml_node o : n.children("object")) l.objects.push_back(parseObject(o));
  } else if (kindName == "imagelayer") {
    l.kind = LayerKind::Image;
    pugi::xml_node img = n.child("image");
    if (img) l.imagePath = joinPath(baseDir, img.attribute("source").as_string());
  } else {
    l.kind = LayerKind::Group;
    for (pugi::xml_node c : n.children()) {
      const std::string name = c.name();
      if (name == "layer" || name == "objectgroup" || name == "imagelayer" || name == "group") {
        l.children.push_back(parseLayer(c, name, map, baseDir));
      }
    }
  }
  return l;
}

// ---- tilesets --------------------------------------------------------------

void parseTilesetNode(const pugi::xml_node& n, const std::string& imageDir, Tileset& ts) {
  ts.name = n.attribute("name").as_string();
  ts.tileWidth = attrInt(n, "tilewidth");
  ts.tileHeight = attrInt(n, "tileheight");
  ts.tileCount = attrInt(n, "tilecount");
  ts.columns = attrInt(n, "columns");
  ts.spacing = attrInt(n, "spacing");
  ts.margin = attrInt(n, "margin");
  ts.properties = parseProperties(n);
  pugi::xml_node img = n.child("image");
  if (img) {
    ts.imagePath = joinPath(imageDir, img.attribute("source").as_string());
    ts.imageWidth = attrInt(img, "width");
    ts.imageHeight = attrInt(img, "height");
  }
  for (pugi::xml_node t : n.children("tile")) {
    TileInfo info;
    info.id = attrInt(t, "id");
    info.type = classOf(t);
    info.properties = parseProperties(t);
    for (pugi::xml_node f : t.child("animation").children("frame")) {
      info.animation.push_back({attrInt(f, "tileid"), attrInt(f, "duration")});
    }
    if (!info.type.empty() || !info.properties.empty() || !info.animation.empty()) {
      ts.tiles[info.id] = std::move(info);
    }
  }
}

Tileset parseTileset(const pugi::xml_node& n, const std::string& baseDir) {
  Tileset ts;
  ts.firstGid = attrInt(n, "firstgid", 1);
  const std::string source = n.attribute("source").as_string();
  if (source.empty()) {
    parseTilesetNode(n, baseDir, ts);
    return ts;
  }
  ts.source = joinPath(baseDir, source);
  pugi::xml_document doc;
  pugi::xml_parse_result res = doc.load_file(ts.source.c_str());
  if (!res) fail("no se pudo leer el tileset '" + ts.source + "': " + res.description());
  pugi::xml_node root = doc.child("tileset");
  if (!root) fail("'" + ts.source + "' no es un tileset (.tsx)");
  parseTilesetNode(root, dirName(ts.source), ts);
  return ts;
}

Result parseDocument(const pugi::xml_document& doc, const std::string& baseDir) {
  Result result;
  try {
    pugi::xml_node root = doc.child("map");
    if (!root) fail("el archivo no tiene un elemento <map>");
    Map& map = result.map;
    map.version = root.attribute("version").as_string();
    map.orientation = root.attribute("orientation").as_string();
    if (map.orientation != "orthogonal") fail("orientacion '" + map.orientation + "' no soportada (solo orthogonal)");
    if (root.attribute("infinite").as_int(0) != 0) fail("mapas infinitos no soportados");
    map.renderOrder = root.attribute("renderorder").as_string();
    map.type = classOf(root);
    map.backgroundColor = root.attribute("backgroundcolor").as_string();
    map.width = attrInt(root, "width");
    map.height = attrInt(root, "height");
    map.tileWidth = attrInt(root, "tilewidth");
    map.tileHeight = attrInt(root, "tileheight");
    map.properties = parseProperties(root);

    for (pugi::xml_node c : root.children()) {
      const std::string name = c.name();
      if (name == "tileset") {
        map.tilesets.push_back(parseTileset(c, baseDir));
      } else if (name == "layer" || name == "objectgroup" || name == "imagelayer" || name == "group") {
        map.layers.push_back(parseLayer(c, name, map, baseDir));
      }
    }
    std::stable_sort(map.tilesets.begin(), map.tilesets.end(),
                     [](const Tileset& a, const Tileset& b) { return a.firstGid < b.firstGid; });
    result.ok = true;
  } catch (const std::exception& e) {
    result.ok = false;
    result.error = e.what();
    result.map = Map();
  }
  return result;
}

}  // namespace

std::string joinPath(const std::string& base, const std::string& rel) {
  std::string all = rel;
  if (!isAbsolute(rel) && !base.empty()) all = base + "/" + rel;
  const bool absolute = !all.empty() && (all[0] == '/' || all[0] == '\\');
  std::vector<std::string> parts;
  std::string cur;
  auto flush = [&]() {
    if (cur.empty() || cur == ".") {
      // nada
    } else if (cur == "..") {
      if (!parts.empty() && parts.back() != "..") {
        parts.pop_back();
      } else if (!absolute) {
        parts.push_back("..");
      }
    } else {
      parts.push_back(cur);
    }
    cur.clear();
  };
  for (char c : all) {
    if (c == '/' || c == '\\') flush();
    else cur += c;
  }
  flush();
  std::string out = absolute ? "/" : "";
  for (size_t i = 0; i < parts.size(); i++) {
    if (i) out += "/";
    out += parts[i];
  }
  return out;
}

bool base64Decode(const std::string& in, std::string& out) {
  out.clear();
  uint32_t acc = 0;
  int bits = 0;
  for (unsigned char c : in) {
    if (std::isspace(c)) continue;
    if (c == '=') break;
    const int v = base64Value(c);
    if (v < 0) return false;
    acc = (acc << 6) | static_cast<uint32_t>(v);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push_back(static_cast<char>((acc >> bits) & 0xFF));
    }
  }
  return true;
}

const Tileset* tilesetForGid(const Map& map, uint32_t gid) {
  const uint32_t g = gidOf(gid);
  if (g == 0) return nullptr;
  const Tileset* best = nullptr;
  for (const Tileset& ts : map.tilesets) {
    if (static_cast<uint32_t>(ts.firstGid) <= g) best = &ts;
  }
  return best;
}

Result loadFile(const std::string& path) {
  pugi::xml_document doc;
  pugi::xml_parse_result res = doc.load_file(path.c_str());
  if (!res) {
    Result r;
    r.error = "no se pudo leer '" + path + "': " + res.description();
    return r;
  }
  return parseDocument(doc, dirName(path));
}

Result loadString(const std::string& xml, const std::string& baseDir) {
  pugi::xml_document doc;
  pugi::xml_parse_result res = doc.load_string(xml.c_str());
  if (!res) {
    Result r;
    r.error = std::string("XML invalido: ") + res.description();
    return r;
  }
  return parseDocument(doc, baseDir);
}

}  // namespace tmx
