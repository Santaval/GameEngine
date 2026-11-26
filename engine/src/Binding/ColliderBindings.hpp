#pragma once

#include <iostream>
#include <sol/sol.hpp>
#include <tuple>

#include "../ECS/Entity.hpp"
#include "../Components/BoxColliderComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Game/Game.hpp"
#include "../Physics/MoveAndSlide.hpp"
#include "../Util/ColliderCenter.hpp"

inline void addCircleCollider(Entity e, int radius, int width, int height, sol::optional<Entity> owner) {
  int ownerId = owner ? owner->getId() : -1;
  e.addComponent<CircleColliderComponent>(radius, width, height, ownerId);
}

// Caja de colision alineada a los ejes. opts (todo opcional): x, y (offset desde
// la esquina del sprite), solid, trigger, mover, owner (entidad). Ver
// engine/docs/collision.md para las combinaciones de flags.
inline void addBoxCollider(Entity e, float width, float height, sol::optional<sol::table> opts) {
  float offsetX = 0.0f, offsetY = 0.0f;
  bool solid = false, trigger = false, mover = false;
  int ownerId = -1;

  if (opts) {
    offsetX = (*opts).get_or("x", 0.0f);
    offsetY = (*opts).get_or("y", 0.0f);
    solid = (*opts).get_or("solid", false);
    trigger = (*opts).get_or("trigger", false);
    mover = (*opts).get_or("mover", false);
    sol::optional<Entity> owner = (*opts)["owner"];
    if (owner) ownerId = owner->getId();
  }

  if (trigger && solid) {
    std::cerr << "[BoxCollider] trigger y solid a la vez: gana trigger, no bloquea" << std::endl;
  }

  e.addComponent<BoxColliderComponent>(width, height, offsetX, offsetY, solid, trigger, mover, ownerId);
  // addComponent no avisa a los sistemas: sin esto la caja no entraria hasta
  // el proximo ciclo de vida de la entidad
  e.registry->refreshEntity(e);
}

// Cambia campos de la caja de una entidad que ya la tiene: width, height, x, y,
// solid, trigger, mover, enabled, owner. Devuelve false si no tiene BoxCollider.
inline bool setBoxCollider(Entity e, sol::table opts) {
  if (!e.hasComponent<BoxColliderComponent>()) return false;
  auto& box = e.getComponent<BoxColliderComponent>();

  box.width = opts.get_or("width", box.width);
  box.height = opts.get_or("height", box.height);
  box.offsetX = opts.get_or("x", box.offsetX);
  box.offsetY = opts.get_or("y", box.offsetY);
  box.solid = opts.get_or("solid", box.solid);
  box.trigger = opts.get_or("trigger", box.trigger);
  box.mover = opts.get_or("mover", box.mover);
  box.enabled = opts.get_or("enabled", box.enabled);
  sol::optional<Entity> owner = opts["owner"];
  if (owner) box.ownerId = owner->getId();

  if (box.trigger && box.solid) {
    std::cerr << "[BoxCollider] trigger y solid a la vez: gana trigger, no bloquea" << std::endl;
  }
  return true;
}

// Lados bloqueados en el ultimo movimiento del mover: left, right, top, bottom
inline std::tuple<bool, bool, bool, bool> getWallContacts(Entity e) {
  if (!e.hasComponent<BoxColliderComponent>()) return { false, false, false, false };
  const unsigned contacts = e.getComponent<BoxColliderComponent>().contacts;
  return {
    (contacts & physics::CONTACT_LEFT) != 0,
    (contacts & physics::CONTACT_RIGHT) != 0,
    (contacts & physics::CONTACT_TOP) != 0,
    (contacts & physics::CONTACT_BOTTOM) != 0
  };
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
  lua.set_function("add_box_collider", addBoxCollider);
  lua.set_function("set_box_collider", setBoxCollider);
  lua.set_function("get_wall_contacts", getWallContacts);
  lua.set_function("get_collider_center", getColliderCenter);
  lua.set_function("toggle_colliders", toggleColliders);
  lua.set_function("set_show_colliders", setShowColliders);
  lua.set_function("is_showing_colliders", isShowingColliders);
}
