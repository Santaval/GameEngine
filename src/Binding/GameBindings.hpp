#pragma once

#include <string>
#include <tuple>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"

// Flujo del juego: cambio de escena y salida. load_scene es diferido: la
// escena nueva se carga al inicio del proximo frame, asi que el script que
// lo llama termina su update() normalmente.
inline void loadScene(const std::string& scenePath) {
  Game::getInstance().requestScene(scenePath);
}

inline void quitGame() {
  Game::getInstance().quit();
}

inline std::tuple<int, int> getWindowSize() {
  auto& game = Game::getInstance();
  return { game.getWindowWidth(), game.getWindowHeight() };
}

inline void registerGameBindings(sol::state& lua) {
  lua.set_function("load_scene", loadScene);
  lua.set_function("quit_game", quitGame);
  lua.set_function("get_window_size", getWindowSize);
}
