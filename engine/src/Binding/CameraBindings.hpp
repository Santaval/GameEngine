#pragma once

#include <sol/sol.hpp>
#include <tuple>

#include "../Game/Game.hpp"

inline void setCameraPosition(float x, float y) {
  auto& camera = Game::getInstance().getCamera();
  camera.x = static_cast<int>(x);
  camera.y = static_cast<int>(y);
}

inline std::tuple<int, int> getCameraPosition() {
  auto& camera = Game::getInstance().getCamera();
  return { camera.x, camera.y };
}

// Deja el punto (x, y) del mundo en el centro de la pantalla
inline void centerCameraOn(float x, float y) {
  auto& camera = Game::getInstance().getCamera();
  camera.x = static_cast<int>(x) - camera.w / 2;
  camera.y = static_cast<int>(y) - camera.h / 2;
}

inline std::tuple<int, int> getScreenSize() {
  auto& camera = Game::getInstance().getCamera();
  return { camera.w, camera.h };
}

inline void registerCameraBindings(sol::state& lua) {
  lua.set_function("set_camera_position", setCameraPosition);
  lua.set_function("get_camera_position", getCameraPosition);
  lua.set_function("center_camera_on", centerCameraOn);
  lua.set_function("get_screen_size", getScreenSize);
}
