#pragma once

#include <memory>
#include <sol/sol.hpp>
#include <iostream>

#include "../ECS/System.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/ScriptComponent.hpp"
#include "../Events/CollisionEvent.hpp"
#include "../EventManager/EventManager.hpp"
#include "../Util/Damage.hpp"
#include "../Util/Culling.hpp"
#include "../Binding/LuaBinding.hpp"

class ScriptSystem : public System {
 public:
  ScriptSystem() {
   this->requireComponent<ScriptComponent>();
  }

  void update(sol::state& lua) {
   for(auto entity : this->getEntities()) {
    // Roca de un chunk lejano: dormida
    if(isDormant(entity)) continue;
    // Copia (no referencia): el script puede crear entidades con script
    // (spawn_local, net_spawn) y el pool de ScriptComponent se realoja
    // mientras corre, dejando colgada una referencia
    sol::function update = entity.getComponent<ScriptComponent>().update;

    if(update != sol::lua_nil) {
      lua["this"] = entity;
     update();
    }
   }
  }

  void subscribeToCollisionEvent(std::unique_ptr<EventManager>& eventManager) {
    eventManager->subscribe<CollisionEvent, ScriptSystem>(this, &ScriptSystem::onCollision);
  }

  // Simetrico, mismo patron que DamageSystem: cada lado se entera de con
  // quien choco. callScriptHook ya se fija si el script define on_collision.
  void onCollision(CollisionEvent& e) {
    callScriptHook(e.a, &ScriptComponent::onCollision, e.b);
    callScriptHook(e.b, &ScriptComponent::onCollision, e.a);
  }

  void createLuaBiding(sol::state& lua) {
    // classes
    lua.new_usertype<Entity>("entity");

    // bindings por dominio
    registerEntityBindings(lua);
    registerInputBindings(lua);
    registerMovementBindings(lua);
    registerGravityBindings(lua);
    registerSpriteBindings(lua);
    registerColliderBindings(lua);
    registerHealthBindings(lua);
    registerScriptBindings(lua);
    registerCameraBindings(lua);
    registerTextBindings(lua);
    registerShapeBindings(lua);
    registerImageBindings(lua);
    registerPathBindings(lua);
    registerEquipmentBindings(lua);
    registerInventoryBindings(lua);
    registerLootBindings(lua);
    registerGameBindings(lua);
    registerNetworkBindings(lua);
    registerCullingBindings(lua);
  }
};
