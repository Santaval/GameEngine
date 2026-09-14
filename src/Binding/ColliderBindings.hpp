#pragma once

#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/CircleColliderComponent.hpp"

inline void addCircleCollider(Entity e, int radius, int width, int height, sol::optional<Entity> owner) {
  int ownerId = owner ? owner->getId() : -1;
  e.addComponent<CircleColliderComponent>(radius, width, height, ownerId);
}

inline void registerColliderBindings(sol::state& lua) {
  lua.set_function("add_circle_collider", addCircleCollider);
}
