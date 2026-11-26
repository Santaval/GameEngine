#pragma once

#include <iostream>
#include <string>
#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Animation/AtlasRegistry.hpp"

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

// Animacion con atlas Aseprite: el atlas se carga en la escena (sprite.atlas) y
// se referencia por su assetId
inline void addAnimationAtlas(Entity e, std::string atlasId, std::string tag, sol::optional<bool> loop) {
  auto found = atlasRegistry().find(atlasId);
  if (found == atlasRegistry().end()) {
    std::cerr << "[Lua] add_animation_atlas: atlas not found: " << atlasId << std::endl;
    return;
  }

  if (!e.hasComponent<AnimationComponent>()) e.addComponent<AnimationComponent>();
  auto& animation = e.getComponent<AnimationComponent>();
  animation.atlas = found->second;

  if (!animation.play(tag, loop.value_or(true))) {
    std::cerr << "[Lua] add_animation_atlas: tag not found: " << tag << std::endl;
    animation.atlas = nullptr;
    return;
  }
  if (e.hasComponent<SpriteComponent>()) {
    animation.applyTo(e.getComponent<SpriteComponent>());
  }
}

// Cambia de tag y arranca desde su primer frame. Llamarla cada frame con el
// mismo tag en bucle no reinicia la animacion
inline void playAnimation(Entity e, std::string tag, sol::optional<bool> loop) {
  if (!e.hasComponent<AnimationComponent>()) {
    std::cerr << "[Lua] play_animation: entity has no animation" << std::endl;
    return;
  }
  auto& animation = e.getComponent<AnimationComponent>();
  if (!animation.atlas) {
    std::cerr << "[Lua] play_animation: animation has no atlas" << std::endl;
    return;
  }

  const bool looping = loop.value_or(true);
  if (looping && animation.playback.loop && animation.currentTag == tag) return;

  if (!animation.play(tag, looping)) {
    std::cerr << "[Lua] play_animation: tag not found: " << tag << std::endl;
    return;
  }
  if (e.hasComponent<SpriteComponent>()) {
    animation.applyTo(e.getComponent<SpriteComponent>());
  }
}

inline bool animationFinished(Entity e) {
  if (!e.hasComponent<AnimationComponent>()) return false;
  return e.getComponent<AnimationComponent>().finished;
}

inline void registerSpriteBindings(sol::state& lua) {
  lua.set_function("set_sprite", setSprite);
  lua.set_function("set_sprite_frame", setSpriteFrame);
  lua.set_function("add_sprite", addSprite);
  lua.set_function("add_animation", addAnimation);
  lua.set_function("add_animation_atlas", addAnimationAtlas);
  lua.set_function("play_animation", playAnimation);
  lua.set_function("animation_finished", animationFinished);
}
