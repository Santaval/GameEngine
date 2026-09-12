#pragma once

#include <string>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"

bool isActionActivated(const std::string& action) {
  return Game::getInstance().controllerManager->isActionActivated(action);
}

void setAcceleration(Entity e, float x, float y) {
  auto& rigidBody = e.getComponent<RigidBodyComponent>();
  rigidBody.acceleration.x = x;
  rigidBody.acceleration.y = y;
}

void setRotation(Entity e, float rotation) {
  auto& transform = e.getComponent<TransformComponent>();
  transform.rotation += rotation * Game::getInstance().getDeltaTime();
}

void setSprite(Entity e, std::string assetId) {
  auto& sprite = e.getComponent<SpriteComponent>();
  sprite.teaxtureId = assetId;
}
