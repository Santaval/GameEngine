#pragma once

#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/CircleColliderComponent.hpp"

inline void addCircleCollider(Entity e, int radius, int width, int height) {
  e.addComponent<CircleColliderComponent>(radius, width, height);
}

inline void registerColliderBindings(sol::state& lua) {
  lua.set_function("add_circle_collider", addCircleCollider);
}
