#pragma once

#include <glm/glm.hpp>
#include <SDL2/SDL.h>

struct AnimationComponent {
  int numFrames, currentFrame, frameSpeedRate, startTime;
  bool isLoop;

  AnimationComponent(int numFrames = 1, int frameSpeedRate = 1, bool isLoop = true) {
    this->numFrames = numFrames;
    this->currentFrame = 1;
    this->frameSpeedRate = frameSpeedRate;
    this->isLoop = isLoop;
    this->startTime = SDL_GetTicks();
  }
};
