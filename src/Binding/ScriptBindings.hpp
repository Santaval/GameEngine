#pragma once

#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/ScriptComponent.hpp"

inline void addScript(Entity e, sol::function update) {
  e.addComponent<ScriptComponent>(update);
}

inline void registerScriptBindings(sol::state& lua) {
  lua.set_function("add_script", addScript);
}
