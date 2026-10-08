#pragma once

#include <glm/glm.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"

// Centro del collider en pantalla, con la misma formula que CollisionSystem:
// position es la esquina sup-izq y el frame va escalado. Sin collider cae a
// la posicion del transform, y sin transform a 0, 0. Lo comparten el binding
// get_collider_center y el DamageSystem (normal del impacto).
inline glm::dvec2 colliderCenter(Entity e) {
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
