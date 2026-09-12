#pragma once

#include <string>
#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/SpriteComponent.hpp"

inline void setSprite(Entity e, std::string assetId) {
  auto& sprite = e.getComponent<SpriteComponent>();
  sprite.teaxtureId = assetId;
}

inline void registerSpriteBindings(sol::state& lua) {
  lua.set_function("set_sprite", setSprite);
}
