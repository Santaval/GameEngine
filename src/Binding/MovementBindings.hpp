#pragma once

#include <glm/glm.hpp>
#include <sol/sol.hpp>
#include <tuple>

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

inline double getRotation(Entity e) {
  auto& transform = e.getComponent<TransformComponent>();
  return transform.rotation;
}

inline void setRotationAbsolute(Entity e, float rotation) {
  auto& transform = e.getComponent<TransformComponent>();
  transform.rotation = rotation;
}

inline void addRigidBody(Entity e, float vx, float vy, float ax, float ay) {
  e.addComponent<RigidBodyComponent>(glm::vec2(vx, vy), glm::vec2(ax, ay));
}

inline std::tuple<float, float> getVelocity(Entity e) {
  auto& rigidBody = e.getComponent<RigidBodyComponent>();
  return { rigidBody.velocity.x, rigidBody.velocity.y };
}

inline std::tuple<float, float> getAcceleration(Entity e) {
  auto& rigidBody = e.getComponent<RigidBodyComponent>();
  return { rigidBody.acceleration.x, rigidBody.acceleration.y };
}

inline double getDeltaTime() {
  return Game::getInstance().getDeltaTime();
}

inline void registerMovementBindings(sol::state& lua) {
  lua.set_function("set_acceleration", setAcceleration);
  lua.set_function("set_rotation", setRotation);
  lua.set_function("set_rotation_absolute", setRotationAbsolute);
  lua.set_function("get_rotation", getRotation);
  lua.set_function("add_rigid_body", addRigidBody);
  lua.set_function("get_velocity", getVelocity);
  lua.set_function("get_acceleration", getAcceleration);
  lua.set_function("get_delta_time", getDeltaTime);
}
