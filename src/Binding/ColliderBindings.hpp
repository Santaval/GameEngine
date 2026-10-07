#pragma once

#include <sol/sol.hpp>
#include <tuple>

#include "../ECS/Entity.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Game/Game.hpp"

inline void addCircleCollider(Entity e, int radius, int width, int height, sol::optional<Entity> owner) {
  int ownerId = owner ? owner->getId() : -1;
  e.addComponent<CircleColliderComponent>(radius, width, height, ownerId);
}

inline void toggleColliders() { Game::getInstance().toggleShowColliders(); }
inline void setShowColliders(bool v) { Game::getInstance().setShowColliders(v); }
inline bool isShowingColliders() { return Game::getInstance().isShowingColliders(); }

// Centro del collider en pantalla, con la misma formula que CollisionSystem:
// position es la esquina sup-izq y el frame va escalado. Sin collider cae a
// la posicion del transform, y sin transform a 0, 0
inline std::tuple<double, double> getColliderCenter(Entity e) {
  if (!e.hasComponent<TransformComponent>()) return { 0.0, 0.0 };
  auto& transform = e.getComponent<TransformComponent>();
  if (!e.hasComponent<CircleColliderComponent>()) {
    return { transform.position.x, transform.position.y };
  }
  auto& collider = e.getComponent<CircleColliderComponent>();
  return {
    transform.position.x + (collider.width / 2) * transform.scale.x,
    transform.position.y + (collider.height / 2) * transform.scale.y
  };
}

inline void registerColliderBindings(sol::state& lua) {
  lua.set_function("add_circle_collider", addCircleCollider);
  lua.set_function("get_collider_center", getColliderCenter);
  lua.set_function("toggle_colliders", toggleColliders);
  lua.set_function("set_show_colliders", setShowColliders);
  lua.set_function("is_showing_colliders", isShowingColliders);
}
