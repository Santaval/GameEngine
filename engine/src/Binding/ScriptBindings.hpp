#pragma once

#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/ScriptComponent.hpp"

inline void addScript(Entity e, sol::function update) {
  e.addComponent<ScriptComponent>(update);
}

// Hooks para las entidades creadas en runtime, que no pasan por el SceneLoader.
// Si todavia no hay ScriptComponent se crea sin update: el motor solo llama a
// las funciones que existen.
inline void setOnDamage(Entity e, sol::function onDamage) {
  if (!e.hasComponent<ScriptComponent>()) {
    e.addComponent<ScriptComponent>(sol::lua_nil, onDamage);
    return;
  }

  e.getComponent<ScriptComponent>().onDamage = onDamage;
}

inline void setOnDeath(Entity e, sol::function onDeath) {
  if (!e.hasComponent<ScriptComponent>()) {
    e.addComponent<ScriptComponent>(sol::lua_nil, sol::lua_nil, onDeath);
    return;
  }

  e.getComponent<ScriptComponent>().onDeath = onDeath;
}

inline void setOnCollision(Entity e, sol::function onCollision) {
  if (!e.hasComponent<ScriptComponent>()) {
    e.addComponent<ScriptComponent>(sol::lua_nil, sol::lua_nil, sol::lua_nil, onCollision);
    return;
  }

  e.getComponent<ScriptComponent>().onCollision = onCollision;
}

inline void registerScriptBindings(sol::state& lua) {
  lua.set_function("add_script", addScript);
  lua.set_function("set_on_damage", setOnDamage);
  lua.set_function("set_on_death", setOnDeath);
  lua.set_function("set_on_collision", setOnCollision);
}
