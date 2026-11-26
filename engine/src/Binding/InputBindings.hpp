#pragma once

#include <string>
#include <tuple>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"

inline bool isActionActivated(const std::string& action) {
  return Game::getInstance().controllerManager->isActionActivated(action);
}

inline std::tuple<int, int> getMousePosition() {
  auto& controllerManager = Game::getInstance().controllerManager;
  return { controllerManager->getMouseX(), controllerManager->getMouseY() };
}

inline std::tuple<int, int> getMouseWorldPosition() {
  auto& controllerManager = Game::getInstance().controllerManager;
  const auto& camera = Game::getInstance().getCamera();
  return { controllerManager->getMouseX() + camera.x, controllerManager->getMouseY() + camera.y };
}

inline void registerInputBindings(sol::state& lua) {
  lua.set_function("is_action_activated", isActionActivated);
  lua.set_function("get_mouse_position", getMousePosition);
  lua.set_function("get_mouse_world_position", getMouseWorldPosition);
}
