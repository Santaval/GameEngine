#pragma once

#include <memory>
#include <sol/sol.hpp>
#include <iostream>

#include "../ECS/System.hpp"
#include "../Components/ScriptComponent.hpp"
#include "../Binding/LuaBinding.hpp"

class ScriptSystem : public System {
 public:
  ScriptSystem() {
   this->requireComponent<ScriptComponent>();
  }

  void update(sol::state& lua) {
   for(auto entity : this->getEntities()) {
    const auto& script = entity.getComponent<ScriptComponent>();

    if(script.update != sol::lua_nil) {
     script.update();
    }
   }
  }

  void createLuaBiding(sol::state& lua) {
    lua.set_function("is_action_activated", isActionActivated);
  }
};
