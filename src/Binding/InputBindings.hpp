#pragma once

#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"

inline bool isActionActivated(const std::string& action) {
  return Game::getInstance().controllerManager->isActionActivated(action);
}

inline void registerInputBindings(sol::state& lua) {
  lua.set_function("is_action_activated", isActionActivated);
}
