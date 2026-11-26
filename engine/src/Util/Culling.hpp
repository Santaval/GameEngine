#pragma once

#include "../ECS/Entity.hpp"
#include "../Components/CullComponent.hpp"
#include "../Components/TransformComponent.hpp"

// Area activa del mundo (en px). Con enabled = false nada esta dormido.
// La fija Lua con set_active_area y se apaga al cargar una escena.
struct ActiveArea {
  bool enabled = false;
  double minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
};

inline ActiveArea& activeArea() {
  static ActiveArea area;
  return area;
}

// true si la entidad tiene CullComponent y su posicion queda fuera del area
// activa. Los sistemas la saltan con `if (isDormant(entity)) continue;`
inline bool isDormant(const Entity& e) {
  const ActiveArea& area = activeArea();
  if (!area.enabled) return false;
  if (!e.hasComponent<CullComponent>() || !e.hasComponent<TransformComponent>()) return false;
  const auto& transform = e.getComponent<TransformComponent>();
  return transform.position.x < area.minX || transform.position.x > area.maxX ||
         transform.position.y < area.minY || transform.position.y > area.maxY;
}
