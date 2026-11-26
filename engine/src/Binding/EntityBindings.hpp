#pragma once

#include <glm/glm.hpp>
#include <sol/sol.hpp>
#include <tuple>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Util/Damage.hpp"

inline Entity createEntity() {
  return Game::getInstance().getRegistry()->createEntity();
}

inline void addTransform(Entity e, float x, float y, float scaleX, float scaleY, float rotation) {
  e.addComponent<TransformComponent>(glm::vec2(x, y), glm::vec2(scaleX, scaleY), rotation);
}

inline std::tuple<float, float> getPosition(Entity e) {
  auto& transform = e.getComponent<TransformComponent>();
  return { transform.position.x, transform.position.y };
}

// Mueve la entidad de golpe (esquina sup-izq del sprite, como get_position).
// No toca la velocidad ni avisa a la red: un teletransporte se replica aparte
inline void setPosition(Entity e, float x, float y) {
  auto& transform = e.getComponent<TransformComponent>();
  transform.position.x = x;
  transform.position.y = y;
}

// Mata la entidad sin pasar por HealthComponent: util para pickups y demas
// entidades que no tienen vida (killWithHooks avisa a on_death y difiere el
// kill, mismo camino que usa DamageSystem)
inline void destroyEntity(Entity e) {
  killWithHooks(e);
}

inline void registerEntityBindings(sol::state& lua) {
  lua.set_function("create_entity", createEntity);
  lua.set_function("add_transform", addTransform);
  lua.set_function("get_position", getPosition);
  lua.set_function("set_position", setPosition);
  lua.set_function("destroy_entity", destroyEntity);
}
