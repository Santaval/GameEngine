#pragma once

#include <sol/sol.hpp>
#include <tuple>

#include "../ECS/Entity.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Game/Game.hpp"
#include "../Util/ColliderCenter.hpp"

inline void addCircleCollider(Entity e, int radius, int width, int height, sol::optional<Entity> owner) {
  int ownerId = owner ? owner->getId() : -1;
  e.addComponent<CircleColliderComponent>(radius, width, height, ownerId);
}

inline void toggleColliders() { Game::getInstance().toggleShowColliders(); }
inline void setShowColliders(bool v) { Game::getInstance().setShowColliders(v); }
inline bool isShowingColliders() { return Game::getInstance().isShowingColliders(); }

// Centro del collider en pantalla (ver Util/ColliderCenter.hpp)
inline std::tuple<double, double> getColliderCenter(Entity e) {
  glm::dvec2 center = colliderCenter(e);
  return { center.x, center.y };
}

inline void registerColliderBindings(sol::state& lua) {
  lua.set_function("add_circle_collider", addCircleCollider);
  lua.set_function("get_collider_center", getColliderCenter);
  lua.set_function("toggle_colliders", toggleColliders);
  lua.set_function("set_show_colliders", setShowColliders);
  lua.set_function("is_showing_colliders", isShowingColliders);
}
