#pragma once
#include <sol/sol.hpp>

struct ScriptComponent {
  sol::function update;

  ScriptComponent(sol::function update = sol::lua_nil) {
    this->update = update;
  }
};
