#pragma once

#include <SDL2/SDL.h>
#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/HealthComponent.hpp"
#include "../Components/ScriptComponent.hpp"
#include "../Game/Game.hpp"

// Unico sitio donde se resta vida. Lo usan el DamageSystem (impactos) y los
// bindings de Lua (set_health / heal / daño manual), asi que las reglas de
// invulnerabilidad y muerte viven en un solo lugar.
//
// getComponent no valida nada (ver Registry) y los ids se reciclan, asi que
// todo acceso va precedido de hasComponent.

// Llama a un hook del script de la entidad, si existe. La entidad viaja como
// el global "this", misma convencion que ScriptSystem::update.
template <typename... TArgs>
inline void callScriptHook(Entity e, sol::function ScriptComponent::* hook, TArgs&&... args) {
  if (!e.hasComponent<ScriptComponent>()) return;

  const auto& script = e.getComponent<ScriptComponent>();
  const sol::function& fn = script.*hook;
  if (fn == sol::lua_nil) return;

  Game::getInstance().getLua()["this"] = e;
  fn(std::forward<TArgs>(args)...);
}

// Mata la entidad avisando antes al script. kill() es diferido, asi que
// llamarlo dos veces es inocuo.
inline void killWithHooks(Entity e) {
  callScriptHook(e, &ScriptComponent::onDeath);
  e.kill();
}

// Devuelve true si el daño llego a aplicarse
inline bool applyDamage(Entity target, int amount, sol::optional<Entity> source) {
  // Sin HealthComponent la entidad es indestructible
  if (!target.hasComponent<HealthComponent>()) return false;

  auto& health = target.getComponent<HealthComponent>();

  // Ya murio pero todavia no lo cosecho Registry::update
  if (health.health <= 0) return false;

  Uint32 now = SDL_GetTicks();
  if (health.invulnerability > 0.0 &&
    (now - health.lastDamageTicks) < static_cast<Uint32>(health.invulnerability * 1000)) {
      return false;
  }

  health.health -= amount;
  if (health.health < 0) health.health = 0;
  if (health.health > health.maxHealth) health.health = health.maxHealth;
  health.lastDamageTicks = now;

  callScriptHook(target, &ScriptComponent::onDamage, amount, source);

  if (health.health <= 0) {
    killWithHooks(target);
  }

  return true;
}
