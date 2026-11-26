#pragma once
#include <sol/sol.hpp>

// Funciones Lua que el motor llama sobre la entidad. En todas la entidad
// afectada llega como el global "this" (ver ScriptSystem::update):
//
//   update()                  -> cada frame
//   on_damage(amount, source) -> al recibir daño, source es quien lo causo
//   on_death()                -> justo antes de que la entidad muera
//   on_collision(other)       -> cada frame que sigue solapada con "other"
//   on_trigger_enter(other)   -> "other" entra en una zona trigger (o esta entidad en la suya)
//   on_trigger_stay(other)    -> cada frame que siguen solapados
//   on_trigger_exit(other)    -> dejan de solaparse
//
// Los hooks son opcionales: si el script no los define quedan en lua_nil y no
// se llaman.
struct ScriptComponent {
  sol::function update;
  sol::function onDamage;
  sol::function onDeath;
  sol::function onCollision;
  sol::function onTriggerEnter;
  sol::function onTriggerStay;
  sol::function onTriggerExit;

  ScriptComponent(sol::function update = sol::lua_nil,
    sol::function onDamage = sol::lua_nil, sol::function onDeath = sol::lua_nil,
    sol::function onCollision = sol::lua_nil, sol::function onTriggerEnter = sol::lua_nil,
    sol::function onTriggerStay = sol::lua_nil, sol::function onTriggerExit = sol::lua_nil) {
      this->update = update;
      this->onDamage = onDamage;
      this->onDeath = onDeath;
      this->onCollision = onCollision;
      this->onTriggerEnter = onTriggerEnter;
      this->onTriggerStay = onTriggerStay;
      this->onTriggerExit = onTriggerExit;
  }
};
