#pragma once

#include <algorithm>
#include <iostream>
#include <string>
#include <tuple>
#include <utility>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"
#include "../Map/TileMap.hpp"
#include "../Map/TmxLua.hpp"
#include "../Systems/TileMapRenderSystem.hpp"

// Dibujado de mapas de Tiled (ver engine/docs/lua-api.md, "Tile map rendering").
// Las funciones de capa responden por el nombre de la capa o el de cualquier
// grupo que la contenga.

// load_tile_map(path, opts?) -> true, o nil, mensaje. opts = { x =, y = }. Una
// segunda llamada reemplaza al mapa anterior
inline std::tuple<sol::object, sol::object> loadTileMap(const std::string& path,
                                                        sol::optional<sol::table> opts, sol::this_state s) {
  sol::state_view lua(s);
  const double x = opts ? opts->get_or("x", 0.0) : 0.0;
  const double y = opts ? opts->get_or("y", 0.0) : 0.0;
  std::string error;
  if (!Game::getInstance().loadTileMap(path, x, y, error)) {
    std::cerr << "[TileMap] " << error << std::endl;
    return std::make_tuple(sol::object(sol::lua_nil), sol::make_object(lua, error));
  }
  return std::make_tuple(sol::make_object(lua, true), sol::object(sol::lua_nil));
}

inline void unloadTileMap() { Game::getInstance().unloadTileMap(); }

// Tamaño del mapa en px; 0, 0 si no hay mapa
inline std::tuple<int, int> getTileMapSize() {
  TileMapRenderSystem* tm = Game::getInstance().getTileMap();
  if (!tm) return std::make_tuple(0, 0);
  return std::make_tuple(tm->getMap().pixelWidth(), tm->getMap().pixelHeight());
}

inline const char* passName(tilemap::Pass pass) {
  switch (pass) {
    case tilemap::Pass::Ground: return "ground";
    case tilemap::Pass::YSort: return "ysort";
    case tilemap::Pass::Above: return "above";
  }
  return "ground";
}

inline sol::table getTileLayers(sol::this_state s) {
  sol::state_view lua(s);
  sol::table out = lua.create_table();
  TileMapRenderSystem* tm = Game::getInstance().getTileMap();
  if (!tm) return out;
  int i = 1;
  for (const tilemap::Layer& layer : tm->getMap().layers) {
    sol::table t = lua.create_table();
    t["name"] = layer.names.empty() ? std::string() : layer.names.front();
    t["pass"] = passName(layer.pass);
    t["visible"] = layer.visible;
    t["alpha"] = layer.alpha;
    t["opacity"] = layer.opacity;
    t["roof_of"] = layer.roofOf;
    t["properties"] = tmx::propertiesTable(lua, layer.properties);
    out[i++] = t;
  }
  return out;
}

inline int clampAlpha(int a) { return std::max(0, std::min(255, a)); }

// Devuelve cuantas capas cambio
inline int setLayerAlpha(const std::string& name, int alpha) {
  TileMapRenderSystem* tm = Game::getInstance().getTileMap();
  if (!tm) return 0;
  int count = 0;
  tilemap::forEachLayerNamed(tm->getMap(), name, [&](tilemap::Layer& layer) {
    layer.alpha = clampAlpha(alpha);
    count++;
  });
  return count;
}

inline sol::optional<int> getLayerAlpha(const std::string& name) {
  TileMapRenderSystem* tm = Game::getInstance().getTileMap();
  if (!tm) return sol::nullopt;
  sol::optional<int> result;
  tilemap::forEachLayerNamed(tm->getMap(), name, [&](tilemap::Layer& layer) {
    if (!result) result = layer.alpha;
  });
  return result;
}

inline int setLayerVisible(const std::string& name, bool visible) {
  TileMapRenderSystem* tm = Game::getInstance().getTileMap();
  if (!tm) return 0;
  int count = 0;
  tilemap::forEachLayerNamed(tm->getMap(), name, [&](tilemap::Layer& layer) {
    layer.visible = visible;
    count++;
  });
  return count;
}

// Capas con la propiedad roof_of = <roofOf> (tejados que se desvanecen al entrar)
inline int setRoofAlpha(const std::string& roofOf, int alpha) {
  TileMapRenderSystem* tm = Game::getInstance().getTileMap();
  if (!tm) return 0;
  int count = 0;
  for (tilemap::Layer& layer : tm->getMap().layers) {
    if (layer.roofOf != roofOf) continue;
    layer.alpha = clampAlpha(alpha);
    count++;
  }
  return count;
}

inline void setYSort(bool on) { Game::getInstance().setYSort(on); }

inline void registerTileMapBindings(sol::state& lua) {
  lua.set_function("load_tile_map", loadTileMap);
  lua.set_function("unload_tile_map", unloadTileMap);
  lua.set_function("get_tile_map_size", getTileMapSize);
  lua.set_function("get_tile_layers", getTileLayers);
  lua.set_function("set_layer_alpha", setLayerAlpha);
  lua.set_function("get_layer_alpha", getLayerAlpha);
  lua.set_function("set_layer_visible", setLayerVisible);
  lua.set_function("set_roof_alpha", setRoofAlpha);
  lua.set_function("set_y_sort", setYSort);
}
