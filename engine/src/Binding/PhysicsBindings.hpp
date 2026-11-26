#pragma once

#include <iostream>
#include <string>
#include <tuple>
#include <vector>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"
#include "../Map/TmxColliders.hpp"
#include "../Map/TmxLoader.hpp"
#include "../Physics/Geometry.hpp"
#include "../Util/GamePath.hpp"

// Geometria estatica del nivel (Game::staticWorld): paredes que bloquean a los
// movers sin ser entidades. Se vacia al cargar una escena. Ver
// engine/docs/collision.md.

// Crea una pared (x, y = esquina superior izquierda, en px de mundo); devuelve su id
inline int addStaticBox(double x, double y, double w, double h) {
  return Game::getInstance().getStaticWorld().add({ x, y, w, h });
}

// false si el id no existe o ya estaba borrado
inline bool removeStaticBox(int id) {
  return Game::getInstance().getStaticWorld().remove(id);
}

inline void clearStaticColliders() {
  Game::getInstance().getStaticWorld().clear();
}

inline int staticColliderCount() {
  return Game::getInstance().getStaticWorld().count();
}

// true si la caja solapa alguna pared estatica
inline bool overlapsStatic(double x, double y, double w, double h) {
  return Game::getInstance().getStaticWorld().overlaps({ x, y, w, h });
}

// load_tmx_colliders(path, opts?) -> cantidad de rectangulos creados, o nil, mensaje.
// opts = { tile_layers = {"nombre"}, object_layer = "collision", x = 0, y = 0, scale = 1 }
inline std::tuple<sol::object, sol::object> loadTmxColliders(const std::string& path,
  sol::optional<sol::table> opts, sol::this_state s) {
  sol::state_view lua(s);

  tmx::SolidOptions options;
  if (opts) {
    sol::optional<sol::table> layers = (*opts)["tile_layers"];
    if (layers) {
      for (size_t i = 1; i <= layers->size(); i++) {
        sol::optional<std::string> name = (*layers)[i];
        if (name) options.tileLayers.push_back(*name);
      }
    }
    options.objectLayer = (*opts).get_or<std::string>("object_layer", options.objectLayer);
    options.offsetX = (*opts).get_or("x", 0.0);
    options.offsetY = (*opts).get_or("y", 0.0);
    options.scale = (*opts).get_or("scale", 1.0);
  }

  tmx::Result result = tmx::loadFile(resolveGamePath(currentGameRoot(), path));
  if (!result.ok) {
    std::cerr << "[TmxColliders] " << result.error << std::endl;
    return std::make_tuple(sol::object(sol::lua_nil), sol::make_object(lua, result.error));
  }

  std::vector<std::string> warnings;
  tmx::SolidResult solids = tmx::collectSolidRects(result.map, options, warnings);
  for (const std::string& w : warnings) {
    std::cerr << "[TmxColliders] " << path << ": " << w << std::endl;
  }
  if (!solids.ok) {
    std::cerr << "[TmxColliders] " << path << ": " << solids.error << std::endl;
    return std::make_tuple(sol::object(sol::lua_nil), sol::make_object(lua, solids.error));
  }

  auto& world = Game::getInstance().getStaticWorld();
  for (const tmx::Rect& r : solids.rects) {
    world.add({ r.x, r.y, r.w, r.h });
  }
  return std::make_tuple(sol::make_object(lua, static_cast<int>(solids.rects.size())),
    sol::object(sol::lua_nil));
}

inline void registerPhysicsBindings(sol::state& lua) {
  lua.set_function("add_static_box", addStaticBox);
  lua.set_function("remove_static_box", removeStaticBox);
  lua.set_function("clear_static_colliders", clearStaticColliders);
  lua.set_function("static_collider_count", staticColliderCount);
  lua.set_function("overlaps_static", overlapsStatic);
  lua.set_function("load_tmx_colliders", loadTmxColliders);
}
