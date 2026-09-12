#pragma once

#include <sol/sol.hpp>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"

inline void setAcceleration(Entity e, float x, float y) {
  auto& rigidBody = e.getComponent<RigidBodyComponent>();
  rigidBody.acceleration.x = x;
  rigidBody.acceleration.y = y;
}

inline void setRotation(Entity e, float rotation) {
  auto& transform = e.getComponent<TransformComponent>();
  transform.rotation += rotation * Game::getInstance().getDeltaTime();
}

inline void registerMovementBindings(sol::state& lua) {
  lua.set_function("set_acceleration", setAcceleration);
  lua.set_function("set_rotation", setRotation);
}
