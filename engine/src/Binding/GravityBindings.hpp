#pragma once

#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/GravityComponent.hpp"

inline void addGravity(Entity e, float mass, sol::optional<bool> attracts,
    sol::optional<bool> affected, sol::optional<float> range) {
  e.addComponent<GravityComponent>(mass, attracts.value_or(false),
      affected.value_or(true), range.value_or(0.0f));
}

inline bool hasGravity(Entity e) {
  return e.hasComponent<GravityComponent>();
}

// 0 si la entidad no tiene el componente
inline float getMass(Entity e) {
  if (!e.hasComponent<GravityComponent>()) return 0.0f;
  return e.getComponent<GravityComponent>().mass;
}

// Sin componente no hace nada: add_gravity es quien lo crea
inline void setMass(Entity e, float mass) {
  if (!e.hasComponent<GravityComponent>()) return;
  e.getComponent<GravityComponent>().mass = mass;
}

inline void setGravityAffected(Entity e, bool affected) {
  if (!e.hasComponent<GravityComponent>()) return;
  e.getComponent<GravityComponent>().affected = affected;
}

// Fuente de gravedad = la entidad atrae y tiene masa (los planetas hoy).
// Sin componente devuelve false
inline bool isGravitySource(Entity e) {
  if (!e.hasComponent<GravityComponent>()) return false;
  const auto& g = e.getComponent<GravityComponent>();
  return g.attracts && g.mass > 0.0f;
}

inline void registerGravityBindings(sol::state& lua) {
  lua.set_function("add_gravity", addGravity);
  lua.set_function("has_gravity", hasGravity);
  lua.set_function("get_mass", getMass);
  lua.set_function("set_mass", setMass);
  lua.set_function("set_gravity_affected", setGravityAffected);
  lua.set_function("is_gravity_source", isGravitySource);
}
