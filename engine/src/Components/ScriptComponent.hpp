#pragma once
#include <sol/sol.hpp>

// Funciones Lua que el motor llama sobre la entidad. En todas la entidad
// afectada llega como el global "this" (ver ScriptSystem::update):
//
//   update()                  -> cada frame
//   on_damage(amount, source) -> al recibir daño, source es quien lo causo
//   on_death()                -> justo antes de que la entidad muera
//   on_collision(other)       -> cada frame que sigue solapada con "other"
//
// Los hooks son opcionales: si el script no los define quedan en lua_nil y no
// se llaman.
struct ScriptComponent {
  sol::function update;
  sol::function onDamage;
  sol::function onDeath;
  sol::function onCollision;

  ScriptComponent(sol::function update = sol::lua_nil,
    sol::function onDamage = sol::lua_nil, sol::function onDeath = sol::lua_nil,
    sol::function onCollision = sol::lua_nil) {
      this->update = update;
      this->onDamage = onDamage;
      this->onDeath = onDeath;
      this->onCollision = onCollision;
  }
};
