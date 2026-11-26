#pragma once

#include <iostream>
#include <string>
#include <tuple>
#include <sol/sol.hpp>

#include "../Util/GamePath.hpp"
#include "../Map/TmxLoader.hpp"
#include "../Map/TmxLua.hpp"

// load_tmx(path) -> tabla del mapa de Tiled, o nil, mensaje si falla. Ver
// engine/docs/README.md para la forma de la tabla.
inline std::tuple<sol::object, sol::object> loadTmx(const std::string& path, sol::this_state s) {
  sol::state_view lua(s);
  tmx::Result result = tmx::loadFile(resolveGamePath(currentGameRoot(), path));
  if (!result.ok) {
    std::cerr << "[TmxLoader] " << result.error << std::endl;
    return std::make_tuple(sol::object(sol::lua_nil), sol::make_object(lua, result.error));
  }
  return std::make_tuple(sol::object(tmx::tmxToLua(lua, result.map)), sol::object(sol::lua_nil));
}

inline void registerMapBindings(sol::state& lua) {
  lua.set_function("load_tmx", loadTmx);
}
