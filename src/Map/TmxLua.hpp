#pragma once

#include <sol/sol.hpp>

#include "TmxLoader.hpp"

// Convierte un tmx::Map en tablas de Lua. Enteros -> lua_Integer, floats ->
// double, bool -> boolean, string/color/file -> string, object -> id entero.

namespace tmx {

inline void propertiesToLua(sol::state_view lua, const Properties& props, sol::table out) {
  (void)lua;
  for (const Property& p : props) {
    switch (p.type) {
      case PropType::Int:
      case PropType::Object:
        out[p.name] = static_cast<lua_Integer>(p.intValue);
        break;
      case PropType::Float:
        out[p.name] = p.floatValue;
        break;
      case PropType::Bool:
        out[p.name] = p.boolValue;
        break;
      default:
        out[p.name] = p.stringValue;
        break;
    }
  }
}

inline sol::table propertiesTable(sol::state_view lua, const Properties& props) {
  sol::table t = lua.create_table();
  propertiesToLua(lua, props, t);
  return t;
}

inline const char* shapeName(Shape s) {
  switch (s) {
    case Shape::Rect: return "rect";
    case Shape::Ellipse: return "ellipse";
    case Shape::Point: return "point";
    case Shape::Polygon: return "polygon";
    case Shape::Polyline: return "polyline";
    case Shape::Text: return "text";
    case Shape::Tile: return "tile";
  }
  return "rect";
}

inline sol::table objectToLua(sol::state_view lua, const Object& o, const std::string& layerName) {
  sol::table t = lua.create_table();
  t["id"] = o.id;
  t["name"] = o.name;
  t["type"] = o.type;
  t["layer"] = layerName;
  t["shape"] = shapeName(o.shape);
  t["x"] = o.x;
  t["y"] = o.y;
  t["width"] = o.width;
  t["height"] = o.height;
  t["rotation"] = o.rotation;
  t["visible"] = o.visible;
  const Rect r = objectRect(o);
  sol::table rect = lua.create_table();
  rect["x"] = r.x;
  rect["y"] = r.y;
  rect["w"] = r.w;
  rect["h"] = r.h;
  t["rect"] = rect;
  if (o.shape == Shape::Tile) {
    t["gid"] = static_cast<lua_Integer>(gidOf(o.gid));
    t["flip_h"] = (o.gid & FLIP_H) != 0;
    t["flip_v"] = (o.gid & FLIP_V) != 0;
  }
  if (!o.points.empty()) {
    sol::table pts = lua.create_table();
    int i = 1;
    for (const auto& p : o.points) {
      sol::table pt = lua.create_table();
      pt["x"] = p.first;
      pt["y"] = p.second;
      pts[i++] = pt;
    }
    t["points"] = pts;
  }
  if (o.shape == Shape::Text) t["text"] = o.text;
  t["properties"] = propertiesTable(lua, o.properties);
  return t;
}

inline sol::table layerToLua(sol::state_view lua, const Layer& l, sol::table flatObjects) {
  sol::table t = lua.create_table();
  switch (l.kind) {
    case LayerKind::Tile: t["kind"] = "tile"; break;
    case LayerKind::Object: t["kind"] = "object"; break;
    case LayerKind::Image: t["kind"] = "image"; break;
    case LayerKind::Group: t["kind"] = "group"; break;
  }
  t["id"] = l.id;
  t["name"] = l.name;
  t["class"] = l.type;
  t["visible"] = l.visible;
  t["opacity"] = l.opacity;
  t["offsetx"] = l.offsetX;
  t["offsety"] = l.offsetY;
  t["properties"] = propertiesTable(lua, l.properties);

  if (l.kind == LayerKind::Tile) {
    t["width"] = l.width;
    t["height"] = l.height;
    // data: gids sin flags (1-based, fila a fila). flips: solo las celdas
    // volteadas, indexadas igual que data, con {h, v, d} booleanos.
    sol::table data = lua.create_table();
    sol::table flips = lua.create_table();
    for (size_t i = 0; i < l.data.size(); i++) {
      const uint32_t raw = l.data[i];
      data[i + 1] = static_cast<lua_Integer>(gidOf(raw));
      if (raw & (FLIP_H | FLIP_V | FLIP_D)) {
        sol::table f = lua.create_table();
        f["h"] = (raw & FLIP_H) != 0;
        f["v"] = (raw & FLIP_V) != 0;
        f["d"] = (raw & FLIP_D) != 0;
        flips[i + 1] = f;
      }
    }
    t["data"] = data;
    t["flips"] = flips;
  } else if (l.kind == LayerKind::Object) {
    sol::table objects = lua.create_table();
    int i = 1;
    for (const Object& o : l.objects) {
      sol::table ot = objectToLua(lua, o, l.name);
      objects[i++] = ot;
      flatObjects[flatObjects.size() + 1] = ot;
    }
    t["objects"] = objects;
  } else if (l.kind == LayerKind::Image) {
    t["image"] = l.imagePath;
  } else {
    sol::table children = lua.create_table();
    int i = 1;
    for (const Layer& c : l.children) children[i++] = layerToLua(lua, c, flatObjects);
    t["layers"] = children;
  }
  return t;
}

inline sol::table tilesetToLua(sol::state_view lua, const Tileset& ts) {
  sol::table t = lua.create_table();
  t["firstgid"] = ts.firstGid;
  t["name"] = ts.name;
  t["source"] = ts.source;
  t["tilewidth"] = ts.tileWidth;
  t["tileheight"] = ts.tileHeight;
  t["tilecount"] = ts.tileCount;
  t["columns"] = ts.columns;
  t["spacing"] = ts.spacing;
  t["margin"] = ts.margin;
  t["image"] = ts.imagePath;
  t["imagewidth"] = ts.imageWidth;
  t["imageheight"] = ts.imageHeight;
  t["properties"] = propertiesTable(lua, ts.properties);
  sol::table tiles = lua.create_table();
  for (const auto& kv : ts.tiles) {
    const TileInfo& info = kv.second;
    sol::table ti = lua.create_table();
    ti["type"] = info.type;
    ti["properties"] = propertiesTable(lua, info.properties);
    sol::table anim = lua.create_table();
    int i = 1;
    for (const AnimationFrame& f : info.animation) {
      sol::table fr = lua.create_table();
      fr["tileid"] = f.tileId;
      fr["duration"] = f.durationMs;
      anim[i++] = fr;
    }
    ti["animation"] = anim;
    tiles[static_cast<lua_Integer>(kv.first)] = ti;
  }
  t["tiles"] = tiles;
  return t;
}

inline sol::table tmxToLua(sol::state_view lua, const Map& map) {
  sol::table t = lua.create_table();
  t["width"] = map.width;
  t["height"] = map.height;
  t["tilewidth"] = map.tileWidth;
  t["tileheight"] = map.tileHeight;
  t["orientation"] = map.orientation;
  t["class"] = map.type;
  t["properties"] = propertiesTable(lua, map.properties);

  sol::table tilesets = lua.create_table();
  int i = 1;
  for (const Tileset& ts : map.tilesets) tilesets[i++] = tilesetToLua(lua, ts);
  t["tilesets"] = tilesets;

  sol::table flat = lua.create_table();
  sol::table layers = lua.create_table();
  i = 1;
  for (const Layer& l : map.layers) layers[i++] = layerToLua(lua, l, flat);
  t["layers"] = layers;
  t["objects"] = flat;
  return t;
}

}  // namespace tmx
