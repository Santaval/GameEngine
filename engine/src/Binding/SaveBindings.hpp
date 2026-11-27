#pragma once

#include <SDL2/SDL.h>
#include <filesystem>
#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"
#include "../Network/LuaJson.hpp"
#include "../Util/SaveFile.hpp"

// Guardado de partidas (issue #52). Lua no tiene io, asi que el motor guarda y lee
// tablas como JSON en la carpeta de datos del usuario (SDL_GetPrefPath), nunca junto
// al binario. Escritura atomica con respaldo: ver Util/SaveFile.hpp.

// Carpeta de guardados: <prefPath>, o <gameRoot>/saves si SDL no da la ruta
inline const std::string& saveDir() {
  static std::string dir;
  if (dir.empty()) {
    char* pref = SDL_GetPrefPath("santaval", "Quebrada");
    if (pref) {
      dir = pref;
      SDL_free(pref);
    } else {
      dir = (std::filesystem::path(Game::getInstance().getGameRoot()) / "saves").string();
    }
  }
  return dir;
}

// save_data(slot, tabla) -> bool
inline bool saveData(const std::string& slot, sol::object data) {
  if (data.get_type() != sol::type::table) return false;
  nlohmann::json j = luaToJson(data);
  return savefile::write(saveDir(), slot, j);
}

// load_data(slot) -> tabla o nil
inline sol::object loadData(const std::string& slot, sol::this_state ts) {
  sol::state_view lua(ts);
  auto j = savefile::read(saveDir(), slot);
  if (!j) return sol::make_object(lua, sol::lua_nil);
  return jsonToLua(*j, lua);
}

// has_save(slot) -> bool
inline bool hasSave(const std::string& slot) {
  return savefile::exists(saveDir(), slot);
}

inline void registerSaveBindings(sol::state& lua) {
  lua.set_function("save_data", saveData);
  lua.set_function("load_data", loadData);
  lua.set_function("has_save", hasSave);
}
