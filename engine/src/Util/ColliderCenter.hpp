#pragma once

#include <glm/glm.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/BoxColliderComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Physics/Geometry.hpp"

// Centro del collider en pantalla, con la misma formula que CollisionSystem:
// position es la esquina sup-izq y el frame va escalado. Sin collider cae a
// la posicion del transform, y sin transform a 0, 0. Si no hay circulo pero si
// BoxCollider, es el centro de la caja (el circulo gana si hay los dos). Lo comparten el binding
// get_collider_center y el DamageSystem (normal del impacto).
inline glm::dvec2 colliderCenter(Entity e) {
  if (!e.hasComponent<TransformComponent>()) return { 0.0, 0.0 };
  auto& transform = e.getComponent<TransformComponent>();
  if (!e.hasComponent<CircleColliderComponent>()) {
    if (e.hasComponent<BoxColliderComponent>()) {
      auto& box = e.getComponent<BoxColliderComponent>();
      physics::Aabb rect = physics::boxWorldRect(
        transform.position.x, transform.position.y, transform.scale.x, transform.scale.y,
        box.offsetX, box.offsetY, box.width, box.height);
      return { rect.x + rect.w * 0.5, rect.y + rect.h * 0.5 };
    }
    return { transform.position.x, transform.position.y };
  }
  auto& collider = e.getComponent<CircleColliderComponent>();
  return {
    transform.position.x + (collider.width / 2) * transform.scale.x,
    transform.position.y + (collider.height / 2) * transform.scale.y
  };
}
