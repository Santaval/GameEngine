#pragma once

#include <glm/glm.hpp>
#include <SDL2/SDL.h>
#include <memory>
#include <string>

#include "../Animation/AsepriteAtlas.hpp"
#include "SpriteComponent.hpp"

struct AnimationComponent {
  // Animacion legacy: tira horizontal de frames iguales (atlas == nullptr)
  int numFrames, currentFrame, frameSpeedRate, startTime;
  bool isLoop;

  // Animacion con atlas Aseprite: tags, duracion por frame y rectangulos propios
  std::shared_ptr<const aseprite::Atlas> atlas;
  std::string currentTag;
  aseprite::Playback playback;
  bool finished = false;

  AnimationComponent(int numFrames = 1, int frameSpeedRate = 1, bool isLoop = true) {
    this->numFrames = numFrames;
    this->currentFrame = 1;
    this->frameSpeedRate = frameSpeedRate;
    this->isLoop = isLoop;
    this->startTime = SDL_GetTicks();
  }

  // Empieza el tag desde su primer frame. false si no hay atlas o el tag no existe
  bool play(const std::string& tag, bool loop) {
    if (!atlas) return false;
    int index = atlas->findTag(tag);
    if (index < 0) return false;
    playback.start(index, loop);
    currentTag = tag;
    finished = false;
    return true;
  }

  // Copia el frame actual del atlas al sprite (rect de origen y tamano)
  void applyTo(SpriteComponent& sprite) const {
    if (!atlas) return;
    const aseprite::Frame& f = atlas->frames[playback.frameIndex(*atlas)];
    sprite.srcRect = {f.x, f.y, f.w, f.h};
    sprite.width = f.w;
    sprite.height = f.h;
  }
};
