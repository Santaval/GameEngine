#pragma once

#include <string>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/RigidBodyComponent.hpp"

bool isActionActivated(const std::string& action) {
  return Game::getInstance().controllerManager->isActionActivated(action);
}

void setVelocity(Entity e, float x, float y) {
  auto& rigidBody = e.getComponent<RigidBodyComponent>();
  rigidBody.velocity.x = x;
  rigidBody.velocity.y = y;
}
