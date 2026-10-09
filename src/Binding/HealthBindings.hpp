#pragma once

#include <iostream>
#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/DamageComponent.hpp"
#include "../Components/HealthComponent.hpp"
#include "../Util/Damage.hpp"

// getComponent no valida nada (ver Registry), asi que los getters devuelven un
// valor neutro cuando falta el componente en vez de leer basura

inline void addHealth(Entity e, int maxHealth, sol::optional<double> invulnerability,
                      sol::optional<bool> player) {
  e.addComponent<HealthComponent>(maxHealth, -1, invulnerability.value_or(0.0), player.value_or(false));
}

inline int getHealth(Entity e) {
  if (!e.hasComponent<HealthComponent>()) return 0;
  return e.getComponent<HealthComponent>().health;
}

inline int getMaxHealth(Entity e) {
  if (!e.hasComponent<HealthComponent>()) return 0;
  return e.getComponent<HealthComponent>().maxHealth;
}

// Sin HealthComponent la entidad es indestructible, asi que sigue viva
inline bool isAlive(Entity e) {
  if (!e.hasComponent<HealthComponent>()) return true;
  return e.getComponent<HealthComponent>().health > 0;
}

// Fija la vida saltandose la invulnerabilidad (scripts, cheats, respawn).
// Llegar a 0 por aqui tambien dispara on_death.
// En multijugador solo el dueño puede hacerlo: es la misma regla que en
// applyDamage, y el cambio se difunde como "damage" / "death".
inline void setHealth(Entity e, int value) {
  if (!e.hasComponent<HealthComponent>()) return;

  auto& health = e.getComponent<HealthComponent>();
  if (health.health <= 0) return;

  if (!canChangeHealth(e)) {
    std::cout << "[Net] set_health: entity is owned by another player, ignored" << std::endl;
    return;
  }

  const int before = health.health;
  health.health = value;
  if (health.health < 0) health.health = 0;
  if (health.health > health.maxHealth) health.health = health.maxHealth;

  commitHealth(e, before - health.health, sol::nullopt);
}

inline void heal(Entity e, int amount) {
  setHealth(e, getHealth(e) + amount);
}

// Cambia el tope de vida (mejoras de escudo, por ejemplo). Nunca mata: si la
// vida actual queda por encima del nuevo tope, se recorta, nada mas.
inline void setMaxHealth(Entity e, int value) {
  if (!e.hasComponent<HealthComponent>()) return;
  if (value < 1) value = 1;

  if (!canChangeHealth(e)) {
    std::cout << "[Net] set_max_health: entity is owned by another player, ignored" << std::endl;
    return;
  }

  auto& health = e.getComponent<HealthComponent>();
  health.maxHealth = value;
  if (health.health > health.maxHealth) health.health = health.maxHealth;
}

// Escudo de aparicion: la entidad no recibe daño de applyDamage durante
// `seconds` (0 lo cancela). set_health lo ignora a proposito (scripts)
inline void setShield(Entity e, double seconds) {
  if (!e.hasComponent<HealthComponent>()) return;

  auto& health = e.getComponent<HealthComponent>();
  health.shieldUntilTicks = seconds > 0.0
    ? SDL_GetTicks() + static_cast<Uint32>(seconds * 1000.0)
    : 0;
}

// Segundos de escudo que quedan (0 sin componente o ya vencido)
inline double getShield(Entity e) {
  if (!e.hasComponent<HealthComponent>()) return 0.0;

  const Uint32 until = e.getComponent<HealthComponent>().shieldUntilTicks;
  const Uint32 now = SDL_GetTicks();
  if (now >= until) return 0.0;
  return (until - now) / 1000.0;
}

inline void addDamage(Entity e, int amount, sol::optional<bool> destroyOnHit,
                      sol::optional<bool> player) {
  e.addComponent<DamageComponent>(amount, destroyOnHit.value_or(false), player.value_or(false));
}

// Activa la escala por velocidad de impacto (ver DamageComponent). Añade el
// componente con daño 0 si falta; min = full = 0 la desactiva
inline void setImpactDamage(Entity e, float minSpeed, float fullSpeed) {
  if (!e.hasComponent<DamageComponent>()) e.addComponent<DamageComponent>(0);

  auto& damage = e.getComponent<DamageComponent>();
  damage.minImpactSpeed = minSpeed;
  damage.fullImpactSpeed = fullSpeed;
}

inline int getDamage(Entity e) {
  if (!e.hasComponent<DamageComponent>()) return 0;
  return e.getComponent<DamageComponent>().amount;
}

inline void setDamage(Entity e, int amount) {
  if (!e.hasComponent<DamageComponent>()) {
    e.addComponent<DamageComponent>(amount);
    return;
  }

  e.getComponent<DamageComponent>().amount = amount;
}

inline void registerHealthBindings(sol::state& lua) {
  lua.set_function("add_health", addHealth);
  lua.set_function("get_health", getHealth);
  lua.set_function("get_max_health", getMaxHealth);
  lua.set_function("is_alive", isAlive);
  lua.set_function("set_health", setHealth);
  lua.set_function("heal", heal);
  lua.set_function("set_max_health", setMaxHealth);
  lua.set_function("set_shield", setShield);
  lua.set_function("get_shield", getShield);
  lua.set_function("add_damage", addDamage);
  lua.set_function("get_damage", getDamage);
  lua.set_function("set_damage", setDamage);
  lua.set_function("set_impact_damage", setImpactDamage);
}
