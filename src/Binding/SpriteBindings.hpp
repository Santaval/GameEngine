#pragma once

#include <string>
#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/AnimationComponent.hpp"

inline void setSprite(Entity e, std::string assetId) {
  auto& sprite = e.getComponent<SpriteComponent>();
  sprite.teaxtureId = assetId;
}

inline void addSprite(Entity e, std::string assetId, int width, int height, int srcRectX, int srcRectY) {
  e.addComponent<SpriteComponent>(assetId, width, height, srcRectX, srcRectY);
}

inline void addAnimation(Entity e, int numFrames, int frameSpeedRate, bool isLoop) {
  e.addComponent<AnimationComponent>(numFrames, frameSpeedRate, isLoop);
}

inline void registerSpriteBindings(sol::state& lua) {
  lua.set_function("set_sprite", setSprite);
  lua.set_function("add_sprite", addSprite);
  lua.set_function("add_animation", addAnimation);
}
