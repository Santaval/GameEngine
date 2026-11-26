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

// Mueve el recorte del sprite dentro de la hoja (px del frame de origen). Lo
// usa quien anima a mano un sprite sin AnimationComponent (que solo avanza en x)
inline void setSpriteFrame(Entity e, int srcX, int srcY) {
  auto& sprite = e.getComponent<SpriteComponent>();
  sprite.srcRect.x = srcX;
  sprite.srcRect.y = srcY;
}

inline void addSprite(Entity e, std::string assetId, int width, int height, int srcRectX, int srcRectY) {
  e.addComponent<SpriteComponent>(assetId, width, height, srcRectX, srcRectY);
}

inline void addAnimation(Entity e, int numFrames, int frameSpeedRate, bool isLoop) {
  e.addComponent<AnimationComponent>(numFrames, frameSpeedRate, isLoop);
}

inline void registerSpriteBindings(sol::state& lua) {
  lua.set_function("set_sprite", setSprite);
  lua.set_function("set_sprite_frame", setSpriteFrame);
  lua.set_function("add_sprite", addSprite);
  lua.set_function("add_animation", addAnimation);
}
