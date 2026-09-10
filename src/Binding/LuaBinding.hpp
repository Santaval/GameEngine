#pragma once

#include <string>

#include "../Game/Game.hpp"

bool isActionActivated(const std::string& action) {
  return Game::getInstance().controllerManager->isActionActivated(action);
}

